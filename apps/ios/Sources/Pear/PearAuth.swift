@preconcurrency import AuthenticationServices
import Foundation
import Observation
import UIKit

struct PearSession: Codable, Equatable {
    var sessionID: String
    var email: String?
    var expiresAt: Date?
    var createdAt: Date

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }
}

enum PearSessionStore {
    private static let service = "ai.openclaw.pear"
    private static let account = "playground-session"

    static let didChangeNotification = Notification.Name("PearSessionDidChange")

    static func load() -> PearSession? {
        guard let raw = KeychainStore.loadString(service: self.service, account: self.account),
              let data = raw.data(using: .utf8)
        else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let session = try? decoder.decode(PearSession.self, from: data) else {
            self.clear()
            return nil
        }
        if session.isExpired {
            self.clear()
            return nil
        }
        return session
    }

    @discardableResult
    static func save(_ session: PearSession) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(session),
              let raw = String(data: data, encoding: .utf8),
              KeychainStore.saveString(raw, service: self.service, account: self.account)
        else { return false }
        NotificationCenter.default.post(name: self.didChangeNotification, object: session)
        return true
    }

    @discardableResult
    static func updateEmail(_ email: String?) -> Bool {
        guard var session = self.load() else { return false }
        session.email = email
        return self.save(session)
    }

    static func clear() {
        _ = KeychainStore.delete(service: self.service, account: self.account)
        NotificationCenter.default.post(name: self.didChangeNotification, object: nil)
    }
}

enum PearAuthError: LocalizedError {
    case missingCallback
    case missingDeviceKey
    case invalidDeviceKey
    case couldNotStart
    case keychainWriteFailed

    var errorDescription: String? {
        switch self {
        case .missingCallback:
            "The Google sign-in did not return to PEAR."
        case .missingDeviceKey:
            "The connect handoff did not include a device key."
        case .invalidDeviceKey:
            "The connect handoff included a malformed device key."
        case .couldNotStart:
            "Could not open the Google sign-in sheet."
        case .keychainWriteFailed:
            "Could not save the Playground session."
        }
    }
}

enum PearSessionExchange {
    static func exchangeDeviceKeyAndSave(_ key: String) async throws -> PearSession {
        let session = try await PearAPI(deviceKey: key).exchangeDeviceKeyForSession(key)
        guard PearSessionStore.save(session) else { throw PearAuthError.keychainWriteFailed }

        let authenticatedAPI = PearAPI(deviceKey: key, sessionID: session.sessionID)
        guard let me = try? await authenticatedAPI.me(), let email = me.email, !email.isEmpty else {
            return session
        }

        let updated = PearSession(
            sessionID: session.sessionID,
            email: email,
            expiresAt: session.expiresAt,
            createdAt: session.createdAt)
        guard PearSessionStore.save(updated) else { throw PearAuthError.keychainWriteFailed }
        return updated
    }
}

@MainActor
@Observable
final class PearAuthModel {
    enum Phase: Equatable {
        case signedOut
        case restoring
        case signingIn
        case signedIn(email: String?)
        case failed(String)
    }

    private(set) var phase: Phase

    @ObservationIgnored private var webSession: ASWebAuthenticationSession?
    @ObservationIgnored private let presentationProvider = PearAuthenticationPresentationProvider()
    @ObservationIgnored private var sessionObserver: (any NSObjectProtocol)?

    init() {
        if let session = PearSessionStore.load() {
            self.phase = .signedIn(email: session.email)
        } else {
            self.phase = .signedOut
        }

        self.sessionObserver = NotificationCenter.default.addObserver(
            forName: PearSessionStore.didChangeNotification,
            object: nil,
            queue: .main)
        { [weak self] _ in
            Task { @MainActor in
                self?.syncFromKeychain()
            }
        }
    }

    deinit {
        if let sessionObserver {
            NotificationCenter.default.removeObserver(sessionObserver)
        }
    }

    var isSignedIn: Bool {
        if case .signedIn = self.phase { return true }
        return false
    }

    var isWorking: Bool {
        self.phase == .restoring || self.phase == .signingIn
    }

    var displayEmail: String? {
        if case let .signedIn(email) = self.phase { return email }
        return nil
    }

    var statusText: String {
        switch self.phase {
        case .signedOut:
            "not signed in"
        case .restoring:
            "restoring session"
        case .signingIn:
            "waiting on Google"
        case let .signedIn(email):
            email ?? "signed in"
        case let .failed(reason):
            reason
        }
    }

    func bootstrap() async {
        if PearSessionStore.load() != nil {
            await self.refreshProfile()
            return
        }
        guard let key = PearDeviceKeyStore.load() else {
            self.phase = .signedOut
            return
        }

        self.phase = .restoring
        do {
            let session = try await PearSessionExchange.exchangeDeviceKeyAndSave(key)
            self.phase = .signedIn(email: session.email)
        } catch {
            self.phase = .signedOut
        }
    }

    func signIn() async {
        guard !self.isWorking else { return }
        self.phase = .signingIn

        do {
            let callbackURL = try await self.openBroker()
            let key = try Self.deviceKey(from: callbackURL)
            PearDeviceKeyStore.save(key)
            let session = try await PearSessionExchange.exchangeDeviceKeyAndSave(key)
            self.phase = .signedIn(email: session.email)
        } catch {
            if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                self.syncFromKeychain()
                return
            }
            self.phase = .failed(error.localizedDescription)
        }
    }

    func signOutSessionOnly() {
        PearSessionStore.clear()
        self.syncFromKeychain()
    }

    private func refreshProfile() async {
        guard let session = PearSessionStore.load() else {
            self.phase = .signedOut
            return
        }
        if let me = try? await PearAPI.current.me(), let email = me.email, !email.isEmpty {
            _ = PearSessionStore.updateEmail(email)
        } else {
            self.phase = .signedIn(email: session.email)
        }
    }

    private func syncFromKeychain() {
        if let session = PearSessionStore.load() {
            self.phase = .signedIn(email: session.email)
        } else {
            self.phase = .signedOut
        }
    }

    private func openBroker() async throws -> URL {
        let url = URL(string: "https://pear.metahack.io/connect/app")!
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "openclaw") { callbackURL, error in
                Task { @MainActor in
                    self.webSession = nil
                    if let callbackURL {
                        continuation.resume(returning: callbackURL)
                    } else {
                        continuation.resume(throwing: error ?? PearAuthError.missingCallback)
                    }
                }
            }
            session.presentationContextProvider = self.presentationProvider
            session.prefersEphemeralWebBrowserSession = false
            self.webSession = session
            if !session.start() {
                self.webSession = nil
                continuation.resume(throwing: PearAuthError.couldNotStart)
            }
        }
    }

    private static func deviceKey(from url: URL) throws -> String {
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let key = comps?.queryItems?
            .first(where: { $0.name == "k" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else { throw PearAuthError.missingDeviceKey }
        guard key.count <= 128, key.allSatisfy(\.isHexDigit) else { throw PearAuthError.invalidDeviceKey }
        return key
    }
}

@MainActor
private final class PearAuthenticationPresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            if let window = scene.windows.first(where: \.isKeyWindow) {
                return window
            }
        }
        return ASPresentationAnchor()
    }
}

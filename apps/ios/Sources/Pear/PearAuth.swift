@preconcurrency import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Security
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
    /// Deliberately separate from the old shared-device-key session.
    private static let account = "ols-account-session-v1"

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

    @MainActor deinit {
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
        self.phase = .signedOut
    }

    func signIn() async {
        guard !self.isWorking else { return }
        self.phase = .signingIn

        do {
            let verifier = try Self.randomURLSafeBytes()
            let state = try Self.randomURLSafeBytes()
            let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
            let callbackURL = try await self.openBroker(challenge: challenge, state: state)
            guard callbackURL.scheme == "openclaw", callbackURL.host == "ols-auth",
                  let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                  components.queryItems?.first(where: { $0.name == "state" })?.value == state,
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value
            else { throw PearAuthError.missingCallback }
            let session = try await Self.exchange(code: code, verifier: verifier, state: state)
            guard PearSessionStore.save(session) else { throw PearAuthError.keychainWriteFailed }
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
        do {
            let me = try await PearAPI(sessionID: session.sessionID).me()
            guard let email = me.email, !email.isEmpty else { throw PearAPIError.notAuthorized }
            _ = PearSessionStore.updateEmail(email)
        } catch PearAPIError.notAuthorized {
            PearSessionStore.clear()
            self.phase = .signedOut
        } catch {
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

    private func openBroker(challenge: String, state: String) async throws -> URL {
        var components = URLComponents(string: "https://pear.metahack.io/connect/ols")!
        components.queryItems = [
            URLQueryItem(name: "challenge", value: challenge),
            URLQueryItem(name: "state", value: state),
        ]
        guard let url = components.url else { throw PearAuthError.couldNotStart }
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

    private static func randomURLSafeBytes() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw PearAuthError.couldNotStart
        }
        return Data(bytes).base64URL
    }

    private static func exchange(code: String, verifier: String, state: String) async throws -> PearSession {
        var request = URLRequest(url: URL(string: "https://pear.metahack.io/api/ols/auth/exchange")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["code": code, "verifier": verifier, "state": state])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = 20
        let client = URLSession(configuration: configuration, delegate: PearAuthRedirectPolicy(), delegateQueue: nil)
        let (data, response) = try await client.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw PearAuthError.missingCallback }
        struct Exchange: Decodable {
            let sessionID: String
            let email: String
            let expiresAt: String
            let createdAt: String
        }
        let result = try JSONDecoder().decode(Exchange.self, from: data)
        guard let expires = PearAPI.parseISODate(result.expiresAt),
              expires > Date() else { throw PearAuthError.missingCallback }
        return PearSession(
            sessionID: result.sessionID,
            email: result.email,
            expiresAt: expires,
            createdAt: PearAPI.parseISODate(result.createdAt) ?? Date())
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

extension Data {
    fileprivate var base64URL: String {
        self.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

private final class PearAuthRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _: URLSession, task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse, newRequest _: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void)
    {
        completionHandler(nil)
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

import Foundation

// MARK: - Wire models

/// GET /api/home/feed — the nervous-system home feed being built server-side.
/// Decoded defensively: every field optional, unknown fields ignored, so the
/// client survives contract drift while that lane lands.
struct PearHomeFeed: Codable {
    struct Item: Codable {
        var title: String?
        var summary: String?
        var description: String?
        var tag: String?
        var hashtag: String?
        var kind: String?
        var type: String?
        var url: String?
        var href: String?
        var emoji: String?
        var date: String?
        var pinned: Bool?

        var bestSummary: String? { self.summary ?? self.description }
        var bestTag: String? { self.tag ?? self.hashtag }
        var bestKind: String? { self.kind ?? self.type }
        var bestURL: String? { self.url ?? self.href }
    }

    struct Day: Codable {
        var label: String?
        var date: String?
        var items: [Item]?
    }

    struct Motion: Codable {
        var emoji: String?
        var title: String?
        var text: String?
        var status: String?
        var detail: String?
        var tag: String?
        var hashtag: String?
        var surface: String?

        var bestTitle: String? { self.title ?? self.text }
        var bestStatus: String? { self.status ?? self.detail }
        var bestTag: String? { self.tag ?? self.hashtag }
    }

    var days: [Day]?
    var items: [Item]?
    var inMotion: [Motion]?
}

/// GET /api/briefing (open) — queued + in-motion project pulses.
struct PearBriefing: Codable {
    struct Entry: Codable {
        var text: String
        var emoji: String?
        var detail: String?
        var projectId: Int?
    }

    var queued: [Entry]?
    var inMotion: [Entry]?
    var summary: String?
}

/// GET /api/status/data (open) — the project world.
struct PearStatusData: Codable {
    struct Project: Codable, Identifiable {
        var id: Int
        var slug: String?
        var name: String
        var emoji: String?
        var category: String?
        var health: String?
        var freshness: String?
        var updatedAt: String?
        var summary: String?

        var hashtag: String {
            let raw = (self.slug ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return raw.isEmpty ? "#project-\(self.id)" : "#\(raw.lowercased())"
        }

        var updatedDate: Date? {
            guard let updatedAt else { return nil }
            return PearAPI.parseISODate(updatedAt)
        }
    }

    var totalProjects: Int?
    var activeCount: Int?
    var inMotion: Int?
    var active: [Project]?
    var onDeck: [Project]?
}

/// GET /api/apps/registry (open).
struct PearAppsRegistry: Codable {
    struct Entry: Codable, Identifiable {
        var id: Int
        var name: String
        var slug: String?
        var emoji: String?
        var description: String?
        var path: String?
        var category: String?
        var visible: Bool?
    }

    var apps: [Entry]?
}

/// GET /api/pear-mobile/chat/history (device key).
struct PearChatHistory: Codable {
    struct Message: Codable, Identifiable, Equatable {
        var id: Int
        var author: String
        var text: String
        var at: String?

        var isPear: Bool { self.author.lowercased() == "pear" }
    }

    var messages: [Message]?
}

struct PearChatSendResponse: Codable {
    var ok: Bool?
    var id: Int?
    var error: String?
}

// MARK: - Device key

/// The Playground device key from the Safari handoff (openclaw://playground?k=…).
/// The WebView exchanges it for a session cookie; the native client keeps the key
/// itself in the Keychain and sends it as a Bearer token on the pear-mobile lane.
enum PearDeviceKeyStore {
    private static let service = "ai.openclaw.pear"
    private static let account = "playground-device-key"

    static let didChangeNotification = Notification.Name("PearDeviceKeyDidChange")

    static func load() -> String? {
        let key = KeychainStore.loadString(service: self.service, account: self.account)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let key, !key.isEmpty else { return nil }
        return key
    }

    static func save(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard KeychainStore.saveString(trimmed, service: self.service, account: self.account) else { return }
        NotificationCenter.default.post(name: self.didChangeNotification, object: nil)
    }

    static func clear() {
        _ = KeychainStore.delete(service: self.service, account: self.account)
        NotificationCenter.default.post(name: self.didChangeNotification, object: nil)
    }
}

// MARK: - Client

enum PearAPIError: Error, LocalizedError {
    case badStatus(Int)
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case let .badStatus(code): "PEAR server answered \(code)"
        case .notAuthorized: "This device is not linked yet"
        }
    }
}

/// Thin typed client for pear.metahack.io. Stateless and Sendable; auth is the
/// device key passed per call so callers decide when a lane needs it.
struct PearAPI: Sendable {
    static let baseURL = URL(string: "https://pear.metahack.io")!

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    var deviceKey: String?

    func homeFeed() async throws -> PearHomeFeed {
        try await self.get("/api/home/feed", authorized: true)
    }

    func briefing() async throws -> PearBriefing {
        try await self.get("/api/briefing", authorized: false)
    }

    func statusData() async throws -> PearStatusData {
        try await self.get("/api/status/data", authorized: false)
    }

    func appsRegistry() async throws -> PearAppsRegistry {
        try await self.get("/api/apps/registry", authorized: false)
    }

    func chatHistory(since: Int? = nil) async throws -> [PearChatHistory.Message] {
        var path = "/api/pear-mobile/chat/history"
        if let since {
            path += "?since=\(since)"
        }
        let history: PearChatHistory = try await self.get(path, authorized: true)
        return history.messages ?? []
    }

    func sendChat(message: String) async throws -> PearChatSendResponse {
        var request = self.makeRequest(path: "/api/pear-mobile/chat/send", authorized: true)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["message": message])
        let (data, response) = try await Self.session.data(for: request)
        try Self.check(response)
        return try JSONDecoder().decode(PearChatSendResponse.self, from: data)
    }

    func ping() async -> Bool {
        struct Pong: Codable { var ok: Bool? }
        let pong: Pong? = try? await self.get("/api/pear-mobile/ping", authorized: true)
        return pong?.ok == true
    }

    // MARK: - Plumbing

    private func get<T: Decodable>(_ path: String, authorized: Bool) async throws -> T {
        let request = self.makeRequest(path: path, authorized: authorized)
        let (data, response) = try await Self.session.data(for: request)
        try Self.check(response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func makeRequest(path: String, authorized: Bool) -> URLRequest {
        var request = URLRequest(url: URL(string: path, relativeTo: Self.baseURL)!)
        if authorized, let deviceKey {
            request.setValue("Bearer \(deviceKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw PearAPIError.notAuthorized
        }
        guard (200...299).contains(http.statusCode) else {
            throw PearAPIError.badStatus(http.statusCode)
        }
    }

    static func parseISODate(_ raw: String) -> Date? {
        let withFractions = ISO8601DateFormatter()
        withFractions.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractions.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        return plain.date(from: raw)
    }
}

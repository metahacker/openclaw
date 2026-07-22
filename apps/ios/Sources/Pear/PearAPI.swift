import Foundation

// MARK: - Wire models

/// GET /api/home/feed — the nervous-system home feed being built server-side.
/// Decoded defensively: every field optional, unknown fields ignored, so the
/// client survives contract drift while that lane lands.
struct PearHomeFeed: Codable {
    struct Item: Codable {
        var id: Int?
        var title: String?
        var summary: String?
        var description: String?
        var tag: String?
        var hashtag: String?
        var kind: String?
        var type: String?
        var url: String?
        var href: String?
        var path: String?
        var emoji: String?
        var projectEmoji: String?
        var projectTag: String?
        var projectName: String?
        var projectSlug: String?
        var thumbnail: String?
        var date: String?
        var pinned: Bool?
        var isPinned: Bool?
        var updatedAt: String?

        var bestSummary: String? { self.summary ?? self.description }
        var bestTag: String? { self.tag ?? self.hashtag ?? self.projectTag }
        var bestKind: String? { self.kind ?? self.type }
        var bestURL: String? { self.url ?? self.href ?? self.path }
        var bestEmoji: String? { self.emoji ?? self.projectEmoji }
        var isPinnedInFeed: Bool { self.pinned ?? self.isPinned ?? false }
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
        var whereItStands: String?
        var tag: String?
        var hashtag: String?
        var projectTag: String?
        var projectName: String?
        var surface: String?
        var lastMessageAt: String?

        var bestTitle: String? { self.title ?? self.text }
        var bestStatus: String? { self.status ?? self.detail ?? self.whereItStands }
        var bestTag: String? { self.tag ?? self.hashtag ?? self.projectTag }
    }

    struct Shelf: Codable {
        var id: Int?
        var emoji: String?
        var name: String?
        var slug: String?
        var projectTag: String?
    }

    var days: [Day]?
    var items: [Item]?
    var stream: [Item]?
    var inMotion: [Motion]?
    var shelves: [Shelf]?
    var visibility: String?

    var hasPrivateCorpus: Bool {
        (self.visibility ?? "").lowercased() == "all"
    }
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
        var description: String?

        var hashtag: String {
            let raw = (self.slug ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return raw.isEmpty ? "#project-\(self.id)" : "#\(raw.lowercased())"
        }

        var bestSummary: String? {
            self.summary ?? self.description
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

        var isPear: Bool {
            let normalized = self.author.lowercased()
            return normalized == "pear" || normalized == "assistant"
        }

        enum CodingKeys: String, CodingKey {
            case id
            case author
            case text
            case message
            case at
            case createdAt
        }

        init(id: Int, author: String, text: String, at: String?) {
            self.id = id
            self.author = author
            self.text = text
            self.at = at
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try container.decode(Int.self, forKey: .id)
            self.author = try container.decodeIfPresent(String.self, forKey: .author) ?? "pear"
            self.text = try container.decodeIfPresent(String.self, forKey: .text)
                ?? container.decodeIfPresent(String.self, forKey: .message)
                ?? ""
            self.at = try container.decodeIfPresent(String.self, forKey: .at)
                ?? container.decodeIfPresent(String.self, forKey: .createdAt)
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(self.id, forKey: .id)
            try container.encode(self.author, forKey: .author)
            try container.encode(self.text, forKey: .text)
            try container.encodeIfPresent(self.at, forKey: .at)
        }
    }

    var messages: [Message]?
}

struct PearChatSendResponse: Codable {
    var ok: Bool?
    var id: Int?
    var error: String?
    var code: String?
}

struct PearMe: Codable {
    var email: String?
    var role: String?
    var actorEmail: String?
}

struct PearConversationSummary: Codable, Identifiable {
    var threadId: Int?
    var lastId: Int?
    var page: String?
    var title: String?
    var emoji: String?
    var lastMessage: String?
    var lastTimestamp: String?
    var lastAuthor: String?
    var projectTag: String?
    var sourceTag: String?
    var activityActive: Bool?
    var messageCount: Int?

    var id: String {
        if let threadId { return "thread:\(threadId)" }
        if let page { return page }
        if let lastId { return "message:\(lastId)" }
        return self.title ?? "conversation"
    }

    var bestEmoji: String {
        guard let emoji, !emoji.isEmpty else { return "💬" }
        return emoji
    }

    var bestTitle: String {
        guard let title, !title.isEmpty else { return "Conversation" }
        return title
    }
    var bestStatus: String? { self.lastMessage }
    var bestTag: String? { self.projectTag ?? self.sourceTag }
}

struct PearProjectSites: Codable {
    struct Page: Codable, Identifiable {
        var pageId: Int?
        var title: String?
        var summary: String?
        var description: String?
        var url: String?
        var path: String?
        var kind: String?
        var updatedAt: String?
        var isPinned: Bool?

        var id: String {
            if let pageId { return "page:\(pageId)" }
            return self.path ?? self.url ?? self.title ?? UUID().uuidString
        }

        var bestSummary: String? { self.summary ?? self.description }
        var bestURL: String? { self.url ?? self.path }

        enum CodingKeys: String, CodingKey {
            case pageId = "id"
            case title
            case summary
            case description
            case url
            case path
            case kind
            case updatedAt
            case isPinned
        }
    }

    struct Site: Codable, Identifiable {
        var id: Int
        var slug: String?
        var title: String?
        var summary: String?
        var pages: [Page]?
    }

    struct Counts: Codable {
        var sites: Int?
        var pages: Int?
        var tasksOpen: Int?
        var tasksTotal: Int?
    }

    var sites: [Site]?
    var siteless: [Page]?
    var counts: Counts?
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

/// Thin typed client for pear.metahack.io. The persisted Playground session is
/// the primary auth; the device key stays as the legacy pear-mobile fallback.
struct PearAPI: Sendable {
    static let baseURL = URL(string: "https://pear.metahack.io")!

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    var deviceKey: String?
    var sessionID: String?

    static var current: PearAPI {
        PearAPI(deviceKey: PearDeviceKeyStore.load(), sessionID: PearSessionStore.load()?.sessionID)
    }

    init(deviceKey: String? = nil, sessionID: String? = nil) {
        self.deviceKey = deviceKey
        self.sessionID = sessionID
    }

    func homeFeed() async throws -> PearHomeFeed {
        try await self.get("/api/home/feed", authorized: true)
    }

    func me() async throws -> PearMe {
        try await self.get("/api/me", authorized: true)
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

    func projects() async throws -> [PearStatusData.Project] {
        try await self.get("/api/projects", authorized: true)
    }

    func projectSites(project: PearStatusData.Project) async throws -> PearProjectSites {
        let key = project.slug ?? String(project.id)
        return try await self.get("/api/projects/\(Self.pathEscape(key))/sites", authorized: true)
    }

    func conversations(scope: String = "/", limit: Int = 24) async throws -> [PearConversationSummary] {
        try await self.get(
            "/api/chat/conversations?scope=\(Self.queryEscape(scope))&limit=\(limit)",
            authorized: true)
    }

    func chatHistory(page: String = "/apps/pear-mobile", since: Int? = nil) async throws -> [PearChatHistory.Message] {
        if self.sessionID != nil {
            var path = "/api/chat?page=\(Self.queryEscape(page))"
            if let since {
                path += "&since=\(since)"
            }
            return try await self.get(path, authorized: true)
        }

        guard page == "/apps/pear-mobile" else { throw PearAPIError.notAuthorized }
        var path = "/api/pear-mobile/chat/history"
        if let since {
            path += "?since=\(since)"
        }
        let history: PearChatHistory = try await self.get(path, authorized: true)
        return history.messages ?? []
    }

    func sendChat(message: String, page: String = "/apps/pear-mobile") async throws -> PearChatSendResponse {
        let path = self.sessionID == nil ? "/api/pear-mobile/chat/send" : "/api/chat"
        var request = self.makeRequest(path: path, authorized: true)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if self.sessionID == nil {
            guard page == "/apps/pear-mobile" else { throw PearAPIError.notAuthorized }
            request.httpBody = try JSONEncoder().encode(["message": message])
        } else {
            request.httpBody = try JSONEncoder().encode(["page": page, "message": message])
        }
        let (data, response) = try await Self.session.data(for: request)
        try Self.check(response)
        return try Self.makeDecoder().decode(PearChatSendResponse.self, from: data)
    }

    func ping() async -> Bool {
        if self.sessionID != nil {
            guard let me = try? await self.me() else { return false }
            return me.email != nil
        }
        struct Pong: Codable { var ok: Bool? }
        let pong: Pong? = try? await self.get("/api/pear-mobile/ping", authorized: true)
        return pong?.ok == true
    }

    func exchangeDeviceKeyForSession(_ key: String) async throws -> PearSession {
        var request = self.makeRequest(
            path: "/auth/device?k=\(Self.queryEscape(key))&return=%2F",
            authorized: false)
        request.setValue("text/html,application/json", forHTTPHeaderField: "Accept")
        let (_, response) = try await Self.session.data(for: request)
        try Self.check(response)
        guard let http = response as? HTTPURLResponse,
              let cookie = Self.sessionCookie(from: http)
        else { throw PearAPIError.notAuthorized }
        return PearSession(
            sessionID: cookie.value,
            email: nil,
            expiresAt: cookie.expiresDate ?? Date().addingTimeInterval(30 * 24 * 60 * 60),
            createdAt: Date())
    }

    // MARK: - Plumbing

    private func get<T: Decodable>(_ path: String, authorized: Bool) async throws -> T {
        let request = self.makeRequest(path: path, authorized: authorized)
        let (data, response) = try await Self.session.data(for: request)
        try Self.check(response)
        return try Self.makeDecoder().decode(T.self, from: data)
    }

    private func makeRequest(path: String, authorized: Bool) -> URLRequest {
        var request = URLRequest(url: Self.absoluteURL(path)!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let sessionID {
            request.setValue("pear_session=\(sessionID)", forHTTPHeaderField: "Cookie")
        }
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

    static func absoluteURL(_ raw: String) -> URL? {
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }
        return URL(string: raw, relativeTo: Self.baseURL)?.absoluteURL
    }

    private static func queryEscape(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func pathEscape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private static func sessionCookie(from response: HTTPURLResponse) -> HTTPCookie? {
        let fields = response.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            guard let key = pair.key as? String else { return }
            result[key] = String(describing: pair.value)
        }
        return HTTPCookie.cookies(withResponseHeaderFields: fields, for: Self.baseURL)
            .first { $0.name == "pear_session" && !$0.value.isEmpty }
    }

    // Non-throwing conveniences for concurrent loads where a failed surface
    // should simply come back empty.
    func homeFeedOrNil() async -> PearHomeFeed? {
        try? await self.homeFeed()
    }

    func briefingOrNil() async -> PearBriefing? {
        try? await self.briefing()
    }

    func statusDataOrNil() async -> PearStatusData? {
        try? await self.statusData()
    }

    func projectsOrNil() async -> [PearStatusData.Project]? {
        try? await self.projects()
    }

    func appsRegistryOrNil() async -> PearAppsRegistry? {
        try? await self.appsRegistry()
    }

    func conversationsOrNil() async -> [PearConversationSummary]? {
        try? await self.conversations()
    }

    static func parseISODate(_ raw: String) -> Date? {
        let withFractions = ISO8601DateFormatter()
        withFractions.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractions.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        return plain.date(from: raw)
    }
}

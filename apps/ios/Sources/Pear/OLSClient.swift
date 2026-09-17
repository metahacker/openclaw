import Foundation

/// Where a turn happened. The app is one surface among the person's others; the stream
/// interleaves them all and names the others only quietly.
enum OLSSurface: String, Sendable {
    case app, slack, dm, sendblue

    init(_ raw: String?) {
        self = raw.flatMap(OLSSurface.init(rawValue:)) ?? .app
    }

    /// `Slack`, `Messages` (the texting lane), nil for the app itself.
    var name: String? {
        switch self {
        case .app: nil
        case .slack, .dm: "Slack"
        case .sendblue: "Messages"
        }
    }

    var symbolName: String? {
        switch self {
        case .app: nil
        case .slack, .dm: "bubble.left"
        case .sendblue: "message"
        }
    }
}

struct OLSContext: Codable, Equatable, Identifiable, Sendable {
    /// The visible chronological run this turn belongs to (an entry in `segments`).
    var segmentId: String
    var projectId: Int?
    var slug: String?
    var label: String?
    var source: String?
    /// The backend resolved this context heuristically; the person may correct it.
    var provisional: Bool?
    /// The immutable stored attribution; returning to a subject opens a new run, not a new origin.
    var originSegmentId: String?
    var surface: String?

    var id: String {
        self.segmentId
    }

    var surfaceKind: OLSSurface {
        OLSSurface(self.surface)
    }

    /// `Japan family trip` when the project is known, otherwise the hashtag.
    var displayName: String {
        if let label, !label.trimmingCharacters(in: .whitespaces).isEmpty { return label }
        return self.hashtag
    }

    var hashtag: String {
        guard let slug, !slug.isEmpty else { return "Here with you" }
        return "#" + slug.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    }
}

struct OLSAttachment: Codable, Equatable, Identifiable, Sendable {
    var id: String?
    var url: String
    var name: String?
    var mimeType: String?

    var stableID: String {
        self.id ?? self.url
    }
}

/// How the shared router placed an app turn: stay in, resume, or open a working session.
struct OLSRouting: Codable, Equatable, Sendable {
    var decision: String?
    var trigger: String?
    var sessionRef: String?
}

struct OLSMessage: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var kind: String?
    var threadId: Int?
    var role: String
    var text: String
    var createdAt: String
    var context: OLSContext?
    var attachments: [OLSAttachment]?
    var surface: String?
    /// The runtime session the turn lives in: an epoch page for app turns, a thread ref elsewhere.
    var sessionRef: String?
    /// `accepted` · `queued` · `failed` · `delivery-unknown` · `delivered`.
    var dispatchState: String?
    var routing: OLSRouting?

    var isAssistant: Bool {
        self.role == "assistant" || self.role == "pear"
    }

    var isCommentary: Bool {
        self.kind == "commentary"
    }

    var surfaceKind: OLSSurface {
        OLSSurface(self.surface)
    }

    /// A turn the person typed here; only these can be corrected or retried from the app.
    var isAppTurn: Bool {
        !self.isAssistant && !self.isCommentary && self.surfaceKind == .app
    }

    /// Honest pending state: a queued turn is persisted and will go out when the lane frees.
    var isQueued: Bool {
        self.dispatchState == "queued"
    }

    var isFailed: Bool {
        self.dispatchState == "failed"
    }
}

struct OLSCommentary: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var text: String
    var createdAt: String
}

struct OLSProgressStatus: Codable, Equatable, Sendable {
    var context: OLSContext?
    var commentary: [OLSCommentary]
}

struct OLSProgressFeed: Codable, Equatable, Sendable {
    var statuses: [OLSProgressStatus]
}

/// One visible chronological run of turns inside a project on one page of the stream.
/// Returning to a subject opens a new run with the same project identity (contract 1424).
struct OLSSegment: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var projectId: Int?
    var slug: String?
    var label: String?
    var source: String?
    var provisional: Bool?
    var createdAt: String?
    var originSegmentId: String?
    var page: String?
    var surface: String?
    var firstMessageId: String?
    var lastMessageId: String?
    var count: Int?

    var context: OLSContext {
        OLSContext(
            segmentId: self.id,
            projectId: self.projectId,
            slug: self.slug,
            label: self.label,
            source: self.source,
            provisional: self.provisional,
            originSegmentId: self.originSegmentId,
            surface: self.surface)
    }

    var surfaceKind: OLSSurface {
        OLSSurface(self.surface)
    }
}

/// The display window the opening request covered; older history stays reachable by paging.
struct OLSWindow: Codable, Equatable, Sendable {
    var hours: Int
    var since: String?
    var until: String?
    var applied: Bool?
}

struct OLSTimeline: Codable, Sendable {
    var streamId: String
    var items: [OLSMessage]
    var beforeCursor: String?
    var hasMore: Bool
    var activeContext: OLSContext?
    var segments: [OLSSegment]?
    var status: String?
    var window: OLSWindow?
    var activePage: String?
}

struct OLSSendReceipt: Codable, Sendable {
    var ok: Bool
    var id: Int?
    var clientRequestId: String?
    var segmentId: String?
    var context: OLSContext?
    /// The working session the router chose (`pear:ols:v1:<stream>:c<n>`); `sessionRef` echoes it.
    var page: String?
    var sessionRef: String?
    var status: String?
    /// HTTP 202: the lane was busy, the turn is persisted and will dispatch through the queue.
    var queued: Bool?
    var routing: OLSRouting?
    var duplicate: Bool?
    var error: String?
}

protocol OLSService: Sendable {
    func timeline(before: String?) async throws -> OLSTimeline
    func progress() async throws -> OLSProgressFeed
    func send(text: String, requestID: String, projectID: Int?, attachments: [String]) async throws -> OLSSendReceipt
}

enum OLSError: LocalizedError {
    case signedOut
    case rejected(String)
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .signedOut: "Sign in to continue."
        case let .rejected(message): message
        case .invalidURL: "This link could not be opened."
        }
    }
}

/// Session-authenticated adapter over the existing Playground ledger/outbox.
/// Never sends cookies to an arbitrary artifact or redirect destination.
struct OLSClient: OLSService {
    static let baseURL = URL(string: "https://pear.metahack.io")!
    static var current: OLSClient {
        OLSClient()
    }

    func authenticatedRequest(for url: URL) throws -> URLRequest {
        guard url.scheme == "https" else { throw OLSError.invalidURL }
        var request = URLRequest(url: url)
        if url.host == Self.baseURL.host {
            guard let session = PearSessionStore.load() else { throw OLSError.signedOut }
            request.setValue("pear_session=\(session.sessionID)", forHTTPHeaderField: "Cookie")
        }
        return request
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration, delegate: OLSRedirectPolicy(), delegateQueue: nil)
    }()

    func timeline(before: String? = nil) async throws -> OLSTimeline {
        var components = URLComponents()
        components.path = "/api/ols"
        if let before { components.queryItems = [URLQueryItem(name: "before", value: before)] }
        return try await self.get(components.string ?? "/api/ols")
    }

    func progress() async throws -> OLSProgressFeed {
        try await self.get("/api/ols/progress")
    }

    func send(text: String, requestID: String, projectID: Int?, attachments: [String]) async throws -> OLSSendReceipt {
        struct Payload: Encodable {
            let text: String
            let clientRequestId: String
            let projectId: Int?
            let attachments: [String]
        }
        return try await self.post("/api/ols/send", body: Payload(
            text: text, clientRequestId: requestID, projectId: projectID, attachments: attachments))
    }

    func upload(_ url: URL) async throws -> OLSAttachment {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard (values.fileSize ?? 0) <= 20 * 1024 * 1024 else {
            throw OLSError.rejected("Choose a file smaller than 20 MB.")
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let boundary = "ols-" + UUID().uuidString
        var request = try self.request("/api/ols/upload")
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let name = url.lastPathComponent.replacingOccurrences(of: "\"", with: "_")
            .replacingOccurrences(of: "\r", with: "_").replacingOccurrences(of: "\n", with: "_")
        let header = "--\(boundary)\r\n"
            + "Content-Disposition: form-data; name=\"file\"; filename=\"\(name)\"\r\n"
            + "Content-Type: application/octet-stream\r\n\r\n"
        var body = Data(header.utf8)
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body
        return try await self.execute(request)
    }

    func get<T: Decodable>(_ path: String) async throws -> T {
        try await self.execute(self.request(path))
    }

    func post<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        var request = try self.request(path)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await self.execute(request)
    }

    private func request(_ path: String) throws -> URLRequest {
        guard path.hasPrefix("/api/ols"),
              let url = URL(string: path, relativeTo: Self.baseURL)?.absoluteURL,
              url.host == Self.baseURL.host, url.scheme == "https"
        else { throw OLSError.invalidURL }
        guard let session = PearSessionStore.load() else { throw OLSError.signedOut }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("pear_session=\(session.sessionID)", forHTTPHeaderField: "Cookie")
        return request
    }

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await Self.session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw OLSError.rejected("No reply yet. Try again.") }
        if response.statusCode == 401 || response.statusCode == 403 { throw OLSError.signedOut }
        guard (200...299).contains(response.statusCode) else {
            // Do not surface raw server responses, routes or credentials in product copy.
            throw OLSError.rejected("I couldn’t connect just now. Your words are still here.")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }
}

private final class OLSRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void)
    {
        guard request.url?.scheme == "https", request.url?.host == OLSClient.baseURL.host else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

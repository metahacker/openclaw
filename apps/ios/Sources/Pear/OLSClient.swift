import Foundation

struct OLSContext: Codable, Equatable, Identifiable, Sendable {
    var segmentId: String
    var projectId: Int?
    var slug: String?
    var label: String?
    var source: String?

    var id: String {
        self.segmentId
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

struct OLSMessage: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var kind: String?
    var threadId: Int?
    var role: String
    var text: String
    var createdAt: String
    var context: OLSContext?
    var attachments: [OLSAttachment]?

    var isAssistant: Bool {
        self.role == "assistant" || self.role == "pear"
    }
}

struct OLSTimeline: Codable, Sendable {
    var streamId: String
    var items: [OLSMessage]
    var beforeCursor: String?
    var hasMore: Bool
    var activeContext: OLSContext?
    var status: String?
}

struct OLSSendReceipt: Codable, Sendable {
    var ok: Bool
    var id: Int?
    var clientRequestId: String?
    var segmentId: String?
    var page: String?
    var status: String?
    var error: String?
}

protocol OLSService: Sendable {
    func timeline(before: String?) async throws -> OLSTimeline
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
        completionHandler: @escaping (URLRequest?) -> Void)
    {
        guard request.url?.scheme == "https", request.url?.host == OLSClient.baseURL.host else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

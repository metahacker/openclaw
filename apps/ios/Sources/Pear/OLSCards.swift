import QuickLook
import SwiftUI
import WebKit

/// Card primitives from Mark's screens: eyebrow kicker, serif title, optional rows, one pill action.
/// Built once here; every surface composes these instead of inventing its own card.
struct OLSCard<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        self.content
            .frame(maxWidth: .infinity, alignment: .leading)
            .olsCard(padding: self.padding)
    }
}

/// `CONTINUE` / `Pick up where we left off`: a kicker over a serif heading.
struct OLSSectionHeading: View {
    var kicker: String
    var title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            OLSKicker(text: self.kicker)
            Text(self.title)
                .font(OLSTheme.heading)
                .foregroundStyle(OLSTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle = self.subtitle, !subtitle.isEmpty {
                Text(subtitle).font(OLSTheme.label).foregroundStyle(OLSTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The one pill action at the foot of a card (`Open the trip ›`).
struct OLSPillAction: View {
    var title: String
    var filled = true
    var chevron = true
    var action: () -> Void

    var body: some View {
        Button(action: self.action) {
            HStack(spacing: 8) {
                Text(self.title).font(OLSTheme.action).lineLimit(1)
                if self.chevron {
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                }
            }
            .foregroundStyle(OLSTheme.ink)
            .padding(.horizontal, 16)
            .frame(maxWidth: self.chevron ? CGFloat.infinity : nil, minHeight: 44)
            .background(self.filled ? OLSTheme.human : OLSTheme.paper, in: Capsule())
            .overlay { Capsule().strokeBorder(self.filled ? Color.clear : OLSTheme.cardLine) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A checklist or fact row inside a card (`✓ Check-in moved to 3:00 PM`).
struct OLSCardRow: View {
    var symbol: String
    var text: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: self.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(OLSTheme.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(self.text).font(OLSTheme.label).foregroundStyle(OLSTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = self.detail, !detail.isEmpty {
                    Text(detail).font(OLSTheme.caption).foregroundStyle(OLSTheme.secondary)
                }
            }
        }
    }
}

/// The square tile that opens a card row: an emoji on the project's soft tint.
struct OLSEmojiTile: View {
    var emoji: String?
    var size: CGFloat = 44

    var body: some View {
        Text(self.emoji ?? "🍐")
            .font(.system(size: self.size * 0.5))
            .frame(width: self.size, height: self.size)
            .background(OLSTheme.human, in: RoundedRectangle(cornerRadius: self.size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A file or artifact carried by a message: eyebrow, serif title, one `Open` pill.
struct OLSAttachmentCard: View {
    var eyebrow: String
    var title: String
    var detail: String?
    var action: String
    var onOpen: () -> Void

    var body: some View {
        OLSCard {
            VStack(alignment: .leading, spacing: 12) {
                OLSKicker(text: self.eyebrow)
                Text(self.title)
                    .font(OLSTheme.cardTitle)
                    .foregroundStyle(OLSTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = self.detail, !detail.isEmpty {
                    Text(detail).font(OLSTheme.caption).foregroundStyle(OLSTheme.secondary)
                }
                OLSPillAction(title: self.action, action: self.onOpen)
            }
        }
    }
}

/// `I'M KEEPING THIS WITH / <project> / [Yes, keep it here] [Change context]`: shown only when
/// the backend resolved the latest turn heuristically. Keep dismisses; Change opens the picker.
struct OLSContextCheckCard: View {
    var context: OLSContext
    var project: PearStatusData.Project?
    var onKeep: () -> Void
    var onChange: () -> Void

    var body: some View {
        OLSCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    OLSEmojiTile(emoji: self.project?.emoji ?? "🍐", size: 48)
                    VStack(alignment: .leading, spacing: 5) {
                        OLSKicker(text: "I’m keeping this with")
                        Text(self.project?.name ?? self.context.displayName)
                            .font(OLSTheme.cardTitle)
                            .foregroundStyle(OLSTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(self.context.hashtag).font(OLSTheme.caption).foregroundStyle(OLSTheme.secondary)
                    }
                }
                HStack(spacing: 10) {
                    OLSPillAction(title: "Yes, keep it here", chevron: false, action: self.onKeep)
                        .accessibilityIdentifier("ols.context-check.keep")
                    OLSPillAction(title: "Change context", filled: false, chevron: false, action: self.onChange)
                        .accessibilityIdentifier("ols.context-check.change")
                }
            }
        }
        .accessibilityIdentifier("ols.context-check")
    }
}

/// A conversation or continue row: project eyebrow, serif title, one-line detail, chevron.
struct OLSConversationRow: View {
    var emoji: String?
    var eyebrow: String
    var title: String
    var detail: String?
    var trailing: String?
    var onOpen: () -> Void

    var body: some View {
        Button(action: self.onOpen) {
            HStack(alignment: .top, spacing: 14) {
                OLSEmojiTile(emoji: self.emoji)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        OLSKicker(text: self.eyebrow).lineLimit(1)
                        Spacer(minLength: 8)
                        if let trailing = self.trailing {
                            Text(trailing).font(OLSTheme.caption).foregroundStyle(OLSTheme.secondary)
                        }
                    }
                    Text(self.title)
                        .font(OLSTheme.rowTitle)
                        .foregroundStyle(OLSTheme.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = self.detail, !detail.isEmpty {
                        Text(detail)
                            .font(OLSTheme.caption)
                            .foregroundStyle(OLSTheme.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OLSTheme.secondary)
                    .padding(.top, 14)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OLSTheme.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(OLSTheme.cardLine) }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Project tile for the Details grid: category eyebrow, serif name, summary, on a soft tint.
struct OLSProjectTile: View {
    var project: PearStatusData.Project
    var onOpen: () -> Void

    var body: some View {
        Button(action: self.onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    OLSKicker(text: self.project.category ?? "Project").lineLimit(1)
                    Spacer(minLength: 4)
                    Text(self.project.emoji ?? "🍐").font(.system(size: 18)).accessibilityHidden(true)
                }
                Text(self.project.name)
                    .font(OLSTheme.cardTitle)
                    .foregroundStyle(OLSTheme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let summary = self.project.bestSummary, !summary.isEmpty {
                    Text(OLSProjectTile.plain(summary))
                        .font(OLSTheme.caption)
                        .foregroundStyle(OLSTheme.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                if let date = self.project.updatedDate {
                    Text("Updated \(date, style: .relative) ago")
                        .font(OLSTheme.timestamp)
                        .foregroundStyle(OLSTheme.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(OLSTheme.human, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Open project")
    }

    static func plain(_ value: String) -> String {
        // The collapsed summary is plain reading text, never a chopped Markdown link.
        let attributed = try? AttributedString(markdown: value)
        return attributed.map { String($0.characters) } ?? value
    }
}

struct OLSEmptyState: View {
    var title: String
    var message: String
    var symbol = "leaf"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: self.symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(OLSTheme.accent)
                .accessibilityHidden(true)
            Text(self.title).font(OLSTheme.heading).foregroundStyle(OLSTheme.ink)
            Text(self.message).font(OLSTheme.body).foregroundStyle(OLSTheme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
    }
}

/// A private project artifact opens with a host-scoped session cookie. The cookie
/// is never embedded in a URL or manually attached to requests to other domains.
struct OLSArtifactView: View {
    let url: URL
    let title: String
    let onClose: () -> Void
    @State private var error: String?
    @State private var attempt = 0
    @State private var downloaded: URL?
    @State private var preview: OLSLocalPreview?
    @State private var downloading = false
    @State private var downloadError: String?
    @State private var downloadTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    self.downloadTask?.cancel()
                    self.onClose()
                } label: {
                    Label {
                        Text("Back").font(OLSTheme.label)
                    } icon: {
                        Image(systemName: "chevron.left")
                    }
                    .frame(minWidth: 44, minHeight: 44)
                }
                Text(self.title)
                    .font(OLSTheme.label)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    self.downloadTask = Task { await self.download() }
                } label: {
                    if self.downloading {
                        ProgressView().tint(OLSTheme.accent).frame(width: 44, height: 44)
                    } else {
                        Image(systemName: "arrow.down.to.line").frame(width: 44, height: 44)
                    }
                }
                .disabled(self.downloading)
                .accessibilityLabel(self.downloading ? "Downloading file" : "Download file")
                ShareLink(item: self.downloaded ?? self.url) {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(self.downloaded == nil ? "Share link" : "Share file")
            }
            .foregroundStyle(OLSTheme.ink)
            .padding(.horizontal, 12)
            .background(OLSTheme.background)
            if let downloadError = self.downloadError {
                HStack(alignment: .top, spacing: 12) {
                    Text(downloadError).font(OLSTheme.label).foregroundStyle(OLSTheme.secondary)
                    Spacer()
                    Button {
                        self.downloadTask = Task { await self.download() }
                    } label: {
                        Text("Retry").font(OLSTheme.label).frame(minHeight: 44)
                    }
                    .disabled(self.downloading)
                    .foregroundStyle(OLSTheme.accent)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(OLSTheme.soft)
            }
            ZStack {
                OLSArtifactWebView(url: self.url, error: self.$error).id(self.attempt)
                if let error = self.error {
                    VStack(alignment: .leading, spacing: 18) {
                        OLSEmptyState(title: "This hasn’t opened yet.", message: error, symbol: "doc")
                        Button {
                            self.error = nil
                            self.attempt += 1
                        } label: {
                            Text("Try again").font(OLSTheme.label).frame(minHeight: 44)
                        }
                        .foregroundStyle(OLSTheme.accent)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(OLSTheme.background)
                }
            }
        }
        .background(OLSTheme.background)
        .sheet(item: self.$preview) { item in
            OLSQuickLook(url: item.url)
        }
        .onDisappear {
            self.downloadTask?.cancel()
            if let downloaded = self.downloaded {
                try? FileManager.default.removeItem(at: downloaded.deletingLastPathComponent())
            }
        }
    }

    @MainActor
    private func download() async {
        if let downloaded = self.downloaded {
            self.preview = OLSLocalPreview(url: downloaded)
            return
        }
        guard !self.downloading else { return }
        self.downloading = true
        self.downloadError = nil
        defer { self.downloading = false }
        do {
            let file = try await OLSArtifactDownload.fetch(self.url, title: self.title)
            if Task.isCancelled {
                try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
                return
            }
            self.downloaded = file
            self.preview = OLSLocalPreview(url: file)
        } catch is CancellationError {
            return
        } catch {
            self.downloadError = "The file didn’t download. Try again when you’re ready."
        }
    }
}

private struct OLSArtifactWebView: UIViewRepresentable {
    let url: URL
    @Binding var error: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(error: self.$error)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        guard let safeURL = Self.safeURL(self.url) else {
            self.error = "The file link isn’t available."
            return webView
        }
        if safeURL.host?.lowercased() == PearAPI.baseURL.host?.lowercased(),
           let session = PearSessionStore.load(),
           let cookie = HTTPCookie(properties: [
               .domain: PearAPI.baseURL.host ?? "pear.metahack.io",
               .path: "/",
               .name: "pear_session",
               .value: session.sessionID,
               .secure: "TRUE",
               HTTPCookiePropertyKey("HttpOnly"): "TRUE",
           ])
        {
            webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) { [weak webView] in
                webView?.load(URLRequest(url: safeURL))
            }
        } else {
            webView.load(URLRequest(url: safeURL))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    nonisolated static func safeURL(_ url: URL) -> URL? {
        guard url.scheme?.lowercased() == "https", url.host != nil,
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var error: Binding<String?>

        init(error: Binding<String?>) {
            self.error = error
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void)
        {
            guard let url = navigationAction.request.url, Self.allowed(url) else {
                decisionHandler(.cancel)
                return
            }
            if url.host?.lowercased() != PearAPI.baseURL.host?.lowercased(),
               navigationAction.navigationType == .linkActivated
            {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void)
        {
            if let response = navigationResponse.response as? HTTPURLResponse, response.statusCode >= 400 {
                self.error.wrappedValue = response.statusCode == 401 || response.statusCode == 403
                    ? "This file needs access. Return to chat to check your connection."
                    : "The file couldn’t be reached. You can try again or return to the project."
                decisionHandler(.cancel)
            } else if !navigationResponse.canShowMIMEType {
                self.error.wrappedValue = "Download this file to open it in the preview or share it with another app."
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error)
        {
            self.failed(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            self.failed(error)
        }

        private func failed(_ error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            self.error.wrappedValue = "The connection was interrupted. Try again when you’re ready."
        }

        private static func allowed(_ url: URL) -> Bool {
            OLSArtifactWebView.safeURL(url) != nil || url.absoluteString == "about:blank"
        }
    }
}

private struct OLSLocalPreview: Identifiable {
    var url: URL
    var id: String {
        self.url.path
    }
}

private struct OLSQuickLook: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: self.url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
            self.url as NSURL
        }
    }
}

private enum OLSArtifactDownload {
    static func fetch(_ url: URL, title: String) async throws -> URL {
        guard let url = OLSArtifactWebView.safeURL(url) else { throw OLSError.invalidURL }
        var request = URLRequest(url: url)
        if url.host?.lowercased() == OLSClient.baseURL.host?.lowercased() {
            guard let session = PearSessionStore.load() else { throw OLSError.signedOut }
            request.setValue("pear_session=\(session.sessionID)", forHTTPHeaderField: "Cookie")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 180
        let session = URLSession(
            configuration: configuration,
            delegate: OLSArtifactRedirectPolicy(),
            delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (temporaryURL, response) = try await session.download(for: request)
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw OLSError.rejected("The file could not be downloaded.")
        }
        if Task.isCancelled {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw CancellationError()
        }
        let rawName = response.suggestedFilename ?? url.lastPathComponent.nonEmpty ?? title
        let name = Self.filename(rawName)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pear-ols-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.protectionKey: FileProtectionType.complete, .posixPermissions: 0o700])
        let destination = directory.appendingPathComponent(name)
        do {
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete, .posixPermissions: 0o600],
                ofItemAtPath: destination.path)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private static func filename(_ raw: String) -> String {
        let last = (raw as NSString).lastPathComponent
        let cleaned = String(last.map { character -> Character in
            character.isLetter || character.isNumber || " ._-".contains(character) ? character : "_"
        }.prefix(160)).trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return cleaned.isEmpty ? "File" : cleaned
    }
}

private final class OLSArtifactRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void)
    {
        guard let url = request.url, url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil
        else {
            completionHandler(nil)
            return
        }
        var redirected = request
        // URLSession may carry an explicitly set header across a redirect. App
        // credentials must never accompany an external storage/CDN destination.
        if url.host?.lowercased() != OLSClient.baseURL.host?.lowercased() {
            redirected.setValue(nil, forHTTPHeaderField: "Cookie")
            redirected.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        completionHandler(redirected)
    }
}

extension String {
    fileprivate var nonEmpty: String? {
        self.isEmpty ? nil : self
    }
}

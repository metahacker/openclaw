import QuickLook
import SwiftUI
import WebKit

/// Card primitives ported from the prototype: the thread project object, the quick-check
/// card, project cards, and notices. Built once; every surface composes these.
struct OLSCard<Content: View>: View {
    var padding: CGFloat = 16
    var fill: Color = OLSTheme.paper
    @ViewBuilder var content: Content

    var body: some View {
        self.content
            .frame(maxWidth: .infinity, alignment: .leading)
            .olsCard(padding: self.padding, fill: self.fill)
    }
}

/// Kicker over a serif heading (`FILES` / `Everything we're carrying`).
struct OLSSectionHeading: View {
    var kicker: String
    var title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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

/// The prototype's pill button: dark filled (`Sign in`, `Send`) or white outlined (`Voice`).
struct OLSPillAction: View {
    var title: String
    var filled = true
    var chevron = false
    var symbol: String?
    var action: () -> Void

    var body: some View {
        Button(action: self.action) {
            HStack(spacing: 7) {
                if let symbol { Image(systemName: symbol).font(.system(size: 14, weight: .semibold)) }
                Text(self.title).font(OLSTheme.labelStrong).lineLimit(1)
                if self.chevron {
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                }
            }
            .foregroundStyle(self.filled ? OLSTheme.signInInk : OLSTheme.ink)
            .padding(.horizontal, 16)
            .frame(maxWidth: self.chevron ? CGFloat.infinity : nil, minHeight: 44)
            .background(self.filled ? OLSTheme.signIn : OLSTheme.paper, in: Capsule())
            .overlay { Capsule().strokeBorder(self.filled ? Color.clear : OLSTheme.spineLine) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A checklist or fact row inside a card.
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

/// The `.object-image` slot when a project has no picture: its emoji on the playground tint.
struct OLSEmojiTile: View {
    var emoji: String?
    var size: CGFloat = 44

    var body: some View {
        Text(self.emoji ?? "🍐")
            .font(.system(size: self.size * 0.48))
            .frame(width: self.size, height: self.size)
            .background(OLSTheme.tint, in: RoundedRectangle(cornerRadius: self.size * 0.21, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A file carried by a message, in the object-card language: eyebrow, serif title, `Open`.
struct OLSAttachmentCard: View {
    var eyebrow: String
    var title: String
    var detail: String?
    var onOpen: () -> Void

    var body: some View {
        Button(action: self.onOpen) {
            HStack(spacing: 12) {
                Image(systemName: "doc")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(OLSTheme.ink)
                    .frame(width: 52, height: 52)
                    .background(OLSTheme.tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    OLSKicker(text: self.eyebrow).lineLimit(1)
                    Text(self.title).font(OLSTheme.rowTitle).foregroundStyle(OLSTheme.ink).lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let detail = self.detail, !detail.isEmpty {
                        Text(detail).font(OLSTheme.caption).foregroundStyle(OLSTheme.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .medium))
                    .foregroundStyle(OLSTheme.ink).accessibilityHidden(true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .olsCard(padding: 0)
        .accessibilityHint("Open attachment")
    }
}

/// `.context-check-card`: `QUICK CHECK / Which work did you mean?` Shown only when the backend
/// resolved the latest turn heuristically. Keep dismisses it; Change opens the picker.
struct OLSContextCheckCard: View {
    var context: OLSContext
    var project: PearStatusData.Project?
    var onKeep: () -> Void
    var onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                OLSKicker(text: "Quick check", tracking: 2)
                Text("Which work did you mean?")
                    .font(OLSTheme.cardTitle)
                    .foregroundStyle(OLSTheme.ink)
                Text("I’m keeping this with \(self.project?.name ?? self.context.displayName).")
                    .font(OLSTheme.caption)
                    .foregroundStyle(OLSTheme.secondary)
                    .padding(.bottom, 8)
            }
            self.option(
                title: "Yes, keep it here",
                detail: "Continue in \(self.project?.name ?? self.context.displayName)",
                symbol: "checkmark",
                identifier: "ols.context-check.keep",
                action: self.onKeep)
            self.option(
                title: "Change context",
                detail: "Pick another project for this turn",
                symbol: "chevron.right",
                identifier: "ols.context-check.change",
                action: self.onChange)
        }
        .padding(EdgeInsets(top: 17, leading: 17, bottom: 8, trailing: 17))
        .background(OLSTheme.checkCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(OLSTheme.hairline) }
        .shadow(color: OLSTheme.cardShadow, radius: 14, y: 12)
        .accessibilityIdentifier("ols.context-check")
    }

    private func option(
        title: String,
        detail: String,
        symbol: String,
        identifier: String,
        action: @escaping () -> Void) -> some View
    {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(OLSTheme.labelStrong).foregroundStyle(OLSTheme.ink)
                    Text(detail).font(OLSTheme.caption).foregroundStyle(OLSTheme.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(OLSTheme.ink)
            }
            .frame(maxWidth: .infinity, minHeight: 53, alignment: .leading)
            .overlay(alignment: .top) { OLSTheme.hairline.frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

/// A conversation row: project eyebrow, serif title, one-line detail, chevron.
struct OLSConversationRow: View {
    var emoji: String?
    var eyebrow: String
    var title: String
    var detail: String?
    var trailing: String?
    var onOpen: () -> Void

    var body: some View {
        Button(action: self.onOpen) {
            HStack(alignment: .top, spacing: 12) {
                OLSEmojiTile(emoji: self.emoji, size: 44)
                VStack(alignment: .leading, spacing: 3) {
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
                        .lineLimit(2)
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
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OLSTheme.projectCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(OLSTheme.projectCardLine) }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// `.project-card`: visual area on top, copy below (eyebrow, serif name, detail, time).
struct OLSProjectCardTile: View {
    var project: PearStatusData.Project
    var onOpen: () -> Void

    var body: some View {
        Button(action: self.onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                Text(self.project.emoji ?? "🍐")
                    .font(.system(size: 34))
                    .frame(maxWidth: .infinity, minHeight: 78)
                    .background(OLSTheme.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    OLSKicker(text: self.project.category ?? "Project").lineLimit(1)
                    Text(self.project.name)
                        .font(OLSTheme.cardTitle)
                        .foregroundStyle(OLSTheme.ink)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    if let summary = self.project.bestSummary, !summary.isEmpty {
                        Text(OLSPlainText.plain(summary))
                            .font(OLSTheme.detail)
                            .foregroundStyle(OLSTheme.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 6)
                    if let date = self.project.updatedDate {
                        Text("\(date, style: .relative) ago").font(OLSTheme.caption).foregroundStyle(OLSTheme.secondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 190, alignment: .top)
            .background(OLSTheme.projectCard)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(OLSTheme.projectCardLine) }
            .shadow(color: OLSTheme.cardShadow.opacity(0.6), radius: 12, y: 8)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Open project")
    }
}

/// `.active-project`: the most recently touched project as a tall hero card.
struct OLSFeaturedProjectCard: View {
    var project: PearStatusData.Project
    var decision: OLSProjectDetail.Work?
    var onOpen: () -> Void

    var body: some View {
        Button(action: self.onOpen) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [OLSTheme.tint, OLSTheme.spine, OLSTheme.edge],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing)
                Text(self.project.emoji ?? "🍐")
                    .font(.system(size: 110))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(y: -30)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        OLSKicker(text: self.project.category ?? "Project", color: OLSTheme.ink.opacity(0.7))
                        Spacer()
                        if self.decision != nil {
                            HStack(spacing: 5) {
                                Image(systemName: "exclamationmark.circle").font(.system(size: 12, weight: .semibold))
                                OLSKicker(text: "Decision open", color: OLSTheme.decisionInk, tracking: 0.8)
                            }
                            .foregroundStyle(OLSTheme.decisionInk)
                            .padding(.horizontal, 10).frame(minHeight: 30)
                            .background(Color(red: 1, green: 237 / 255, blue: 158 / 255), in: Capsule())
                        }
                    }
                    Spacer()
                    if let date = self.project.updatedDate {
                        Text("Updated \(date, style: .relative) ago")
                            .font(OLSTheme.kicker).tracking(1.6).textCase(.uppercase)
                            .foregroundStyle(OLSTheme.ink.opacity(0.7))
                    }
                    Text(self.project.name)
                        .font(OLSTheme.hero)
                        .foregroundStyle(OLSTheme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 6)
                    if let summary = self.project.bestSummary, !summary.isEmpty {
                        Text(OLSPlainText.plain(summary))
                            .font(OLSTheme.label)
                            .foregroundStyle(OLSTheme.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .padding(.top, 6)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(OLSTheme.ink)
                    .frame(width: 44, height: 44)
                    .background(OLSTheme.paper.opacity(0.7), in: Circle())
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .bottomTrailing)
                    .accessibilityHidden(true)
            }
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: OLSTheme.cardShadow, radius: 15, y: 12)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Open project")
    }
}

/// `.live-thread-notice`: a calm card with a kicker, serif line, sentence, and one pill.
struct OLSNotice: View {
    var kicker: String
    var title: String
    var message: String
    var action: String?
    var onAction: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            OLSKicker(text: self.kicker, tracking: 1.8)
            Text(self.title).font(OLSTheme.cardTitle).foregroundStyle(OLSTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(self.message).font(OLSTheme.label).foregroundStyle(OLSTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let action = self.action {
                OLSPillAction(title: action, action: self.onAction).padding(.top, 10)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OLSTheme.paper.opacity(0.86), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(OLSTheme.hairline) }
        .shadow(color: OLSTheme.cardShadow.opacity(0.5), radius: 20, y: 14)
    }
}

enum OLSPlainText {
    /// The collapsed summary is plain reading text, never a chopped Markdown link.
    static func plain(_ value: String) -> String {
        let attributed = try? AttributedString(markdown: value)
        return attributed.map { String($0.characters) } ?? value
    }

    /// First sentence, for one-line card details.
    static func firstSentence(_ value: String) -> String {
        let plain = self.plain(value).trimmingCharacters(in: .whitespacesAndNewlines)
        let line = plain.split(whereSeparator: { $0 == "\n" }).first.map(String.init) ?? plain
        let sentence = line.components(separatedBy: ". ").first ?? line
        return sentence.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
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
            .background(OLSTheme.field)
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
                .background(OLSTheme.spine)
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
                    .background(OLSTheme.field)
                }
            }
        }
        .background(OLSTheme.field)
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

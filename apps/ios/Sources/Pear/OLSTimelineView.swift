import SwiftUI
import UniformTypeIdentifiers

/// One continuous conversation: older history above, Mark's present block (date, greeting,
/// summary) at the top of today, inline small-caps anchors wherever the context changes.
struct OLSTimelineView: View {
    @Bindable var model: OLSModel
    let projects: [PearStatusData.Project]
    let openContext: () -> Void
    let openDetails: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var composerFocused = false
    @State private var artifact: OLSArtifact?
    @State private var width: CGFloat = 390
    @State private var anchorJumps = 0

    /// Horizontal anchor swipes: deliberate and axis-dominant, never while editing.
    private static let swipeDistance: CGFloat = 72
    private static let swipeDominance: CGFloat = 1.4

    private enum Entry: Identifiable {
        case present
        case message(OLSMessage, label: String?, anchor: Bool)

        var id: String {
            switch self {
            case .present: OLSModel.presentID
            case let .message(message, _, _): message.id
            }
        }
    }

    private var entries: [Entry] {
        var entries: [Entry] = []
        let present = self.model.presentMessageID
        var previousSegment: String?
        var previousPeriod: String?
        for message in self.model.messages {
            if message.id == present { entries.append(.present) }
            let period = self.model.periodLabel(for: message)
            let segment = message.context?.segmentId
            let contextChanged = segment != nil && segment != previousSegment
            let periodChanged = period != nil && period != previousPeriod
            var label: String?
            if contextChanged, let context = message.context {
                label = periodChanged ? "\(context.displayName) · \(period ?? "")" : context.displayName
            } else if periodChanged {
                label = period
            }
            entries.append(.message(message, label: label, anchor: contextChanged))
            if segment != nil { previousSegment = segment }
            if period != nil { previousPeriod = period }
        }
        if present == nil { entries.append(.present) }
        return entries
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    // Not lazy: a lazy stack's estimated content frame changes with the scroll
                    // offset, and the scroll view re-aligns its offset to that frame on every
                    // pass. A page of messages is small enough to lay out eagerly.
                    VStack(alignment: .leading, spacing: 14) {
                        if self.model.hasMore {
                            Button {
                                Task { await self.model.loadEarlier() }
                            } label: {
                                OLSKicker(text: self.model.isPaging ? "Loading…" : "Earlier in our conversation")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .disabled(self.model.isPaging)
                            .accessibilityIdentifier("ols.earlier")
                        }
                        ForEach(self.entries) { entry in
                            switch entry {
                            case .present:
                                self.presentBlock
                            case let .message(message, label, anchor):
                                VStack(alignment: .leading, spacing: 16) {
                                    if let label { self.sectionLabel(label, message: message, anchor: anchor) }
                                    if message.isCommentary {
                                        self.commentary(message)
                                    } else {
                                        self.bubble(message)
                                    }
                                }
                            }
                        }
                        if let check = self.model.contextCheck {
                            OLSContextCheckCard(
                                context: check,
                                project: self.projects.first(where: { $0.id == check.projectId }),
                                onKeep: { self.model.dismissContextCheck() },
                                onChange: self.openContext)
                        }
                        Color.clear.frame(height: 1).id("ols-bottom")
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                    .frame(maxWidth: 700)
                    .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("ols.timeline")
                .scrollDismissesKeyboard(.interactively)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { self.width = $0 }
                .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.3) { ids in
                    guard let first = ids.first(where: { $0 != "ols-bottom" && $0 != OLSModel.presentID })
                    else { return }
                    if self.model.visibleMessageID != first { self.model.visibleMessageID = first }
                }
                .onAppear { self.applyScrollRequest(proxy) }
                .onChange(of: self.model.scrollRequest) { _, _ in self.applyScrollRequest(proxy) }
                .onChange(of: self.model.messages.count) { _, _ in self.applyScrollRequest(proxy) }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentSize.height - (geometry.contentOffset.y + geometry.containerSize.height)
                } action: { _, distance in
                    // Hysteresis: a few points of keyboard-layout wobble must not toggle state.
                    let atPresent = distance <= (self.model.isAtPresent ? 160 : 60)
                    if self.model.isAtPresent != atPresent { self.model.isAtPresent = atPresent }
                }
                .onChange(of: self.model.messages.last) { previous, _ in
                    // The first page lands on Mark's first viewport; later arrivals follow the present.
                    guard previous != nil, self.model.isAtPresent else { return }
                    withAnimation(self.reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        proxy.scrollTo("ols-bottom", anchor: .bottom)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !self.model.isAtPresent, !self.model.messages.isEmpty {
                        Button {
                            self.model.isAtPresent = true
                            withAnimation(self.reduceMotion ? nil : .easeOut(duration: 0.2)) {
                                proxy.scrollTo("ols-bottom", anchor: .bottom)
                            }
                        } label: {
                            Label { Text("Present").font(OLSTheme.action) } icon: { Image(systemName: "arrow.down") }
                                .foregroundStyle(OLSTheme.ink)
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(OLSTheme.paper, in: Capsule())
                                .overlay { Capsule().strokeBorder(OLSTheme.cardLine) }
                        }
                        .accessibilityIdentifier("ols.present")
                        .padding(14)
                    }
                }
                .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { value in
                    guard !self.composerFocused else { return }
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) >= Self.swipeDistance, abs(dx) >= abs(dy) * Self.swipeDominance else { return }
                    // Left carries the conversation forward to the next anchor; right returns to the previous one.
                    let target = dx < 0 ? self.model.nextAnchor() : self.model.previousAnchor()
                    guard let target else { return }
                    self.anchorJumps += 1
                    self.model.jump(to: target)
                })
                .sensoryFeedback(.impact(weight: .light), trigger: self.anchorJumps)
            }
            self.detailsGrabber
            OLSComposer(model: self.model, projects: self.projects, openContext: self.openContext) {
                self.composerFocused = $0
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .frame(maxWidth: 740)
        }
        .sheet(item: self.$artifact) { artifact in
            OLSArtifactView(url: artifact.url, title: artifact.title, onClose: { self.artifact = nil })
        }
    }

    /// Requests wait until the message is loaded; pagination may deliver it later.
    private func applyScrollRequest(_ proxy: ScrollViewProxy) {
        guard let request = self.model.scrollRequest else { return }
        let isPresent = request.messageID == OLSModel.presentID
        guard isPresent || self.model.messages.contains(where: { $0.id == request.messageID }) else { return }
        if isPresent, self.model.isLoading, self.model.messages.isEmpty { return }
        withAnimation(self.reduceMotion || isPresent ? nil : .spring(response: 0.4, dampingFraction: 0.85)) {
            proxy.scrollTo(request.messageID, anchor: .top)
        }
        self.model.completeScrollRequest(request)
    }

    private var presentBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            OLSKicker(text: self.model.dateKicker)
                .padding(.top, 16)
            Text(self.model.greeting)
                .font(OLSTheme.greeting)
                .foregroundStyle(OLSTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("ols.greeting")
            Text(OLSModel.summaryLine(projects: self.projects))
                .font(OLSTheme.body)
                .foregroundStyle(OLSTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if self.model.messages.isEmpty {
                Text(self.model.isLoading ? "Bringing our conversation back…" : "What’s on your mind?")
                    .font(OLSTheme.body).foregroundStyle(OLSTheme.secondary)
                if let error = self.model.error {
                    Text(error).font(OLSTheme.caption).foregroundStyle(OLSTheme.warning)
                    Button { Task { await self.model.refresh() } } label: {
                        Text("Try again").font(OLSTheme.action).frame(minHeight: 44)
                    }
                }
            }
            OLSTheme.line.frame(height: 1).padding(.top, 10)
        }
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(OLSModel.presentID)
    }

    /// `JAPAN FAMILY TRIP · THIS MORNING`: the inline anchor that scrolls with the messages.
    @ViewBuilder
    private func sectionLabel(_ text: String, message: OLSMessage, anchor: Bool) -> some View {
        if anchor, let context = message.context {
            Button(action: self.openContext) {
                OLSKicker(text: text)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityIdentifier("ols.anchor.\(context.segmentId)")
            .accessibilityLabel("\(context.displayName). Context and places in our conversation")
            .padding(.top, 6)
        } else {
            OLSKicker(text: text)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 32)
                .padding(.top, 6)
        }
    }

    private func bubble(_ message: OLSMessage) -> some View {
        let human = !message.isAssistant
        let maxWidth = min(560, self.width * 0.78)
        return VStack(alignment: human ? .trailing : .leading, spacing: 12) {
            HStack(spacing: 0) {
                if human { Spacer(minLength: 0) }
                VStack(alignment: .leading, spacing: 8) {
                    Text((try? AttributedString(markdown: message.text)) ?? AttributedString(message.text))
                        .font(OLSTheme.body)
                        .foregroundStyle(OLSTheme.ink)
                        .tint(OLSTheme.accent)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    if let date = PearAPI.parseISODate(message.createdAt) {
                        Text(date, format: .dateTime.hour().minute())
                            .font(OLSTheme.timestamp)
                            .foregroundStyle(OLSTheme.secondary)
                            .accessibilityLabel(date.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 14)
                .background(
                    human ? OLSTheme.human : OLSTheme.paper,
                    in: UnevenRoundedRectangle(
                        topLeadingRadius: 22,
                        bottomLeadingRadius: human ? 22 : 6,
                        bottomTrailingRadius: human ? 6 : 22,
                        topTrailingRadius: 22,
                        style: .continuous))
                .overlay {
                    if !human {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 22, bottomLeadingRadius: 6, bottomTrailingRadius: 22,
                            topTrailingRadius: 22, style: .continuous)
                            .strokeBorder(OLSTheme.cardLine, lineWidth: 1)
                    }
                }
                .frame(maxWidth: maxWidth, alignment: .leading)
                if !human { Spacer(minLength: 0) }
            }
            ForEach(message.attachments ?? [], id: \.stableID) { attachment in
                if let url = PearAPI.absoluteURL(attachment.url), url.scheme == "https" {
                    OLSAttachmentCard(
                        eyebrow: [message.context?.displayName, "Attachment"].compactMap { $0 }.joined(separator: " · "),
                        title: attachment.name ?? "Attachment",
                        detail: attachment.mimeType,
                        action: "Open")
                    {
                        self.artifact = OLSArtifact(url: url, title: attachment.name ?? "Attachment")
                    }
                    .frame(maxWidth: maxWidth)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: human ? .trailing : .leading)
    }

    private func commentary(_ message: OLSMessage) -> some View {
        HStack {
            Text(Self.parenthesizedCommentary(message.text))
                .font(OLSTheme.label)
                .foregroundStyle(OLSTheme.secondary)
                .italic()
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("PEAR update: \(message.text)")
                .accessibilityIdentifier("ols.commentary.\(message.id)")
            Spacer(minLength: 36)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private static func parenthesizedCommentary(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("("), trimmed.hasSuffix(")") { return trimmed }
        return "(\(trimmed))"
    }

    /// The explicit Details affordance: a thin grabber above the composer. Tap or pull up.
    /// It is the only bottom control, so it can never collide with the timeline's gestures.
    private var detailsGrabber: some View {
        Button(action: self.openDetails) {
            VStack(spacing: 5) {
                Capsule().fill(OLSTheme.line).frame(width: 36, height: 5)
                Text("DETAILS")
                    .font(Font.custom("Inter", size: 10, relativeTo: .caption2).weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(OLSTheme.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ols.details")
        .accessibilityLabel("Details")
        .accessibilityHint("Continue, conversations, and projects")
        .simultaneousGesture(DragGesture(minimumDistance: 20).onEnded { value in
            if value.translation.height < -40, abs(value.translation.height) > abs(value.translation.width) {
                self.openDetails()
            }
        })
    }
}

struct OLSArtifact: Identifiable {
    let url: URL
    let title: String
    var id: String {
        self.url.absoluteString
    }
}

/// Mark's composer: one white pill, `+` for files, a small lime up-arrow to send.
struct OLSComposer: View {
    @Bindable var model: OLSModel
    let projects: [PearStatusData.Project]
    let openContext: () -> Void
    var onFocusChange: (Bool) -> Void = { _ in }
    @State private var showImporter = false
    @State private var uploading = false
    @State private var uploadError: String?

    private var canSend: Bool {
        !(self.model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && self.model.attachments.isEmpty)
            && !self.model.isSending && !self.uploading
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(self.model.attachments, id: \.stableID) { attachment in
                HStack(spacing: 8) {
                    Image(systemName: "doc").foregroundStyle(OLSTheme.secondary)
                    Text(attachment.name ?? "Attachment").font(OLSTheme.caption).lineLimit(1)
                    Button { self.model.attachments.removeAll { $0.stableID == attachment.stableID } } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(OLSTheme.secondary)
                    }.accessibilityLabel("Remove attachment")
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(OLSTheme.paper, in: Capsule())
            }
            if let uploadError { Text(uploadError).font(OLSTheme.caption).foregroundStyle(OLSTheme.warning) }
            if let selected = self.projects.first(where: { $0.id == self.model.selectedProjectID }) {
                Button(action: self.openContext) {
                    OLSKicker(text: "Talking about \(selected.name)", color: OLSTheme.accent)
                }
                .accessibilityIdentifier("ols.talking-about")
            }
            HStack(alignment: .center, spacing: 6) {
                Button { self.showImporter = true } label: {
                    Image(systemName: self.uploading ? "hourglass" : "plus")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(OLSTheme.secondary)
                        .frame(width: 40, height: 44)
                }
                .accessibilityLabel("Add a file")
                .disabled(self.uploading)
                ZStack(alignment: .leading) {
                    if self.model.draft.isEmpty {
                        Text("Type a message…")
                            .font(OLSTheme.body)
                            .foregroundStyle(OLSTheme.secondary)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    OLSTextView(
                        text: self.$model.draft,
                        minLines: 1,
                        maxLines: 5,
                        accessibilityLabel: "Message",
                        accessibilityIdentifier: "ols.composer",
                        onFocusChange: self.onFocusChange)
                }
                .padding(.vertical, 11)
                Button {
                    Task { await self.model.send() }
                } label: {
                    Image(systemName: self.model.isSending ? "ellipsis" : "arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(OLSTheme.sendArrow)
                        .frame(width: 36, height: 36)
                        .background(OLSTheme.human, in: Circle())
                        .opacity(self.canSend ? 1 : 0.45)
                        .frame(width: 44, height: 44)
                }
                .disabled(!self.canSend)
                .accessibilityLabel(self.model.isSending ? "Sending" : "Send")
                .accessibilityIdentifier("ols.send")
            }
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .padding(.vertical, 2)
            .background(OLSTheme.paper, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(OLSTheme.cardLine) }
            if let status = self.model.sendStatus ?? self.model.error {
                Text(status).font(OLSTheme.caption).foregroundStyle(OLSTheme.secondary)
                    .padding(.leading, 16)
                    .accessibilityIdentifier("ols.send-status")
            }
        }
        .fileImporter(
            isPresented: self.$showImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false)
        { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            self.uploading = true
            self.uploadError = nil
            Task {
                defer { self.uploading = false }
                do {
                    let attachment = try await OLSClient().upload(url)
                    self.model.attachments.append(attachment)
                } catch {
                    self.uploadError = error.localizedDescription
                }
            }
        }
    }
}

import SwiftUI
import UniformTypeIdentifiers

/// The conversation surface: day rules and inline `#project` anchors scroll with PEAR and
/// human bubbles, while the composer and Projects edge remain available around the flow.
struct OLSTimelineView: View {
    @Bindable var model: OLSModel
    let projects: [PearStatusData.Project]
    let openContext: () -> Void
    let openProjects: () -> Void
    let openVoice: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var composerFocused = false
    @State private var artifact: OLSArtifact?
    @State private var width: CGFloat = 390
    @State private var anchorJumps = 0

    /// Horizontal anchor swipes: deliberate and axis-dominant (the prototype's 72pt / 1.4×).
    private static let swipeDistance: CGFloat = 72
    private static let swipeDominance: CGFloat = 1.4

    private struct Entry: Identifiable {
        var message: OLSMessage
        var rule: String?
        var anchor: Bool
        var id: String {
            self.message.id
        }
    }

    /// Day rules and anchors: a rule wherever the day or the context changes.
    private var entries: [Entry] {
        var entries: [Entry] = []
        var previousSegment: String?
        var previousPeriod: String?
        for message in self.model.messages {
            let period = self.model.periodLabel(for: message)
            let segment = message.context?.segmentId
            let contextChanged = segment != nil && segment != previousSegment
            let periodChanged = period != nil && period != previousPeriod
            var rule: String?
            if contextChanged, let context = message.context {
                rule = periodChanged ? "\(period ?? "") · \(context.hashtag)" : context.hashtag
            } else if periodChanged {
                rule = period
            }
            entries.append(Entry(message: message, rule: rule, anchor: contextChanged))
            if segment != nil { previousSegment = segment }
            if period != nil { previousPeriod = period }
        }
        return entries
    }

    private var currentProject: PearStatusData.Project? {
        let context = self.model.context(before: self.model.visibleMessageID) ?? self.model.activeContext
        return self.projects.first(where: { $0.id == context?.projectId })
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    // Not lazy: a lazy stack's estimated content frame changes with the scroll
                    // offset, and the scroll view re-aligns its offset to that frame on every
                    // pass. A page of messages is small enough to lay out eagerly.
                    VStack(alignment: .leading, spacing: 0) {
                        if self.model.hasMore {
                            Button {
                                Task { await self.model.loadEarlier() }
                            } label: {
                                OLSKicker(
                                    text: self.model.isPaging ? "Loading…" : "Earlier in our conversation",
                                    color: OLSTheme.rule)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .disabled(self.model.isPaging)
                            .accessibilityIdentifier("ols.earlier")
                        }
                        if self.model.messages.isEmpty { self.emptyState }
                        ForEach(self.entries) { entry in
                            VStack(alignment: .leading, spacing: 0) {
                                if let rule = entry.rule {
                                    self.dayRule(rule, message: entry.message, anchor: entry.anchor)
                                }
                                if entry.message.isCommentary {
                                    self.commentary(entry.message)
                                } else {
                                    self.bubble(entry.message)
                                }
                            }
                        }
                        if let check = self.model.contextCheck {
                            OLSContextCheckCard(
                                context: check,
                                project: self.projects.first(where: { $0.id == check.projectId }),
                                onKeep: { self.model.dismissContextCheck() },
                                onChange: self.openContext)
                                .padding(.top, 4)
                                .padding(.bottom, 16)
                        }
                        Color.clear.frame(height: 1).id("ols-bottom")
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 12)
                    .frame(maxWidth: 740)
                    .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("ols.timeline")
                .scrollDismissesKeyboard(.interactively)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { self.width = $0 }
                .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.3) { ids in
                    guard let first = ids.first(where: { $0 != "ols-bottom" }) else { return }
                    if self.model.visibleMessageID != first { self.model.visibleMessageID = first }
                }
                .onAppear {
                    self.applyScrollRequest(proxy)
                    // A conversation opens at the present unless a saved place asks otherwise. The
                    // list has not been laid out yet inside onAppear, so the jump waits one turn.
                    guard self.model.scrollRequest == nil, self.model.isAtPresent, !self.model.messages.isEmpty
                    else { return }
                    Task { @MainActor in
                        await Task.yield()
                        guard self.model.scrollRequest == nil, self.model.isAtPresent else { return }
                        proxy.scrollTo("ols-bottom", anchor: .bottom)
                    }
                }
                .onChange(of: self.model.scrollRequest) { _, _ in self.applyScrollRequest(proxy) }
                .onChange(of: self.model.messages.count) { _, _ in self.applyScrollRequest(proxy) }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentSize.height - (geometry.contentOffset.y + geometry.containerSize.height)
                } action: { _, distance in
                    // Hysteresis: a few points of keyboard-layout wobble must not toggle state.
                    let atPresent = distance <= (self.model.isAtPresent ? 160 : 60)
                    if self.model.isAtPresent != atPresent { self.model.isAtPresent = atPresent }
                }
                .onChange(of: self.model.messages.last) { _, _ in
                    guard self.model.isAtPresent else { return }
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
                            Label {
                                Text("Present").font(OLSTheme.labelStrong)
                            } icon: {
                                Image(systemName: "arrow.down")
                            }
                            .foregroundStyle(OLSTheme.ink)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(OLSTheme.paper, in: Capsule())
                            .overlay { Capsule().strokeBorder(OLSTheme.hairline) }
                            .shadow(color: OLSTheme.composerShadow, radius: 12, y: 8)
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
            OLSComposer(
                model: self.model,
                projects: self.projects,
                openContext: self.openContext,
                openVoice: self.openVoice)
            {
                self.composerFocused = $0
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .frame(maxWidth: 740)
            self.projectsEdge
        }
        .background(OLSTheme.field)
        .sheet(item: self.$artifact) { artifact in
            OLSArtifactView(url: artifact.url, title: artifact.title, onClose: { self.artifact = nil })
        }
    }

    /// Requests wait until the message is loaded; pagination may deliver it later.
    private func applyScrollRequest(_ proxy: ScrollViewProxy) {
        guard let request = self.model.scrollRequest,
              self.model.messages.contains(where: { $0.id == request.messageID })
        else { return }
        withAnimation(self.reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85)) {
            proxy.scrollTo(request.messageID, anchor: .top)
        }
        self.model.completeScrollRequest(request)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            OLSNotice(
                kicker: self.currentProject?.name ?? "Here with you",
                title: self.model.isLoading ? "Bringing our conversation back…" : "Start here.",
                message: self.model.isLoading
                    ? "One moment."
                    : "Talk about anything. I’ll keep each thread attached to the right project underneath.")
            if let error = self.model.error {
                Text(error).font(OLSTheme.caption).foregroundStyle(OLSTheme.warning)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(OLSTheme.warning.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                Button { Task { await self.model.refresh() } } label: {
                    Text("Try again").font(OLSTheme.labelStrong).frame(minHeight: 44)
                }
            }
        }
        .padding(.bottom, 18)
    }

    /// `.day-rule`: hairline · SUNDAY · hairline. Anchors use the same rule with the hashtag.
    @ViewBuilder
    private func dayRule(_ text: String, message: OLSMessage, anchor: Bool) -> some View {
        // The label keeps its full width; the hairlines take whatever is left.
        let rule = HStack(spacing: 12) {
            OLSTheme.hairline.frame(height: 1)
            OLSKicker(text: text, color: OLSTheme.rule, tracking: 1.7)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            OLSTheme.hairline.frame(height: 1)
        }
        .frame(minHeight: 44)
        .padding(.bottom, 4)
        if anchor, let context = message.context {
            Button(action: self.openContext) { rule.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ols.anchor.\(context.segmentId)")
                .accessibilityLabel("\(context.displayName). Context and places in our conversation")
        } else {
            rule.accessibilityAddTraits(.isHeader)
        }
    }

    private func bubble(_ message: OLSMessage) -> some View {
        let human = !message.isAssistant
        let maxWidth = min(600, self.width * 0.88)
        return VStack(alignment: human ? .trailing : .leading, spacing: 10) {
            HStack(spacing: 0) {
                if human { Spacer(minLength: 0) }
                VStack(alignment: .leading, spacing: 7) {
                    Text((try? AttributedString(markdown: message.text)) ?? AttributedString(message.text))
                        .font(OLSTheme.body)
                        .foregroundStyle(human ? OLSTheme.humanInk : OLSTheme.ink)
                        .tint(OLSTheme.accent)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    if let date = PearAPI.parseISODate(message.createdAt) {
                        Text(date, format: .dateTime.hour().minute())
                            .font(OLSTheme.caption)
                            .foregroundStyle((human ? OLSTheme.humanInk : OLSTheme.ink).opacity(0.48))
                            .accessibilityLabel(date.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                .padding(EdgeInsets(top: 14, leading: 15, bottom: 12, trailing: 15))
                .background(
                    human ? OLSTheme.human : OLSTheme.paper,
                    in: UnevenRoundedRectangle(
                        topLeadingRadius: 17,
                        bottomLeadingRadius: human ? 17 : 5,
                        bottomTrailingRadius: human ? 5 : 17,
                        topTrailingRadius: 17,
                        style: .continuous))
                .shadow(color: human ? .clear : OLSTheme.bubbleShadow, radius: 11, y: 8)
                .frame(maxWidth: maxWidth, alignment: .leading)
                if !human { Spacer(minLength: 0) }
            }
            ForEach(message.attachments ?? [], id: \.stableID) { attachment in
                if let url = PearAPI.absoluteURL(attachment.url), url.scheme == "https" {
                    OLSAttachmentCard(
                        eyebrow: message.context?.displayName ?? "Attachment",
                        title: attachment.name ?? "Attachment",
                        detail: attachment.mimeType)
                    {
                        self.artifact = OLSArtifact(url: url, title: attachment.name ?? "Attachment")
                    }
                    .frame(maxWidth: maxWidth)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: human ? .trailing : .leading)
        .padding(.bottom, 16)
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
        .padding(.bottom, 14)
    }

    private static func parenthesizedCommentary(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("("), trimmed.hasSuffix(")") { return trimmed }
        return "(\(trimmed))"
    }

    /// `.projects-edge`: the explicit bottom bar. Tap or pull up for Projects; it is the only
    /// control on the bottom edge, so it never collides with the timeline's swipes.
    private var projectsEdge: some View {
        Button(action: self.openProjects) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up").font(.system(size: 13, weight: .semibold))
                Text("Projects").font(OLSTheme.serif(16, weight: .semibold, relativeTo: .subheadline))
                Spacer()
                OLSKicker(text: "Shared work", color: OLSTheme.muted)
            }
            .foregroundStyle(OLSTheme.ink)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(OLSTheme.edge)
            .overlay(alignment: .top) { OLSTheme.hairline.frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ols.projects")
        .accessibilityLabel("Projects")
        .accessibilityHint("Shared work")
        .simultaneousGesture(DragGesture(minimumDistance: 20).onEnded { value in
            if value.translation.height < -40, abs(value.translation.height) > abs(value.translation.width) {
                self.openProjects()
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

/// `.composer-shell`: `+ · Message PEAR… · mic · Send ➤` in one white pill.
struct OLSComposer: View {
    @Bindable var model: OLSModel
    let projects: [PearStatusData.Project]
    let openContext: () -> Void
    let openVoice: () -> Void
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
                .padding(.leading, 6)
            }
            if let uploadError {
                Text(uploadError).font(OLSTheme.caption).foregroundStyle(OLSTheme.warning).padding(.leading, 6)
            }
            if let selected = self.projects.first(where: { $0.id == self.model.selectedProjectID }) {
                Button(action: self.openContext) {
                    OLSKicker(text: "Talking about \(selected.name)", color: OLSTheme.accent)
                }
                .accessibilityIdentifier("ols.talking-about")
                .padding(.leading, 6)
            }
            HStack(alignment: .center, spacing: 4) {
                Button { self.showImporter = true } label: {
                    Image(systemName: self.uploading ? "hourglass" : "plus")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(OLSTheme.muted)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Add a file")
                .disabled(self.uploading)
                ZStack(alignment: .leading) {
                    if self.model.draft.isEmpty {
                        Text(self.model.isSending ? "I’m working…" : "Message PEAR…")
                            .font(OLSTheme.body)
                            .foregroundStyle(OLSTheme.muted)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    OLSTextView(
                        text: self.$model.draft,
                        minLines: 1,
                        maxLines: 5,
                        accessibilityLabel: "Message PEAR",
                        accessibilityIdentifier: "ols.composer",
                        onFocusChange: self.onFocusChange)
                }
                .padding(.vertical, 11)
                Button(action: self.openVoice) {
                    Image(systemName: "mic")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(OLSTheme.muted)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Open voice mode")
                .accessibilityIdentifier("ols.composer.voice")
                Button {
                    Task { await self.model.send() }
                } label: {
                    HStack(spacing: 6) {
                        Text(self.model.isSending ? "Working" : "Send").font(OLSTheme.labelStrong)
                        Image(systemName: "paperplane.fill").font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(self.canSend ? OLSTheme.sendInk : OLSTheme.sendDisabledInk)
                    .padding(.horizontal, 14)
                    .frame(minWidth: 80, minHeight: 44)
                    .background(self.canSend ? OLSTheme.send : OLSTheme.sendDisabled, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!self.canSend)
                .accessibilityLabel(self.model.isSending ? "Sending" : "Send")
                .accessibilityIdentifier("ols.send")
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(OLSTheme.paper.opacity(0.93), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(OLSTheme.hairline) }
            .shadow(color: OLSTheme.composerShadow, radius: 14, y: 10)
            if let status = self.model.sendStatus ?? self.model.error {
                Text(status).font(OLSTheme.caption).foregroundStyle(OLSTheme.secondary)
                    .padding(.leading, 18)
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

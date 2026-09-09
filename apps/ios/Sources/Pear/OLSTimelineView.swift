import SwiftUI
import UniformTypeIdentifiers

struct OLSTimelineView: View {
    @Bindable var model: OLSModel
    let projects: [PearStatusData.Project]
    let openContext: () -> Void
    let inspectProject: (PearStatusData.Project) -> Void
    let openVoice: () -> Void
    let openProjects: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var composerFocused: Bool
    @State private var artifact: Artifact?
    @State private var showImporter = false
    @State private var uploading = false
    @State private var uploadError: String?

    private struct Artifact: Identifiable {
        let url: URL
        let title: String
        var id: String {
            self.url.absoluteString
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if self.model.hasMore {
                            Button {
                                Task { await self.model.loadEarlier() }
                            } label: {
                                Text(self.model.isPaging ? "Loading…" : "Earlier in our conversation")
                                    .font(OLSTheme.caption).frame(maxWidth: .infinity, minHeight: 44)
                            }.disabled(self.model.isPaging)
                        }
                        if self.model.messages.isEmpty {
                            self.emptyState
                        }
                        ForEach(Array(self.model.messages.enumerated()), id: \.element.id) { index, message in
                            VStack(alignment: .leading, spacing: 16) {
                                if let context = message.context,
                                   index == 0 || self.model.messages[index - 1].context?.segmentId != context.segmentId
                                {
                                    if let project = self.projects.first(where: { $0.id == context.projectId }) {
                                        OLSProjectCard(
                                            project: project,
                                            isCurrent: false,
                                            onOpen: { self.inspectProject(project) })
                                    }
                                    Button(action: self.openContext) {
                                        HStack(spacing: 8) {
                                            Text(context.hashtag).font(OLSTheme.chip)
                                            Image(systemName: "chevron.down").font(.system(size: 10))
                                        }
                                        .padding(.horizontal, 12).padding(.vertical, 10)
                                        .background(OLSTheme.soft, in: Capsule())
                                    }
                                    .accessibilityIdentifier("ols.anchor.\(context.segmentId)")
                                    .padding(.top, 8)
                                }
                                self.bubble(message)
                            }
                            .id(message.id)
                        }
                        Color.clear.frame(height: 1).id("ols-bottom")
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("ols.timeline")
                .scrollPosition(id: self.$model.visibleMessageID, anchor: .top)
                .scrollDismissesKeyboard(.interactively)
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 90
                } action: { _, nearBottom in self.model.isAtPresent = nearBottom }
                .onChange(of: self.model.messages.last?.id) { _, _ in
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
                            Label { Text("Present").font(OLSTheme.caption) } icon: { Image(systemName: "arrow.down") }
                                .padding(12).background(OLSTheme.paper, in: Capsule())
                                .overlay { Capsule().strokeBorder(OLSTheme.line) }
                        }.padding(14)
                    }
                }
                .simultaneousGesture(DragGesture(minimumDistance: 35).onEnded { value in
                    guard !self.composerFocused,
                          value.translation.width > 90,
                          abs(value.translation.width) > abs(value.translation.height) * 2
                    else { return }
                    self.openVoice()
                })
            }
            self.composer
            Button(action: self.openProjects) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.up").font(.system(size: 10, weight: .semibold))
                    Text("Projects").font(OLSTheme.caption)
                }.frame(maxWidth: .infinity, minHeight: 36)
            }
            .accessibilityIdentifier("ols.projects")
            .gesture(DragGesture(minimumDistance: 25).onEnded { value in
                if value.translation.height < -35 { self.openProjects() }
            })
        }
        .sheet(item: self.$artifact) { artifact in
            OLSArtifactView(url: artifact.url, title: artifact.title, onClose: { self.artifact = nil })
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
                do { try await self.model.attachments.append(OLSClient().upload(url)) }
                catch { self.uploadError = error.localizedDescription }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Here with you.").font(OLSTheme.title)
            Text(self.model.isLoading ? "Bringing our conversation back…" : "What’s on your mind?")
                .font(OLSTheme.body).foregroundStyle(OLSTheme.secondary)
            if let error = self.model.error {
                Text(error).font(OLSTheme.caption).foregroundStyle(OLSTheme.warning)
                Button { Task { await self.model.refresh() } } label: { Text("Try again").font(OLSTheme.label) }
            }
        }.padding(.top, 36).padding(.bottom, 24)
    }

    private func bubble(_ message: OLSMessage) -> some View {
        HStack {
            if !message.isAssistant { Spacer(minLength: 34) }
            VStack(alignment: .leading, spacing: 10) {
                Text((try? AttributedString(markdown: message.text)) ?? AttributedString(message.text))
                    .font(OLSTheme.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(message.attachments ?? [], id: \.stableID) { attachment in
                    if let url = PearAPI.absoluteURL(attachment.url), url.scheme == "https" {
                        Button {
                            self.artifact = Artifact(url: url, title: attachment.name ?? "Attachment")
                        } label: {
                            Label { Text(attachment.name ?? "Open attachment").font(OLSTheme.label) } icon: {
                                Image(systemName: "doc")
                            }
                        }
                    }
                }
            }
            .padding(18)
            .background(
                message.isAssistant ? OLSTheme.paper : OLSTheme.human,
                in: UnevenRoundedRectangle(
                    topLeadingRadius: 22,
                    bottomLeadingRadius: message.isAssistant ? 6 : 22,
                    bottomTrailingRadius: message.isAssistant ? 22 : 6,
                    topTrailingRadius: 22))
            .frame(maxWidth: 620, alignment: .leading)
            if message.isAssistant { Spacer(minLength: 28) }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(self.model.attachments, id: \.stableID) { attachment in
                HStack {
                    Text(attachment.name ?? "Attachment").font(OLSTheme.caption).lineLimit(1)
                    Button { self.model.attachments.removeAll { $0.stableID == attachment.stableID } } label: {
                        Image(systemName: "xmark.circle.fill")
                    }.accessibilityLabel("Remove attachment")
                }
            }
            if let uploadError { Text(uploadError).font(OLSTheme.caption).foregroundStyle(OLSTheme.warning) }
            if let selected = self.projects.first(where: { $0.id == self.model.selectedProjectID }) {
                Button(action: self.openContext) {
                    Text("Talking about \(selected.name)").font(OLSTheme.caption)
                }
            }
            HStack(alignment: .bottom, spacing: 10) {
                Button { self.showImporter = true } label: {
                    Image(systemName: self.uploading ? "hourglass" : "plus")
                        .font(.system(size: 19)).frame(width: 44, height: 44)
                }.accessibilityLabel("Add a file").disabled(self.uploading)
                TextField(
                    "",
                    text: self.$model.draft,
                    prompt: Text("Type a message…").font(OLSTheme.body),
                    axis: .vertical)
                    .font(OLSTheme.body)
                    .lineLimit(1...5)
                    .focused(self.$composerFocused)
                    .padding(.vertical, 11)
                    .accessibilityLabel("Message")
                    .accessibilityIdentifier("ols.composer")
                Button(action: self.openVoice) {
                    Image(systemName: "mic").font(.system(size: 18)).frame(width: 36, height: 44)
                }
                .accessibilityLabel("Voice")
                .accessibilityIdentifier("ols.voice")
                Button {
                    Task { await self.model.send() }
                } label: {
                    Text(self.model.isSending ? "…" : "Send")
                        .font(OLSTheme.label)
                        .frame(minWidth: 46, minHeight: 44)
                        .padding(.horizontal, 8)
                        .background(OLSTheme.human, in: Capsule())
                }
                .disabled((self.model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && self.model
                        .attachments.isEmpty) || self.model.isSending || self.uploading)
                .accessibilityIdentifier("ols.send")
            }
            .padding(6)
            .background(OLSTheme.paper, in: RoundedRectangle(cornerRadius: 30))
            .overlay { RoundedRectangle(cornerRadius: 30).strokeBorder(OLSTheme.line) }
            if let status = self.model.sendStatus ?? self.model.error {
                Text(status).font(OLSTheme.caption).foregroundStyle(OLSTheme.secondary)
                    .accessibilityIdentifier("ols.send-status")
            }
        }
        .padding(.horizontal, 16).padding(.top, 8)
        .frame(maxWidth: 800)
    }
}

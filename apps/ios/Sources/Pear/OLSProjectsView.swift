import SwiftUI

/// The endpoint is identity-scoped; none of these fields is populated from the
/// public project corpus or demonstration trip content.
struct OLSProjectDetail: Decodable {
    struct Brief: Decodable {
        var summary: String?
        var updatedAt: String?
        var stale: Bool?
    }

    struct Work: Decodable, Identifiable {
        var id: Int
        var title: String
        var status: String
        var blockedBy: String?

        var isComplete: Bool {
            ["done", "completed", "cancelled", "canceled"].contains(self.status)
        }

        var isBlocked: Bool {
            self.status == "blocked"
        }

        var statusLabel: String {
            switch self.status {
            case "in-progress", "in_progress": "In progress"
            case "blocked": "Waiting"
            case "done", "completed": "Done"
            case "cancelled", "canceled": "Cancelled"
            default: "Planned"
            }
        }
    }

    struct Page: Decodable, Identifiable {
        var id: Int
        var title: String
        var url: String?
        var updatedAt: String?
    }

    struct Site: Decodable, Identifiable {
        var id: Int
        var title: String?
        var slug: String?
        var pages: [Page]?
    }

    struct File: Decodable, Identifiable {
        var id: String
        var name: String
        var url: String?
        var mimeType: String?
        var sizeBytes: Int?
    }

    struct Actions: Decodable {
        var openProject: String?
        var contextHistoryProjectId: Int?
    }

    var project: PearStatusData.Project
    var brief: Brief?
    var tasks: [Work]?
    var sites: [Site]?
    var pages: [Page]?
    var files: [File]?
    var actions: Actions?

    var allPages: [Page] {
        var seen = Set<Int>()
        return ((self.sites ?? []).flatMap { $0.pages ?? [] } + (self.pages ?? []))
            .filter { seen.insert($0.id).inserted }
    }
}

/// Mark's Details surface: the conversation stays primary; Continue, Conversations, and
/// Projects sit underneath. Cards without real data are omitted rather than faked.
struct OLSDetailsView: View {
    @Bindable var model: OLSModel
    let projects: [PearStatusData.Project]
    let email: String?
    let openContext: () -> Void
    let jumpToSegment: (String) -> Void
    let openProject: (PearStatusData.Project) -> Void
    let openDeviceControls: () -> Void
    let signOut: () -> Void
    let projectError: String?
    let retryProjects: () -> Void

    @State private var query = ""
    @State private var allConversations = false
    @State private var allProjects = false

    private var sortedProjects: [PearStatusData.Project] {
        self.projects.sorted {
            let left = $0.updatedDate ?? .distantPast
            let right = $1.updatedDate ?? .distantPast
            return left == right ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : left > right
        }
    }

    private struct ContinueEntry: Identifiable {
        var segment: OLSSegment
        var project: PearStatusData.Project
        var id: String {
            self.segment.id
        }
    }

    /// Newest segment per project, newest first: the short ranked return path.
    private var continueSegments: [ContinueEntry] {
        var seen = Set<Int>()
        let entries = self.model.segments.compactMap { segment -> ContinueEntry? in
            guard let projectID = segment.projectId, seen.insert(projectID).inserted,
                  let project = self.projects.first(where: { $0.id == projectID })
            else { return nil }
            return ContinueEntry(segment: segment, project: project)
        }
        return Array(entries.prefix(3))
    }

    private struct ConversationEntry: Identifiable {
        var segment: OLSSegment
        var project: PearStatusData.Project?
        var title: String
        var detail: String?
        var id: String {
            self.segment.id
        }
    }

    private var conversations: [ConversationEntry] {
        let search = self.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let entries = self.model.segments.map { segment -> ConversationEntry in
            let rows = self.model.messages.filter { $0.context?.segmentId == segment.id && !$0.isCommentary }
            let opening = rows.first(where: { !$0.isAssistant })?.text ?? rows.first?.text
            let reply = rows.last(where: { $0.isAssistant })?.text
            return ConversationEntry(
                segment: segment,
                project: self.projects.first(where: { $0.id == segment.projectId }),
                title: opening.map(OLSProjectTile.plain) ?? segment.context.displayName,
                detail: reply.map(OLSProjectTile.plain))
        }
        guard !search.isEmpty else { return entries }
        return entries.filter {
            $0.title.localizedStandardContains(search) || ($0.detail?.localizedStandardContains(search) ?? false)
                || $0.segment.context.displayName.localizedStandardContains(search)
                || $0.segment.context.hashtag.localizedStandardContains(search)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                OLSComposer(model: self.model, projects: self.projects, openContext: self.openContext)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 14) {
                    OLSKicker(text: "Details").padding(.top, 8)
                    Text("Everything is here when you want it.")
                        .font(OLSTheme.greeting)
                        .foregroundStyle(OLSTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("Your conversations stay primary. I keep the work organized underneath.")
                        .font(OLSTheme.body)
                        .foregroundStyle(OLSTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let projectError {
                    HStack(spacing: 12) {
                        Text(projectError).font(OLSTheme.caption).foregroundStyle(OLSTheme.secondary)
                        Button(action: self.retryProjects) { Text("Retry").font(OLSTheme.action) }
                    }
                }
                if !self.continueSegments.isEmpty { self.continueCard }
                if !self.model.segments.isEmpty { self.conversationsCard }
                if !self.projects.isEmpty { self.projectsCard }
                self.accountCard
            }
            .frame(maxWidth: 700)
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(OLSTheme.background)
        .accessibilityIdentifier("ols.details.surface")
    }

    private var continueCard: some View {
        OLSCard {
            VStack(alignment: .leading, spacing: 18) {
                OLSSectionHeading(kicker: "Continue", title: "Pick up where we left off")
                ForEach(self.continueSegments) { item in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 14) {
                            OLSEmojiTile(emoji: item.project.emoji, size: 52)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline) {
                                    OLSKicker(text: item.project.category ?? "Project").lineLimit(1)
                                    Spacer(minLength: 8)
                                    if let raw = item.segment.createdAt, let date = PearAPI.parseISODate(raw) {
                                        Text(date, style: .relative).font(OLSTheme.caption)
                                            .foregroundStyle(OLSTheme.secondary)
                                    }
                                }
                                Text(item.project.name)
                                    .font(OLSTheme.cardTitle)
                                    .foregroundStyle(OLSTheme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let summary = item.project.bestSummary, !summary.isEmpty {
                                    Text(OLSProjectTile.plain(summary))
                                        .font(OLSTheme.caption)
                                        .foregroundStyle(OLSTheme.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        OLSPillAction(title: "Return to this conversation") { self.jumpToSegment(item.segment.id) }
                            .accessibilityIdentifier("ols.continue.\(item.segment.id)")
                    }
                    .padding(14)
                    .background(OLSTheme.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(OLSTheme.cardLine) }
                }
            }
        }
    }

    private var conversationsCard: some View {
        OLSCard {
            VStack(alignment: .leading, spacing: 16) {
                OLSSectionHeading(kicker: "Conversations", title: "Every place we can return to")
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(OLSTheme.secondary)
                    TextField(text: self.$query) {
                        Text("Search what we talked about").font(OLSTheme.label).foregroundStyle(OLSTheme.secondary)
                    }
                    .font(OLSTheme.label)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Search conversations")
                    .accessibilityIdentifier("ols.details.search")
                    if !self.query.isEmpty {
                        Button { self.query = "" } label: {
                            Image(systemName: "xmark.circle.fill").frame(width: 32, height: 32)
                        }
                        .foregroundStyle(OLSTheme.secondary)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 46)
                .background(OLSTheme.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(OLSTheme.cardLine) }
                let rows = self.conversations
                if rows.isEmpty {
                    Text("Nothing matches yet.").font(OLSTheme.label).foregroundStyle(OLSTheme.secondary)
                }
                ForEach(self.allConversations || !self.query.isEmpty ? rows : Array(rows.prefix(5))) { entry in
                    OLSConversationRow(
                        emoji: entry.project?.emoji,
                        eyebrow: entry.segment.context.displayName,
                        title: entry.title,
                        detail: entry.detail,
                        trailing: entry.segment.createdAt.flatMap(PearAPI.parseISODate)
                            .map { OLSModel.periodLabel(for: $0, now: self.model.now()) })
                    {
                        self.jumpToSegment(entry.segment.id)
                    }
                    .accessibilityIdentifier("ols.conversation.\(entry.segment.id)")
                }
                if self.query.isEmpty, rows.count > 5 {
                    OLSPillAction(
                        title: self.allConversations ? "Fewer conversations" : "All \(rows.count) conversations",
                        filled: false)
                    {
                        self.allConversations.toggle()
                    }
                }
            }
        }
    }

    private var projectsCard: some View {
        OLSCard {
            VStack(alignment: .leading, spacing: 16) {
                OLSSectionHeading(kicker: "Projects", title: "The work your conversations created")
                let shown = self.allProjects ? self.sortedProjects : Array(self.sortedProjects.prefix(6))
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(shown) { project in
                        OLSProjectTile(project: project) { self.openProject(project) }
                            .accessibilityIdentifier("ols.project.\(project.id)")
                    }
                }
                if self.sortedProjects.count > 6 {
                    OLSPillAction(
                        title: self.allProjects ? "Fewer projects" : "All \(self.sortedProjects.count) projects",
                        filled: false)
                    {
                        self.allProjects.toggle()
                    }
                }
            }
        }
        .accessibilityIdentifier("ols.projects")
    }

    private var accountCard: some View {
        OLSCard {
            VStack(alignment: .leading, spacing: 14) {
                OLSSectionHeading(kicker: "Account", title: self.email ?? "Signed in")
                OLSPillAction(title: "Device & connection", filled: false, action: self.openDeviceControls)
                OLSPillAction(title: "Sign out", filled: false, chevron: false, action: self.signOut)
                    .accessibilityIdentifier("ols.sign-out")
            }
        }
    }
}

/// Mark's Project screen: hero, eyebrow chips, serif title, RIGHT NOW, NEEDS YOU, FILES,
/// and the conversations that created it. Every section renders only from real data.
struct OLSProjectView: View {
    let project: PearStatusData.Project
    @Bindable var model: OLSModel
    let jumpToSegment: (String) -> Void
    let talkAbout: (PearStatusData.Project) -> Void

    @State private var detail: OLSProjectDetail?
    @State private var isLoading = false
    @State private var error: String?
    @State private var showAllWork = false
    @State private var artifact: OLSArtifact?

    private var currentProject: PearStatusData.Project {
        self.detail?.project ?? self.project
    }

    private var openWork: [OLSProjectDetail.Work] {
        (self.detail?.tasks ?? []).filter { !$0.isComplete }
    }

    private var segments: [OLSSegment] {
        self.model.segments.filter { $0.projectId == self.project.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                self.hero
                if self.isLoading, self.detail == nil {
                    HStack(spacing: 12) {
                        ProgressView().tint(OLSTheme.accent)
                        Text("Bringing this up to date…").font(OLSTheme.label).foregroundStyle(OLSTheme.secondary)
                    }
                }
                if let error = self.error {
                    OLSCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(error).font(OLSTheme.body).foregroundStyle(OLSTheme.secondary)
                            OLSPillAction(title: "Try again", filled: false, chevron: false) {
                                Task { await self.load() }
                            }
                        }
                    }
                }
                if let detail = self.detail {
                    self.rightNow(detail)
                    self.needsYou(detail)
                    self.inTheWorks(detail)
                    self.files(detail)
                }
                if !self.segments.isEmpty { self.conversations }
                OLSPillAction(title: "Talk about this", chevron: false) { self.talkAbout(self.currentProject) }
                    .accessibilityIdentifier("ols.talk-about-project")
                if let path = self.detail?.actions?.openProject {
                    OLSPillAction(title: "Full project on the Playground", filled: false) {
                        self.open(path, title: self.currentProject.name)
                    }
                }
            }
            .frame(maxWidth: 700)
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .background(OLSTheme.background)
        .task { await self.load() }
        .refreshable { await self.load() }
        .fullScreenCover(item: self.$artifact) { item in
            OLSArtifactView(url: item.url, title: item.title) { self.artifact = nil }
        }
        .accessibilityIdentifier("ols.project.surface")
    }

    /// Category and health chips, deduplicated so identical strings never collide as row IDs.
    private var heroChips: [String] {
        var chips: [String] = []
        for chip in [self.currentProject.category, self.currentProject.health].compactMap({ $0 })
            where !chip.isEmpty && !chips.contains(chip)
        {
            chips.append(chip)
        }
        return chips
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(OLSTheme.human)
                Text(self.currentProject.emoji ?? "🍐")
                    .font(.system(size: 84))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)
                HStack(spacing: 8) {
                    ForEach(self.heroChips, id: \.self) { chip in
                        OLSKicker(text: chip, color: OLSTheme.ink)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(OLSTheme.paper.opacity(0.85), in: Capsule())
                    }
                }
                .padding(16)
            }
            .frame(height: 200)
            .padding(.top, 4)
            Text(self.currentProject.name)
                .font(OLSTheme.greeting)
                .foregroundStyle(OLSTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(self.currentProject.hashtag).font(OLSTheme.chip).foregroundStyle(OLSTheme.secondary)
        }
    }

    @ViewBuilder
    private func rightNow(_ detail: OLSProjectDetail) -> some View {
        let summary = detail.brief?.summary ?? detail.project.bestSummary
        if let summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                OLSKicker(text: detail.brief?.stale == true ? "Last update" : "Right now")
                Text(self.markdown(summary))
                    .font(OLSTheme.heading)
                    .foregroundStyle(OLSTheme.ink)
                    .tint(OLSTheme.accent)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let raw = detail.brief?.updatedAt, let date = PearAPI.parseISODate(raw) {
                    Text(date, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(OLSTheme.caption)
                        .foregroundStyle(OLSTheme.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func needsYou(_ detail: OLSProjectDetail) -> some View {
        let waiting = self.openWork.filter { $0.isBlocked && !($0.blockedBy ?? "").isEmpty }
        if !waiting.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                OLSKicker(text: "Needs you")
                ForEach(waiting) { item in
                    OLSCard(padding: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title).font(OLSTheme.cardTitle).foregroundStyle(OLSTheme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(item.blockedBy ?? "").font(OLSTheme.label).foregroundStyle(OLSTheme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func inTheWorks(_ detail: OLSProjectDetail) -> some View {
        let moving = self.openWork.filter { !$0.isBlocked || ($0.blockedBy ?? "").isEmpty }
        if !moving.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                OLSSectionHeading(kicker: "In the works", title: "What’s moving")
                OLSCard(padding: 16) {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(self.showAllWork ? moving : Array(moving.prefix(6))) { item in
                            OLSCardRow(
                                symbol: item.isBlocked ? "ellipsis" : "checkmark",
                                text: item.title,
                                detail: item.statusLabel)
                        }
                        if moving.count > 6 {
                            OLSPillAction(
                                title: self.showAllWork ? "Show less" : "Show all \(moving.count)",
                                filled: false)
                            {
                                self.showAllWork.toggle()
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func files(_ detail: OLSProjectDetail) -> some View {
        let pages = detail.allPages
        let files = (detail.files ?? []).filter { $0.url != nil }
        if !pages.isEmpty || !files.isEmpty {
            OLSCard {
                VStack(alignment: .leading, spacing: 14) {
                    OLSSectionHeading(kicker: "Files", title: "Everything we’re carrying")
                    ForEach(pages) { page in
                        self.fileRow(title: page.title, kind: "Page", symbol: "doc.text", path: page.url ?? "/p/\(page.id)")
                    }
                    ForEach(files) { file in
                        self.fileRow(
                            title: file.name,
                            kind: self.fileSubtitle(file),
                            symbol: file.mimeType?.hasPrefix("image/") == true ? "photo" : "doc",
                            path: file.url ?? "")
                    }
                }
            }
        }
    }

    private var conversations: some View {
        OLSCard {
            VStack(alignment: .leading, spacing: 14) {
                OLSSectionHeading(kicker: "Conversations", title: "How we got here")
                ForEach(self.segments) { segment in
                    let rows = self.model.messages.filter { $0.context?.segmentId == segment.id && !$0.isCommentary }
                    OLSConversationRow(
                        emoji: self.currentProject.emoji,
                        eyebrow: segment.context.displayName,
                        title: rows.first(where: { !$0.isAssistant }).map { OLSProjectTile.plain($0.text) }
                            ?? "Return to this conversation",
                        detail: rows.last(where: { $0.isAssistant }).map { OLSProjectTile.plain($0.text) },
                        trailing: segment.createdAt.flatMap(PearAPI.parseISODate)
                            .map { OLSModel.periodLabel(for: $0, now: self.model.now()) })
                    {
                        self.jumpToSegment(segment.id)
                    }
                    .accessibilityIdentifier("ols.project.conversation.\(segment.id)")
                }
            }
        }
    }

    private func fileRow(title: String, kind: String, symbol: String, path: String) -> some View {
        Button {
            self.open(path, title: title)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .foregroundStyle(OLSTheme.ink)
                    .frame(width: 40, height: 40)
                    .background(OLSTheme.soft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    OLSKicker(text: kind)
                    Text(title).font(OLSTheme.rowTitle).foregroundStyle(OLSTheme.ink)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OLSTheme.secondary)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .frame(minHeight: 56)
            .background(OLSTheme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(OLSTheme.cardLine) }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func fileSubtitle(_ file: OLSProjectDetail.File) -> String {
        let kind = file.mimeType?.hasPrefix("image/") == true ? "Image" : "File"
        guard let size = file.sizeBytes, size >= 0 else { return kind }
        return kind + " · " + ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    private func open(_ path: String, title: String) {
        guard let url = URL(string: path, relativeTo: OLSClient.baseURL)?.absoluteURL,
              url.scheme?.lowercased() == "https", url.host != nil,
              url.user == nil, url.password == nil
        else {
            self.error = "That link isn’t available yet."
            return
        }
        self.artifact = OLSArtifact(url: url, title: title)
    }

    @MainActor
    private func load() async {
        guard !self.isLoading else { return }
        self.isLoading = true
        defer { self.isLoading = false }
        do {
            let detail: OLSProjectDetail = try await OLSClient().get("/api/ols/projects/\(self.project.id)")
            try Task.checkCancellation()
            self.detail = detail
            self.error = nil
        } catch is CancellationError {
            return
        } catch {
            self.error = "I couldn’t bring this project up to date. Your conversation is still here."
        }
    }
}

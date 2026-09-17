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

/// `.projects-surface`: the context spine on top (tap or pull down to return to the thread),
/// then the light workspace: nav, `YOUR SHARED WORK / Projects`, search, filters, the featured
/// project, the card grid, and a Conversations tab that lists every place we can return to.
struct OLSProjectsView: View {
    @Bindable var model: OLSModel
    let projects: [PearStatusData.Project]
    let projectError: String?
    let retry: () -> Void
    let onReturn: () -> Void
    let openProject: (PearStatusData.Project) -> Void
    let openVoice: () -> Void
    let jumpToSegment: (String) -> Void

    enum Mode: String, CaseIterable { case projects = "Projects", conversations = "Conversations" }
    enum Filter: String, CaseIterable { case recent = "Recent", all = "All", shared = "Shared", archived = "Archived" }

    @State private var mode: Mode = .projects
    @State private var filter: Filter = .recent
    @State private var query = ""

    private var sorted: [PearStatusData.Project] {
        self.projects.sorted {
            let left = $0.updatedDate ?? .distantPast
            let right = $1.updatedDate ?? .distantPast
            return left == right ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : left > right
        }
    }

    private static func isArchived(_ project: PearStatusData.Project) -> Bool {
        [project.health, project.category, project.freshness]
            .contains { $0?.localizedCaseInsensitiveContains("archiv") == true }
    }

    private static func isShared(_ project: PearStatusData.Project) -> Bool {
        [project.health, project.category].contains { $0?.localizedCaseInsensitiveContains("shared") == true }
    }

    private var visibleProjects: [PearStatusData.Project] {
        let search = self.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !search.isEmpty {
            return self.sorted.filter {
                $0.name.localizedStandardContains(search) || $0.hashtag.localizedStandardContains(search)
                    || ($0.bestSummary?.localizedStandardContains(search) ?? false)
            }
        }
        switch self.filter {
        case .recent: return Array(self.sorted.filter { !Self.isArchived($0) }.prefix(9))
        case .all: return self.sorted
        case .shared: return self.sorted.filter(Self.isShared)
        case .archived: return self.sorted.filter(Self.isArchived)
        }
    }

    private var latestReply: OLSMessage? {
        self.model.latestFinalReply
    }

    /// `.context-copy` ink (#53604f).
    private static let spineInk = Color(red: 83 / 255, green: 96 / 255, blue: 79 / 255)
    /// `.workspace-nav button.active` ink (#273323).
    private static let navInk = Color(red: 39 / 255, green: 51 / 255, blue: 35 / 255)

    /// `.context-orb`: the small lime-to-green sphere on the spine.
    private static let orbGradient = RadialGradient(
        colors: [
            Color(red: 251 / 255, green: 1, blue: 233 / 255),
            Color(red: 186 / 255, green: 221 / 255, blue: 103 / 255),
            Color(red: 118 / 255, green: 149 / 255, blue: 63 / 255),
            Color(red: 66 / 255, green: 85 / 255, blue: 52 / 255),
        ],
        center: UnitPoint(x: 0.42, y: 0.4),
        startRadius: 1,
        endRadius: 15)

    var body: some View {
        VStack(spacing: 0) {
            self.spine
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    self.nav
                    self.workspaceHeader
                    if let projectError {
                        HStack(spacing: 12) {
                            Text(projectError).font(OLSTheme.caption).foregroundStyle(OLSTheme.secondary)
                            Button(action: self.retry) { Text("Retry").font(OLSTheme.labelStrong) }
                        }
                        .padding(.bottom, 16)
                    }
                    switch self.mode {
                    case .projects: self.projectsMode
                    case .conversations: self.conversationsMode
                    }
                }
                .padding(EdgeInsets(top: 16, leading: 18, bottom: 40, trailing: 18))
                .frame(maxWidth: 740)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(OLSTheme.workspaceField)
    }

    /// `.context-spine`: orb, `THREAD · <when>`, the latest reply, chevron down.
    private var spine: some View {
        Button(action: self.onReturn) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Self.orbGradient)
                    .frame(width: 26, height: 26)
                    .shadow(color: OLSTheme.accent.opacity(0.16), radius: 9)
                    .accessibilityHidden(true)
                if let reply = self.latestReply {
                    OLSKicker(text: "Thread · \(self.model.periodLabel(for: reply) ?? "")", color: Self.spineInk)
                        .lineLimit(1)
                    Text(OLSPlainText.plain(reply.text))
                        .font(OLSTheme.detail)
                        .foregroundStyle(Color(red: 41 / 255, green: 53 / 255, blue: 39 / 255))
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    OLSKicker(text: "Thread", color: Self.spineInk)
                    Text("Back to our conversation").font(OLSTheme.detail).foregroundStyle(OLSTheme.secondary)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.down").font(.system(size: 16, weight: .medium))
                    .foregroundStyle(OLSTheme.ink).accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(OLSTheme.spine)
            .overlay(alignment: .bottom) { OLSTheme.spineLine.frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ols.projects.return")
        .accessibilityLabel("Return to the conversation")
        // Only the spine owns room navigation; scrolling the workspace never pulls the thread back.
        .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { value in
            if value.translation.height > 60, value.translation.height > abs(value.translation.width) * 1.4 {
                self.onReturn()
            }
        })
    }

    /// `.workspace-nav`: a segmented row on a soft white bar.
    private var nav: some View {
        HStack(spacing: 5) {
            ForEach(Mode.allCases, id: \.self) { item in
                Button { withAnimation(.easeOut(duration: 0.15)) { self.mode = item } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item == .projects ? "square.grid.2x2" : "bubble.left.and.text.bubble.right")
                            .font(.system(size: 13, weight: .semibold))
                        Text(item.rawValue).font(OLSTheme.labelStrong)
                    }
                    .foregroundStyle(self.mode == item ? Self.navInk : OLSTheme.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(
                        self.mode == item ? OLSTheme.navActive : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ols.workspace.\(item.rawValue.lowercased())")
            }
        }
        .padding(5)
        .background(OLSTheme.paper.opacity(0.68), in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(OLSTheme.projectCardLine) }
        .shadow(color: OLSTheme.cardShadow.opacity(0.6), radius: 9, y: 8)
        .padding(.bottom, 22)
    }

    private var workspaceHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                OLSKicker(text: "Your shared work", tracking: 2.4)
                Text(self.mode.rawValue)
                    .font(OLSTheme.display)
                    .tracking(-1.4)
                    .foregroundStyle(OLSTheme.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            OLSPillAction(title: "Voice", filled: false, symbol: "mic", action: self.openVoice)
                .accessibilityLabel("Open voice mode")
        }
        .padding(.bottom, 18)
    }

    private var search: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 17)).foregroundStyle(OLSTheme.secondary)
            TextField(text: self.$query) {
                Text(self.mode == .projects ? "Find a project" : "Search what we talked about")
                    .font(OLSTheme.body).foregroundStyle(OLSTheme.muted)
            }
            .font(OLSTheme.body)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityLabel(self.mode == .projects ? "Find a project" : "Search conversations")
            .accessibilityIdentifier("ols.workspace.search")
            if !self.query.isEmpty {
                Button { self.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").frame(width: 32, height: 32)
                }
                .foregroundStyle(OLSTheme.secondary)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 54)
        .background(OLSTheme.paper, in: RoundedRectangle(cornerRadius: 4))
        .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(OLSTheme.projectCardLine) }
    }

    @ViewBuilder
    private var projectsMode: some View {
        self.search
        HStack(spacing: 12) {
            ForEach(Filter.allCases, id: \.self) { item in
                Button { withAnimation(.easeOut(duration: 0.15)) { self.filter = item } } label: {
                    Text(item.rawValue)
                        .font(OLSTheme.labelStrong)
                        .foregroundStyle(self.filter == item ? OLSTheme.ink : OLSTheme.secondary)
                        .padding(.bottom, 8)
                        .frame(minHeight: 42)
                        .overlay(alignment: .bottom) {
                            (self.filter == item ? OLSTheme.accent : Color.clear).frame(height: 2)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(self.filter == item ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.top, 14)
        .padding(.bottom, 18)
        .opacity(self.query.isEmpty ? 1 : 0.4)
        .disabled(!self.query.isEmpty)
        let visible = self.visibleProjects
        if visible.isEmpty {
            Text(self.query.isEmpty ? self.emptyFilterText : "No projects match “\(self.query)”.")
                .font(OLSTheme.label).foregroundStyle(OLSTheme.secondary).padding(.vertical, 28)
        }
        if let featured = visible.first, self.query.isEmpty, self.filter == .recent {
            OLSFeaturedProjectCard(project: featured, decision: nil) { self.openProject(featured) }
                .accessibilityIdentifier("ols.project.\(featured.id)")
                .padding(.bottom, 12)
        }
        let grid = (self.query.isEmpty && self.filter == .recent) ? Array(visible.dropFirst()) : visible
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(grid) { project in
                OLSProjectCardTile(project: project) { self.openProject(project) }
                    .accessibilityIdentifier("ols.project.\(project.id)")
            }
        }
        if self.query.isEmpty, self.filter != .all {
            Button { withAnimation(.easeOut(duration: 0.15)) { self.filter = .all } } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("All projects").font(OLSTheme.rowTitle).foregroundStyle(OLSTheme.ink)
                        Text("Searchable list · newest first").font(OLSTheme.caption)
                            .foregroundStyle(OLSTheme.secondary)
                    }
                    Spacer()
                    Text("\(self.projects.count)").font(OLSTheme.caption).foregroundStyle(OLSTheme.secondary)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(OLSTheme.secondary)
                }
                .padding(.vertical, 10)
                .frame(minHeight: 78)
                .overlay(alignment: .top) { OLSTheme.hairline.frame(height: 1) }
                .overlay(alignment: .bottom) { OLSTheme.hairline.frame(height: 1) }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
        }
    }

    private var emptyFilterText: String {
        switch self.filter {
        case .shared: "No shared projects yet."
        case .archived: "Nothing archived."
        default: "Your shared work will appear here as we get things moving."
        }
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
                title: opening.map(OLSPlainText.plain) ?? segment.context.displayName,
                detail: reply.map(OLSPlainText.plain))
        }
        guard !search.isEmpty else { return entries }
        return entries.filter {
            $0.title.localizedStandardContains(search) || ($0.detail?.localizedStandardContains(search) ?? false)
                || $0.segment.context.displayName.localizedStandardContains(search)
                || $0.segment.context.hashtag.localizedStandardContains(search)
        }
    }

    /// `NEW YORK ARRANGEMENTS · SLACK`: the project first, the surface only when it is not this app.
    static func eyebrow(for segment: OLSSegment) -> String {
        guard let surface = segment.surfaceKind.name else { return segment.context.displayName }
        return "\(segment.context.displayName) · \(surface)"
    }

    @ViewBuilder
    private var conversationsMode: some View {
        self.search.padding(.bottom, 16)
        let rows = self.conversations
        if rows.isEmpty {
            Text(self.query.isEmpty ? "Every place we can return to will appear here." : "Nothing matches yet.")
                .font(OLSTheme.label).foregroundStyle(OLSTheme.secondary).padding(.vertical, 28)
        }
        VStack(spacing: 10) {
            ForEach(rows) { entry in
                OLSConversationRow(
                    emoji: entry.project?.emoji,
                    eyebrow: Self.eyebrow(for: entry.segment),
                    title: entry.title,
                    detail: entry.detail,
                    trailing: entry.segment.createdAt.flatMap(PearAPI.parseISODate)
                        .map { OLSModel.periodLabel(for: $0, now: self.model.now()) })
                {
                    self.jumpToSegment(entry.segment.id)
                }
                .accessibilityIdentifier("ols.conversation.\(entry.segment.id)")
            }
        }
    }
}

/// A project screen: `.project-chrome` on top (back, return to thread, voice), then the hero,
/// RIGHT NOW, NEEDS YOU, in the works, FILES, and the conversations that created it.
struct OLSProjectView: View {
    let project: PearStatusData.Project
    @Bindable var model: OLSModel
    let back: () -> Void
    let returnToThread: () -> Void
    let openVoice: () -> Void
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
        VStack(spacing: 0) {
            self.chrome
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
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
                                OLSPillAction(title: "Try again", filled: false) { Task { await self.load() } }
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
                    OLSPillAction(title: "Talk about this", symbol: "bubble.left") {
                        self.talkAbout(self.currentProject)
                    }
                    .accessibilityIdentifier("ols.talk-about-project")
                    if let path = self.detail?.actions?.openProject {
                        OLSPillAction(title: "Full project on the Playground", filled: false, chevron: true) {
                            self.open(path, title: self.currentProject.name)
                        }
                    }
                }
                .padding(EdgeInsets(top: 8, leading: 18, bottom: 40, trailing: 18))
                .frame(maxWidth: 740)
                .frame(maxWidth: .infinity)
            }
        }
        .background(OLSTheme.workspaceField)
        .task { await self.load() }
        .refreshable { await self.load() }
        .fullScreenCover(item: self.$artifact) { item in
            OLSArtifactView(url: item.url, title: item.title) { self.artifact = nil }
        }
    }

    /// `.project-chrome`: `‹ Projects`, the thread-return pill, and the voice button.
    private var chrome: some View {
        HStack(spacing: 10) {
            Button(action: self.back) {
                Label { Text("Projects").font(OLSTheme.labelStrong) } icon: { Image(systemName: "chevron.left") }
                    .foregroundStyle(OLSTheme.ink)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ols.project.back")
            Button(action: self.returnToThread) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward").font(.system(size: 12, weight: .semibold))
                    Text("Thread").font(OLSTheme.caption.weight(.bold))
                }
                .foregroundStyle(OLSTheme.ink)
                .padding(.horizontal, 10)
                .frame(minHeight: 38)
                .background(OLSTheme.paper, in: Capsule())
                .overlay { Capsule().strokeBorder(OLSTheme.spineLine) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Return to the conversation")
            Spacer()
            Button(action: self.openVoice) {
                Image(systemName: "mic").font(.system(size: 17)).foregroundStyle(OLSTheme.ink)
                    .frame(width: 44, height: 44)
                    .background(OLSTheme.paper, in: Circle())
                    .overlay { Circle().strokeBorder(OLSTheme.spineLine) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open voice mode")
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 60)
    }

    private var heroChips: [String] {
        var chips: [String] = []
        for chip in [self.currentProject.category, self.currentProject.health].compactMap(\.self)
            where !chip.isEmpty && !chips.contains(chip)
        {
            chips.append(chip)
        }
        return chips
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [OLSTheme.tint, OLSTheme.spine, OLSTheme.edge],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing)
                Text(self.currentProject.emoji ?? "🍐")
                    .font(.system(size: 84))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)
                HStack(spacing: 8) {
                    ForEach(self.heroChips, id: \.self) { chip in
                        OLSKicker(text: chip, color: OLSTheme.ink, tracking: 1.2)
                            .padding(.horizontal, 10).frame(minHeight: 30)
                            .background(OLSTheme.paper.opacity(0.85), in: Capsule())
                    }
                }
                .padding(16)
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: OLSTheme.cardShadow, radius: 15, y: 12)
            Text(self.currentProject.name)
                .font(OLSTheme.display)
                .tracking(-1.4)
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
                    OLSCard(fill: OLSTheme.decision) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title).font(OLSTheme.cardTitle).foregroundStyle(OLSTheme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(item.blockedBy ?? "").font(OLSTheme.label).foregroundStyle(OLSTheme.decisionInk)
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
                OLSCard {
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
            VStack(alignment: .leading, spacing: 12) {
                OLSSectionHeading(kicker: "Files", title: "Everything we’re carrying")
                VStack(spacing: 10) {
                    ForEach(pages) { page in
                        self.fileRow(
                            title: page.title,
                            kind: "Page",
                            symbol: "doc.text",
                            path: page.url ?? "/p/\(page.id)")
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
        VStack(alignment: .leading, spacing: 12) {
            OLSSectionHeading(kicker: "Conversations", title: "How we got here")
            VStack(spacing: 10) {
                ForEach(self.segments) { segment in
                    let rows = self.model.messages.filter { $0.context?.segmentId == segment.id && !$0.isCommentary }
                    OLSConversationRow(
                        emoji: self.currentProject.emoji,
                        eyebrow: OLSProjectsView.eyebrow(for: segment),
                        title: rows.first(where: { !$0.isAssistant }).map { OLSPlainText.plain($0.text) }
                            ?? "Return to this conversation",
                        detail: rows.last(where: { $0.isAssistant }).map { OLSPlainText.plain($0.text) },
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
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .foregroundStyle(OLSTheme.ink)
                    .frame(width: 40, height: 40)
                    .background(OLSTheme.tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
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
            .frame(minHeight: 78)
            .background(OLSTheme.projectCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(OLSTheme.projectCardLine) }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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

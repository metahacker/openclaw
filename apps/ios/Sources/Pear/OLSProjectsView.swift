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

struct OLSProjectsView: View {
    let projects: [PearStatusData.Project]
    let selectedProject: PearStatusData.Project?
    let onSelect: (PearStatusData.Project) -> Void
    let onReturn: () -> Void

    @State private var query = ""
    @State private var recentOnly = true
    @State private var inspecting: PearStatusData.Project?

    private var visibleProjects: [PearStatusData.Project] {
        let sorted = self.projects.sorted {
            let left = $0.updatedDate ?? .distantPast
            let right = $1.updatedDate ?? .distantPast
            return left == right ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : left > right
        }
        let search = self.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !search.isEmpty {
            return sorted.filter {
                $0.name.localizedStandardContains(search) || $0.hashtag.localizedStandardContains(search)
                    || ($0.bestSummary?.localizedStandardContains(search) ?? false)
            }
        }
        return self.recentOnly ? Array(sorted.prefix(12)) : sorted
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    if self.inspecting != nil { self.inspecting = nil } else { self.onReturn() }
                } label: {
                    Label {
                        Text(self.inspecting == nil ? "Chat" : "Projects").font(OLSTheme.label)
                    } icon: {
                        Image(systemName: "chevron.left")
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityIdentifier("ols.projects.return")
                Spacer()
                if self.inspecting != nil {
                    Button(action: self.onReturn) {
                        Label {
                            Text("Chat").font(OLSTheme.label)
                        } icon: {
                            Image(systemName: "bubble.left")
                        }
                        .frame(minHeight: 44)
                    }
                }
            }
            .padding(.horizontal, 20)
            .foregroundStyle(OLSTheme.ink)
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { value in
                // Only the header owns room navigation; scrolling project text
                // and files must never pull the conversation into view.
                if value.translation.height > 60,
                   value.translation.height > abs(value.translation.width) * 1.4
                {
                    self.onReturn()
                }
            })

            if let project = self.inspecting {
                OLSProjectDetailView(project: project, onSelect: self.onSelect)
                    .id(project.id)
            } else {
                self.projectList
            }
        }
        .background(OLSTheme.background)
    }

    private var projectList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Projects")
                    .font(OLSTheme.title)
                    .foregroundStyle(OLSTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(OLSTheme.secondary)
                    TextField(text: self.$query) {
                        Text("Find a project").font(OLSTheme.body).foregroundStyle(OLSTheme.secondary)
                    }
                    .font(OLSTheme.body)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Find a project")
                    if !self.query.isEmpty {
                        Button {
                            self.query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 52)
                .background(OLSTheme.paper, in: RoundedRectangle(cornerRadius: 16))
                .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(OLSTheme.line) }

                if self.query.isEmpty, self.projects.count > 12 {
                    Picker(selection: self.$recentOnly) {
                        Text("Recent").font(OLSTheme.label).tag(true)
                        Text("All").font(OLSTheme.label).tag(false)
                    } label: {
                        Text("Projects").font(OLSTheme.label)
                    }
                    .pickerStyle(.segmented)
                }

                if self.visibleProjects.isEmpty {
                    OLSEmptyState(
                        title: self.query.isEmpty ? "Room for what matters." : "No matching projects.",
                        message: self.query.isEmpty
                            ? "Your shared work will appear here as we get things moving."
                            : "Try another name or return to our conversation.",
                        symbol: "square.stack")
                }
                ForEach(self.visibleProjects) { project in
                    OLSProjectCard(project: project, isCurrent: project.id == self.selectedProject?.id) {
                        self.inspecting = project
                    }
                }
            }
            .frame(maxWidth: 720)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct OLSArtifactSelection: Identifiable {
    var url: URL
    var title: String
    var id: String {
        self.url.absoluteString
    }
}

private struct OLSProjectDetailView: View {
    let project: PearStatusData.Project
    let onSelect: (PearStatusData.Project) -> Void

    @State private var detail: OLSProjectDetail?
    @State private var isLoading = false
    @State private var error: String?
    @State private var showAllWork = false
    @State private var artifact: OLSArtifactSelection?

    private var currentProject: PearStatusData.Project {
        self.detail?.project ?? self.project
    }

    private var openWork: [OLSProjectDetail.Work] {
        (self.detail?.tasks ?? []).filter { !$0.isComplete }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                self.identity
                if self.isLoading, self.detail == nil {
                    HStack(spacing: 12) {
                        ProgressView().tint(OLSTheme.accent)
                        Text("Bringing this up to date…").font(OLSTheme.label).foregroundStyle(OLSTheme.secondary)
                    }
                    .padding(.vertical, 24)
                }
                if let error = self.error {
                    OLSCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(error).font(OLSTheme.body).foregroundStyle(OLSTheme.secondary)
                            Button {
                                Task { await self.load() }
                            } label: {
                                Text("Try again").font(OLSTheme.label).frame(minHeight: 44)
                            }
                            .foregroundStyle(OLSTheme.accent)
                        }
                    }
                }
                if let detail = self.detail {
                    self.currentState(detail)
                    self.work(detail)
                    self.materials(detail)
                    if let path = detail.actions?.openProject {
                        Button {
                            self.open(path, title: self.currentProject.name)
                        } label: {
                            HStack {
                                Text("Full project").font(OLSTheme.label)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                            }
                            .frame(minHeight: 44)
                        }
                        .foregroundStyle(OLSTheme.accent)
                    }
                }
            }
            .frame(maxWidth: 720)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .task { await self.load() }
        .refreshable { await self.load() }
        .fullScreenCover(item: self.$artifact) { item in
            OLSArtifactView(url: item.url, title: item.title) { self.artifact = nil }
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(self.currentProject.emoji ?? "🍐")
                .font(OLSTheme.title)
                .frame(width: 64, height: 64)
                .background(OLSTheme.soft, in: RoundedRectangle(cornerRadius: 18))
                .accessibilityHidden(true)
            Text(self.currentProject.name)
                .font(OLSTheme.title)
                .foregroundStyle(OLSTheme.ink)
                .accessibilityAddTraits(.isHeader)
            Text(self.currentProject.hashtag).font(OLSTheme.chip).foregroundStyle(OLSTheme.secondary)
            Button {
                self.onSelect(self.currentProject)
            } label: {
                Label {
                    Text("Talk about this").font(OLSTheme.label)
                } icon: {
                    Image(systemName: "bubble.left")
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 46)
                .background(OLSTheme.soft, in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(OLSTheme.ink)
            .accessibilityHint("Return to our conversation with this project selected")
        }
    }

    @ViewBuilder
    private func currentState(_ detail: OLSProjectDetail) -> some View {
        let summary = detail.brief?.summary ?? detail.project.bestSummary
        if let summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            OLSCard {
                VStack(alignment: .leading, spacing: 14) {
                    OLSSectionHeading(title: detail.brief?.stale == true ? "Last update" : "Right now")
                    Text(self.markdown(summary))
                        .font(OLSTheme.body)
                        .foregroundStyle(OLSTheme.ink)
                        .tint(OLSTheme.accent)
                        .textSelection(.enabled)
                    if let raw = detail.brief?.updatedAt, let date = PearAPI.parseISODate(raw) {
                        Text(date, format: .dateTime.month(.abbreviated).day().hour().minute())
                            .font(OLSTheme.caption)
                            .foregroundStyle(OLSTheme.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func work(_ detail: OLSProjectDetail) -> some View {
        let waiting = self.openWork.filter { $0.isBlocked && !($0.blockedBy ?? "").isEmpty }
        if !waiting.isEmpty {
            OLSCard {
                VStack(alignment: .leading, spacing: 16) {
                    OLSSectionHeading(title: "What’s waiting")
                    ForEach(waiting) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title).font(OLSTheme.label).foregroundStyle(OLSTheme.ink)
                            Text(item.blockedBy ?? "").font(OLSTheme.body).foregroundStyle(OLSTheme.secondary)
                        }
                    }
                }
            }
        }
        let moving = self.openWork.filter { !$0.isBlocked || ($0.blockedBy ?? "").isEmpty }
        if !moving.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                OLSSectionHeading(title: "In the works")
                OLSCard {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(self.showAllWork ? moving : Array(moving.prefix(6))) { item in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.title).font(OLSTheme.label).foregroundStyle(OLSTheme.ink)
                                Text(item.statusLabel).font(OLSTheme.caption).foregroundStyle(OLSTheme.secondary)
                            }
                        }
                        if moving.count > 6 {
                            Button {
                                self.showAllWork.toggle()
                            } label: {
                                Text(self.showAllWork ? "Show less" : "Show all \(moving.count)")
                                    .font(OLSTheme.label)
                                    .frame(minHeight: 44)
                            }
                            .foregroundStyle(OLSTheme.accent)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func materials(_ detail: OLSProjectDetail) -> some View {
        let pages = detail.allPages
        let files = (detail.files ?? []).filter { $0.url != nil }
        if !pages.isEmpty || !files.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                OLSSectionHeading(title: "Made and gathered")
                OLSCard {
                    VStack(spacing: 0) {
                        ForEach(pages) { page in
                            self.fileRow(
                                title: page.title,
                                subtitle: "Page",
                                symbol: "doc.text",
                                path: page.url ?? "/p/\(page.id)")
                        }
                        ForEach(files) { file in
                            self.fileRow(
                                title: file.name,
                                subtitle: self.fileSubtitle(file),
                                symbol: file.mimeType?.hasPrefix("image/") == true ? "photo" : "doc",
                                path: file.url ?? "")
                        }
                    }
                }
            }
        }
    }

    private func fileRow(title: String, subtitle: String, symbol: String, path: String) -> some View {
        Button {
            self.open(path, title: title)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol).foregroundStyle(OLSTheme.accent).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(OLSTheme.label).foregroundStyle(OLSTheme.ink)
                    Text(subtitle).font(OLSTheme.caption).foregroundStyle(OLSTheme.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").foregroundStyle(OLSTheme.secondary).accessibilityHidden(true)
            }
            .padding(.vertical, 12)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
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
        self.artifact = OLSArtifactSelection(url: url, title: title)
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

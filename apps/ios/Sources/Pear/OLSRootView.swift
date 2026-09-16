import SwiftUI

/// The prototype's stage: the thread is home, Projects rises from the bottom edge, a project
/// opens from Projects, and Voice slides in from the header's presence button.
struct OLSRootView: View {
    @Environment(NodeAppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var auth = PearAuthModel()
    @State private var model = OLSModel()
    @State private var projects: [PearStatusData.Project] = []
    @State private var activeDetail: OLSProjectDetail?
    @State private var openedProject: PearStatusData.Project?
    @State private var surface: Surface = .chat
    @State private var voiceOrigin: Surface = .chat
    @State private var showContext = false
    @State private var showProfile = false
    @State private var showDeviceControls = false
    @State private var projectError: String?

    enum Surface { case chat, projects, project, voice }

    private var screenshotMode: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--pear-ols-screenshot")
        #else
        false
        #endif
    }

    private var signedIn: Bool {
        self.auth.isSignedIn || self.screenshotMode
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                self.header
                if self.signedIn {
                    OLSTimelineView(
                        model: self.model,
                        projects: self.projects,
                        activeDetail: self.activeDetail,
                        openContext: { self.showContext = true },
                        openProjects: { self.navigate(.projects) },
                        openProject: { project in
                            self.openedProject = project
                            self.navigate(.project)
                        },
                        openVoice: { self.navigate(.voice) })
                } else {
                    self.signIn
                }
            }
            .opacity(self.surface == .chat ? 1 : 0)
            .allowsHitTesting(self.surface == .chat)
            .accessibilityHidden(self.surface != .chat)
            if self.surface == .projects || self.surface == .project {
                OLSProjectsView(
                    model: self.model,
                    projects: self.projects,
                    projectError: self.projectError,
                    retry: { Task { await self.begin() } },
                    onReturn: { self.navigate(.chat) },
                    openProject: { project in
                        self.openedProject = project
                        self.navigate(.project)
                    },
                    openVoice: { self.navigate(.voice) },
                    jumpToSegment: self.jump(toSegment:))
                    .opacity(self.surface == .projects ? 1 : 0)
                    .allowsHitTesting(self.surface == .projects)
                    .accessibilityHidden(self.surface != .projects)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if self.surface == .project, let project = self.openedProject {
                OLSProjectView(
                    project: project,
                    model: self.model,
                    back: { self.navigate(.projects) },
                    returnToThread: { self.navigate(.chat) },
                    openVoice: { self.navigate(.voice) },
                    jumpToSegment: self.jump(toSegment:),
                    talkAbout: { project in
                        self.model.selectProject(project.id)
                        self.navigate(.chat)
                    })
                    .id(project.id)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            if self.surface == .voice {
                OLSVoiceView(
                    model: self.model,
                    originLabel: self.originLabel,
                    projectName: self.projects.first(where: { $0.id == self.model.activeContext?.projectId })?.name,
                    onReturn: { self.navigate(self.voiceOrigin) })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(OLSTheme.field)
        .foregroundStyle(OLSTheme.ink)
        .tint(OLSTheme.accent)
        .statusBarHidden(false)
        .task {
            if self.screenshotMode {
                #if DEBUG
                self.projects = OLSModel.screenshotProjects
                self.model.installScreenshotFixture()
                #endif
                return
            }
            await self.auth.bootstrap()
            if self.auth.isSignedIn { await self.begin() }
        }
        .onChange(of: self.auth.isSignedIn) { _, signedIn in
            if signedIn {
                Task { await self.begin() }
            } else {
                self.model.clear()
                self.projects = []
                self.activeDetail = nil
                self.openedProject = nil
                self.surface = .chat
            }
        }
        .onChange(of: self.scenePhase) { _, phase in
            guard !self.screenshotMode else { return }
            if phase == .active, self.auth.isSignedIn { self.model.start() } else { self.model.stop() }
        }
        .onChange(of: self.model.activeContext?.projectId) { _, projectID in
            guard !self.screenshotMode else { return }
            Task { await self.loadActiveDetail(projectID) }
        }
        .sheet(isPresented: self.$showContext) { self.contextPicker }
        .sheet(isPresented: self.$showProfile) { self.profile }
        .fullScreenCover(isPresented: self.$showDeviceControls) {
            VStack(spacing: 0) {
                HStack {
                    Button { self.showDeviceControls = false } label: {
                        Label { Text("Back to PEAR").font(OLSTheme.label) } icon: { Image(systemName: "chevron.left") }
                    }
                    Spacer()
                }.padding()
                RootTabs()
            }
        }
        // Preserve upstream device-driven navigation without making it the
        // primary product interface or changing any gateway connection state.
        .onChange(of: self.appModel.openChatRequestID) { _, _ in self.showDeviceControls = true }
    }

    // MARK: - Header (`.thread-header`)

    private var header: some View {
        HStack(spacing: 11) {
            Button { self.navigate(.voice) } label: {
                ZStack {
                    Circle().fill(OLSTheme.presence)
                    Circle().strokeBorder(OLSTheme.presenceMark.opacity(0.32), lineWidth: 1)
                        .frame(width: 28, height: 28)
                        .shadow(color: OLSTheme.presenceMark.opacity(0.22), radius: 9)
                    Image("PearMark")
                        .resizable().renderingMode(.template).scaledToFit()
                        .foregroundStyle(OLSTheme.presenceMark)
                        .frame(width: 18, height: 27)
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(!self.signedIn)
            .accessibilityIdentifier("ols.voice")
            .accessibilityLabel("Open voice")
            VStack(alignment: .leading, spacing: 3) {
                Text("PEAR").font(OLSTheme.wordmark).foregroundStyle(OLSTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                Button { self.showContext = true } label: {
                    Text(self.subtitle)
                        .font(OLSTheme.detail)
                        .foregroundStyle(OLSTheme.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.plain)
                .disabled(!self.signedIn)
                .accessibilityIdentifier("ols.context")
                .accessibilityLabel("Context and places in our conversation")
            }
            Spacer(minLength: 8)
            Button { self.showProfile = true } label: {
                Image(systemName: "person.circle")
                    .font(.system(size: 21, weight: .light))
                    .foregroundStyle(OLSTheme.secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ols.profile")
            .accessibilityLabel("Profile")
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(OLSTheme.field)
        .overlay(alignment: .bottom) { OLSTheme.hairline.frame(height: 1) }
    }

    /// `Here with you` normally, `Working with you` while a send is in flight, and the hashtag
    /// of the moment being read when that adds information.
    private var subtitle: String {
        if self.model.isSending { return "Working with you" }
        guard self.signedIn, let context = self.model.context(before: self.model.visibleMessageID),
              context.slug?.isEmpty == false
        else { return "Here with you" }
        return context.hashtag
    }

    private var originLabel: String {
        switch self.voiceOrigin {
        case .project: self.openedProject?.name ?? "Project"
        case .projects: "Projects"
        default: "Thread"
        }
    }

    // MARK: - Sign in (`.live-thread-notice`)

    private var signIn: some View {
        ScrollView {
            VStack(spacing: 16) {
                OLSNotice(
                    kicker: "Private by default",
                    title: "Sign in to continue with me.",
                    message: "Your projects and conversations stay behind your Playground account.",
                    action: self.auth.isWorking ? "Connecting…" : "Continue with Google")
                {
                    Task { await self.auth.signIn() }
                }
                .disabled(self.auth.isWorking)
                if case let .failed(message) = self.auth.phase {
                    Text(message).font(OLSTheme.caption).foregroundStyle(OLSTheme.warning)
                }
            }
            .padding(EdgeInsets(top: 20, leading: 18, bottom: 40, trailing: 18))
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Profile (`.profile-popover`)

    private var profile: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(self.model.personName.map { "\($0.split(separator: " ").first ?? "") + PEAR" } ?? "You + PEAR")
                            .font(OLSTheme.rowTitle).foregroundStyle(OLSTheme.ink)
                        Text(self.auth.displayEmail ?? "Shared context · private")
                            .font(OLSTheme.caption).foregroundStyle(OLSTheme.secondary)
                    }
                }
                Section {
                    Button {
                        self.showProfile = false
                        self.showDeviceControls = true
                    } label: { Text("Device & connection").font(OLSTheme.label) }
                    Button {
                        self.auth.signOutSessionOnly()
                        self.showProfile = false
                    } label: { Text("Sign out").font(OLSTheme.label) }
                        .accessibilityIdentifier("ols.sign-out")
                }
            }
            .scrollContentBackground(.hidden)
            .background(OLSTheme.field)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { self.showProfile = false } label: { Text("Done").font(OLSTheme.labelStrong) }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Context picker

    private var pickerSegments: [OLSSegment] {
        if !self.model.segments.isEmpty { return self.model.segments }
        return self.model.contexts.reversed().map { context in
            OLSSegment(
                id: context.segmentId, projectId: context.projectId, slug: context.slug,
                label: context.label, source: context.source, provisional: context.provisional)
        }
    }

    private var contextPicker: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Button {
                            if let id = self.model.previousAnchor() { self.jump(to: id) }
                        } label: {
                            Label { Text("Previous").font(OLSTheme.labelStrong) } icon: { Image(systemName: "chevron.left") }
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .disabled(self.model.previousAnchor() == nil)
                        .accessibilityIdentifier("ols.anchor.previous")
                        .accessibilityLabel("Previous anchor")
                        Button {
                            if let id = self.model.nextAnchor() { self.jump(to: id) }
                        } label: {
                            Label { Text("Next").font(OLSTheme.labelStrong) } icon: { Image(systemName: "chevron.right") }
                                .labelStyle(.trailingIcon)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .disabled(self.model.nextAnchor() == nil)
                        .accessibilityIdentifier("ols.anchor.next")
                        .accessibilityLabel("Next anchor")
                    }
                    .buttonStyle(.borderless)
                } header: {
                    Text("Move between anchors · or swipe left and right").font(OLSTheme.caption)
                }
                Section {
                    ForEach(self.pickerSegments) { segment in
                        Button {
                            self.jump(toSegment: segment.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(segment.context.displayName).font(OLSTheme.rowTitle).foregroundStyle(OLSTheme.ink)
                                HStack {
                                    Text(segment.context.hashtag).font(OLSTheme.chip).foregroundStyle(OLSTheme.secondary)
                                    if let raw = segment.createdAt, let date = PearAPI.parseISODate(raw) {
                                        Text(OLSModel.periodLabel(for: date, now: self.model.now()))
                                            .font(OLSTheme.caption).foregroundStyle(OLSTheme.secondary)
                                    }
                                }
                            }
                        }
                        .accessibilityIdentifier("ols.moment.\(segment.id)")
                    }
                } header: { Text("Return to a moment").font(OLSTheme.caption) }
                Section {
                    Button {
                        self.model.selectProject(nil)
                        self.showContext = false
                    } label: { Text("Let our conversation guide it").font(OLSTheme.label) }
                    ForEach(self.projects) { project in
                        Button {
                            self.model.selectProject(project.id)
                            self.showContext = false
                            self.navigate(.chat)
                        } label: {
                            HStack(spacing: 12) {
                                Text(project.emoji ?? "🍐").accessibilityHidden(true)
                                Text(project.name).font(OLSTheme.label).foregroundStyle(OLSTheme.ink)
                            }
                        }
                        .accessibilityIdentifier("ols.talk-about.\(project.id)")
                    }
                } header: { Text("Talk about").font(OLSTheme.caption) }
            }
            .scrollContentBackground(.hidden)
            .background(OLSTheme.field)
            .navigationTitle("Our conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { self.showContext = false } label: { Text("Done").font(OLSTheme.labelStrong) }
                }
            }
        }
    }

    // MARK: - Navigation

    private func navigate(_ destination: Surface) {
        if destination == .voice, self.surface != .voice { self.voiceOrigin = self.surface }
        withAnimation(self.reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.9)) {
            self.surface = destination
        }
    }

    private func jump(to messageID: String) {
        self.showContext = false
        self.navigate(.chat)
        self.model.jump(to: messageID)
    }

    private func jump(toSegment segmentID: String) {
        self.showContext = false
        self.navigate(.chat)
        Task { await self.model.jump(toSegment: segmentID) }
    }

    private func begin() async {
        let session = PearSessionStore.load()
        guard let identity = session?.sessionID else { return }
        self.model.personName = session?.name
        self.model.restore(scope: self.auth.displayEmail ?? identity)
        self.model.start()
        struct Projects: Decodable { var projects: [PearStatusData.Project] }
        do {
            let result: Projects = try await OLSClient().get("/api/ols/projects")
            guard self.auth.isSignedIn, PearSessionStore.load()?.sessionID == identity else { return }
            self.projects = result.projects
            self.projectError = nil
        } catch {
            guard self.auth.isSignedIn, PearSessionStore.load()?.sessionID == identity else { return }
            self.projectError = "Projects couldn’t load just now."
        }
        await self.loadActiveDetail(self.model.activeContext?.projectId)
    }

    /// The object card's decision row needs the project's tasks; only the current project is fetched.
    private func loadActiveDetail(_ projectID: Int?) async {
        guard let projectID else {
            self.activeDetail = nil
            return
        }
        if self.activeDetail?.project.id == projectID { return }
        let detail: OLSProjectDetail? = try? await OLSClient().get("/api/ols/projects/\(projectID)")
        guard self.model.activeContext?.projectId == projectID else { return }
        self.activeDetail = detail
    }
}

struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon
        }
    }
}

extension LabelStyle where Self == TrailingIconLabelStyle {
    static var trailingIcon: TrailingIconLabelStyle { TrailingIconLabelStyle() }
}

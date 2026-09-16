import SwiftUI

/// The app frame: Mark's header (mark + `pear` wordmark, voice button), one surface at a
/// time underneath. Chat is home; Details and Project sit under it; Voice is a side room.
struct OLSRootView: View {
    @Environment(NodeAppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var auth = PearAuthModel()
    @State private var model = OLSModel()
    @State private var projects: [PearStatusData.Project] = []
    @State private var openedProject: PearStatusData.Project?
    @State private var surface: Surface = .chat
    @State private var voiceOrigin: Surface = .chat
    @State private var showContext = false
    @State private var showDeviceControls = false
    @State private var projectError: String?

    enum Surface { case chat, details, project, voice }

    private var screenshotMode: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--pear-ols-screenshot")
        #else
        false
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            self.header
            if self.auth.isSignedIn || self.screenshotMode {
                self.content
            } else {
                self.signIn
            }
        }
        .background(OLSTheme.background)
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
                self.openedProject = nil
                self.surface = .chat
            }
        }
        .onChange(of: self.scenePhase) { _, phase in
            guard !self.screenshotMode else { return }
            if phase == .active, self.auth.isSignedIn { self.model.start() } else { self.model.stop() }
        }
        .sheet(isPresented: self.$showContext) { self.contextPicker }
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

    // MARK: - Header

    private var header: some View {
        ZStack {
            if self.surface == .chat || !(self.auth.isSignedIn || self.screenshotMode) {
                HStack(spacing: 10) {
                    Button(action: { self.navigate(.details) }) {
                        HStack(spacing: 10) {
                            Image("PearMark")
                                .resizable().scaledToFit().frame(width: 34, height: 34)
                                .accessibilityHidden(true)
                            Text("pear").font(OLSTheme.wordmark).foregroundStyle(OLSTheme.ink)
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(!(self.auth.isSignedIn || self.screenshotMode))
                    .accessibilityIdentifier("ols.header")
                    .accessibilityLabel("pear")
                    .accessibilityHint("Open details")
                    if self.surface == .chat, let context = self.model.context(before: self.model.visibleMessageID) {
                        Button { self.showContext = true } label: {
                            Text(context.hashtag)
                                .font(OLSTheme.chip)
                                .foregroundStyle(OLSTheme.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("ols.context")
                        .accessibilityLabel("Context and places in our conversation")
                    }
                    Spacer(minLength: 8)
                }
            } else {
                Text("pear").font(OLSTheme.wordmark).foregroundStyle(OLSTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                HStack {
                    Button(action: self.goBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(OLSTheme.ink)
                            .frame(width: 44, height: 44)
                            .background(OLSTheme.soft, in: Circle())
                    }
                    .accessibilityIdentifier("ols.back")
                    .accessibilityLabel(self.backLabel)
                    Spacer()
                }
            }
            HStack {
                Spacer()
                if self.surface != .voice, self.auth.isSignedIn || self.screenshotMode {
                    Button { self.navigate(.voice) } label: {
                        Image(systemName: "waveform")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(OLSTheme.ink)
                            .frame(width: 44, height: 44)
                            .background(OLSTheme.soft, in: Circle())
                    }
                    .accessibilityIdentifier("ols.voice")
                    .accessibilityLabel("Voice")
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(OLSTheme.header)
        .overlay(alignment: .bottom) { OLSTheme.line.frame(height: 1) }
        .contentShape(Rectangle())
        // Pulling down on the header spine returns from Details or a Project; taps always work too.
        .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { value in
            guard self.surface == .details || self.surface == .project else { return }
            if value.translation.height > 60, value.translation.height > abs(value.translation.width) * 1.4 {
                self.goBack()
            }
        })
    }

    private var backLabel: String {
        switch self.surface {
        case .project: "Back to details"
        case .voice: "Back"
        default: "Back to conversation"
        }
    }

    private func goBack() {
        switch self.surface {
        case .project: self.navigate(.details)
        case .voice: self.navigate(self.voiceOrigin)
        default: self.navigate(.chat)
        }
    }

    // MARK: - Surfaces

    private var content: some View {
        GeometryReader { geometry in
            ZStack {
                OLSTimelineView(
                    model: self.model,
                    projects: self.projects,
                    openContext: { self.showContext = true },
                    openDetails: { self.navigate(.details) })
                    .opacity(self.surface == .chat ? 1 : 0)
                    .allowsHitTesting(self.surface == .chat)
                    .accessibilityHidden(self.surface != .chat)
                if self.surface == .details || self.surface == .project {
                    OLSDetailsView(
                        model: self.model,
                        projects: self.projects,
                        email: self.auth.displayEmail,
                        openContext: { self.showContext = true },
                        jumpToSegment: self.jump(toSegment:),
                        openProject: { project in
                            self.openedProject = project
                            self.navigate(.project)
                        },
                        openDeviceControls: { self.showDeviceControls = true },
                        signOut: { self.auth.signOutSessionOnly() },
                        projectError: self.projectError,
                        retryProjects: { Task { await self.begin() } })
                        .opacity(self.surface == .details ? 1 : 0)
                        .allowsHitTesting(self.surface == .details)
                        .accessibilityHidden(self.surface != .details)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if self.surface == .project, let project = self.openedProject {
                    OLSProjectView(
                        project: project,
                        model: self.model,
                        jumpToSegment: self.jump(toSegment:),
                        talkAbout: { project in
                            self.model.selectProject(project.id)
                            self.navigate(.chat)
                        })
                        .id(project.id)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                if self.surface == .voice {
                    OLSVoiceView(model: self.model, onReturn: { self.navigate(self.voiceOrigin) })
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
    }

    private var signIn: some View {
        VStack(spacing: 22) {
            Spacer()
            Image("PearMark").resizable().scaledToFit().frame(width: 72, height: 72).accessibilityHidden(true)
            Text("Here with you.").font(OLSTheme.greeting).foregroundStyle(OLSTheme.ink)
            Text("Your conversation, and the things we’re making together.")
                .font(OLSTheme.body).foregroundStyle(OLSTheme.secondary).multilineTextAlignment(.center)
            Button { Task { await self.auth.signIn() } } label: {
                Text(self.auth.isWorking ? "Connecting…" : "Continue with Google")
                    .font(OLSTheme.action).foregroundStyle(OLSTheme.ink)
                    .padding(.horizontal, 24).frame(minHeight: 50)
                    .background(OLSTheme.human, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(self.auth.isWorking)
            if case let .failed(message) = self.auth.phase {
                Text(message).font(OLSTheme.caption).foregroundStyle(OLSTheme.warning)
            }
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                            Label { Text("Previous").font(OLSTheme.action) } icon: { Image(systemName: "chevron.left") }
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .disabled(self.model.previousAnchor() == nil)
                        .accessibilityIdentifier("ols.anchor.previous")
                        .accessibilityLabel("Previous anchor")
                        Button {
                            if let id = self.model.nextAnchor() { self.jump(to: id) }
                        } label: {
                            Label { Text("Next").font(OLSTheme.action) } icon: { Image(systemName: "chevron.right") }
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
            .background(OLSTheme.background)
            .navigationTitle("Our conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { self.showContext = false } label: { Text("Done").font(OLSTheme.action) }
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

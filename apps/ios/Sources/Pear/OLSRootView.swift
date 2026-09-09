import SwiftUI

struct OLSRootView: View {
    @Environment(NodeAppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var auth = PearAuthModel()
    @State private var model = OLSModel()
    @State private var projects: [PearStatusData.Project] = []
    @State private var inspectedProject: PearStatusData.Project?
    @State private var surface: Surface = .chat
    @State private var voiceOrigin: Surface = .chat
    @State private var showContext = false
    @State private var showSettings = false
    @State private var showDeviceControls = false
    @State private var projectError: String?

    enum Surface { case chat, projects, voice }

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
                self.model.installScreenshotFixture()
                self.projects = [
                    PearStatusData.Project(
                        id: 1,
                        slug: "weekend-garden",
                        name: "Weekend garden",
                        emoji: "🌱",
                        summary: "Saturday afternoon stays free."),
                    PearStatusData.Project(
                        id: 2,
                        slug: "summer-trip",
                        name: "Summer trip",
                        emoji: "☀️",
                        summary: "A little room to wander."),
                ]
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
                self.inspectedProject = nil
                self.surface = .chat
            }
        }
        .onChange(of: self.scenePhase) { _, phase in
            guard !self.screenshotMode else { return }
            if phase == .active, self.auth.isSignedIn { self.model.start() } else { self.model.stop() }
        }
        .sheet(isPresented: self.$showContext) { self.contextPicker }
        .sheet(isPresented: self.$showSettings) { self.settings }
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

    private var header: some View {
        HStack(spacing: 12) {
            Image("PearMark")
                .resizable().scaledToFit().frame(width: 44, height: 44)
                .clipShape(Circle()).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("PEAR").font(OLSTheme.heading)
                Button { self.showContext = true } label: {
                    Text(self.model.context(before: self.model.visibleMessageID)?.hashtag ?? "Here with you")
                        .font(OLSTheme.caption)
                        .foregroundStyle(OLSTheme.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .accessibilityIdentifier("ols.context")
                .accessibilityLabel("Context and places in our conversation")
            }
            Spacer(minLength: 8)
            if self.horizontalSizeClass == .regular {
                HStack(spacing: 18) {
                    Button { self.navigate(.chat) } label: { Text("Chat").font(OLSTheme.label) }
                    Button { self.navigate(.projects) } label: { Text("Projects").font(OLSTheme.label) }
                }
            }
            Button { self.showSettings = true } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(OLSTheme.secondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("PEAR settings")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .background(OLSTheme.background)
        .overlay(alignment: .bottom) { OLSTheme.line.frame(height: 1) }
    }

    private var content: some View {
        GeometryReader { geometry in
            ZStack {
                OLSTimelineView(
                    model: self.model,
                    projects: self.projects,
                    openContext: { self.showContext = true },
                    inspectProject: { project in
                        self.inspectedProject = project
                        self.navigate(.projects)
                    },
                    openVoice: { self.navigate(.voice) },
                    openProjects: { self.navigate(.projects) })
                    .opacity(self.surface == .chat ? 1 : 0)
                    .allowsHitTesting(self.surface == .chat)
                    .accessibilityHidden(self.surface != .chat)
                OLSProjectsView(
                    projects: self.projects,
                    selectedProject: self.inspectedProject,
                    onSelect: { project in
                        self.model.selectProject(project.id)
                        self.inspectedProject = project
                        self.navigate(.chat)
                    },
                    onReturn: { self.navigate(.chat) })
                    .opacity(self.surface == .projects ? 1 : 0)
                    .offset(y: self.surface == .projects ? 0 : geometry.size.height)
                    .allowsHitTesting(self.surface == .projects)
                    .accessibilityHidden(self.surface != .projects)
                    .overlay(alignment: .top) {
                        if let projectError, self.surface == .projects {
                            HStack {
                                Text(projectError).font(OLSTheme.caption)
                                Button { Task { await self.begin() } } label: { Text("Retry").font(OLSTheme.label) }
                            }.padding().background(OLSTheme.paper)
                        }
                    }
                if self.surface == .voice {
                    OLSVoiceView(model: self.model, onReturn: { self.navigate(self.voiceOrigin) })
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }.clipped()
        }
    }

    private var signIn: some View {
        VStack(spacing: 22) {
            Spacer()
            Text("Here with you.").font(OLSTheme.title)
            Text("Your conversation, and the things we’re making together.")
                .font(OLSTheme.body).foregroundStyle(OLSTheme.secondary).multilineTextAlignment(.center)
            Button { Task { await self.auth.signIn() } } label: {
                Text(self.auth.isWorking ? "Connecting…" : "Continue with Google")
                    .font(OLSTheme.body).padding(16)
                    .background(OLSTheme.human, in: Capsule())
            }.disabled(self.auth.isWorking)
            if case let .failed(message) = self.auth.phase {
                Text(message).font(OLSTheme.caption).foregroundStyle(OLSTheme.warning)
            }
            Spacer()
        }.padding(32)
    }

    private var contextPicker: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(self.model.contexts) { context in
                        Button {
                            self.showContext = false
                            self.navigate(.chat)
                            self.model.isAtPresent = false
                            self.model.visibleMessageID = self.model.messages.first(where: {
                                $0.context?.segmentId == context.segmentId
                            })?.id
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(context.label ?? context.hashtag).font(OLSTheme.label)
                                Text(context.hashtag).font(OLSTheme.chip).foregroundStyle(OLSTheme.secondary)
                            }
                        }
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
                            self.inspectedProject = project
                            self.showContext = false
                            self.navigate(.chat)
                        } label: { Text(project.name).font(OLSTheme.label) }
                    }
                } header: { Text("Talk about").font(OLSTheme.caption) }
            }
            .navigationTitle("Our conversation")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { self.showContext = false } label: { Text("Done").font(OLSTheme.label) }
                }
            }
        }
    }

    private var settings: some View {
        NavigationStack {
            List {
                if let email = self.auth.displayEmail { Text(email).font(OLSTheme.label) }
                Button {
                    self.showSettings = false
                    self.showDeviceControls = true
                } label: { Text("Device & connection").font(OLSTheme.label) }
                Button {
                    self.auth.signOutSessionOnly()
                    self.showSettings = false
                } label: { Text("Sign out").font(OLSTheme.label) }
            }
            .navigationTitle("PEAR")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { self.showSettings = false } label: { Text("Done").font(OLSTheme.label) }
                }
            }
        }
    }

    private func navigate(_ destination: Surface) {
        if destination == .voice, self.surface != .voice { self.voiceOrigin = self.surface }
        withAnimation(self.reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.9)) {
            self.surface = destination
        }
    }

    private func begin() async {
        let identity = PearSessionStore.load()?.sessionID
        guard let identity else { return }
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

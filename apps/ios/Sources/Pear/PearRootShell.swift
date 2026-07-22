import SwiftUI
import UIKit

/// The native Playground world: Home · Chats · Projects · Apps · ⋯
/// Replaces the fullscreen WebView as the app's root; the old canvas stays one
/// tap away as "Classic view" (backstage) so nothing the node could do is lost.
struct PearRootShell: View {
    @Environment(NodeAppModel.self) private var appModel
    @State private var store = PearStore()
    @State private var authModel = PearAuthModel()
    @State private var chatModel = PearChatModel()
    @State private var selectedTab: Tab = .home
    @State private var showClassicCanvas = false
    @State private var showNodeChat = false

    enum Tab: Hashable {
        case home
        case chats
        case projects
        case apps
        case backstage
    }

    var body: some View {
        TabView(selection: self.$selectedTab) {
            PearHomeView(store: self.store, authModel: self.authModel, openChats: { self.selectedTab = .chats })
                .tabItem { Label("Home", systemImage: "house") }
                .tag(Tab.home)

            PearChatsView(store: self.store, chatModel: self.chatModel)
                .tabItem { Label("Chats", systemImage: "bubble.left.and.bubble.right") }
                .tag(Tab.chats)

            PearProjectsView(store: self.store)
                .tabItem { Label("Projects", systemImage: "shippingbox") }
                .tag(Tab.projects)

            PearAppsView(store: self.store)
                .tabItem { Label("Apps", systemImage: "square.grid.2x2") }
                .tag(Tab.apps)

            PearBackstageView(
                store: self.store,
                authModel: self.authModel,
                openClassicCanvas: { self.showClassicCanvas = true },
                openNodeChat: { self.showNodeChat = true })
                .tabItem { Label("More", systemImage: "ellipsis") }
                .tag(Tab.backstage)
        }
        .tint(PearTheme.pear)
        // Info.plist hides the status bar for the fullscreen canvas; the native
        // shell wants it back (the classic cover re-hides its own).
        .statusBarHidden(false)
        .task {
            await self.authModel.bootstrap()
            await self.store.refresh()
        }
        // Node-world plumbing stays live at the root so pairing, trust prompts,
        // gateway deep links, and camera flashes work without the classic view.
        .gatewayTrustPromptAlert()
        .deepLinkAgentPromptAlert()
        .overlay {
            if self.appModel.cameraFlashNonce != 0 {
                PearCameraFlashOverlay(nonce: self.appModel.cameraFlashNonce)
            }
        }
        .onChange(of: self.appModel.openChatRequestID) { _, _ in
            self.showNodeChat = true
        }
        .onChange(of: self.appModel.canvasCommandNonce) { _, _ in
            // The gateway explicitly drove the canvas (canvas.present/navigate,
            // a2ui.reset) — surface the classic view so agent-driven navigation
            // still lands. Connect-time auto-navigation does not bump the nonce,
            // so launching the app on a paired phone stays in the native shell.
            self.showClassicCanvas = true
        }
        .sheet(isPresented: self.$showNodeChat) {
            ChatSheet(
                gateway: self.appModel.operatorSession,
                sessionKey: self.appModel.chatSessionKey,
                agentName: self.appModel.activeAgentName,
                userAccent: self.appModel.seamColor)
        }
        .fullScreenCover(isPresented: self.$showClassicCanvas) {
            PearClassicCanvasCover()
        }
    }
}

/// The pre-native app, intact: fullscreen Playground WebView with all of its
/// overlays, onboarding, and sheets — now a reachable fallback surface.
private struct PearClassicCanvasCover: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RootCanvas()

            Button {
                self.dismiss()
            } label: {
                Label("Back to app", systemImage: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.leading, 12)
            .padding(.bottom, 26)
            .accessibilityLabel("Close classic view")
        }
    }
}

/// Camera flash feedback, mirrored from the classic canvas so remote captures
/// stay visible in the native shell.
private struct PearCameraFlashOverlay: View {
    var nonce: Int

    @State private var opacity: CGFloat = 0
    @State private var task: Task<Void, Never>?

    var body: some View {
        Color.white
            .opacity(self.opacity)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .onChange(of: self.nonce) { _, _ in
                self.task?.cancel()
                self.task = Task { @MainActor in
                    withAnimation(.easeOut(duration: 0.08)) {
                        self.opacity = 0.85
                    }
                    try? await Task.sleep(nanoseconds: 110_000_000)
                    withAnimation(.easeOut(duration: 0.32)) {
                        self.opacity = 0
                    }
                }
            }
    }
}

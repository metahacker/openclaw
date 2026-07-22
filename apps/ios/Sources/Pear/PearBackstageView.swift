import SwiftUI

/// ⋯ — backstage. Machinery lives here: the classic canvas, the node's gateway
/// chat, settings, and the honest state of both connections.
struct PearBackstageView: View {
    var store: PearStore
    var authModel: PearAuthModel
    var openClassicCanvas: () -> Void
    var openNodeChat: () -> Void

    @Environment(NodeAppModel.self) private var appModel
    @Environment(GatewayConnectionController.self) private var gatewayController
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    Text("Backstage")
                        .font(PearTheme.pageTitle)
                        .foregroundStyle(PearTheme.ink)
                        .padding(.top, 12)

                    Text("Everything else — one layer back, exactly where it belongs.")
                        .font(.system(size: 14))
                        .foregroundStyle(PearTheme.walnut)
                        .padding(.bottom, 10)

                    PearDayMark(label: "Surfaces")
                    PearBackstageRow(
                        emoji: "🖥️",
                        title: "Classic view",
                        subtitle: "The full Playground web canvas — everything, exactly as before.",
                        action: self.openClassicCanvas)
                    PearBackstageRow(
                        emoji: "🔧",
                        title: "Node chat",
                        subtitle: "Talk to the agent over the OpenClaw gateway session.",
                        action: self.openNodeChat)
                    PearBackstageRow(
                        emoji: "⚙️",
                        title: "Settings",
                        subtitle: "Gateway pairing, voice wake, camera, and node options.",
                        action: { self.showSettings = true })

                    PearDayMark(label: "State")
                    PearStateRow(
                        label: "Google",
                        value: self.authModel.statusText,
                        healthy: self.store.hasPlaygroundSession)
                    PearStateRow(
                        label: "Gateway",
                        value: self.appModel.gatewayServerName ?? "not connected",
                        healthy: self.appModel.gatewayServerName != nil)
                    PearStateRow(
                        label: "Home stream",
                        value: self.store.feedSource == .homeFeed ? "live feed" : "projects fallback",
                        healthy: self.store.feedSource == .homeFeed)
                    if self.store.hasPlaygroundSession {
                        PearBackstageRow(
                            emoji: "🔑",
                            title: "Forget Playground session",
                            subtitle: "Keep the legacy device key, but require Google again for private data.",
                            action: self.authModel.signOutSessionOnly)
                    }

                    if let summary = self.store.briefingSummary {
                        PearDayMark(label: "This morning")
                        Text(summary.strippingMarkdownLinks)
                            .font(.system(size: 13.5))
                            .foregroundStyle(PearTheme.walnut)
                            .padding(15)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .pearCard()
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
            .background(PearTheme.cream)
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: self.$showSettings) {
                // Same explicit re-injection RootCanvas uses for its settings sheet.
                SettingsTab()
                    .environment(self.appModel)
                    .environment(self.appModel.voiceWake)
                    .environment(self.gatewayController)
            }
        }
    }
}

struct PearBackstageRow: View {
    let emoji: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            HStack(spacing: 13) {
                PearGlyphTile(emoji: self.emoji, side: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(self.title)
                        .font(PearTheme.rowTitle)
                        .foregroundStyle(PearTheme.ink)
                    Text(self.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(PearTheme.walnut)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PearTheme.faint)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .pearCard()
        }
        .buttonStyle(PearPressableStyle())
    }
}

struct PearStateRow: View {
    let label: String
    let value: String
    let healthy: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(self.healthy ? PearTheme.presence : PearTheme.amber)
                .frame(width: 8, height: 8)
            Text(self.label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(PearTheme.ink)
            Spacer()
            Text(self.value)
                .font(PearTheme.kind)
                .foregroundStyle(PearTheme.faint)
                .lineLimit(1)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .pearCard()
    }
}

extension String {
    /// The briefing summary arrives with Markdown links; backstage renders it quiet.
    var strippingMarkdownLinks: String {
        self.replacingOccurrences(
            of: #"\[([^\]]+)\]\([^)]*\)"#,
            with: "$1",
            options: .regularExpression)
    }
}

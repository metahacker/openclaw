import SwiftUI

/// Home — "What we're working on": the conversations in motion, then the
/// day-grouped stream of real work, newest first. Machinery lives one layer back.
struct PearHomeView: View {
    var store: PearStore
    var authModel: PearAuthModel
    var openChats: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    self.header

                    if !self.store.hasPlaygroundSession {
                        PearConnectCard(authModel: self.authModel)
                    }

                    if !self.store.inMotion.isEmpty {
                        self.inMotionSection
                    }

                    ForEach(self.store.daySections) { section in
                        PearDayMark(label: section.label)
                        ForEach(section.cards) { card in
                            PearStreamCardView(card: card)
                        }
                    }

                    if self.store.daySections.isEmpty, self.store.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    }

                    if let error = self.store.lastError {
                        Text(error)
                            .font(PearTheme.truthLine)
                            .foregroundStyle(PearTheme.faint)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
            .background(PearTheme.cream)
            .scrollIndicators(.hidden)
            .refreshable { await self.store.refresh() }
            .task { await self.store.refreshIfStale() }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("🍐")
                    .font(.system(size: 17))
                Text("Playground")
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundStyle(PearTheme.ink)
                Spacer()
                PearPresenceDot()
            }
            .padding(.top, 10)

            Text("What we're working on")
                .font(PearTheme.pageTitle)
                .foregroundStyle(PearTheme.ink)
                .padding(.top, 14)

            Text("The real things we made, wrote, and put down — newest first — "
                + "and the conversations still in motion.")
                .font(.system(size: 15))
                .foregroundStyle(PearTheme.walnut)
                .padding(.bottom, 8)
        }
    }

    private var inMotionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("IN MOTION — CONVERSATIONS")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .kerning(1.6)
                    .foregroundStyle(PearTheme.walnut)
                Spacer()
                Button("all conversations →", action: self.openChats)
                    .font(PearTheme.kind)
                    .foregroundStyle(PearTheme.faint)
            }
            .padding(.top, 8)

            ForEach(self.store.inMotion.prefix(4)) { motion in
                Button(action: self.openChats) {
                    PearMotionCardView(motion: motion)
                }
                .buttonStyle(PearPressableStyle())
            }
        }
        .padding(.bottom, 10)
    }
}

/// A conversation-in-motion card (prototype `.chatcard`).
struct PearMotionCardView: View {
    let motion: PearStore.MotionCard

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(self.motion.emoji) \(self.motion.title)")
                .font(PearTheme.rowTitle)
                .foregroundStyle(PearTheme.ink)
                .multilineTextAlignment(.leading)
            if let status = self.motion.status, !status.isEmpty {
                Text(status)
                    .font(.system(size: 13))
                    .foregroundStyle(PearTheme.walnut)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
            HStack(spacing: 9) {
                if let tag = self.motion.tag {
                    PearTagChip(tag: tag)
                }
                Spacer()
                PearKindTag(text: self.motion.surface ?? "in motion")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .pearCard(accented: true)
    }
}

/// A deliverable card in the home stream (prototype `.card`).
struct PearStreamCardView: View {
    let card: PearStore.StreamCard
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = self.card.url {
                self.openURL(url)
            }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                PearGlyphTile(emoji: self.card.emoji)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(self.card.title)
                            .font(PearTheme.cardTitle)
                            .foregroundStyle(PearTheme.ink)
                            .multilineTextAlignment(.leading)
                        if self.card.pinned {
                            Text("★")
                                .font(.system(size: 12))
                                .foregroundStyle(PearTheme.amber)
                        }
                    }
                    if let summary = self.card.summary, !summary.isEmpty {
                        Text(summary)
                            .font(PearTheme.summary)
                            .foregroundStyle(PearTheme.walnut)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                    }
                    HStack(spacing: 10) {
                        if let tag = self.card.tag {
                            PearTagChip(tag: tag)
                        }
                        if let kind = self.card.kind {
                            PearKindTag(text: kind)
                        }
                    }
                    .padding(.top, 3)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .pearCard()
        }
        .buttonStyle(PearPressableStyle())
        .disabled(self.card.url == nil)
    }
}

/// Gentle spring press feedback for cards.
struct PearPressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

/// Shown until the Safari handoff has linked this device.
struct PearConnectCard: View {
    var authModel: PearAuthModel

    var body: some View {
        Button {
            Task { await self.authModel.signIn() }
        } label: {
            HStack(spacing: 13) {
                Text("🍐")
                    .font(.system(size: 26))
                VStack(alignment: .leading, spacing: 3) {
                    Text(self.title)
                        .font(PearTheme.rowTitle)
                        .foregroundStyle(PearTheme.ink)
                    Text(self.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(PearTheme.walnut)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                if self.authModel.isWorking {
                    ProgressView()
                        .tint(PearTheme.pear)
                } else {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PearTheme.pear)
                }
            }
            .padding(15)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(PearTheme.pearSoft)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(PearTheme.pear.opacity(0.35), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(PearPressableStyle())
        .disabled(self.authModel.isWorking)
        .padding(.vertical, 6)
    }

    private var title: String {
        switch self.authModel.phase {
        case .failed:
            "Sign in again"
        case .restoring:
            "Restoring your session"
        case .signingIn:
            "Finish Google sign-in"
        default:
            "Sign in with Google"
        }
    }

    private var subtitle: String {
        switch self.authModel.phase {
        case let .failed(reason):
            "\(reason) Tap to retry."
        case .restoring:
            "Turning the saved device link into a real Playground session."
        case .signingIn:
            "Use Google once; PEAR will keep the Playground session on this phone."
        default:
            "Use Google once to unlock the private stream, chats, and project wiki homes."
        }
    }
}

import SwiftUI

/// Chats — the direct line to PEAR first, then everything in motion.
struct PearChatsView: View {
    var store: PearStore
    var chatModel: PearChatModel

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    Text("Chats")
                        .font(PearTheme.pageTitle)
                        .foregroundStyle(PearTheme.ink)
                        .padding(.top, 12)
                        .padding(.bottom, 6)

                    NavigationLink {
                        PearConversationView(chatModel: self.chatModel, title: "PEAR")
                    } label: {
                        PearThreadRow(
                            emoji: "🍐",
                            title: "PEAR",
                            status: self.directThreadStatus,
                            tag: nil,
                            live: true)
                    }
                    .buttonStyle(PearPressableStyle())

                    if !self.store.conversations.isEmpty {
                        PearDayMark(label: "Recent")
                        ForEach(self.store.conversations) { conversation in
                            NavigationLink {
                                PearConversationScreen(conversation: conversation)
                            } label: {
                                PearThreadRow(
                                    emoji: conversation.bestEmoji,
                                    title: conversation.bestTitle,
                                    status: conversation.bestStatus,
                                    tag: conversation.bestTag,
                                    live: conversation.activityActive == true)
                            }
                            .buttonStyle(PearPressableStyle())
                        }
                    }

                    if !self.store.inMotion.isEmpty {
                        PearDayMark(label: "In motion")
                        ForEach(self.store.inMotion) { motion in
                            NavigationLink {
                                PearConversationView(
                                    chatModel: self.chatModel,
                                    title: "PEAR",
                                    contextTitle: motion.title)
                            } label: {
                                PearThreadRow(
                                    emoji: motion.emoji,
                                    title: motion.title,
                                    status: motion.status,
                                    tag: motion.tag,
                                    live: false)
                            }
                            .buttonStyle(PearPressableStyle())
                        }
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

    private var directThreadStatus: String {
        if let last = self.chatModel.messages.last {
            return last.text
        }
        return "here with you"
    }
}

private struct PearConversationScreen: View {
    let conversation: PearConversationSummary
    @State private var chatModel: PearChatModel

    init(conversation: PearConversationSummary) {
        self.conversation = conversation
        _chatModel = State(initialValue: PearChatModel(page: conversation.page ?? "/apps/pear-mobile"))
    }

    var body: some View {
        PearConversationView(chatModel: self.chatModel, title: self.conversation.bestTitle)
    }
}

/// Prototype `.threadrow`: emoji · serif title · one-line status · hashtag chip.
struct PearThreadRow: View {
    let emoji: String
    let title: String
    let status: String?
    let tag: String?
    let live: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            Text(self.emoji)
                .font(.system(size: 20))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(self.title)
                        .font(PearTheme.rowTitle)
                        .foregroundStyle(PearTheme.ink)
                        .lineLimit(1)
                    if self.live {
                        PearPresenceDot(size: 6)
                    }
                }
                if let status, !status.isEmpty {
                    Text(status)
                        .font(.system(size: 13.5))
                        .foregroundStyle(PearTheme.walnut)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let tag {
                PearTagChip(tag: tag)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .pearCard()
    }
}

/// The intimate conversation: your words right in soft green, PEAR's left on
/// paper, no borders, no avatars — with the Field and its truth line beneath.
struct PearConversationView: View {
    @Bindable var chatModel: PearChatModel
    var title: String
    var contextTitle: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 3) {
                        if let contextTitle {
                            Text(contextTitle)
                                .font(PearTheme.kind)
                                .kerning(1.2)
                                .foregroundStyle(PearTheme.faint)
                                .padding(.vertical, 12)
                        }
                        ForEach(self.chatModel.messages) { message in
                            PearBubble(message: message)
                                .id(message.id)
                        }
                        if self.chatModel.messages.isEmpty, !self.chatModel.isLoadingHistory {
                            Text("say anything — I'm here")
                                .font(PearTheme.truthLine)
                                .foregroundStyle(PearTheme.faint)
                                .padding(.top, 80)
                        }
                        Color.clear
                            .frame(height: 6)
                            .id("chat-bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: self.chatModel.messages.count) { _, _ in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        proxy.scrollTo("chat-bottom", anchor: .bottom)
                    }
                }
                .onAppear {
                    proxy.scrollTo("chat-bottom", anchor: .bottom)
                }
            }

            PearFieldComposer(chatModel: self.chatModel)
        }
        .background(PearTheme.cream)
        .navigationTitle(self.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Text(self.title)
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                        .foregroundStyle(PearTheme.ink)
                        .lineLimit(1)
                    PearPresenceDot(size: 6)
                }
            }
        }
        .onAppear { self.chatModel.startPolling() }
        .onDisappear { self.chatModel.stopPolling() }
    }
}

/// iMessage grammar, warm palette. Trailing tail corner tightened like the prototype.
struct PearBubble: View {
    let message: PearChatHistory.Message

    var body: some View {
        HStack {
            if !self.message.isPear {
                Spacer(minLength: 48)
            }
            Text(self.message.text)
                .font(.system(size: 15))
                .foregroundStyle(PearTheme.ink)
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
                .background {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 20,
                        bottomLeadingRadius: self.message.isPear ? 7 : 20,
                        bottomTrailingRadius: self.message.isPear ? 20 : 7,
                        topTrailingRadius: 20)
                        .fill(self.message.isPear ? PearTheme.pearBubble : PearTheme.youBubble)
                        .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
                }
                .frame(
                    maxWidth: .infinity,
                    alignment: self.message.isPear ? .leading : .trailing)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.94, anchor: self.message.isPear ? .bottomLeading : .bottomTrailing)
                        .combined(with: .opacity),
                    removal: .opacity))
            if self.message.isPear {
                Spacer(minLength: 48)
            }
        }
        .padding(.vertical, 2)
    }
}

/// The Field: one compact pill — ＋, the draft, mic, send — and beneath it the
/// truth line, one quiet mono line that always tells the real state.
struct PearFieldComposer: View {
    @Bindable var chatModel: PearChatModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(PearTheme.walnut)
                    .frame(width: 30, height: 30)
                    .background(PearTheme.tile, in: Circle())

                TextField("I'm here — say anything…", text: self.$chatModel.draft, axis: .vertical)
                    .font(.system(size: 15))
                    .foregroundStyle(PearTheme.ink)
                    .lineLimit(1...4)
                    .focused(self.$focused)
                    .onSubmit { self.sendNow() }

                Image(systemName: "mic")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(PearTheme.walnut)

                Button(action: self.sendNow) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(self.canSend ? PearTheme.pear : PearTheme.faint, in: Circle())
                }
                .disabled(!self.canSend)
                .accessibilityLabel("Send")
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: self.canSend)
            }
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(PearTheme.paper)
                    .overlay { Capsule().strokeBorder(PearTheme.line, lineWidth: 1) }
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
            }

            Text(self.chatModel.truthLine)
                .font(PearTheme.truthLine)
                .foregroundStyle(PearTheme.faint)
                .animation(.easeInOut(duration: 0.2), value: self.chatModel.truthLine)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(PearTheme.cream)
    }

    private var canSend: Bool {
        !self.chatModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && self.chatModel.sendState != .sending
    }

    private func sendNow() {
        guard self.canSend else { return }
        Task { await self.chatModel.send() }
    }
}

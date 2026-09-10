import CryptoKit
import Foundation
import Observation

@MainActor
@Observable
final class OLSModel {
    private(set) var messages: [OLSMessage] = []
    private(set) var activeContext: OLSContext?
    private(set) var hasMore = false
    private(set) var isLoading = false
    private(set) var isSending = false
    private(set) var isPaging = false
    private(set) var error: String?
    private(set) var sendStatus: String?
    private(set) var selectedProjectID: Int?
    var attachments: [OLSAttachment] = []
    var draft = "" {
        didSet { self.savePlace() }
    }

    var visibleMessageID: String? {
        didSet { self.savePlace() }
    }

    var isAtPresent = true

    /// One-shot request for the timeline to bring a message to the top. Explicit jumps
    /// (restoring a saved place, choosing a moment) go through here rather than a two-way
    /// scrollPosition binding: that binding re-anchors on every layout pass and, once the
    /// composer changes height under the keyboard, spins the main thread indefinitely.
    struct ScrollRequest: Equatable {
        let messageID: String
        let token: UUID
    }

    private(set) var scrollRequest: ScrollRequest?

    @ObservationIgnored private let service: any OLSService
    @ObservationIgnored private var beforeCursor: String?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var pending: PendingSend?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var selectionRevision = 0
    @ObservationIgnored private var storageKey: String?

    private struct SavedPlace: Codable {
        var draft: String
        var messageID: String?
    }

    func restore(scope: String) {
        let key = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
        guard key != self.storageKey else { return }
        self.storageKey = nil
        if let raw = KeychainStore.loadString(service: "ai.openclaw.pear.ols-place", account: key),
           let data = raw.data(using: .utf8),
           let saved = try? JSONDecoder().decode(SavedPlace.self, from: data)
        {
            self.draft = saved.draft
            if let messageID = saved.messageID {
                self.jump(to: messageID)
            } else {
                self.visibleMessageID = nil
                self.isAtPresent = true
            }
        }
        self.storageKey = key
    }

    func jump(to messageID: String) {
        self.isAtPresent = false
        self.visibleMessageID = messageID
        self.scrollRequest = ScrollRequest(messageID: messageID, token: UUID())
    }

    func completeScrollRequest(_ request: ScrollRequest) {
        if self.scrollRequest == request { self.scrollRequest = nil }
    }

    private func savePlace() {
        guard let storageKey,
              let data = try? JSONEncoder().encode(SavedPlace(draft: self.draft, messageID: self.visibleMessageID)),
              let raw = String(data: data, encoding: .utf8)
        else { return }
        _ = KeychainStore.saveString(raw, service: "ai.openclaw.pear.ols-place", account: storageKey)
    }

    private struct PendingSend {
        let text: String
        let requestID: String
        let projectID: Int?
        let attachments: [String]
    }

    init(service: any OLSService = OLSClient()) {
        self.service = service
    }

    var contexts: [OLSContext] {
        var seen = Set<String>()
        return self.messages.compactMap(\.context).filter { seen.insert($0.segmentId).inserted }
    }

    func context(before messageID: String?) -> OLSContext? {
        guard let messageID, let index = self.messages.firstIndex(where: { $0.id == messageID }) else {
            return self.activeContext
        }
        return self.messages[...index].last(where: { $0.context != nil })?.context
    }

    /// Looking at an anchor never invokes this. Only "Talk about this" or an
    /// explicit context correction sets the next send's project override.
    func selectProject(_ id: Int?) {
        self.selectedProjectID = id
        self.selectionRevision += 1
    }

    func refresh() async {
        guard !self.isLoading else { return }
        let generation = self.generation
        self.isLoading = true
        defer { if self.generation == generation { self.isLoading = false } }
        do {
            let page = try await self.service.timeline(before: nil)
            guard self.generation == generation else { return }
            let wasEmpty = self.messages.isEmpty
            self.merge(page.items)
            self.activeContext = page.activeContext
            if wasEmpty {
                self.beforeCursor = page.beforeCursor
                self.hasMore = page.hasMore
            }
            self.error = nil
        } catch is CancellationError {
            return
        } catch {
            guard self.generation == generation else { return }
            self.error = error.localizedDescription
        }
    }

    func loadEarlier() async {
        guard self.hasMore, !self.isPaging, let beforeCursor else { return }
        let generation = self.generation
        self.isPaging = true
        defer { if self.generation == generation { self.isPaging = false } }
        do {
            let page = try await self.service.timeline(before: beforeCursor)
            guard self.generation == generation else { return }
            self.merge(page.items)
            self.beforeCursor = page.beforeCursor
            self.hasMore = page.hasMore
            self.error = nil
        } catch {
            guard self.generation == generation else { return }
            self.error = error.localizedDescription
        }
    }

    func send() async {
        let text = self.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachmentIDs = self.attachments.compactMap(\.id)
        guard !text.isEmpty || !attachmentIDs.isEmpty, !self.isSending else { return }
        let generation = self.generation
        let selectionRevision = self.selectionRevision
        // A retry of unchanged words reuses its identity and original context.
        // Navigation or a late response cannot redirect an in-flight turn.
        let attempt: PendingSend = if let pending, pending.text == text, pending.attachments == attachmentIDs {
            pending
        } else {
            PendingSend(
                text: text,
                requestID: UUID().uuidString,
                projectID: self.selectedProjectID,
                attachments: attachmentIDs)
        }
        self.pending = attempt
        self.isSending = true
        self.sendStatus = "Sending…"
        defer { if self.generation == generation { self.isSending = false } }
        do {
            let receipt = try await self.service.send(
                text: attempt.text,
                requestID: attempt.requestID,
                projectID: attempt.projectID,
                attachments: attempt.attachments)
            guard self.generation == generation else { return }
            guard receipt.ok else {
                self.sendStatus = "Not sent. Tap Send to try again."
                return
            }
            // The person can keep typing while the send is in flight.
            if self.draft.trimmingCharacters(in: .whitespacesAndNewlines) == text { self.draft = "" }
            self.pending = nil
            self.attachments.removeAll { attempt.attachments.contains($0.id ?? "") }
            if self.selectionRevision == selectionRevision { self.selectedProjectID = nil }
            self.sendStatus = receipt.status == "queued" ? "Queued" : "Sent"
            await self.refresh()
        } catch is CancellationError {
            guard self.generation == generation else { return }
            self.sendStatus = "Send interrupted. Your words are still here."
        } catch {
            guard self.generation == generation else { return }
            self.sendStatus = "Not sent. Tap Send to try again."
        }
    }

    func start() {
        guard self.refreshTask == nil else { return }
        self.refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(for: .seconds(4)) } catch { return }
            }
        }
    }

    func stop() {
        self.refreshTask?.cancel()
        self.refreshTask = nil
    }

    func clear() {
        self.stop()
        self.savePlace()
        self.storageKey = nil
        self.generation += 1
        self.selectionRevision += 1
        self.isLoading = false
        self.isPaging = false
        self.isSending = false
        self.messages = []
        self.activeContext = nil
        self.draft = ""
        self.pending = nil
        self.attachments = []
        self.beforeCursor = nil
        self.selectedProjectID = nil
        self.sendStatus = nil
        self.error = nil
        self.visibleMessageID = nil
        self.scrollRequest = nil
        self.hasMore = false
    }

    private func merge(_ incoming: [OLSMessage]) {
        var byID = Dictionary(self.messages.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        for message in incoming {
            byID[message.id] = message
        }
        self.messages = byID.values.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.localizedStandardCompare($1.id) == .orderedAscending
        }
    }

    #if DEBUG
    func installScreenshotFixture() {
        let context = OLSContext(
            segmentId: "sample-garden", projectId: 1, slug: "weekend-garden", label: "Weekend garden", source: "sample")
        let next = OLSContext(
            segmentId: "sample-trip", projectId: 2, slug: "summer-trip", label: "Summer trip", source: "sample")
        self.messages = [
            OLSMessage(
                id: "1",
                role: "user",
                text: "Can we keep Saturday afternoon free?",
                createdAt: "2026-09-09T10:00:00Z",
                context: context),
            OLSMessage(
                id: "2",
                role: "assistant",
                text: "The morning plan still fits. Saturday afternoon stays open, "
                    + "and the plant list is ready when you want it.",
                createdAt: "2026-09-09T10:01:00Z",
                context: context),
            OLSMessage(
                id: "3",
                role: "user",
                text: "And where did we leave the summer trip?",
                createdAt: "2026-09-09T10:02:00Z",
                context: next),
            OLSMessage(
                id: "4",
                role: "assistant",
                text: "The itinerary is together. The only open question is which evening to leave unplanned.",
                createdAt: "2026-09-09T10:03:00Z",
                context: next),
        ]
        self.activeContext = next
    }
    #endif
}

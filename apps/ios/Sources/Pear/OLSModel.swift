import CryptoKit
import Foundation
import Observation

@MainActor
@Observable
final class OLSModel {
    private(set) var messages: [OLSMessage] = []
    private(set) var activeContext: OLSContext?
    /// Every segment the person owns, newest first, including ones not loaded yet.
    private(set) var segments: [OLSSegment] = []
    /// Display name from the signed-in identity; nil keeps the greeting nameless.
    var personName: String?
    /// The segment whose context-check card the person already answered.
    private(set) var dismissedContextCheck: String?
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
    @ObservationIgnored private var commentaryTask: Task<Void, Never>?
    @ObservationIgnored private var pending: PendingSend?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var selectionRevision = 0
    @ObservationIgnored private var storageKey: String?
    /// Injectable clock so the screenshot fixture renders a stable date kicker.
    @ObservationIgnored var now: () -> Date = { Date() }

    /// Scroll target for the greeting block at the top of the present.
    static let presentID = "ols-present"

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
            if let messageID = saved.messageID, !messageID.hasPrefix("commentary:") {
                self.jump(to: messageID)
            } else {
                self.showPresent()
            }
        } else {
            self.showPresent()
        }
        self.storageKey = key
    }

    /// Mark's first viewport: the date, greeting, and today's conversation from its start.
    func showPresent() {
        self.visibleMessageID = nil
        self.isAtPresent = true
        self.scrollRequest = ScrollRequest(messageID: Self.presentID, token: UUID())
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
              let data = try? JSONEncoder().encode(SavedPlace(
                  draft: self.draft,
                  messageID: self.durableMessageID(for: self.visibleMessageID))),
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

    var latestFinalReply: OLSMessage? {
        self.messages.last(where: { $0.isAssistant && !$0.isCommentary })
    }

    func durableMessageID(for messageID: String?) -> String? {
        guard let messageID, let index = self.messages.firstIndex(where: { $0.id == messageID }) else {
            return messageID
        }
        guard self.messages[index].isCommentary else { return messageID }
        if let preceding = self.messages.prefix(index).last(where: { !$0.isCommentary }) { return preceding.id }
        return self.messages.dropFirst(index + 1).first(where: { !$0.isCommentary })?.id
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
            if let segments = page.segments { self.segments = segments }
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

    /// Commentary is a best-effort presence lane. If it is temporarily unavailable,
    /// the durable conversation remains usable and the next poll quietly tries again.
    func refreshCommentary() async {
        let generation = self.generation
        do {
            let feed = try await self.service.progress()
            guard self.generation == generation else { return }
            let messages = feed.statuses.flatMap { status in
                status.commentary.map { commentary in
                    OLSMessage(
                        id: "commentary:\(commentary.id)",
                        kind: "commentary",
                        role: "assistant",
                        text: commentary.text,
                        createdAt: commentary.createdAt,
                        context: status.context)
                }
            }
            self.merge(messages)
        } catch is CancellationError {
            return
        } catch {
            guard self.generation == generation else { return }
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
        if self.refreshTask == nil {
            self.refreshTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.refresh()
                    do { try await Task.sleep(for: .seconds(4)) } catch { return }
                }
            }
        }
        if self.commentaryTask == nil {
            self.commentaryTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.refreshCommentary()
                    do { try await Task.sleep(for: .seconds(3)) } catch { return }
                }
            }
        }
    }

    func stop() {
        self.refreshTask?.cancel()
        self.refreshTask = nil
        self.commentaryTask?.cancel()
        self.commentaryTask = nil
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
        self.segments = []
        self.personName = nil
        self.dismissedContextCheck = nil
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

    // MARK: - Inline anchors

    /// IDs of the messages that open a new context segment, in timeline order.
    /// Returning to a subject later opens a new anchor; earlier ones are never regrouped.
    static func anchorIDs(_ messages: [OLSMessage]) -> [String] {
        var previous: String?
        var ids: [String] = []
        for message in messages {
            guard let segment = message.context?.segmentId else { continue }
            if segment != previous { ids.append(message.id) }
            previous = segment
        }
        return ids
    }

    var anchorIDs: [String] {
        Self.anchorIDs(self.messages)
    }

    /// The anchor that opens the segment containing `messageID` (nil above the first anchor).
    static func anchor(containing messageID: String?, in messages: [OLSMessage]) -> String? {
        guard let messageID, let index = messages.firstIndex(where: { $0.id == messageID }) else { return nil }
        let anchors = Set(self.anchorIDs(messages))
        return messages[...index].last(where: { anchors.contains($0.id) })?.id
    }

    /// Swipe left: the anchor after the one the person is reading.
    static func nextAnchor(after messageID: String?, in messages: [OLSMessage]) -> String? {
        let anchors = self.anchorIDs(messages)
        guard let current = self.anchor(containing: messageID, in: messages),
              let index = anchors.firstIndex(of: current)
        else { return anchors.first }
        return anchors.indices.contains(index + 1) ? anchors[index + 1] : nil
    }

    /// Swipe right: the start of the current segment, or the previous anchor when already there.
    static func previousAnchor(before messageID: String?, in messages: [OLSMessage]) -> String? {
        let anchors = self.anchorIDs(messages)
        guard let messageID, let current = self.anchor(containing: messageID, in: messages),
              let index = anchors.firstIndex(of: current)
        else { return nil }
        if current != messageID { return current }
        return index > 0 ? anchors[index - 1] : nil
    }

    func nextAnchor() -> String? {
        Self.nextAnchor(after: self.visibleMessageID, in: self.messages)
    }

    func previousAnchor() -> String? {
        Self.previousAnchor(before: self.visibleMessageID, in: self.messages)
    }

    /// The first loaded message of a segment; pages back a bounded number of times to find it.
    func jump(toSegment segmentID: String) async {
        for _ in 0..<6 {
            if let id = self.messages.first(where: { $0.context?.segmentId == segmentID })?.id {
                self.jump(to: id)
                return
            }
            guard self.hasMore, !self.isPaging else { break }
            await self.loadEarlier()
        }
        if let id = self.messages.first(where: { $0.context?.segmentId == segmentID })?.id { self.jump(to: id) }
    }

    // MARK: - Context check

    /// The latest turn's context when the backend only guessed it; the person can keep or change it.
    var contextCheck: OLSContext? {
        guard let latest = self.messages.last(where: { !$0.isCommentary && !$0.isAssistant }),
              let context = latest.context, context.provisional == true,
              context.segmentId != self.dismissedContextCheck
        else { return nil }
        return context
    }

    func dismissContextCheck() {
        self.dismissedContextCheck = self.contextCheck?.segmentId
    }

    // MARK: - Present block

    /// ID of the first message from today; the greeting sits right above it.
    var presentMessageID: String? {
        let calendar = Calendar.autoupdatingCurrent
        let today = self.now()
        return self.messages.first(where: { message in
            guard let date = PearAPI.parseISODate(message.createdAt) else { return false }
            return calendar.isDate(date, inSameDayAs: today)
        })?.id
    }

    static func greeting(hour: Int, name: String?) -> String {
        let opening = switch hour {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
        guard let first = name?.split(separator: " ").first.map(String.init), !first.isEmpty else {
            return opening + "."
        }
        return "\(opening), \(first)."
    }

    var greeting: String {
        Self.greeting(hour: Calendar.autoupdatingCurrent.component(.hour, from: self.now()), name: self.personName)
    }

    /// `Monday · August 17`, uppercased by the kicker style.
    var dateKicker: String {
        let day = self.now()
        return day.formatted(.dateTime.weekday(.wide)) + " · " + day.formatted(.dateTime.month(.wide).day())
    }

    /// `This morning` / `Yesterday` / `August 12`: the day-part label that precedes a run of messages.
    static func periodLabel(for date: Date, now: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return switch calendar.component(.hour, from: date) {
            case ..<12: "This morning"
            case 12..<17: "This afternoon"
            default: "This evening"
            }
        }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return date.formatted(.dateTime.month(.wide).day())
        }
        return date.formatted(.dateTime.month(.wide).day().year())
    }

    func periodLabel(for message: OLSMessage) -> String? {
        guard let date = PearAPI.parseISODate(message.createdAt) else { return nil }
        return Self.periodLabel(for: date, now: self.now())
    }

    /// One calm sentence built only from real project summaries; never invented.
    static func summaryLine(projects: [PearStatusData.Project]) -> String {
        let recent = projects.sorted { ($0.updatedDate ?? .distantPast) > ($1.updatedDate ?? .distantPast) }
        var sentences: [String] = []
        for project in recent {
            guard let summary = project.bestSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !summary.isEmpty
            else { continue }
            let plain = (try? AttributedString(markdown: summary)).map { String($0.characters) } ?? summary
            let first = plain.split(whereSeparator: { $0 == "\n" }).first.map(String.init) ?? plain
            let sentence = first.components(separatedBy: ". ").first ?? first
            let trimmed = sentence.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
            guard !trimmed.isEmpty, trimmed.count <= 110 else { continue }
            sentences.append(trimmed + ".")
            if sentences.count == 2 { break }
        }
        return sentences.isEmpty ? "Your conversation is here when you want it." : sentences.joined(separator: " ")
    }

    private func merge(_ incoming: [OLSMessage]) {
        var byID = Dictionary(self.messages.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        for message in incoming {
            if let existing = byID[message.id], existing.isCommentary, message.isCommentary {
                var updated = message
                updated.createdAt = existing.createdAt
                byID[message.id] = updated
            } else {
                byID[message.id] = message
            }
        }
        self.messages = byID.values.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.localizedStandardCompare($1.id) == .orderedAscending
        }
    }

    #if DEBUG
    /// Synthetic projects for the CI proof images only; never shown above a real account.
    static let screenshotProjects: [PearStatusData.Project] = [
        PearStatusData.Project(
            id: 1, slug: "japan-family-trip", name: "Japan family trip", emoji: "🗾", category: "Travel",
            updatedAt: "2026-09-16T09:40:00Z", summary: "Tokyo is reconciled; one Kyoto dinner remains open."),
        PearStatusData.Project(
            id: 2, slug: "pear-mvp", name: "PEAR MVP", emoji: "🍐", category: "Product",
            updatedAt: "2026-09-16T09:29:00Z", summary: "Mark is tightening five complete long-form screens."),
        PearStatusData.Project(
            id: 3, slug: "new-york-arrangements", name: "New York arrangements", emoji: "🗽", category: "Family",
            updatedAt: "2026-09-15T18:00:00Z", summary: "Travel and family coordination are current."),
    ]

    /// A → B → A: two Japan segments around one PEAR MVP segment, one attachment card, one
    /// provisional context check. Fixed clock so the kicker and labels are stable in CI.
    func installScreenshotFixture() {
        self.now = { PearAPI.parseISODate("2026-09-16T09:41:00Z") ?? Date() }
        self.personName = "Alex"
        let japan = OLSContext(
            segmentId: "sample-japan-1", projectId: 1, slug: "japan-family-trip", label: "Japan family trip",
            source: "named", provisional: false)
        let mvp = OLSContext(
            segmentId: "sample-mvp", projectId: 2, slug: "pear-mvp", label: "PEAR MVP", source: "named",
            provisional: false)
        let japanAgain = OLSContext(
            segmentId: "sample-japan-2", projectId: 1, slug: "japan-family-trip", label: "Japan family trip",
            source: "heuristic", provisional: true)
        self.messages = [
            OLSMessage(
                id: "1",
                role: "user",
                text: "Our Tokyo hotel moved check-in. Can you make sure the quieter afternoon still works?",
                createdAt: "2026-09-16T07:38:00Z",
                context: japan),
            OLSMessage(
                id: "2",
                role: "assistant",
                text: "I moved the slower afternoon forward and kept the family dinner open. "
                    + "The route and reservations still agree.",
                createdAt: "2026-09-16T07:40:00Z",
                context: japan,
                attachments: [OLSAttachment(
                    id: "sample-plan",
                    url: "https://pear.metahack.io/api/ols/files/sample-plan",
                    name: "Tokyo day plan.pdf",
                    mimeType: "application/pdf")]),
            OLSMessage(
                id: "3",
                role: "user",
                text: "Back to the MVP UI—give Mark complete screens, not a design system.",
                createdAt: "2026-09-16T09:27:00Z",
                context: mvp),
            OLSMessage(
                id: "commentary:sample",
                kind: "commentary",
                role: "assistant",
                text: "I’m laying out the whole composition before extracting anything.",
                createdAt: "2026-09-16T09:28:00Z",
                context: mvp),
            OLSMessage(
                id: "4",
                role: "assistant",
                text: "Whole composition first. I’ll extract the system after the visual language coheres.",
                createdAt: "2026-09-16T09:29:00Z",
                context: mvp),
            OLSMessage(
                id: "5",
                role: "user",
                text: "And the Kyoto dinner—did that get settled?",
                createdAt: "2026-09-16T09:36:00Z",
                context: japanAgain),
            OLSMessage(
                id: "6",
                role: "assistant",
                text: "Not yet. Two good paths remain, and no reservation has been made.",
                createdAt: "2026-09-16T09:38:00Z",
                context: japanAgain),
        ]
        self.segments = [
            OLSSegment(
                id: "sample-japan-2", projectId: 1, slug: "japan-family-trip", label: "Japan family trip",
                source: "heuristic", provisional: true, createdAt: "2026-09-16T09:36:00Z"),
            OLSSegment(
                id: "sample-mvp", projectId: 2, slug: "pear-mvp", label: "PEAR MVP", source: "named",
                provisional: false, createdAt: "2026-09-16T09:27:00Z"),
            OLSSegment(
                id: "sample-japan-1", projectId: 1, slug: "japan-family-trip", label: "Japan family trip",
                source: "named", provisional: false, createdAt: "2026-09-16T07:38:00Z"),
        ]
        self.activeContext = japanAgain
    }
    #endif
}

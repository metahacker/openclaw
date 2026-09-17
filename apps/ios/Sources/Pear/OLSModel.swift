import CryptoKit
import Foundation
import Observation

@MainActor
@Observable
final class OLSModel {
    private(set) var messages: [OLSMessage] = []
    private(set) var activeContext: OLSContext?
    /// Visible runs from every loaded page, newest first. The server computes runs per page;
    /// merging here keeps the picker and Projects honest after paging back.
    private(set) var segments: [OLSSegment] = []
    /// The opening display window (hours) when the server applied one; nil before the first page.
    private(set) var windowHours: Int?
    /// True once paging has reached history older than the opening window.
    private(set) var beyondWindow = false
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
    /// Injectable clock so day rules are stable in the screenshot fixture and tests.
    @ObservationIgnored var now: () -> Date = { Date() }

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
            self.mergeSegments(page.segments)
            if wasEmpty {
                self.beforeCursor = page.beforeCursor
                self.hasMore = page.hasMore
                if let window = page.window, window.applied != false { self.windowHours = window.hours }
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
            self.mergeSegments(page.segments)
            self.beforeCursor = page.beforeCursor
            self.hasMore = page.hasMore
            self.beyondWindow = true
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
        self.windowHours = nil
        self.beyondWindow = false
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

    /// IDs of the messages that open a new context run, in timeline order.
    /// Returning to a subject later opens a new anchor; earlier ones are never regrouped.
    /// Runs are computed per page, so two runs of one project that touch across a page
    /// boundary read as a single anchor here.
    static func anchorIDs(_ messages: [OLSMessage]) -> [String] {
        var previous: OLSContext?
        var ids: [String] = []
        for message in messages {
            guard let context = message.context else { continue }
            if !self.sameRun(context, previous) { ids.append(message.id) }
            previous = context
        }
        return ids
    }

    private static func sameRun(_ context: OLSContext, _ previous: OLSContext?) -> Bool {
        guard let previous else { return false }
        if context.segmentId == previous.segmentId { return true }
        guard let project = context.projectId else { return false }
        return project == previous.projectId
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

    /// The latest app turn's context when the backend only guessed it; the person can keep or
    /// change it. Turns from Slack or Messages are read here, never corrected here.
    var contextCheck: OLSContext? {
        guard let latest = self.messages.last(where: \.isAppTurn),
              let context = latest.context, context.provisional == true,
              context.segmentId != self.dismissedContextCheck
        else { return nil }
        return context
    }

    func dismissContextCheck() {
        self.dismissedContextCheck = self.contextCheck?.segmentId
    }

    // MARK: - Day rules

    /// `Today` / `Yesterday` / `Sunday` / `August 12`: the prototype's day rule text.
    static func periodLabel(for date: Date, now: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let style = Date.FormatStyle(
            locale: calendar.locale ?? .autoupdatingCurrent,
            calendar: calendar,
            timeZone: calendar.timeZone)
        if let week = calendar.date(byAdding: .day, value: -6, to: now), date >= week, date <= now {
            return date.formatted(style.weekday(.wide))
        }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return date.formatted(style.month(.wide).day())
        }
        return date.formatted(style.month(.wide).day().year())
    }

    func periodLabel(for message: OLSMessage) -> String? {
        guard let date = PearAPI.parseISODate(message.createdAt) else { return nil }
        return Self.periodLabel(for: date, now: self.now())
    }

    private func mergeSegments(_ incoming: [OLSSegment]?) {
        guard let incoming, !incoming.isEmpty else { return }
        var byID = Dictionary(self.segments.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        for segment in incoming {
            byID[segment.id] = segment
        }
        self.segments = byID.values.sorted {
            if $0.createdAt != $1.createdAt { return ($0.createdAt ?? "") > ($1.createdAt ?? "") }
            return $0.id.localizedStandardCompare($1.id) == .orderedDescending
        }
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
            id: 1,
            slug: "japan-family-trip",
            name: "Japan family trip",
            emoji: "🗾",
            category: "Travel",
            updatedAt: "2026-09-16T09:40:00Z",
            summary: "Tokyo is reconciled; one Kyoto dinner remains open."),
        PearStatusData.Project(
            id: 2,
            slug: "pear-mvp",
            name: "PEAR MVP",
            emoji: "🍐",
            category: "Product",
            updatedAt: "2026-09-16T09:29:00Z",
            summary: "Mark is tightening five complete long-form screens."),
        PearStatusData.Project(
            id: 3,
            slug: "new-york-arrangements",
            name: "New York arrangements",
            emoji: "🗽",
            category: "Family",
            updatedAt: "2026-09-15T18:00:00Z",
            summary: "Travel and family coordination are current."),
    ]

    /// The recent stream across surfaces: two Japan runs (app) around one New York run that
    /// happened on Slack and one PEAR MVP run (app), a text with no project yet, one queued turn,
    /// one attachment card, one provisional context check. Fixed clock so labels are stable in CI.
    func installScreenshotFixture() {
        self.now = { PearAPI.parseISODate("2026-09-16T09:41:00Z") ?? Date() }
        self.personName = "Alex"
        self.windowHours = 24
        self.hasMore = true
        let japan = OLSContext(
            segmentId: "sample-japan-1",
            projectId: 1,
            slug: "japan-family-trip",
            label: "Japan family trip",
            source: "named",
            provisional: false,
            originSegmentId: "sample-japan-1",
            surface: "app")
        let newYork = OLSContext(
            segmentId: "sample-ny-slack",
            projectId: 3,
            slug: "new-york-arrangements",
            label: "New York arrangements",
            source: "session",
            provisional: false,
            originSegmentId: "slack:sample-ny",
            surface: "slack")
        let mvp = OLSContext(
            segmentId: "sample-mvp",
            projectId: 2,
            slug: "pear-mvp",
            label: "PEAR MVP",
            source: "named",
            provisional: false,
            originSegmentId: "sample-mvp",
            surface: "app")
        let texts = OLSContext(
            segmentId: "sample-texts",
            projectId: nil,
            slug: nil,
            label: "Here with you",
            source: "unresolved",
            provisional: true,
            originSegmentId: "sb:sample-texts",
            surface: "sendblue")
        let japanAgain = OLSContext(
            segmentId: "sample-japan-2",
            projectId: 1,
            slug: "japan-family-trip",
            label: "Japan family trip",
            source: "llm",
            provisional: true,
            originSegmentId: "sample-japan-2",
            surface: "app")
        let plan = OLSAttachment(
            id: "sample-plan",
            url: "https://pear.metahack.io/api/ols/files/sample-plan",
            name: "Tokyo day plan.pdf",
            mimeType: "application/pdf")
        let resume = OLSRouting(decision: "resume", trigger: "similarity", sessionRef: "pear:ols:v1:sample:c1")
        let stay = OLSRouting(decision: "stay", trigger: nil, sessionRef: "pear:ols:v1:sample:c1")
        self.messages = [
            Self.sample(
                "1",
                "Our Tokyo hotel moved check-in. Can you make sure the quieter afternoon still works?",
                at: "2026-09-16T07:38:00Z",
                in: japan),
            Self.sample(
                "2",
                "I moved the slower afternoon forward and kept the family dinner open. "
                    + "The route and reservations still agree.",
                at: "2026-09-16T07:40:00Z",
                in: japan,
                reply: true,
                attachments: [plan]),
            Self.sample(
                "3",
                "Mom’s flight now lands at six. Can Thursday dinner hold?",
                at: "2026-09-16T08:12:00Z",
                in: newYork),
            Self.sample(
                "4",
                "Thursday holds. I moved the table to seven and told the restaurant.",
                at: "2026-09-16T08:14:00Z",
                in: newYork,
                reply: true),
            Self.sample(
                "5",
                "Back to the MVP UI—give Mark complete screens, not a design system.",
                at: "2026-09-16T09:27:00Z",
                in: mvp),
            OLSMessage(
                id: "commentary:sample",
                kind: "commentary",
                role: "assistant",
                text: "I’m laying out the whole composition before extracting anything.",
                createdAt: "2026-09-16T09:28:00Z",
                context: mvp),
            Self.sample(
                "6",
                "Whole composition first. I’ll extract the system after the visual language coheres.",
                at: "2026-09-16T09:29:00Z",
                in: mvp,
                reply: true),
            Self.sample("7", "Landed. Call you in ten.", at: "2026-09-16T09:33:00Z", in: texts),
            Self.sample(
                "8",
                "And the Kyoto dinner—did that get settled?",
                at: "2026-09-16T09:36:00Z",
                in: japanAgain,
                routing: resume),
            Self.sample(
                "9",
                "Not yet. Two good paths remain, and no reservation has been made.",
                at: "2026-09-16T09:38:00Z",
                in: japanAgain,
                reply: true),
            Self.sample(
                "10",
                "Take the riverside one if it still has the early seating.",
                at: "2026-09-16T09:40:00Z",
                in: japanAgain,
                state: "queued",
                routing: stay),
        ]
        self.segments = [
            Self.sampleSegment(japanAgain, first: "8", last: "10", count: 3, createdAt: "2026-09-16T09:36:00Z"),
            Self.sampleSegment(texts, first: "7", last: "7", count: 1, createdAt: "2026-09-16T09:33:00Z"),
            Self.sampleSegment(mvp, first: "5", last: "6", count: 2, createdAt: "2026-09-16T09:27:00Z"),
            Self.sampleSegment(newYork, first: "3", last: "4", count: 2, createdAt: "2026-09-16T08:12:00Z"),
            Self.sampleSegment(japan, first: "1", last: "2", count: 2, createdAt: "2026-09-16T07:38:00Z"),
        ]
        self.activeContext = japanAgain
    }

    /// A fixture turn on the surface its context names; the session reference follows the surface.
    private static func sample(
        _ id: String,
        _ text: String,
        at createdAt: String,
        in context: OLSContext,
        reply: Bool = false,
        state: String? = nil,
        routing: OLSRouting? = nil,
        attachments: [OLSAttachment]? = nil) -> OLSMessage
    {
        let sessionRef = switch context.surfaceKind {
        case .app: "pear:ols:v1:sample:\(context.projectId == 2 ? "c2" : "c1")"
        case .slack, .dm: "channel:sample:thread:\(context.originSegmentId ?? "")"
        case .sendblue: "+15555550100:c3"
        }
        return OLSMessage(
            id: id,
            role: reply ? "assistant" : "user",
            text: text,
            createdAt: createdAt,
            context: context,
            attachments: attachments,
            surface: context.surface,
            sessionRef: sessionRef,
            dispatchState: state ?? (reply ? "delivered" : "accepted"),
            routing: routing)
    }

    private static func sampleSegment(
        _ context: OLSContext,
        first: String,
        last: String,
        count: Int,
        createdAt: String) -> OLSSegment
    {
        OLSSegment(
            id: context.segmentId,
            projectId: context.projectId,
            slug: context.slug,
            label: context.label,
            source: context.source,
            provisional: context.provisional,
            createdAt: createdAt,
            originSegmentId: context.originSegmentId,
            page: nil,
            surface: context.surface,
            firstMessageId: first,
            lastMessageId: last,
            count: count)
    }
    #endif
}

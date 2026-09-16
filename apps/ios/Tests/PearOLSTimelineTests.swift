import Foundation
import Testing
@testable import OpenClaw

@MainActor
struct PearOLSTimelineTests {
    @Test func `timeline merges without relabeling history or duplicating messages`() async {
        let old = OLSContext(segmentId: "a", projectId: 1, slug: "garden", label: "Garden", source: "explicit")
        let next = OLSContext(segmentId: "b", projectId: 2, slug: "trip", label: "Trip", source: "named")
        let first = OLSMessage(id: "1", role: "user", text: "garden", createdAt: "2026-09-09T01:00:00Z", context: old)
        let second = OLSMessage(
            id: "2",
            role: "assistant",
            text: "answer",
            createdAt: "2026-09-09T01:01:00Z",
            context: old)
        let third = OLSMessage(id: "3", role: "user", text: "trip", createdAt: "2026-09-09T01:02:00Z", context: next)
        let service = StubOLSService(pages: [
            OLSTimeline(streamId: "pair", items: [second, first], hasMore: false, activeContext: old),
            OLSTimeline(streamId: "pair", items: [third, second], hasMore: false, activeContext: next),
        ])
        let model = OLSModel(service: service)
        await model.refresh()
        model.visibleMessageID = "1"
        await model.refresh()
        #expect(model.messages.map(\.id) == ["1", "2", "3"])
        #expect(model.messages.first?.context == old)
        #expect(model.activeContext == next)
        #expect(model.context(before: "1") == old)
        #expect(model.selectedProjectID == nil)
        #expect(model.visibleMessageID == "1")
    }

    @Test func `rejection retains draft and retry identity and origin`() async {
        let service = StubOLSService(receipts: [
            OLSSendReceipt(ok: false, error: "queue unavailable"),
            OLSSendReceipt(ok: true, status: "queued"),
        ])
        let model = OLSModel(service: service)
        model.draft = "Keep the afternoon free."
        model.selectProject(7)
        await model.send()
        #expect(model.draft == "Keep the afternoon free.")
        model.visibleMessageID = "older-project"
        await model.send()
        let requests = await service.requests
        #expect(requests.count == 2)
        #expect(requests[0].requestID == requests[1].requestID)
        #expect(requests[0].projectID == 7 && requests[1].projectID == 7)
        #expect(model.draft.isEmpty)
        #expect(model.sendStatus == "Queued")
    }

    @Test func `delayed history cannot repopulate after sign out`() async {
        let service = SuspendedOLSService()
        let model = OLSModel(service: service)
        let task = Task { await model.refresh() }
        await service.waitForHistory()
        model.clear()
        await service.resolveHistory(OLSTimeline(streamId: "old-account", items: [
            OLSMessage(id: "old", role: "user", text: "private old account", createdAt: "2026-01-01T00:00:00Z"),
        ], hasMore: false))
        await task.value
        #expect(model.messages.isEmpty)
        #expect(!model.isLoading)
    }

    @Test func `pagination retains newer rows and does not duplicate boundary`() async {
        let first = OLSMessage(id: "1", role: "user", text: "older", createdAt: "2026-01-01T00:00:00Z")
        let second = OLSMessage(id: "2", role: "assistant", text: "newer", createdAt: "2026-01-01T00:01:00Z")
        let service = StubOLSService(pages: [
            OLSTimeline(streamId: "pair", items: [second], beforeCursor: "2", hasMore: true),
            OLSTimeline(streamId: "pair", items: [first, second], hasMore: false),
        ])
        let model = OLSModel(service: service)
        await model.refresh()
        model.visibleMessageID = "2"
        await model.loadEarlier()
        #expect(model.messages.map(\.id) == ["1", "2"])
        #expect(model.visibleMessageID == "2")
        #expect(!model.hasMore)
        #expect(await service.beforeValues == [nil, "2"])
    }

    @Test func `commentary snapshots update one row while final reply stays distinct`() async {
        let context = OLSContext(
            segmentId: "context-a",
            projectId: 7,
            slug: "japan-family-trip",
            label: "Japan family trip",
            source: "named")
        let final = OLSMessage(
            id: "final",
            role: "assistant",
            text: "The itinerary is ready.",
            createdAt: "2026-09-10T19:00:04Z",
            context: context)
        let user = OLSMessage(
            id: "user",
            role: "user",
            text: "Where are we on the itinerary?",
            createdAt: "2026-09-10T19:00:00Z",
            context: context)
        let service = StubOLSService(
            pages: [OLSTimeline(streamId: "pair", items: [user, final], hasMore: false, activeContext: context)],
            progressFeeds: [
                OLSProgressFeed(statuses: [OLSProgressStatus(context: context, commentary: [
                    OLSCommentary(
                        id: "run:commentary:0",
                        text: "I’m checking the saved itinerary.",
                        createdAt: "2026-09-10T19:00:01Z"),
                ])]),
                OLSProgressFeed(statuses: [OLSProgressStatus(context: context, commentary: [
                    OLSCommentary(
                        id: "run:commentary:0",
                        text: "I’m checking the saved itinerary and current reservations.",
                        createdAt: "2026-09-10T19:00:02Z"),
                ])]),
            ])
        let model = OLSModel(service: service)
        await model.refresh()
        await model.refreshCommentary()
        await model.refreshCommentary()

        let commentary = model.messages.filter(\.isCommentary)
        #expect(commentary.count == 1)
        #expect(commentary.first?.text == "I’m checking the saved itinerary and current reservations.")
        #expect(commentary.first?.createdAt == "2026-09-10T19:00:01Z")
        #expect(commentary.first?.context == context)
        #expect(model.durableMessageID(for: commentary.first?.id) == "user")
        #expect(model.latestFinalReply?.id == "final")
    }

    @Test func `delayed commentary cannot repopulate after sign out`() async {
        let service = SuspendedCommentaryOLSService()
        let model = OLSModel(service: service)
        let task = Task { await model.refreshCommentary() }
        await service.waitForProgress()
        model.clear()
        await service.resolveProgress(OLSProgressFeed(statuses: [OLSProgressStatus(context: nil, commentary: [
            OLSCommentary(
                id: "old-account:commentary:0",
                text: "I’m still working in the old account.",
                createdAt: "2026-09-10T19:00:01Z"),
        ])]))
        await task.value
        #expect(model.messages.isEmpty)
    }
    @Test func `anchors open each context run and horizontal steps move between neighbours`() {
        let japan = OLSContext(segmentId: "a", projectId: 1, slug: "japan", label: "Japan", source: "named")
        let mvp = OLSContext(segmentId: "b", projectId: 2, slug: "mvp", label: "MVP", source: "named")
        let japanAgain = OLSContext(segmentId: "c", projectId: 1, slug: "japan", label: "Japan", source: "named")
        let messages = [
            OLSMessage(id: "1", role: "user", text: "1", createdAt: "2026-09-16T07:00:00Z", context: japan),
            OLSMessage(id: "2", role: "assistant", text: "2", createdAt: "2026-09-16T07:01:00Z", context: japan),
            OLSMessage(id: "3", role: "user", text: "3", createdAt: "2026-09-16T08:00:00Z", context: mvp),
            OLSMessage(id: "4", role: "assistant", text: "4", createdAt: "2026-09-16T08:01:00Z", context: mvp),
            OLSMessage(id: "5", role: "user", text: "5", createdAt: "2026-09-16T09:00:00Z", context: japanAgain),
            OLSMessage(id: "6", role: "assistant", text: "6", createdAt: "2026-09-16T09:01:00Z", context: japanAgain),
        ]
        // Returning to Japan is a new anchor; the earlier Japan run keeps its own.
        #expect(OLSModel.anchorIDs(messages) == ["1", "3", "5"])
        #expect(OLSModel.nextAnchor(after: "2", in: messages) == "3")
        #expect(OLSModel.nextAnchor(after: "6", in: messages) == nil)
        #expect(OLSModel.nextAnchor(after: nil, in: messages) == "1")
        #expect(OLSModel.previousAnchor(before: "4", in: messages) == "3")
        #expect(OLSModel.previousAnchor(before: "3", in: messages) == "1")
        #expect(OLSModel.previousAnchor(before: "1", in: messages) == nil)
    }

    @Test func `context check appears only for a provisional latest turn and dismisses once`() async {
        let guessed = OLSContext(
            segmentId: "g", projectId: 1, slug: "japan", label: "Japan", source: "heuristic", provisional: true)
        let service = StubOLSService(pages: [
            OLSTimeline(streamId: "pair", items: [
                OLSMessage(id: "1", role: "user", text: "Kyoto?", createdAt: "2026-09-16T09:36:00Z", context: guessed),
                OLSMessage(id: "2", role: "assistant", text: "Not yet.", createdAt: "2026-09-16T09:38:00Z", context: guessed),
            ], hasMore: false, activeContext: guessed, segments: [
                OLSSegment(id: "g", projectId: 1, slug: "japan", label: "Japan", source: "heuristic", provisional: true),
            ]),
        ])
        let model = OLSModel(service: service)
        await model.refresh()
        #expect(model.contextCheck?.segmentId == "g")
        #expect(model.segments.map(\.id) == ["g"])
        model.dismissContextCheck()
        #expect(model.contextCheck == nil)
    }

    @Test func `day rules follow the prototype: today, yesterday, weekday, then the date`() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        let now = PearAPI.parseISODate("2026-09-16T09:41:00Z")!
        #expect(OLSModel.periodLabel(for: PearAPI.parseISODate("2026-09-16T07:38:00Z")!, now: now, calendar: calendar) == "Today")
        #expect(OLSModel.periodLabel(for: PearAPI.parseISODate("2026-09-15T20:00:00Z")!, now: now, calendar: calendar) == "Yesterday")
        #expect(OLSModel.periodLabel(for: PearAPI.parseISODate("2026-09-13T20:00:00Z")!, now: now, calendar: calendar) == "Sunday")
        #expect(OLSModel.periodLabel(for: PearAPI.parseISODate("2026-08-12T20:00:00Z")!, now: now, calendar: calendar) == "August 12")
    }
}

private actor StubOLSService: OLSService {
    struct Request: Sendable {
        var requestID: String
        var projectID: Int?
    }

    var pages: [OLSTimeline]
    var progressFeeds: [OLSProgressFeed]
    var receipts: [OLSSendReceipt]
    var requests: [Request] = []
    var beforeValues: [String?] = []

    init(
        pages: [OLSTimeline] = [],
        progressFeeds: [OLSProgressFeed] = [],
        receipts: [OLSSendReceipt] = [])
    {
        self.pages = pages
        self.progressFeeds = progressFeeds
        self.receipts = receipts
    }

    func timeline(before: String?) async throws -> OLSTimeline {
        self.beforeValues.append(before)
        return self.pages.isEmpty ? OLSTimeline(streamId: "pair", items: [], hasMore: false) : self.pages.removeFirst()
    }

    func progress() async throws -> OLSProgressFeed {
        self.progressFeeds.isEmpty ? OLSProgressFeed(statuses: []) : self.progressFeeds.removeFirst()
    }

    func send(
        text _: String,
        requestID: String,
        projectID: Int?,
        attachments _: [String]) async throws -> OLSSendReceipt
    {
        self.requests.append(Request(requestID: requestID, projectID: projectID))
        return self.receipts.isEmpty ? OLSSendReceipt(ok: true) : self.receipts.removeFirst()
    }
}

private actor SuspendedOLSService: OLSService {
    private var history: CheckedContinuation<OLSTimeline, any Error>?
    private var began: CheckedContinuation<Void, Never>?

    func timeline(before _: String?) async throws -> OLSTimeline {
        try await withCheckedThrowingContinuation { continuation in
            self.history = continuation
            self.began?.resume()
            self.began = nil
        }
    }

    func waitForHistory() async {
        if self.history != nil { return }
        await withCheckedContinuation { self.began = $0 }
    }

    func resolveHistory(_ page: OLSTimeline) {
        self.history?.resume(returning: page)
        self.history = nil
    }

    func progress() async throws -> OLSProgressFeed {
        OLSProgressFeed(statuses: [])
    }

    func send(
        text _: String,
        requestID _: String,
        projectID _: Int?,
        attachments _: [String]) async throws -> OLSSendReceipt
    {
        OLSSendReceipt(ok: true)
    }
}

private actor SuspendedCommentaryOLSService: OLSService {
    private var progressFeed: CheckedContinuation<OLSProgressFeed, any Error>?
    private var began: CheckedContinuation<Void, Never>?

    func timeline(before _: String?) async throws -> OLSTimeline {
        OLSTimeline(streamId: "pair", items: [], hasMore: false)
    }

    func progress() async throws -> OLSProgressFeed {
        try await withCheckedThrowingContinuation { continuation in
            self.progressFeed = continuation
            self.began?.resume()
            self.began = nil
        }
    }

    func waitForProgress() async {
        if self.progressFeed != nil { return }
        await withCheckedContinuation { self.began = $0 }
    }

    func resolveProgress(_ feed: OLSProgressFeed) {
        self.progressFeed?.resume(returning: feed)
        self.progressFeed = nil
    }

    func send(
        text _: String,
        requestID _: String,
        projectID _: Int?,
        attachments _: [String]) async throws -> OLSSendReceipt
    {
        OLSSendReceipt(ok: true)
    }
}

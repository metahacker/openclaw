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
            segmentId: "g",
            projectId: 1,
            slug: "japan",
            label: "Japan",
            source: "heuristic",
            provisional: true)
        let asked = OLSMessage(
            id: "1",
            role: "user",
            text: "Kyoto?",
            createdAt: "2026-09-16T09:36:00Z",
            context: guessed)
        let answered = OLSMessage(
            id: "2",
            role: "assistant",
            text: "Not yet.",
            createdAt: "2026-09-16T09:38:00Z",
            context: guessed)
        let segment = OLSSegment(
            id: "g",
            projectId: 1,
            slug: "japan",
            label: "Japan",
            source: "heuristic",
            provisional: true)
        let service = StubOLSService(pages: [
            OLSTimeline(
                streamId: "pair",
                items: [asked, answered],
                hasMore: false,
                activeContext: guessed,
                segments: [segment]),
        ])
        let model = OLSModel(service: service)
        await model.refresh()
        #expect(model.contextCheck?.segmentId == "g")
        #expect(model.segments.map(\.id) == ["g"])
        model.dismissContextCheck()
        #expect(model.contextCheck == nil)
    }

    @Test func `decodes the cross-surface stream: surfaces, sessions, visible runs, window, receipts`() throws {
        let json = """
        {"streamId":"s","window":{"hours":24,"since":"2026-09-16T14:00:00.000Z","until":"2026-09-17T14:00:00.000Z",
        "applied":true},"items":[
        {"id":"91","kind":"message","threadId":5,"page":"channel:C1:thread:1.2","sessionRef":"channel:C1:thread:1.2",
        "surface":"slack","role":"user","text":"hold Thursday","createdAt":"2026-09-17T08:12:00.597Z",
        "context":{"segmentId":"slack:5@91","originSegmentId":"slack:5","surface":"slack","projectId":3,
        "slug":"new-york","label":"New York","source":"session","provisional":false},
        "clientRequestId":null,"dispatchState":"accepted","routing":null,"attachments":[]},
        {"id":"92","kind":"message","threadId":9,"page":"pear:ols:v1:s:c2","sessionRef":"pear:ols:v1:s:c2",
        "surface":"app","role":"user","text":"kyoto?","createdAt":"2026-09-17T09:36:00.000Z",
        "context":{"segmentId":"ctx-r1","originSegmentId":"ctx-r1","surface":"app","projectId":1,
        "slug":"japan","label":"Japan","source":"llm","provisional":true},
        "clientRequestId":"r1","dispatchState":"queued",
        "routing":{"decision":"resume","trigger":"similarity","sessionRef":"pear:ols:v1:s:c2"},"attachments":[]}],
        "segments":[{"id":"slack:5@91","originSegmentId":"slack:5","page":"channel:C1:thread:1.2","surface":"slack",
        "projectId":3,"slug":"new-york","label":"New York","source":"session","provisional":false,
        "createdAt":"2026-09-17T08:12:00.597Z","firstMessageId":"91","lastMessageId":"91","count":1},
        {"id":"ctx-r1","originSegmentId":"ctx-r1","page":"pear:ols:v1:s:c2","surface":"app","projectId":1,
        "slug":"japan","label":"Japan","source":"llm","provisional":true,"createdAt":"2026-09-17T09:36:00.000Z",
        "firstMessageId":"92","lastMessageId":"92","count":1}],
        "activeContext":{"segmentId":"ctx-r1","originSegmentId":"ctx-r1","projectId":1,"slug":"japan"},
        "activePage":"pear:ols:v1:s:c2","beforeCursor":"b","afterCursor":"a","hasMore":true,"status":"connected",
        "capabilities":{"contextEngine":"shared-router","crossSurface":true,"surfaces":["app","sendblue","slack","dm"]}}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let page = try decoder.decode(OLSTimeline.self, from: Data(json.utf8))
        let window = OLSWindow(
            hours: 24,
            since: "2026-09-16T14:00:00.000Z",
            until: "2026-09-17T14:00:00.000Z",
            applied: true)
        #expect(page.window == window)
        #expect(page.hasMore && page.beforeCursor == "b" && page.activePage == "pear:ols:v1:s:c2")
        let slack = try #require(page.items.first)
        #expect(slack.surfaceKind == .slack && slack.sessionRef == "channel:C1:thread:1.2" && !slack.isAppTurn)
        #expect(slack.context?.segmentId == "slack:5@91" && slack.context?.originSegmentId == "slack:5")
        #expect(slack.routing == nil && slack.dispatchState == "accepted")
        let app = try #require(page.items.last)
        #expect(app.isAppTurn && app.isQueued && app.routing?.decision == "resume")
        #expect(app.context?.surfaceKind == .app && app.context?.provisional == true)
        let runs = try #require(page.segments)
        #expect(runs.map(\.id) == ["slack:5@91", "ctx-r1"])
        #expect(runs[0].surfaceKind == .slack && runs[0].count == 1 && runs[0].firstMessageId == "91")
        #expect(runs[0].context.originSegmentId == "slack:5" && runs[0].context.surface == "slack")
        #expect(OLSSurface("dm").name == "Slack" && OLSSurface("sendblue").name == "Messages")
        #expect(OLSSurface(nil) == .app && OLSSurface("unknown") == .app)
        #expect(OLSTimelineView.pendingLabel(app) == "Queued" && OLSTimelineView.pendingLabel(slack) == nil)
        #expect(OLSTimelineView.anchorTitle(slack.context!) == "#new-york")
        let unresolved = OLSContext(segmentId: "sb:1@7", label: "Here with you", surface: "sendblue")
        #expect(OLSTimelineView.anchorTitle(unresolved) == "Messages")

        let receiptJSON = """
        {"ok":true,"id":93,"clientRequestId":"r2","page":"pear:ols:v1:s:c2","sessionRef":"pear:ols:v1:s:c2",
        "segmentId":"ctx-r2","context":{"segmentId":"ctx-r2","projectId":1},"status":"queued","queued":true,
        "routing":{"decision":"stay","trigger":null,"sessionRef":"pear:ols:v1:s:c2","epoch":2,"similarity":0.8}}
        """
        let receipt = try decoder.decode(OLSSendReceipt.self, from: Data(receiptJSON.utf8))
        #expect(receipt.ok && receipt.queued == true && receipt.status == "queued")
        #expect(receipt.sessionRef == receipt.page && receipt.routing?.decision == "stay")
    }

    @Test func `anchors merge one project's runs that touch across a page and keep surfaces apart`() {
        let ny = OLSContext(segmentId: "slack:5@91", projectId: 3, slug: "ny", surface: "slack")
        let nyTail = OLSContext(segmentId: "slack:5@93", projectId: 3, slug: "ny", surface: "slack")
        let texts = OLSContext(segmentId: "sb:1@94", label: "Here with you", surface: "sendblue")
        let texts2 = OLSContext(segmentId: "sb:2@95", label: "Here with you", surface: "sendblue")
        let japan = OLSContext(segmentId: "ctx-r1", projectId: 1, slug: "japan", surface: "app")
        let messages = [
            OLSMessage(id: "91", role: "user", text: "1", createdAt: "2026-09-17T08:00:00Z", context: ny),
            OLSMessage(id: "92", role: "assistant", text: "2", createdAt: "2026-09-17T08:01:00Z", context: ny),
            OLSMessage(id: "93", role: "user", text: "3", createdAt: "2026-09-17T08:02:00Z", context: nyTail),
            OLSMessage(id: "94", role: "user", text: "4", createdAt: "2026-09-17T09:00:00Z", context: texts),
            OLSMessage(id: "95", role: "user", text: "5", createdAt: "2026-09-17T09:10:00Z", context: texts2),
            OLSMessage(id: "96", role: "user", text: "6", createdAt: "2026-09-17T09:36:00Z", context: japan),
        ]
        // The second New York run only exists because the page boundary split it: one anchor.
        // Two unplaced text runs are different threads with no shared project: two anchors.
        #expect(OLSModel.anchorIDs(messages) == ["91", "94", "95", "96"])
        #expect(OLSModel.nextAnchor(after: "93", in: messages) == "94")
        #expect(OLSModel.previousAnchor(before: "96", in: messages) == "95")
        #expect(OLSModel.previousAnchor(before: "93", in: messages) == "91")
    }

    @Test func `context check answers only app turns, never a provisional Slack row`() async {
        let guessed = OLSContext(
            segmentId: "slack:1@1",
            projectId: 1,
            slug: "japan",
            provisional: true,
            surface: "slack")
        let own = OLSContext(segmentId: "ctx-r1", projectId: 1, slug: "japan", provisional: true, surface: "app")
        let slack = OLSMessage(
            id: "1",
            role: "user",
            text: "from slack",
            createdAt: "2026-09-17T09:00:00Z",
            context: guessed,
            surface: "slack")
        let app = OLSMessage(
            id: "2",
            role: "user",
            text: "from here",
            createdAt: "2026-09-17T09:30:00Z",
            context: own,
            surface: "app")
        let service = StubOLSService(pages: [
            OLSTimeline(streamId: "s", items: [slack], hasMore: false),
            OLSTimeline(streamId: "s", items: [app], hasMore: false),
        ])
        let model = OLSModel(service: service)
        await model.refresh()
        #expect(model.contextCheck == nil)
        await model.refresh()
        #expect(model.contextCheck?.segmentId == "ctx-r1")
    }

    @Test func `paging past the window keeps runs from every page and says so`() async {
        let today = OLSSegment(id: "ctx-r2", projectId: 1, createdAt: "2026-09-17T09:00:00Z", surface: "app")
        let older = OLSSegment(id: "slack:4@40", projectId: 3, createdAt: "2026-09-15T09:00:00Z", surface: "slack")
        let service = StubOLSService(pages: [
            OLSTimeline(
                streamId: "s",
                items: [OLSMessage(id: "50", role: "user", text: "now", createdAt: "2026-09-17T09:00:00Z")],
                beforeCursor: "w",
                hasMore: true,
                segments: [today],
                window: OLSWindow(hours: 24, applied: true)),
            OLSTimeline(
                streamId: "s",
                items: [OLSMessage(id: "40", role: "user", text: "then", createdAt: "2026-09-15T09:00:00Z")],
                hasMore: false,
                segments: [older]),
        ])
        let model = OLSModel(service: service)
        await model.refresh()
        #expect(model.windowHours == 24 && !model.beyondWindow && model.hasMore)
        await model.loadEarlier()
        #expect(model.segments.map(\.id) == ["ctx-r2", "slack:4@40"])
        #expect(model.beyondWindow && !model.hasMore)
        #expect(model.messages.map(\.id) == ["40", "50"])
    }

    @Test func `day rules follow the prototype: today, yesterday, weekday, then the date`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        calendar.locale = Locale(identifier: "en_US")
        let now = try #require(PearAPI.parseISODate("2026-09-16T09:41:00Z"))
        func label(_ iso: String) -> String {
            OLSModel.periodLabel(for: PearAPI.parseISODate(iso)!, now: now, calendar: calendar)
        }
        #expect(label("2026-09-16T07:38:00Z") == "Today")
        #expect(label("2026-09-15T20:00:00Z") == "Yesterday")
        #expect(label("2026-09-13T20:00:00Z") == "Sunday")
        #expect(label("2026-08-12T20:00:00Z") == "August 12")
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

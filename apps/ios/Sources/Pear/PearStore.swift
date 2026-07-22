import Foundation
import Observation

/// View-facing state for the native Playground shell. Loads the home feed when
/// the server lane ships it, and until then composes an honest fallback from the
/// open pear-mobile APIs (briefing + status + apps registry).
@MainActor
@Observable
final class PearStore {
    // MARK: - Display models

    struct StreamCard: Identifiable {
        let id = UUID()
        var emoji: String
        var title: String
        var summary: String?
        var tag: String?
        var kind: String?
        var url: URL?
        var pinned: Bool = false
    }

    struct DaySection: Identifiable {
        let id = UUID()
        var label: String
        var cards: [StreamCard]
    }

    struct MotionCard: Identifiable {
        let id = UUID()
        var emoji: String
        var title: String
        var status: String?
        var tag: String?
        var surface: String?
    }

    enum FeedSource {
        case homeFeed
        case fallback
    }

    // MARK: - State

    private(set) var daySections: [DaySection] = []
    private(set) var inMotion: [MotionCard] = []
    private(set) var projects: [PearStatusData.Project] = []
    private(set) var onDeckProjects: [PearStatusData.Project] = []
    private(set) var apps: [PearAppsRegistry.Entry] = []
    private(set) var briefingSummary: String?
    private(set) var feedSource: FeedSource = .fallback
    private(set) var isLoading = false
    private(set) var lastError: String?
    private(set) var lastRefreshed: Date?
    private(set) var hasDeviceKey: Bool = PearDeviceKeyStore.load() != nil

    private var keyObserver: (any NSObjectProtocol)?

    init() {
        self.keyObserver = NotificationCenter.default.addObserver(
            forName: PearDeviceKeyStore.didChangeNotification,
            object: nil,
            queue: .main)
        { [weak self] _ in
            // Hop through MainActor explicitly; the observer closure itself is nonisolated.
            Task { @MainActor in
                guard let self else { return }
                self.hasDeviceKey = PearDeviceKeyStore.load() != nil
                await self.refresh()
            }
        }
    }

    private var api: PearAPI {
        PearAPI(deviceKey: PearDeviceKeyStore.load())
    }

    // MARK: - Refresh

    func refreshIfStale(maxAge: TimeInterval = 120) async {
        if let lastRefreshed, Date().timeIntervalSince(lastRefreshed) < maxAge { return }
        await self.refresh()
    }

    func refresh() async {
        if self.isLoading { return }
        self.isLoading = true
        defer { self.isLoading = false }

        let api = self.api
        self.hasDeviceKey = api.deviceKey != nil

        // Each surface degrades independently — a failing endpoint should not
        // blank the whole world.
        async let feedTask = api.homeFeedOrNil()
        async let briefingTask = api.briefingOrNil()
        async let statusTask = api.statusDataOrNil()
        async let appsTask = api.appsRegistryOrNil()

        let (feed, briefing, status, registry) = await (feedTask, briefingTask, statusTask, appsTask)

        if let status {
            self.projects = (status.active ?? []).sorted { lhs, rhs in
                (lhs.updatedDate ?? .distantPast) > (rhs.updatedDate ?? .distantPast)
            }
            self.onDeckProjects = status.onDeck ?? []
        }
        if let registry {
            self.apps = (registry.apps ?? [])
                .filter { $0.visible ?? true }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        self.briefingSummary = briefing?.summary

        if let feed, feed.days?.isEmpty == false || feed.items?.isEmpty == false {
            self.apply(feed: feed)
            self.feedSource = .homeFeed
        } else {
            self.applyFallback(briefing: briefing, status: status)
            self.feedSource = .fallback
        }

        if feed == nil, briefing == nil, status == nil, registry == nil {
            self.lastError = "Couldn't reach pear.metahack.io"
        } else {
            self.lastError = nil
        }
        self.lastRefreshed = Date()
    }

    // MARK: - Feed mapping

    private func apply(feed: PearHomeFeed) {
        self.inMotion = (feed.inMotion ?? []).compactMap { motion in
            guard let title = motion.bestTitle, !title.isEmpty else { return nil }
            return MotionCard(
                emoji: motion.emoji ?? "💬",
                title: title,
                status: motion.bestStatus,
                tag: motion.bestTag,
                surface: motion.surface)
        }

        var sections: [DaySection] = []
        if let days = feed.days, !days.isEmpty {
            sections = days.compactMap { day in
                let cards = (day.items ?? []).compactMap(Self.streamCard(from:))
                guard !cards.isEmpty else { return nil }
                return DaySection(label: day.label ?? day.date ?? "Recently", cards: cards)
            }
        } else if let items = feed.items, !items.isEmpty {
            let cards = items.compactMap(Self.streamCard(from:))
            if !cards.isEmpty {
                sections = [DaySection(label: "Recently", cards: cards)]
            }
        }
        self.daySections = sections
    }

    private static func streamCard(from item: PearHomeFeed.Item) -> StreamCard? {
        guard let title = item.title, !title.isEmpty else { return nil }
        return StreamCard(
            emoji: item.emoji ?? "📄",
            title: title,
            summary: item.bestSummary,
            tag: item.bestTag,
            kind: item.bestKind,
            url: item.bestURL.flatMap { URL(string: $0) },
            pinned: item.pinned ?? false)
    }

    // MARK: - Fallback composition (no /api/home/feed yet)

    private func applyFallback(briefing: PearBriefing?, status: PearStatusData?) {
        self.inMotion = (briefing?.inMotion ?? []).prefix(6).map { entry in
            MotionCard(
                emoji: entry.emoji ?? "💬",
                title: entry.text,
                status: entry.detail,
                tag: self.hashtag(forProjectId: entry.projectId, status: status),
                surface: nil)
        }

        // Deliverable pages aren't exposed on an open endpoint yet, so the honest
        // stream is the project world by recency: what actually moved, when.
        var sections: [DaySection] = []
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: self.projects.prefix(30)) { project -> String in
            guard let date = project.updatedDate else { return "Earlier" }
            if calendar.isDateInToday(date) { return "Today" }
            if calendar.isDateInYesterday(date) { return "Yesterday" }
            let days = calendar.dateComponents([.day], from: date, to: Date()).day ?? 99
            if days < 7 { return date.formatted(.dateTime.weekday(.wide)) }
            return "Earlier"
        }
        let order = ["Today", "Yesterday"]
        let rest = grouped.keys
            .filter { !order.contains($0) && $0 != "Earlier" }
            .sorted { lhs, rhs in
                let lhsDate = grouped[lhs]?.first?.updatedDate ?? .distantPast
                let rhsDate = grouped[rhs]?.first?.updatedDate ?? .distantPast
                return lhsDate > rhsDate
            }
        for label in order + rest + ["Earlier"] {
            guard let projects = grouped[label], !projects.isEmpty else { continue }
            let cards = projects.map { project in
                StreamCard(
                    emoji: project.emoji ?? "📦",
                    title: project.name,
                    summary: project.summary,
                    tag: project.hashtag,
                    kind: project.freshness ?? "project",
                    url: nil)
            }
            sections.append(DaySection(label: label, cards: cards))
        }
        self.daySections = sections
    }

    private func hashtag(forProjectId id: Int?, status: PearStatusData?) -> String? {
        guard let id else { return nil }
        let all = (status?.active ?? []) + (status?.onDeck ?? [])
        return all.first { $0.id == id }?.hashtag
    }

    func project(withId id: Int) -> PearStatusData.Project? {
        (self.projects + self.onDeckProjects).first { $0.id == id }
    }
}

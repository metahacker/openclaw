import SwiftUI

/// Projects — the shelves. Every project is a durable routing pillar keyed by
/// its hashtag; tapping one opens its wiki-style home.
struct PearProjectsView: View {
    var store: PearStore

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    Text("Projects")
                        .font(PearTheme.pageTitle)
                        .foregroundStyle(PearTheme.ink)
                        .padding(.top, 12)
                        .padding(.bottom, 6)

                    ForEach(self.store.projects) { project in
                        NavigationLink {
                            PearProjectDetailView(store: self.store, project: project)
                        } label: {
                            PearProjectRow(project: project)
                        }
                        .buttonStyle(PearPressableStyle())
                    }

                    if self.store.projects.isEmpty, self.store.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
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
}

struct PearProjectRow: View {
    let project: PearStatusData.Project

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            PearGlyphTile(emoji: self.project.emoji ?? "📦", side: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(self.project.name)
                    .font(PearTheme.rowTitle)
                    .foregroundStyle(PearTheme.ink)
                    .lineLimit(1)
                if let summary = self.project.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 13))
                        .foregroundStyle(PearTheme.walnut)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let freshness = self.project.freshness {
                PearKindTag(text: freshness)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .pearCard()
    }
}

/// A project's wiki home: hero (emoji, name, hashtag, stats), what's in motion
/// here, and its pages — from the home feed when the tag matches, with the full
/// wiki one tap away until the sites/pages API lands.
struct PearProjectDetailView: View {
    var store: PearStore
    let project: PearStatusData.Project
    @Environment(\.openURL) private var openURL
    @State private var wiki: PearProjectSites?
    @State private var isLoadingWiki = false
    @State private var wikiError: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                self.hero

                if !self.motionHere.isEmpty {
                    PearDayMark(label: "In motion here")
                    ForEach(self.motionHere) { motion in
                        PearMotionCardView(motion: motion)
                    }
                }

                if !self.wikiSections.isEmpty {
                    PearDayMark(label: "Pages")
                    ForEach(self.wikiSections) { section in
                        PearSiteBox(title: section.title, subtitle: section.subtitle, cards: section.cards)
                    }
                } else if !self.pagesHere.isEmpty {
                    PearDayMark(label: "Pages")
                    PearSiteBox(title: "📖 Project wiki", subtitle: "What we put down here", cards: self.pagesHere)
                } else if self.isLoadingWiki {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                } else if let wikiError {
                    Text(wikiError)
                        .font(PearTheme.truthLine)
                        .foregroundStyle(PearTheme.faint)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 18)
                }

                Button {
                    self.openURL(self.projectURL)
                } label: {
                    HStack {
                        Text("Open the full wiki")
                            .font(PearTheme.rowTitle)
                            .foregroundStyle(PearTheme.pear)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(PearTheme.pear)
                    }
                    .padding(16)
                    .pearCard()
                }
                .buttonStyle(PearPressableStyle())
                .padding(.top, 12)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .background(PearTheme.cream)
        .scrollIndicators(.hidden)
        .navigationBarTitleDisplayMode(.inline)
        .task { await self.loadWiki() }
        .refreshable { await self.loadWiki(force: true) }
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(self.project.emoji ?? "📦")
                .font(.system(size: 40))
                .padding(12)
                .background(PearTheme.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(self.project.name)
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                    .foregroundStyle(PearTheme.ink)
                if let summary = self.project.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 14))
                        .foregroundStyle(PearTheme.walnut)
                }
                HStack(spacing: 10) {
                    PearTagChip(tag: self.project.hashtag)
                    if let health = self.project.health {
                        PearKindTag(text: health)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.top, 10)
    }

    private var motionHere: [PearStore.MotionCard] {
        self.store.inMotion.filter { $0.tag == self.project.hashtag }
    }

    private var pagesHere: [PearStore.StreamCard] {
        self.store.daySections.flatMap(\.cards).filter { $0.tag == self.project.hashtag }
    }

    private var wikiSections: [PearProjectWikiSection] {
        guard let wiki else { return [] }
        var sections: [PearProjectWikiSection] = []
        for site in wiki.sites ?? [] {
            let cards = (site.pages ?? []).compactMap { self.card(from: $0) }
            guard !cards.isEmpty else { continue }
            sections.append(PearProjectWikiSection(
                id: "site:\(site.id)",
                title: "📖 \(site.title ?? site.slug ?? "Project wiki")",
                subtitle: site.summary ?? "What we put down here",
                cards: cards))
        }
        let siteless = (wiki.siteless ?? []).compactMap { self.card(from: $0) }
        if !siteless.isEmpty {
            sections.append(PearProjectWikiSection(
                id: "siteless",
                title: "📄 Pages",
                subtitle: "Loose notes and artifacts",
                cards: siteless))
        }
        return sections
    }

    private var projectURL: URL {
        let slug = self.project.slug ?? String(self.project.id)
        return URL(string: "https://pear.metahack.io/projects/\(slug)") ?? PearAPI.baseURL
    }

    private func card(from page: PearProjectSites.Page) -> PearStore.StreamCard? {
        guard let title = page.title, !title.isEmpty else { return nil }
        return PearStore.StreamCard(
            emoji: "📄",
            title: title,
            summary: page.bestSummary,
            tag: self.project.hashtag,
            kind: page.kind,
            url: page.bestURL.flatMap(PearAPI.absoluteURL(_:)),
            pinned: page.isPinned ?? false)
    }

    @MainActor
    private func loadWiki(force: Bool = false) async {
        if self.isLoadingWiki { return }
        if self.wiki != nil, !force { return }
        self.isLoadingWiki = true
        defer { self.isLoadingWiki = false }
        do {
            self.wiki = try await PearAPI.current.projectSites(project: self.project)
            self.wikiError = nil
        } catch {
            self.wikiError = "couldn't load project wiki"
        }
    }
}

private struct PearProjectWikiSection: Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var cards: [PearStore.StreamCard]
}

/// Prototype `.sitebox`: a site section with page rows.
struct PearSiteBox: View {
    let title: String
    let subtitle: String
    let cards: [PearStore.StreamCard]
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(self.title)
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundStyle(PearTheme.ink)
                Text(self.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(PearTheme.walnut)
            }
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(PearTheme.line)
                    .frame(height: 1)
            }

            ForEach(self.cards) { card in
                Button {
                    if let url = card.url {
                        self.openURL(url)
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.title)
                                .font(PearTheme.rowTitle)
                                .foregroundStyle(PearTheme.ink)
                                .multilineTextAlignment(.leading)
                            if let summary = card.summary, !summary.isEmpty {
                                Text(summary)
                                    .font(.system(size: 13))
                                    .foregroundStyle(PearTheme.walnut)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                            }
                        }
                        Spacer(minLength: 8)
                        if let kind = card.kind {
                            PearKindTag(text: kind)
                        }
                    }
                    .padding(.vertical, 11)
                }
                .buttonStyle(.plain)
                .disabled(card.url == nil)
                .overlay(alignment: .bottom) {
                    if card.id != self.cards.last?.id {
                        Rectangle()
                            .fill(PearTheme.line.opacity(0.6))
                            .frame(height: 1)
                    }
                }
            }
        }
        .padding(.horizontal, 17)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(PearTheme.paper)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(PearTheme.line, lineWidth: 1)
                }
        }
    }
}

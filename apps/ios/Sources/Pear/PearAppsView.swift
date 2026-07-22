import SwiftUI

/// Apps — the tile shelf, promoted out of the kitchen sink into global nav.
struct PearAppsView: View {
    var store: PearStore
    @Environment(\.openURL) private var openURL

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    Text("Apps")
                        .font(PearTheme.pageTitle)
                        .foregroundStyle(PearTheme.ink)
                        .padding(.top, 12)
                        .padding(.bottom, 6)

                    LazyVGrid(columns: self.columns, spacing: 10) {
                        ForEach(self.store.apps) { app in
                            Button {
                                if let url = self.url(for: app) {
                                    self.openURL(url)
                                }
                            } label: {
                                PearAppTile(app: app)
                            }
                            .buttonStyle(PearPressableStyle())
                        }
                    }

                    if self.store.apps.isEmpty, self.store.isLoading {
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

    private func url(for app: PearAppsRegistry.Entry) -> URL? {
        guard let path = app.path, path.hasPrefix("/") else { return nil }
        return URL(string: path, relativeTo: PearAPI.baseURL)
    }
}

struct PearAppTile: View {
    let app: PearAppsRegistry.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(self.app.emoji ?? "🧩")
                .font(.system(size: 28))
            Text(self.app.name)
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .foregroundStyle(PearTheme.ink)
                .multilineTextAlignment(.leading)
                .lineLimit(1)
            Text(self.app.description ?? "")
                .font(.system(size: 12.5))
                .foregroundStyle(PearTheme.walnut)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
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

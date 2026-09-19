import SwiftUI
import SwiftData

private struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct SearchView: View {
    @State private var viewModel = SearchViewModel()
    @AppStorage("recentSearches") private var recentSearchesData: String = "PLTR,TSM,VOO"
    @State private var safariURL: IdentifiableURL?

    @Query private var watchlist: [WatchlistItem]
    @Environment(\.modelContext) private var modelContext

    private var recentSearches: [String] {
        recentSearchesData.split(separator: ",").map(String.init)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    searchBar

                    if let error = viewModel.errorMessage {
                        ErrorBanner(message: error) {
                            Task {
                                if viewModel.query.isEmpty {
                                    await viewModel.loadNews()
                                } else {
                                    await viewModel.search(viewModel.query)
                                }
                            }
                        }
                    }

                    if viewModel.query.isEmpty {
                        recentSearchesSection
                        marketNewsSection
                    } else {
                        searchResultsSection
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
                .responsiveContainer(maxWidth: 900)
            }
            .navigationTitle("Search")
            .task {
                viewModel.watchedSymbols = watchlist.map(\.ticker)
                await viewModel.loadNews()
            }
            .onChange(of: watchlist.map(\.ticker)) { _, symbols in
                viewModel.watchedSymbols = symbols
            }
            .navigationDestination(for: SearchResult.self) { result in
                AssetDetailView(symbol: result.symbol)
            }
            .sheet(item: $safariURL) { item in
                SafariView(url: item.url)
            }
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search ticker or company", text: $viewModel.query)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .onChange(of: viewModel.query) { _, newValue in
                    viewModel.scheduleSearch(for: newValue)
                }
            if viewModel.isSearching {
                ProgressView()
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var recentSearchesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Searches")
                .font(.title3.bold())
            FlowLayout(spacing: 8) {
                ForEach(recentSearches, id: \.self) { term in
                    Button {
                        viewModel.query = term
                        Task { await viewModel.search(term) }
                    } label: {
                        Label(term, systemImage: "clock.arrow.circlepath")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.results.isEmpty && !viewModel.isSearching {
                Text("No results found.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 20)
            } else {
                ForEach(viewModel.results) { result in
                    NavigationLink(value: result) {
                        HStack(spacing: 10) {
                            StockLogoView(symbol: result.symbol, diameter: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.displaySymbol).fontWeight(.bold)
                                Text(result.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()

                            WatchlistStarButton(
                                isWatched: Watchlist.contains(result.symbol, in: watchlist)
                            ) {
                                Watchlist.toggle(result.symbol, items: watchlist, context: modelContext)
                            }

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded { addToRecent(result.displaySymbol) })
                    Divider()
                }
            }
        }
    }

    /// Slim bar by default; expands to the full brief once generated. The
    /// old always-tall card pushed the actual headlines below the fold.
    private var aiSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
                Text("AI Market Brief")
                    .font(.subheadline.bold())
                Spacer()

                if viewModel.isSummarizing {
                    ProgressView().controlSize(.small)
                } else {
                    Button(viewModel.analysis == nil ? "Analyse" : "Refresh") {
                        Task { await viewModel.analyzeNews() }
                    }
                    .font(.caption.bold())
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .disabled(viewModel.news.isEmpty)
                }
            }

            if let analysis = viewModel.analysis {
                // Sentiment gauge
                HStack(spacing: 7) {
                    Image(systemName: analysis.sentiment.systemImage)
                        .foregroundStyle(analysis.sentiment.tint)
                    Text(analysis.sentiment.label)
                        .font(.caption.bold())
                        .foregroundStyle(analysis.sentiment.tint)
                    SentimentBar(score: analysis.clampedScore, tint: analysis.sentiment.tint)
                    Text("\(analysis.clampedScore > 0 ? "+" : "")\(analysis.clampedScore)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(analysis.headline)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 9) {
                    ForEach(analysis.themes) { theme in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(theme.title)
                                .font(.caption.bold())
                            Text(theme.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if !theme.symbols.isEmpty {
                                HStack(spacing: 4) {
                                    ForEach(theme.symbols, id: \.self) { symbol in
                                        Text(symbol)
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Color.accentColor.opacity(0.14))
                                            .foregroundStyle(Color.accentColor)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                }
                            }
                        }
                    }
                }

                if let note = analysis.watchlistNote, !note.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.yellow)
                            .padding(.top, 2)
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Text("AI-generated from headlines. Not financial advice.")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            if let summaryError = viewModel.summaryError {
                Text(summaryError)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .animation(.snappy(duration: 0.25), value: viewModel.analysis)
    }

    private var newsFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                filterChip(
                    title: "Top news",
                    icon: "flame.fill",
                    isOn: viewModel.topNewsOnly
                ) { viewModel.toggleTopNews() }

                Divider().frame(height: 18)

                filterChip(title: "All", icon: nil, isOn: viewModel.sourceFilter == nil) {
                    viewModel.setSource(nil)
                }

                ForEach(viewModel.availableSources, id: \.self) { source in
                    filterChip(
                        title: source,
                        icon: nil,
                        isOn: viewModel.sourceFilter == source
                    ) { viewModel.setSource(source) }
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
    }

    private func filterChip(title: String, icon: String?, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 9, weight: .bold))
                }
                Text(title).font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(isOn ? Color.accentColor : Color(.secondarySystemBackground))
            .foregroundStyle(isOn ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func openStory(_ item: MarketNews) {
        if let url = URL(string: item.url),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            safariURL = IdentifiableURL(url: url)
        }
    }

    private var marketNewsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            aiSummaryCard

            SectionHeader(
                title: "Market News",
                subtitle: viewModel.news.isEmpty
                    ? nil
                    : "\(viewModel.filteredNews.count) stories"
            )

            if !viewModel.news.isEmpty {
                newsFilterBar
            }

            if viewModel.isLoadingNews && viewModel.news.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
            } else if viewModel.filteredNews.isEmpty {
                Text("No stories match these filters.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
            } else {
                if let featured = viewModel.featuredStory {
                    Button { openStory(featured) } label: {
                        FeaturedNewsCard(news: featured)
                    }
                    .buttonStyle(.plain)
                }

                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.pagedNews.enumerated()), id: \.element.id) { index, item in
                        Button { openStory(item) } label: {
                            NewsCardView(news: item)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if index < viewModel.pagedNews.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))

                if viewModel.hasMoreNews {
                    Button {
                        withAnimation(.snappy) { viewModel.showMoreNews() }
                    } label: {
                        Text("Show \(min(viewModel.remainingNewsCount, 12)) more")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func addToRecent(_ term: String) {
        var list = recentSearches
        let upper = term.uppercased()
        list.removeAll { $0 == upper }
        list.insert(upper, at: 0)
        recentSearchesData = list.prefix(5).joined(separator: ",")
    }
}

#Preview {
    SearchView()
}

import Foundation
import Observation

@MainActor
@Observable
final class SearchViewModel {
    var query = ""
    var results: [SearchResult] = []
    var news: [MarketNews] = []
    var isSearching = false
    var isLoadingNews = false
    var errorMessage: String? = nil

    var isSummarizing = false
    var summaryError: String? = nil

    var analysis: NewsAnalysis? = nil
    /// Symbols the user follows, pushed in from the view's @Query so the
    /// analysis can say what the news means for them specifically.
    var watchedSymbols: [String] = []

    // MARK: - News filtering / paging

    /// Selected source, or nil for all. Feed carries only ~3 publishers, so
    /// a chip row covers the whole space.
    var sourceFilter: String? = nil
    var topNewsOnly = false
    /// The feed returns 100 items at once; render a page at a time so the
    /// first paint isn't a 100-card scroll.
    var visibleCount = 12
    private let pageSize = 12

    private let service = FinnhubService.shared
    private let typhoon = TyphoonService.shared
    private var searchTask: Task<Void, Never>?

    init() {
        // Show the last batch of headlines immediately; the network pass
        // replaces them. Avoids an empty page on every cold launch.
        if let cached = LocalStore.load([MarketNews].self, as: LocalStore.Key.news) {
            news = cached.value
        }
        // The AI brief costs a Typhoon call, so keep it rather than making
        // the user regenerate the same summary each launch.
        if let cached = LocalStore.load(NewsAnalysis.self, as: LocalStore.Key.newsAnalysis) {
            analysis = cached.value
        }
    }

    /// Publishers present in the current feed, most frequent first.
    var availableSources: [String] {
        let counts = news.reduce(into: [String: Int]()) { $0[$1.source, default: 0] += 1 }
        return counts.sorted { $0.value > $1.value }.map(\.key)
    }

    var filteredNews: [MarketNews] {
        news.filter { item in
            if let sourceFilter, item.source != sourceFilter { return false }
            if topNewsOnly, item.category?.lowercased() != "top news" { return false }
            return true
        }
    }

    /// Lead story gets a larger card; the rest render as compact rows.
    var featuredStory: MarketNews? { filteredNews.first }

    var pagedNews: [MarketNews] {
        Array(filteredNews.dropFirst().prefix(visibleCount))
    }

    var hasMoreNews: Bool {
        filteredNews.count - 1 > visibleCount
    }

    var remainingNewsCount: Int {
        max(filteredNews.count - 1 - visibleCount, 0)
    }

    func showMoreNews() {
        visibleCount += pageSize
    }

    /// Any filter change resets paging — otherwise switching source while
    /// scrolled deep leaves the user staring at an already-exhausted list.
    func setSource(_ source: String?) {
        sourceFilter = (sourceFilter == source) ? nil : source
        visibleCount = pageSize
    }

    func toggleTopNews() {
        topNewsOnly.toggle()
        visibleCount = pageSize
    }

    /// Groups by recency for section headers.
    func bucket(for item: MarketNews) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(item.date) { return "Today" }
        if calendar.isDateInYesterday(item.date) { return "Yesterday" }
        return "Earlier"
    }

    /// Debounces by 0.4s, cancelling any in-flight scheduled search.
    func scheduleSearch(for query: String) {
        searchTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await search(query)
        }
    }

    func search(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            return
        }
        isSearching = true
        errorMessage = nil
        do {
            let found = try await service.symbolSearch(query: trimmed)
            guard !Task.isCancelled, trimmed == self.query.trimmingCharacters(in: .whitespaces) else {
                isSearching = false
                return
            }
            results = found
        } catch {
            if !Task.isCancelled {
                errorMessage = error.userFacingMessage
            }
        }
        isSearching = false
    }

    func loadNews() async {
        isLoadingNews = true
        errorMessage = nil
        do {
            news = try await service.marketNews()
            LocalStore.save(news, as: LocalStore.Key.news)
            // A new batch of headlines invalidates the previous summary.
            analysis = nil
            LocalStore.clear(LocalStore.Key.newsAnalysis)
        } catch {
            errorMessage = error.userFacingMessage
        }
        isLoadingNews = false
    }

    func analyzeNews() async {
        guard !news.isEmpty else { return }
        isSummarizing = true
        summaryError = nil
        do {
            analysis = try await typhoon.analyzeNews(news, watching: watchedSymbols)
            LocalStore.save(analysis, as: LocalStore.Key.newsAnalysis)
        } catch {
            summaryError = error.userFacingMessage
        }
        isSummarizing = false
    }
}

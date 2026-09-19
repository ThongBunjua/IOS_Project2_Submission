import Foundation

/// Historical price data for charts.
///
/// Finnhub's `/stock/candle` returns 403 on the free tier, which left the
/// asset chart and the dashboard sparklines with nothing to draw. Yahoo's
/// chart endpoint needs no key and covers stocks and ETFs, so it fills the
/// gap. It's an undocumented endpoint rather than a supported public API —
/// fine for a study project, worth revisiting before shipping commercially.
actor ChartDataService {
    static let shared = ChartDataService()
    private init() {}

    /// Yahoo rejects requests without a browser-ish User-Agent.
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    private let limiter = RateLimiter(limit: 40, window: 60, minimumSpacing: 0.15)

    struct Range {
        let range: String
        let interval: String
    }

    /// Last traded price outside the regular session, with the baseline it
    /// should be compared against.
    ///
    /// Finnhub's free `/quote` only reports the regular session, so
    /// pre-market and after-hours moves are invisible there. Yahoo's chart
    /// endpoint exposes extended bars via `includePrePost=true` plus the
    /// session windows, which is enough to derive both.
    struct ExtendedQuote {
        enum Session: String {
            case pre, regular, post, closed

            var label: String {
                switch self {
                case .pre:     return "Pre-market"
                case .regular: return "Market open"
                case .post:    return "After hours"
                case .closed:  return "Closed"
                }
            }
        }

        let session: Session
        /// Latest print, including extended-hours bars.
        let price: Double
        /// Regular-session close this move is measured from.
        let baseline: Double
        let asOf: Date

        var change: Double { price - baseline }
        var changePercent: Double {
            baseline > 0 ? (change / baseline) * 100 : 0
        }
        /// Only pre/post moves are worth surfacing separately — during the
        /// regular session the normal quote already shows this.
        var isExtendedSession: Bool { session == .pre || session == .post }
    }

    // MARK: - Wire format

    private struct ChartResponse: Decodable {
        struct Chart: Decodable {
            let result: [Result]?
            let error: ErrorPayload?
        }
        struct ErrorPayload: Decodable {
            let code: String?
            let description: String?
        }
        struct Result: Decodable {
            let timestamp: [Int]?
            let indicators: Indicators
            let meta: Meta?
        }
        struct Meta: Decodable {
            struct Period: Decodable {
                let start: Int
                let end: Int
            }
            struct TradingPeriod: Decodable {
                let pre: Period?
                let regular: Period?
                let post: Period?
            }
            let regularMarketPrice: Double?
            let previousClose: Double?
            let chartPreviousClose: Double?
            let currentTradingPeriod: TradingPeriod?
        }
        struct Indicators: Decodable {
            let quote: [Quote]
        }
        struct Quote: Decodable {
            let close: [Double?]?
            let high: [Double?]?
            let low: [Double?]?
            let open: [Double?]?
            let volume: [Double?]?
        }
        let chart: Chart
    }

    /// Formats a symbol for Yahoo Finance (e.g. "BRK.B" -> "BRK-B").
    private static func yahooSymbol(for symbol: String) -> String {
        let converted = symbol.replacingOccurrences(of: ".", with: "-")
        return converted.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? converted
    }

    /// Fetches candles and maps them onto the app's existing `CandleData`
    /// so every chart view keeps working unchanged.
    func candles(symbol: String, range: Range) async throws -> CandleData {
        let encoded = Self.yahooSymbol(for: symbol)
        guard let url = URL(string:
            "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?range=\(range.range)&interval=\(range.interval)"
        ) else { throw FinnhubError.badURL }

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        await limiter.acquire()
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FinnhubError.serverError(-1)
        }
        guard http.statusCode == 200 else {
            throw FinnhubError.serverError(http.statusCode)
        }

        let decoded: ChartResponse
        do {
            decoded = try JSONDecoder().decode(ChartResponse.self, from: data)
        } catch {
            throw FinnhubError.decodingFailed
        }

        guard let result = decoded.chart.result?.first,
              let timestamps = result.timestamp,
              let quote = result.indicators.quote.first else {
            return CandleData(c: nil, h: nil, l: nil, o: nil, t: nil, v: nil, s: "no_data")
        }

        // Yahoo pads gaps (holidays, halts) with nulls; drop those indices
        // across every series so the arrays stay aligned.
        let closes = quote.close ?? []
        var t: [Int] = [], c: [Double] = [], h: [Double] = [],
            l: [Double] = [], o: [Double] = [], v: [Double] = []

        for (index, stamp) in timestamps.enumerated() {
            guard index < closes.count, let close = closes[index] else { continue }
            t.append(stamp)
            c.append(close)
            h.append(quote.high?[safe: index].flatMap { $0 } ?? close)
            l.append(quote.low?[safe: index].flatMap { $0 } ?? close)
            o.append(quote.open?[safe: index].flatMap { $0 } ?? close)
            v.append(quote.volume?[safe: index].flatMap { $0 } ?? 0)
        }

        guard !c.isEmpty else {
            return CandleData(c: nil, h: nil, l: nil, o: nil, t: nil, v: nil, s: "no_data")
        }
        return CandleData(c: c, h: h, l: l, o: o, t: t, v: v, s: "ok")
    }
}

// MARK: - Extended hours

extension ChartDataService {
    /// Latest price including pre-market and after-hours bars.
    func extendedQuote(symbol: String) async throws -> ExtendedQuote? {
        let encoded = Self.yahooSymbol(for: symbol)
        guard let url = URL(string:
            "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?range=1d&interval=5m&includePrePost=true"
        ) else { throw FinnhubError.badURL }

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        await limiter.acquire()
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw FinnhubError.serverError((response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        let decoded = try JSONDecoder().decode(ChartResponse.self, from: data)
        guard let result = decoded.chart.result?.first,
              let meta = result.meta,
              let stamps = result.timestamp,
              let closes = result.indicators.quote.first?.close
        else { return nil }

        // Last non-null bar — with includePrePost this is the newest
        // extended-hours print when one exists.
        var latest: (Date, Double)?
        for index in stride(from: min(stamps.count, closes.count) - 1, through: 0, by: -1) {
            if let close = closes[index] {
                latest = (Date(timeIntervalSince1970: TimeInterval(stamps[index])), close)
                break
            }
        }
        guard let (asOf, price) = latest else { return nil }

        let now = Date().timeIntervalSince1970
        let periods = meta.currentTradingPeriod
        let session: ExtendedQuote.Session = {
            if let regular = periods?.regular,
               now >= Double(regular.start), now < Double(regular.end) { return .regular }
            if let pre = periods?.pre,
               now >= Double(pre.start), now < Double(pre.end) { return .pre }
            if let post = periods?.post,
               now >= Double(post.start), now < Double(post.end) { return .post }
            return .closed
        }()

        // Pre-market moves are measured from the prior close; after-hours
        // from the close that just happened.
        let baseline: Double? = {
            switch session {
            case .pre, .closed:
                return meta.previousClose ?? meta.chartPreviousClose
            case .post, .regular:
                return meta.regularMarketPrice ?? meta.previousClose
            }
        }()
        guard let baseline, baseline > 0 else { return nil }

        return ExtendedQuote(session: session, price: price, baseline: baseline, asOf: asOf)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

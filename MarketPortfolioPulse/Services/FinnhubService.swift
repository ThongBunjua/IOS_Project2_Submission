import Foundation

enum FinnhubError: LocalizedError {
    case badURL
    case rateLimited
    case serverError(Int)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "Invalid request URL."
        case .rateLimited:
            return "Rate limit exceeded. Please try again shortly."
        case .serverError(let code):
            return "Server returned an error (\(code))."
        case .decodingFailed:
            return "Failed to parse server response."
        }
    }
}

/// All Finnhub API calls. Every method is async/throws; wrap calls in a
/// do-catch at the ViewModel layer. On HTTP 429 the request is retried once
/// automatically after a 60s backoff.
actor FinnhubService {
    static let shared = FinnhubService()
    private init() {}

    /// Kept a little under Finnhub's ~60/min free-tier ceiling to leave
    /// headroom for retries and for calls made outside this pacing.
    private let limiter = RateLimiter(limit: 40, window: 60)

    private func fetch<T: Decodable>(_ urlString: String, allowRetryOn429: Bool = true) async throws -> T {
        guard let url = URL(string: urlString) else { throw FinnhubError.badURL }
        await limiter.acquire()
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw FinnhubError.serverError(-1)
        }

        // Feed the server's own accounting back into the limiter.
        let remaining = http.value(forHTTPHeaderField: "x-ratelimit-remaining").flatMap(Int.init)
        let resetAt = http.value(forHTTPHeaderField: "x-ratelimit-reset")
            .flatMap(Double.init)
            .map { Date(timeIntervalSince1970: $0) }
        await limiter.syncBudget(remaining: remaining, resetAt: resetAt)

        if http.statusCode == 429 {
            guard allowRetryOn429 else { throw FinnhubError.rateLimited }
            // If the server reported when it resets, wait for it; otherwise
            // fall back to the full 60s window rather than retrying in 1s.
            let wait = await limiter.secondsUntilReset()
            let delay = wait > 0 ? min(wait, 61) : 60
            try await Task.sleep(nanoseconds: UInt64((delay + 0.5) * 1_000_000_000))
            return try await fetch(urlString, allowRetryOn429: false)
        }

        guard http.statusCode == 200 else {
            throw FinnhubError.serverError(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw FinnhubError.decodingFailed
        }
    }

    func quote(symbol: String) async throws -> StockQuote {
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? symbol
        let url = "\(API.baseURL)/quote?symbol=\(encoded)&token=\(API.key)"
        return try await fetch(url)
    }

    func candles(symbol: String, resolution: String, from: Int, to: Int) async throws -> CandleData {
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? symbol
        let url = "\(API.baseURL)/stock/candle?symbol=\(encoded)&resolution=\(resolution)&from=\(from)&to=\(to)&token=\(API.key)"
        return try await fetch(url)
    }

    func profile(symbol: String) async throws -> CompanyProfile {
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? symbol
        let url = "\(API.baseURL)/stock/profile2?symbol=\(encoded)&token=\(API.key)"
        return try await fetch(url)
    }

    func marketNews() async throws -> [MarketNews] {
        let url = "\(API.baseURL)/news?category=general&token=\(API.key)"
        return try await fetch(url)
    }

    func symbolSearch(query: String) async throws -> [SearchResult] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let url = "\(API.baseURL)/search?q=\(encoded)&token=\(API.key)"
        let response: SymbolLookupResponse = try await fetch(url)
        return response.result
    }
}

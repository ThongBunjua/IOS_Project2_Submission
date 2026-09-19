import Foundation
import SwiftUI

// MARK: - News analysis

/// Structured read of the day's headlines.
///
/// Asked for as JSON rather than prose so the UI can render sentiment,
/// themes and affected tickers as real components — a plain-text blob can
/// only ever be dumped into one `Text`.
struct NewsAnalysis: Codable, Equatable {
    enum Sentiment: String, Codable {
        case bullish, bearish, mixed

        var label: String { rawValue.capitalized }
        var systemImage: String {
            switch self {
            case .bullish: return "arrow.up.right.circle.fill"
            case .bearish: return "arrow.down.right.circle.fill"
            case .mixed:   return "arrow.left.arrow.right.circle.fill"
            }
        }
        var tint: Color {
            switch self {
            case .bullish: return .green
            case .bearish: return .red
            case .mixed:   return .orange
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let raw = (try? container.decode(String.self))?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "mixed"
            switch raw {
            case "bullish", "positive", "up":
                self = .bullish
            case "bearish", "negative", "down":
                self = .bearish
            default:
                self = .mixed
            }
        }
    }

    struct Theme: Codable, Equatable, Identifiable {
        let title: String
        let detail: String
        let tickers: [String]?
        var id: String { title }
        var symbols: [String] { tickers ?? [] }
    }

    let sentiment: Sentiment
    /// -100 (very bearish) to +100 (very bullish).
    let score: Int
    let headline: String
    let themes: [Theme]
    /// What these headlines mean for the user's own symbols, if anything.
    let watchlistNote: String?

    var clampedScore: Int { min(max(score, -100), 100) }

    init(
        sentiment: Sentiment,
        score: Int,
        headline: String,
        themes: [Theme],
        watchlistNote: String? = nil
    ) {
        self.sentiment = sentiment
        self.score = score
        self.headline = headline
        self.themes = themes
        self.watchlistNote = watchlistNote
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sentiment = (try? container.decode(Sentiment.self, forKey: .sentiment)) ?? .mixed
        if let intScore = try? container.decode(Int.self, forKey: .score) {
            self.score = intScore
        } else if let doubleScore = try? container.decode(Double.self, forKey: .score) {
            self.score = Int(doubleScore)
        } else if let stringScore = try? container.decode(String.self, forKey: .score), let parsed = Int(stringScore) {
            self.score = parsed
        } else {
            self.score = 0
        }
        self.headline = (try? container.decode(String.self, forKey: .headline)) ?? "Market News Summary"
        self.themes = (try? container.decode([Theme].self, forKey: .themes)) ?? []
        self.watchlistNote = try? container.decodeIfPresent(String.self, forKey: .watchlistNote)
    }
}

// MARK: - Portfolio risk

/// Hard numbers computed in Swift and handed to the model.
///
/// The model interprets; it never derives the figures. Letting an LLM do
/// the arithmetic invites confidently wrong percentages in a screen about
/// someone's money.
struct PortfolioMetrics: Codable {
    struct Position: Codable {
        let ticker: String
        let name: String
        let weightPercent: Double
        let returnPercent: Double
        let marketValue: Double
    }

    let totalValue: Double
    let totalCost: Double
    let totalReturnPercent: Double
    let positionCount: Int
    let largestWeightPercent: Double
    let largestTicker: String
    /// Herfindahl-Hirschman Index over position weights, 0–10,000.
    /// 10,000 means a single holding; under ~1,500 is broadly spread.
    let concentrationIndex: Double
    let positions: [Position]
}

struct PortfolioRisk: Codable, Equatable {
    enum Level: String, Codable {
        case low, moderate, high

        var label: String { rawValue.capitalized }
        var tint: Color {
            switch self {
            case .low:      return .green
            case .moderate: return .orange
            case .high:     return .red
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let raw = (try? container.decode(String.self))?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "moderate"
            switch raw {
            case "low", "safe":
                self = .low
            case "high", "risky", "danger":
                self = .high
            default:
                self = .moderate
            }
        }
    }

    struct Concern: Codable, Equatable, Identifiable {
        let title: String
        let detail: String
        var id: String { title }
    }

    let level: Level
    /// 0 (very safe) to 100 (very risky).
    let score: Int
    let headline: String
    let concerns: [Concern]
    let diversificationNote: String?

    var clampedScore: Int { min(max(score, 0), 100) }

    init(
        level: Level,
        score: Int,
        headline: String,
        concerns: [Concern],
        diversificationNote: String? = nil
    ) {
        self.level = level
        self.score = score
        self.headline = headline
        self.concerns = concerns
        self.diversificationNote = diversificationNote
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.level = (try? container.decode(Level.self, forKey: .level)) ?? .moderate
        if let intScore = try? container.decode(Int.self, forKey: .score) {
            self.score = intScore
        } else if let doubleScore = try? container.decode(Double.self, forKey: .score) {
            self.score = Int(doubleScore)
        } else if let stringScore = try? container.decode(String.self, forKey: .score), let parsed = Int(stringScore) {
            self.score = parsed
        } else {
            self.score = 50
        }
        self.headline = (try? container.decode(String.self, forKey: .headline)) ?? "Risk Assessment"
        self.concerns = (try? container.decode([Concern].self, forKey: .concerns)) ?? []
        self.diversificationNote = try? container.decodeIfPresent(String.self, forKey: .diversificationNote)
    }
}

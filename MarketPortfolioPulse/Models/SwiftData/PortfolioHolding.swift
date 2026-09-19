import Foundation
import SwiftData

@Model
final class PortfolioHolding {
    var ticker: String
    var companyName: String
    var shares: Double
    var averageCost: Double          // price per share when added
    var addedDate: Date

    init(
        ticker: String,
        companyName: String,
        shares: Double,
        averageCost: Double,
        addedDate: Date = Date()
    ) {
        self.ticker      = ticker.uppercased()
        self.companyName = companyName
        self.shares      = shares
        self.averageCost = averageCost
        self.addedDate   = addedDate
    }

    var costBasis: Double { shares * averageCost }
}

extension PortfolioHolding {
    /// Records a purchase, merging into an existing position rather than
    /// creating a second row for the same ticker.
    ///
    /// Buying the same stock twice at different prices is normal, and two
    /// separate rows would double-count it in the donut chart and skew
    /// every concentration figure. Merging keeps one position per ticker
    /// with a share-weighted average cost — the same basis a broker
    /// reports.
    static func record(
        ticker: String,
        companyName: String,
        shares: Double,
        pricePerShare: Double,
        date: Date,
        existing: [PortfolioHolding],
        context: ModelContext
    ) {
        let key = ticker.uppercased()
        guard shares > 0 else { return }

        if let holding = existing.first(where: { $0.ticker == key }) {
            let combinedShares = holding.shares + shares
            let combinedCost = holding.costBasis + (shares * pricePerShare)
            holding.averageCost = combinedShares > 0 ? combinedCost / combinedShares : pricePerShare
            holding.shares = combinedShares
            // Keep the earliest purchase date — it's when the position began.
            holding.addedDate = min(holding.addedDate, date)
        } else {
            context.insert(
                PortfolioHolding(
                    ticker: key,
                    companyName: companyName,
                    shares: shares,
                    averageCost: pricePerShare,
                    addedDate: date
                )
            )
        }
        try? context.save()
    }
}

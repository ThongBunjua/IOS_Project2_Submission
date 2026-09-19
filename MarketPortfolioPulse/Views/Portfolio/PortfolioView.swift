import SwiftUI
import SwiftData

struct PortfolioView: View {
    @Query(sort: \PortfolioHolding.addedDate) private var holdings: [PortfolioHolding]
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = PortfolioViewModel()
    @State private var showSetup = false

    private var totalValue: Double {
        holdings.reduce(0) { $0 + $1.shares * (viewModel.livePrices[$1.ticker] ?? $1.averageCost) }
    }

    private var donutSlices: [(ticker: String, value: Double)] {
        holdings.map { holding in
            (holding.ticker, holding.shares * (viewModel.livePrices[holding.ticker] ?? holding.averageCost))
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if holdings.isEmpty {
                    emptyState
                } else {
                    List {
                        Section {
                            header
                            DonutChartView(slices: donutSlices)
                                .frame(height: 220)
                                .responsiveContainer(maxWidth: 320)
                        }
                        .listRowSeparator(.hidden)

                        Section {
                            RiskAnalysisCard(
                                risk: viewModel.risk,
                                metrics: viewModel.metrics(for: holdings),
                                isAnalyzing: viewModel.isAnalyzingRisk,
                                errorMessage: viewModel.riskError
                            ) {
                                Task { await viewModel.analyzeRisk(for: holdings) }
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            .listRowBackground(Color.clear)
                        }
                        .listRowSeparator(.hidden)

                        Section("Holdings") {
                            ForEach(holdings) { holding in
                                NavigationLink(value: holding.ticker) {
                                    holdingRow(holding)
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete(perform: deleteHoldings)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable {
                        await viewModel.fetchPrices(for: holdings.map(\.ticker))
                    }
                }
            }
            .navigationTitle("My Portfolio")
            .navigationDestination(for: String.self) { symbol in
                AssetDetailView(symbol: symbol)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSetup = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add positions")
                }
            }
            .sheet(isPresented: $showSetup) {
                PortfolioSetupView()
                    .environment(\.modelContext, modelContext)
            }
            .task { await viewModel.fetchPrices(for: holdings.map(\.ticker)) }
            .onChange(of: holdings.map(\.ticker)) { _, tickers in
                Task { await viewModel.fetchPrices(for: tickers) }
            }
            .overlay(alignment: .top) {
                if let error = viewModel.errorMessage {
                    ErrorBanner(message: error) {
                        Task { await viewModel.fetchPrices(for: holdings.map(\.ticker)) }
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)
                }
            }
        }
    }

    /// Total cost basis and unrealised P&L across all holdings.
    private var totalCost: Double {
        holdings.reduce(0) { $0 + $1.shares * $1.averageCost }
    }
    private var totalPNL: Double { totalValue - totalCost }
    private var totalPNLPercent: Double {
        totalCost > 0 ? (totalPNL / totalCost) * 100 : 0
    }

    private var header: some View {
        let isUp = totalPNL >= 0

        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Total value")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("$" + totalValue.formatted(.number.precision(.fractionLength(2))))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                ChangeChip(change: totalPNL, changePercent: totalPNLPercent)
                Text("all time")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Divider().padding(.vertical, 2)

            HStack {
                summaryStat("Invested", value: totalCost, tint: .primary)
                Spacer()
                summaryStat(isUp ? "Gain" : "Loss", value: totalPNL, tint: isUp ? .green : .red)
                Spacer()
                summaryStat("Holdings", count: holdings.count)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.spring(duration: 0.35), value: totalValue)
    }

    private func summaryStat(_ label: String, value: Double? = nil, count: Int? = nil, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let value {
                Text("$" + value.formatted(.number.precision(.fractionLength(0))))
                    .font(.subheadline.bold())
                    .foregroundStyle(tint)
            } else if let count {
                Text("\(count)")
                    .font(.subheadline.bold())
            }
        }
    }

    private func holdingRow(_ holding: PortfolioHolding) -> some View {
        let livePrice = viewModel.livePrices[holding.ticker] ?? holding.averageCost
        let marketValue = holding.shares * livePrice
        let cost = holding.shares * holding.averageCost
        let pnl = marketValue - cost
        let pnlPercent = cost > 0 ? (pnl / cost) * 100 : 0

        return HStack(spacing: 12) {
            StockLogoView(symbol: holding.ticker, diameter: 38)

            VStack(alignment: .leading, spacing: 1) {
                Text(holding.ticker)
                    .font(.subheadline.bold())
                Text(holding.companyName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(holding.shares.formatted(.number.precision(.fractionLength(0...2)))) sh · avg $\(holding.averageCost.formatted(.number.precision(.fractionLength(2))))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text("$" + marketValue.formatted(.number.precision(.fractionLength(2))))
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.numericText())
                ChangeChip(change: pnl, changePercent: pnlPercent)
            }

            Image(systemName: "chevron.right")
                .font(.caption2.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func deleteHoldings(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(holdings[index])
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "briefcase")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
                .frame(width: 84, height: 84)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(Circle())

            VStack(spacing: 5) {
                Text("No holdings yet")
                    .font(.headline)
                Text("Already own stocks elsewhere? Add them with the price you paid so your returns are accurate.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 40)
            }

            Button {
                showSetup = true
            } label: {
                Label("Set up my portfolio", systemImage: "square.and.arrow.down")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

#Preview {
    PortfolioView()
        .modelContainer(for: [PortfolioHolding.self], inMemory: true)
}

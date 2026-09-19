import SwiftUI
import Charts

private enum SimField: Hashable {
    case amount, years, rate
}

struct SimulatorView: View {
    @State private var viewModel = SimulatorViewModel()
    @State private var showTickerPicker = false
    @FocusState private var focusedField: SimField?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    tickerCard

                    if let error = viewModel.errorMessage {
                        ErrorBanner(message: error) {
                            Task { await viewModel.loadSymbol() }
                        }
                    }

                    inputsCard
                    resultCard
                    projectionChart
                    aiCard
                    disclaimer
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .navigationTitle("DCA Simulator")
            .task { await viewModel.loadSymbol() }
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        focusedField = nil
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                    }
                    .accessibilityLabel("Dismiss keyboard")
                }
            }
            .sheet(isPresented: $showTickerPicker) {
                TickerPickerSheet { picked in
                    viewModel.symbol = picked
                    Task { await viewModel.loadSymbol() }
                }
            }
        }
    }

    // MARK: - Ticker

    private var tickerCard: some View {
        Button {
            focusedField = nil
            showTickerPicker = true
        } label: {
            HStack(spacing: 12) {
                StockLogoView(
                    symbol: viewModel.symbol,
                    logoURL: viewModel.profile?.logo,
                    diameter: 44
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.symbol)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if viewModel.isLoadingQuote {
                        Text("Loading…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let quote = viewModel.quote {
                        Text("\(viewModel.profile?.name ?? viewModel.symbol) · \(String(format: "$%.2f", quote.c))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Tap to choose a stock or ETF")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(Circle())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(14)
        .cardBackground()
    }

    // MARK: - Inputs

    private var inputsCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            inputRow(
                title: "Monthly investment",
                unit: "$",
                unitLeading: true,
                text: Binding(
                    get: { viewModel.monthlyAmount.formattedInput(decimals: 0) },
                    set: { viewModel.monthlyAmount = $0.clampedDouble(
                        to: 10...100_000,
                        fallback: viewModel.monthlyAmount) }
                ),
                field: .amount,
                slider: $viewModel.monthlyAmount,
                range: 50...max(5000, viewModel.monthlyAmount),
                step: 50,
                stepAmount: 50,
                presets: [100, 250, 500, 1000, 2000],
                presetLabel: { "$\(Int($0))" },
                onPreset: { viewModel.monthlyAmount = $0 },
                isSelected: { viewModel.monthlyAmount == $0 }
            )

            inputRow(
                title: "Time horizon",
                unit: "yr",
                unitLeading: false,
                text: Binding(
                    get: { String(viewModel.years) },
                    set: { viewModel.years = Int($0.clampedDouble(
                        to: 1...50,
                        fallback: Double(viewModel.years))) }
                ),
                field: .years,
                slider: Binding(
                    get: { Double(viewModel.years) },
                    set: { viewModel.years = Int($0) }
                ),
                range: 1...max(40, Double(viewModel.years)),
                step: 1,
                stepAmount: 1,
                presets: [5, 10, 15, 20, 30],
                presetLabel: { "\(Int($0))y" },
                onPreset: { viewModel.years = Int($0) },
                isSelected: { Double(viewModel.years) == $0 }
            )

            inputRow(
                title: "Assumed annual return",
                unit: "%",
                unitLeading: false,
                text: Binding(
                    get: { viewModel.annualReturnPercent.formattedInput(decimals: 1) },
                    set: { viewModel.annualReturnPercent = $0.clampedDouble(
                        to: -20...50,
                        fallback: viewModel.annualReturnPercent) }
                ),
                field: .rate,
                slider: $viewModel.annualReturnPercent,
                range: min(-5, viewModel.annualReturnPercent)...max(20, viewModel.annualReturnPercent),
                step: 0.5,
                stepAmount: 0.5,
                presets: [4, 6, 8, 10, 12],
                presetLabel: { String(format: "%.0f%%", $0) },
                onPreset: { viewModel.annualReturnPercent = $0 },
                isSelected: { viewModel.annualReturnPercent == $0 }
            )
        }
        .padding(16)
        .cardBackground()
    }

    private func inputRow(
        title: String,
        unit: String,
        unitLeading: Bool,
        text: Binding<String>,
        field: SimField,
        slider: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        stepAmount: Double,
        presets: [Double],
        presetLabel: @escaping (Double) -> String,
        onPreset: @escaping (Double) -> Void,
        isSelected: @escaping (Double) -> Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()

                HStack(spacing: 2) {
                    if unitLeading {
                        Text(unit).font(.subheadline.bold()).foregroundStyle(.secondary)
                    }
                    TextField("", text: text)
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                        .font(.subheadline.bold())
                        .focused($focusedField, equals: field)
                        .frame(minWidth: 44)
                        .fixedSize()
                    if !unitLeading {
                        Text(unit).font(.subheadline.bold()).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(focusedField == field ? 0.09 : 0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Stepper("") {
                    slider.wrappedValue = min(slider.wrappedValue + stepAmount, range.upperBound)
                } onDecrement: {
                    slider.wrappedValue = max(slider.wrappedValue - stepAmount, range.lowerBound)
                }
                .labelsHidden()
            }

            Slider(value: slider, in: range, step: step)

            HStack(spacing: 6) {
                ForEach(presets, id: \.self) { preset in
                    Button {
                        focusedField = nil
                        onPreset(preset)
                    } label: {
                        Text(presetLabel(preset))
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                isSelected(preset)
                                    ? Color.accentColor
                                    : Color.primary.opacity(0.05)
                            )
                            .foregroundStyle(isSelected(preset) ? .white : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .animation(.spring(duration: 0.25), value: slider.wrappedValue)
    }

    // MARK: - Results

    private var resultCard: some View {
        let isGain = viewModel.totalGain >= 0

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Projected value in \(viewModel.years) years")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(currency(viewModel.projectedValue))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
            }

            HStack(spacing: 10) {
                statTile(
                    label: "Invested",
                    value: currency(viewModel.totalInvested),
                    tint: .secondary
                )
                statTile(
                    label: isGain ? "Gain" : "Loss",
                    value: currency(viewModel.totalGain),
                    tint: isGain ? .green : .red
                )
                statTile(
                    label: "Return",
                    value: String(format: "%@%.0f%%", isGain ? "+" : "", viewModel.gainPercent),
                    tint: isGain ? .green : .red
                )
            }

            if let shares = viewModel.estimatedShares {
                Text(String(
                    format: "≈ %.2f shares if every contribution bought at today's price of $%.2f",
                    shares,
                    viewModel.quote?.c ?? 0
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(tint: isGain ? .green : .red)
        .animation(.spring(duration: 0.35), value: viewModel.projectedValue)
    }

    private func statTile(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(tint == .secondary ? Color.primary : tint)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Chart

    private var projectionChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Growth over time", systemImage: "chart.xyaxis.line")
                .font(.title3.bold())

            Chart {
                ForEach(viewModel.projection) { point in
                    AreaMark(
                        x: .value("Year", Double(point.month) / 12),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)
                }

                ForEach(viewModel.projection) { point in
                    LineMark(
                        x: .value("Year", Double(point.month) / 12),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.monotone)
                }

                ForEach(viewModel.projection) { point in
                    LineMark(
                        x: .value("Year", Double(point.month) / 12),
                        y: .value("Invested", point.invested)
                    )
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .interpolationMethod(.monotone)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let year = value.as(Double.self) {
                            Text("\(Int(year))y")
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(compactCurrency(amount))
                        }
                    }
                }
            }
            .frame(height: 220)

            HStack(spacing: 16) {
                legendSwatch(color: .accentColor, label: "Portfolio value", dashed: false)
                legendSwatch(color: .secondary, label: "Money invested", dashed: true)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .cardBackground()
    }

    private func legendSwatch(color: Color, label: String, dashed: Bool) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 16, height: dashed ? 2 : 3)
                .opacity(dashed ? 0.7 : 1)
            Text(label)
        }
    }

    // MARK: - AI

    private var aiCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("AI explanation", systemImage: "sparkles")
                .font(.title3.bold())

            if let explanation = viewModel.aiExplanation {
                Text(explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !viewModel.isExplaining {
                Text("Get a plain-language breakdown of what this projection means.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let aiError = viewModel.aiError {
                Text(aiError)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task { await viewModel.explainWithAI() }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isExplaining {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(viewModel.isExplaining
                         ? "Thinking…"
                         : (viewModel.aiExplanation == nil ? "Explain this" : "Regenerate"))
                }
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
            .disabled(viewModel.isExplaining)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private var disclaimer: some View {
        Text("Projections assume a constant average return and reinvested growth. Real markets fluctuate, and actual results will differ. This is an educational tool, not financial advice.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Formatting

    private func currency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        // Pinned to en_US so the symbol renders as "$" rather than the
        // locale-disambiguated "US$" on non-US devices.
        formatter.locale = Locale(identifier: "en_US")
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }

    private func compactCurrency(_ value: Double) -> String {
        switch abs(value) {
        case 1_000_000...:
            return String(format: "$%.1fM", value / 1_000_000)
        case 1_000...:
            return String(format: "$%.0fk", value / 1_000)
        default:
            return String(format: "$%.0f", value)
        }
    }
}

#Preview {
    SimulatorView()
}

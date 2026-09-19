import SwiftUI
import SwiftData

struct SettingsView: View {
    @AppStorage("appTheme") private var themeRaw = AppTheme.system.rawValue
    @Environment(\.dismiss) private var dismiss

    @Query private var watchlist: [WatchlistItem]
    @Query private var holdings: [PortfolioHolding]

    @AppStorage("customFinnhubKey") private var customFinnhubKey = ""
    @AppStorage("customTyphoonKey") private var customTyphoonKey = ""

    private var theme: Binding<AppTheme> {
        Binding(
            get: { AppTheme(rawValue: themeRaw) ?? .system },
            set: { themeRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    ThemePicker(selection: theme)
                        .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
                        .listRowBackground(Color.clear)
                }

                Section("Saved on this device") {
                    storedRow("Holdings", count: holdings.count, icon: "briefcase.fill")
                    storedRow("Watchlist", count: watchlist.count, icon: "star.fill")
                }

                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Finnhub API Key")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Default Built-in Key", text: $customFinnhubKey)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.system(.subheadline, design: .monospaced))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Typhoon AI API Key")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Default Built-in Key", text: $customTyphoonKey)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.system(.subheadline, design: .monospaced))
                    }
                    if !customFinnhubKey.isEmpty || !customTyphoonKey.isEmpty {
                        Button("Reset to Default Keys") {
                            customFinnhubKey = ""
                            customTyphoonKey = ""
                        }
                        .font(.footnote)
                    }
                } header: {
                    Text("API Keys (Optional)")
                } footer: {
                    Text("Leave blank to use the built-in default keys. You can specify custom keys if the free quota is exhausted.")
                }

                Section {
                    Button(role: .destructive) {
                        clearCaches()
                    } label: {
                        Label("Clear cached prices & news", systemImage: "trash")
                    }
                } footer: {
                    Text("Removes downloaded market data only. Your holdings and watchlist are untouched.")
                }

                Section("Data") {
                    LabeledContent("Market data", value: "Finnhub")
                    LabeledContent("Charts", value: "Yahoo Finance")
                    LabeledContent("AI analysis", value: "Typhoon")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func storedRow(_ title: String, count: Int, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text("\(count)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    /// Only clears derived network data. User-authored records live in
    /// SwiftData and are deliberately left alone.
    private func clearCaches() {
        LocalStore.clear(LocalStore.Key.quotes)
        LocalStore.clear(LocalStore.Key.news)
        LocalStore.clear(LocalStore.Key.newsAnalysis)
        URLCache.shared.removeAllCachedResponses()
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [PortfolioHolding.self, WatchlistItem.self], inMemory: true)
}

import SwiftUI
import UIKit

/// A resolved logo plus the tile colour it needs to be legible on.
struct StockLogo {
    let image: UIImage
    /// Some logos ship as white-on-transparent (Invesco's QQQ is a pure
    /// white mark) and vanish on a white tile; others are dark and vanish
    /// on a dark one. The tile follows the artwork rather than the other
    /// way round.
    let prefersDarkTile: Bool
    /// True when the artwork already carries its own solid background
    /// (NVIDIA, AMD and Salesforce all ship as filled squares). Those are
    /// drawn edge-to-edge so they read as a proper icon, instead of being
    /// inset on a tile — which is what produced a square-inside-a-circle.
    let isSelfContained: Bool
}

/// Loads and memoises ticker logos, trying several sources in order.
///
/// No single free source covers everything: Finnhub's library has company
/// logos but omits ETFs (VOO/SPY/QQQ all 404), while FMP's covers both.
/// Each symbol resolves once and is cached, so a logo reused across
/// Dashboard, Search, Detail and Portfolio costs a single request.
@MainActor
final class StockLogoCache {
    static let shared = StockLogoCache()
    private init() {}

    private var cache: [String: StockLogo] = [:]
    private var knownMissing: Set<String> = []
    private var inFlight: [String: Task<StockLogo?, Never>] = [:]

    private func candidates(for symbol: String, preferred: String?) -> [URL] {
        var urls: [URL] = []
        if let preferred, !preferred.isEmpty, let url = URL(string: preferred) {
            urls.append(url)
        }
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        if let finnhub = URL(string: "https://static2.finnhub.io/file/publicdatany/finnhubimage/stock_logo/\(encoded).png") {
            urls.append(finnhub)
        }
        if let fmp = URL(string: "https://financialmodelingprep.com/image-stock/\(encoded).png") {
            urls.append(fmp)
        }
        return urls
    }

    func cachedLogo(for symbol: String) -> StockLogo? {
        cache[symbol.uppercased()]
    }

    func logo(for symbol: String, preferred: String? = nil) async -> StockLogo? {
        let key = symbol.trimmingCharacters(in: .whitespaces).uppercased()
        guard !key.isEmpty else { return nil }

        if let cached = cache[key] { return cached }
        if knownMissing.contains(key) { return nil }
        if let existing = inFlight[key] { return await existing.value }

        let urls = candidates(for: key, preferred: preferred)
        let task = Task<StockLogo?, Never> {
            for url in urls {
                guard let (data, response) = try? await URLSession.shared.data(from: url),
                      let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let image = UIImage(data: data),
                      let logo = Self.evaluate(image) else { continue }
                return logo
            }
            return nil
        }
        inFlight[key] = task

        let logo = await task.value
        inFlight[key] = nil
        if let logo {
            cache[key] = logo
        } else {
            knownMissing.insert(key)
        }
        return logo
    }

    /// Measures how much of the artwork would actually be visible against a
    /// light tile versus a dark one, and picks the better. Returns nil when
    /// neither works — the caller then falls back to the initials avatar.
    private nonisolated static func evaluate(_ image: UIImage) -> StockLogo? {
        let side = 48
        guard let cgImage = image.cgImage else {
            return StockLogo(image: image, prefersDarkTile: false, isSelfContained: false)
        }

        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        return pixels.withUnsafeMutableBytes { rawBuffer -> StockLogo? in
            guard let context = CGContext(
                data: rawBuffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return StockLogo(image: image, prefersDarkTile: false, isSelfContained: false)
            }

            context.clear(CGRect(x: 0, y: 0, width: side, height: side))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

            let darkTile = 0.12
            var visibleOnLight = 0
            var visibleOnDark = 0

            for index in stride(from: 0, to: pixels.count, by: 4) {
                let alpha = Double(pixels[index + 3]) / 255
                guard alpha > 0.15 else { continue }
                // Values are premultiplied, so compositing is just an add.
                let r = Double(pixels[index]) / 255
                let g = Double(pixels[index + 1]) / 255
                let b = Double(pixels[index + 2]) / 255

                let onLight = 0.2126 * (r + (1 - alpha))
                            + 0.7152 * (g + (1 - alpha))
                            + 0.0722 * (b + (1 - alpha))
                let onDark = 0.2126 * (r + (1 - alpha) * darkTile)
                           + 0.7152 * (g + (1 - alpha) * darkTile)
                           + 0.0722 * (b + (1 - alpha) * darkTile)

                if onLight < 0.82 { visibleOnLight += 1 }
                if onDark > 0.30 { visibleOnDark += 1 }
            }

            // Does the artwork fill its own frame? Sample the border ring —
            // if it's mostly opaque, the logo brings its own background.
            var borderSamples = 0
            var opaqueBorder = 0
            for x in 0..<side {
                for y in [0, 1, side - 2, side - 1] {
                    let index = (y * side + x) * 4
                    borderSamples += 1
                    if Double(pixels[index + 3]) / 255 > 0.85 { opaqueBorder += 1 }
                }
            }
            for y in 0..<side {
                for x in [0, 1, side - 2, side - 1] {
                    let index = (y * side + x) * 4
                    borderSamples += 1
                    if Double(pixels[index + 3]) / 255 > 0.85 { opaqueBorder += 1 }
                }
            }
            let isSelfContained = Double(opaqueBorder) / Double(max(borderSamples, 1)) > 0.85

            let total = Double(side * side)
            let lightCoverage = Double(visibleOnLight) / total
            let darkCoverage = Double(visibleOnDark) / total
            let minimum = 0.012

            // A self-contained icon is legible on its own; it doesn't need a
            // tile behind it and shouldn't be rejected for low contrast.
            if isSelfContained {
                return StockLogo(image: image, prefersDarkTile: false, isSelfContained: true)
            }
            if lightCoverage >= minimum && lightCoverage >= darkCoverage {
                return StockLogo(image: image, prefersDarkTile: false, isSelfContained: false)
            }
            if darkCoverage >= minimum {
                return StockLogo(image: image, prefersDarkTile: true, isSelfContained: false)
            }
            return nil
        }
    }
}

/// Logo for a ticker, falling back to a coloured initials avatar when no
/// source has usable artwork.
struct StockLogoView: View {
    let symbol: String
    var logoURL: String? = nil
    var diameter: CGFloat = 36

    @State private var logo: StockLogo?

    /// Rounded square rather than a circle: most ticker logos ship as
    /// filled squares, and clipping those to a circle shaves their corners
    /// and leaves a square floating inside a ring. A squircle matches the
    /// artwork's own shape and reads like an app icon.
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: diameter * 0.26, style: .continuous)
    }

    var body: some View {
        Group {
            if let logo {
                if logo.isSelfContained {
                    // Already an icon — fill the frame, no tile, no inset.
                    Image(uiImage: logo.image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(uiImage: logo.image)
                        .resizable()
                        .scaledToFit()
                        .padding(diameter * 0.18)
                        .frame(width: diameter, height: diameter)
                        .background(logo.prefersDarkTile ? Color(white: 0.12) : Color.white)
                }
            } else {
                TickerAvatar(symbol: symbol, diameter: diameter)
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.08)))
        .task(id: symbol) {
            logo = StockLogoCache.shared.cachedLogo(for: symbol)
            if logo == nil {
                logo = await StockLogoCache.shared.logo(for: symbol, preferred: logoURL)
            }
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        StockLogoView(symbol: "QQQ", diameter: 48)
        StockLogoView(symbol: "VOO", diameter: 48)
        StockLogoView(symbol: "SPY", diameter: 48)
        StockLogoView(symbol: "AAPL", diameter: 48)
    }
    .padding()
}

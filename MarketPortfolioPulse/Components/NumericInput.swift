import Foundation

extension Double {
    /// Renders a value for an editable text field: no thousands separators
    /// (they fight with typing) and trailing ".0" dropped for whole numbers.
    func formattedInput(decimals: Int) -> String {
        if decimals == 0 || self == rounded() {
            return String(Int(rounded()))
        }
        return String(format: "%.\(decimals)f", self)
    }
}

extension String {
    /// Parses partially-typed numeric input, tolerating stray currency
    /// symbols, separators and a lone "-" mid-typing. Returns `fallback`
    /// when the field can't be parsed yet, so clearing a field never
    /// collapses the projection to zero while the user is still typing.
    func clampedDouble(to range: ClosedRange<Double>, fallback: Double) -> Double {
        let normalized = replacingOccurrences(of: ",", with: ".")
        let cleaned = normalized.filter { $0.isNumber || $0 == "." || $0 == "-" }
        guard let value = Double(cleaned) else { return fallback }
        return Swift.min(Swift.max(value, range.lowerBound), range.upperBound)
    }
}

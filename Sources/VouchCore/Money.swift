import Foundation

/// Money parsing and formatting.
///
/// `Decimal` only — never `Double`, not once, not for display. The proof compares
/// values with exact equality (SPEC 3.6), which `Double` cannot support.
public enum Money {

    /// Parses a statement amount such as `1,436.69` into an exact `Decimal`.
    ///
    /// Returns nil unless the string is exactly a comma-grouped decimal with two
    /// fraction digits. Deliberately strict: a lenient money parser is how wrong
    /// numbers enter a ledger.
    public static func parse(_ text: some StringProtocol) -> Decimal? {
        let raw = text.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return nil }

        var seenDot = false
        var fractionDigits = 0
        for ch in raw {
            switch ch {
            case "0"..."9": if seenDot { fractionDigits += 1 }
            case ",": if seenDot { return nil }          // no commas after the point
            case ".": if seenDot { return nil }; seenDot = true
            default: return nil
            }
        }
        guard seenDot, fractionDigits == 2 else { return nil }

        // Decimal(string:) is exact for this shape; Double would not be.
        return Decimal(string: raw.replacingOccurrences(of: ",", with: ""), locale: nil)
    }

    /// Formats for console output with grouping and two fraction digits.
    public static func string(_ value: Decimal) -> String {
        Self.formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.usesGroupingSeparator = true
        f.groupingSeparator = ","
        f.decimalSeparator = "."
        return f
    }()
}

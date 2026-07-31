import SwiftUI

/// Type scale (SPEC 6.2).
///
/// The one risk worth taking: a serif on the *figures*, not the headlines.
/// Everything else is SF Pro, because on iOS a bundled UI face costs Dynamic
/// Type and tabular figures — and this app is a column of amounts.
public enum VouchType {

    /// Name of the bundled display serif, or nil to use the system serif
    /// (New York) — itself a legitimate candidate, since it ships with real
    /// tabular figures and Dynamic Type. See `DECISIONS.md` Q6b.
    ///
    /// A `let`, not a `var`: the face is a build-time decision, and mutable
    /// global state isn't concurrency-safe under Swift 6.
    public static let heroSerifName: String? = nil

    /// The month total. Instrument Serif if bundled, otherwise New York.
    ///
    /// `relativeTo:` is mandatory for a bundled face — without it the font
    /// ignores Dynamic Type entirely and fails SPEC 6.7.
    public static func hero(_ size: CGFloat = 48) -> Font {
        if let name = heroSerifName {
            return .custom(name, size: size, relativeTo: .largeTitle)
        }
        return .system(size: size, weight: .regular, design: .serif)
    }

    /// Row amounts and balances.
    ///
    /// **SF Pro with tabular digits, not SF Mono.** A ledger needs figures of
    /// equal advance width; it does not need every *letter* monospaced, which
    /// is what makes a monospaced font read as terminal output. Apply
    /// `.monospacedDigit()` at the call site — SF Pro ships tabular numerals,
    /// so this is free and keeps Dynamic Type intact.
    public static let figure = Font.system(size: 15)

    public static let body = Font.system(size: 15)

    /// Uppercase, tracked. Pair with `.tracking(1.0)`.
    public static let eyebrow = Font.system(size: 11, weight: .medium)

    /// Provenance only — the raw parsed line. A machine-output texture is
    /// correct here because that is exactly what it is.
    public static let source = Font.system(size: 12, design: .monospaced)
}

public extension Text {
    /// Figures always get tabular digits. There is no case where they don't.
    func vouchFigure() -> Text {
        self.font(VouchType.figure).monospacedDigit()
    }

    func vouchEyebrow() -> some View {
        self.font(VouchType.eyebrow).tracking(1.0).textCase(.uppercase)
    }
}

/// Formats a `Decimal` the way a statement does: grouped, two fraction digits,
/// no currency symbol inside a single-account list (SPEC 6.2).
public enum Figure {
    public static func string(_ value: Decimal) -> String {
        formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    /// Splits into dollars and cents so the cents can be set one step down and
    /// dimmed — the eye reads magnitude first.
    public static func parts(_ value: Decimal) -> (dollars: String, cents: String) {
        let s = string(value)
        guard let dot = s.lastIndex(of: ".") else { return (s, "") }
        return (String(s[s.startIndex..<dot]), String(s[dot...]))
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

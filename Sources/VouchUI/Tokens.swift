import SwiftUI

/// The two modes (SPEC 6.1). Not a dark app with a light setting bolted on —
/// the same object at two stages.
public enum VouchMode: String, Sendable, CaseIterable {
    /// The original document: warm off-white stock, dark violet-black ink.
    case paper
    /// The copy: near-black violet-cast surface, paper-white figures.
    case carbon
}

/// Semantic colour tokens (SPEC 6.2).
///
/// **No component ever names a hex or a mode.** Everything resolves through
/// this type, which is what makes shipping two modes cost an hour rather than a
/// weekend. Changing the accent is one line here.
public struct VouchTheme: Sendable, Equatable {
    public let mode: VouchMode

    public let surface: Color
    public let surfaceRaised: Color
    public let surfaceSunken: Color
    public let ink: Color
    public let inkDim: Color
    public let rule: Color
    /// **Proved.** Proof strip, agreeing figures, primary action. Nothing else.
    public let accent: Color
    public let accentSunken: Color
    public let debit: Color
    public let credit: Color
    public let pending: Color

    static func hex(_ v: UInt32) -> Color {
        Color(.sRGB,
              red: Double((v >> 16) & 0xFF) / 255,
              green: Double((v >> 8) & 0xFF) / 255,
              blue: Double(v & 0xFF) / 255,
              opacity: 1)
    }

    public static let paper = VouchTheme(
        mode: .paper,
        surface:       hex(0xF4F1EA),
        surfaceRaised: hex(0xFFFFFF),
        surfaceSunken: hex(0xE7E2D8),
        ink:           hex(0x1A1626),
        inkDim:        hex(0x5C556B),
        rule:          hex(0xD6D0C4),
        accent:        hex(0x5B3FBF),
        accentSunken:  hex(0xEDE7FB),
        debit:         hex(0xB03A2E),
        credit:        hex(0x2A6B58),
        pending:       hex(0xA9761B)
    )

    public static let carbon = VouchTheme(
        mode: .carbon,
        surface:       hex(0x14111C),
        surfaceRaised: hex(0x1D1929),
        surfaceSunken: hex(0x0E0C14),
        ink:           hex(0xEAE6F2),
        inkDim:        hex(0x9A93AD),
        rule:          hex(0x2C2638),
        accent:        hex(0x9B7DF5),
        accentSunken:  hex(0x221B38),
        debit:         hex(0xE06A5E),
        credit:        hex(0x4CA88C),
        pending:       hex(0xE0A94A)
    )

    public static func of(_ mode: VouchMode) -> VouchTheme {
        mode == .paper ? .paper : .carbon
    }
}

// MARK: - Environment

private struct VouchThemeKey: EnvironmentKey {
    static let defaultValue: VouchTheme = .carbon
}

public extension EnvironmentValues {
    var vouch: VouchTheme {
        get { self[VouchThemeKey.self] }
        set { self[VouchThemeKey.self] = newValue }
    }
}

public extension View {
    /// Applies a mode and paints the surface behind the content.
    func vouchTheme(_ mode: VouchMode) -> some View {
        let theme = VouchTheme.of(mode)
        return self
            .environment(\.vouch, theme)
            .background(theme.surface)
            .colorScheme(mode == .paper ? .light : .dark)
    }
}

/// 8pt grid (SPEC 6.2 Layout).
public enum Space {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 16
    public static let l: CGFloat = 24
    public static let xl: CGFloat = 32
    /// Consistent horizontal margin so decimal points align down the column.
    public static let gutter: CGFloat = 20
    /// Full-bleed hairline. One device pixel, not one point.
    public static let hairline: CGFloat = 1.0 / 3.0
}

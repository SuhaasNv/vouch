import SwiftUI

/// The signature element (SPEC 6.1).
///
/// Carries the verdict in its own **form**, not in a label — solid, dashed and
/// broken are three different shapes, so it survives greyscale and every form
/// of colour blindness. Never render this as one bar in three colours.
///
/// Never glass (SPEC 6.5): its legibility is load-bearing, and a translucent
/// verdict is a hedged verdict.
public struct ProofStrip: View {

    public enum State: Sendable, Equatable {
        case vouched
        case unvouched(delta: Decimal)
        /// `at` is the fractional position of the break, 0…1.
        case gap(delta: Decimal, at: Double)
    }

    private let state: State
    private let height: CGFloat
    @Environment(\.vouch) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ state: State, height: CGFloat = 3) {
        self.state = state
        self.height = height
    }

    private var color: Color {
        switch state {
        case .vouched: theme.accent
        case .unvouched, .gap: theme.pending
        }
    }

    public var body: some View {
        Canvas { ctx, size in
            let y = size.height / 2
            var path = Path()

            switch state {
            case .vouched:
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(path, with: .color(color),
                           style: StrokeStyle(lineWidth: height, lineCap: .butt))

            case .unvouched:
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(path, with: .color(color),
                           style: StrokeStyle(lineWidth: height, lineCap: .butt,
                                              dash: [6, 5]))

            case .gap(_, let at):
                // The break sits where the gap is — the strip is a timeline.
                let clamped = min(max(at, 0.08), 0.92)
                let mid = size.width * clamped
                let half = min(18, size.width * 0.06)
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: max(0, mid - half), y: y))
                path.move(to: CGPoint(x: min(size.width, mid + half), y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(path, with: .color(color),
                           style: StrokeStyle(lineWidth: height, lineCap: .butt))
            }
        }
        .frame(height: height)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: state)
        .accessibilityElement()
        .accessibilityLabel(voiceOverLabel)
    }

    /// The signature element cannot be the one thing a screen reader can't see.
    private var voiceOverLabel: String {
        switch state {
        case .vouched:
            "Vouched. Every figure agrees with the bank."
        case .unvouched(let delta):
            "Unvouched. \(Figure.string(delta)) unaccounted for."
        case .gap(let delta, _):
            "Gap. A statement is missing, \(Figure.string(delta)) unaccounted for."
        }
    }
}

/// The one-word state label that sits under the strip. One word per state,
/// everywhere, forever (SPEC 6.4).
public struct ProofLabel: View {
    private let state: ProofStrip.State
    @Environment(\.vouch) private var theme

    public init(_ state: ProofStrip.State) { self.state = state }

    public var body: some View {
        HStack(spacing: Space.s) {
            Text(word).vouchEyebrow()
                .foregroundStyle(state.isVouched ? theme.accent : theme.pending)
            if let detail {
                Text(detail).font(VouchType.eyebrow).monospacedDigit()
                    .foregroundStyle(theme.inkDim)
            }
            Spacer(minLength: 0)
        }
    }

    private var word: String {
        switch state {
        case .vouched: "Vouched"
        case .unvouched: "Unvouched"
        case .gap: "Gap"
        }
    }

    private var detail: String? {
        switch state {
        case .vouched: nil
        case .unvouched(let d): "Δ \(Figure.string(d)) unaccounted"
        case .gap(let d, _): "Δ \(Figure.string(d)) between statements"
        }
    }
}

public extension ProofStrip.State {
    var isVouched: Bool { if case .vouched = self { true } else { false } }
}

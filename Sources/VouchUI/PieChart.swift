import SwiftUI

/// Category breakdown as a pie/donut.
///
/// SPEC 6.3 argued for a single stacked bar because a pie "lies about small
/// slices". That's a real failure mode and it's visible in this user's own
/// data — vending is 28% of rows and 1.8% of value — but it is a failure of
/// *unordered, unlabelled* pies. Sorted largest-first, with a collapsed tail
/// and figures on the legend, a donut is legible and is what most people
/// expect from an expense tracker.
///
/// Same discipline as everywhere else: a tonal ramp, not a rainbow. Colour
/// distinguishes adjacent slices; it never encodes meaning that the label
/// doesn't already carry.
public struct PieChart: View {

    public struct Slice: Sendable, Equatable, Identifiable {
        public let category: String
        public let amount: Decimal
        public var id: String { category }
        public init(category: String, amount: Decimal) {
            self.category = category
            self.amount = amount
        }
    }

    private let slices: [Slice]
    private let diameter: CGFloat
    private let thickness: CGFloat
    private let collapseBelowPercent: Decimal

    @Environment(\.vouch) private var theme

    public init(_ slices: [Slice], diameter: CGFloat = 190,
                thickness: CGFloat = 34, collapseBelowPercent: Decimal = 3) {
        self.slices = slices
        self.diameter = diameter
        self.thickness = thickness
        self.collapseBelowPercent = collapseBelowPercent
    }

    private var total: Decimal { slices.reduce(0) { $0 + $1.amount } }

    /// Sorted largest-first with sub-threshold slices folded into one tail.
    /// An unsorted pie with a dozen slivers is the thing worth avoiding.
    private var ordered: [Slice] {
        guard total > 0 else { return [] }
        let sorted = slices.sorted { $0.amount > $1.amount }
        var kept: [Slice] = []
        var tail: Decimal = 0
        for s in sorted {
            if (s.amount / total) * 100 >= collapseBelowPercent { kept.append(s) }
            else { tail += s.amount }
        }
        if tail > 0 { kept.append(Slice(category: "Other", amount: tail)) }
        return kept
    }

    /// Tonal ramp on `ink`, darkest first. Distinguishes neighbours without
    /// inventing a palette — `accent` stays reserved for proved (SPEC 6.1).
    private func tone(_ i: Int, of n: Int) -> Color {
        guard n > 1 else { return theme.ink.opacity(0.85) }
        let t = Double(i) / Double(n - 1)
        return theme.ink.opacity(0.88 - 0.60 * t)
    }

    public var body: some View {
        let items = ordered
        let sum = total
        return VStack(alignment: .leading, spacing: Space.l) {
            ZStack {
                Canvas { ctx, size in
                    guard sum > 0 else { return }
                    let r = min(size.width, size.height) / 2
                    let c = CGPoint(x: size.width / 2, y: size.height / 2)
                    var angle = -Double.pi / 2          // start at 12 o'clock
                    for (i, s) in items.enumerated() {
                        let frac = NSDecimalNumber(decimal: s.amount / sum).doubleValue
                        let end = angle + frac * 2 * .pi
                        var p = Path()
                        p.addArc(center: c, radius: r - thickness / 2,
                                 startAngle: .radians(angle), endAngle: .radians(end),
                                 clockwise: false)
                        ctx.stroke(p, with: .color(tone(i, of: items.count)),
                                   style: StrokeStyle(lineWidth: thickness, lineCap: .butt))
                        angle = end
                    }
                }
                .frame(width: diameter, height: diameter)

                VStack(spacing: 2) {
                    Text(Figure.string(sum)).font(.system(size: 24, design: .serif))
                        .monospacedDigit().foregroundStyle(theme.ink)
                    Text("total out").vouchEyebrow().foregroundStyle(theme.inkDim)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Spending by category, \(Figure.string(sum)) total")

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, s in
                    HStack(spacing: Space.s) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(tone(i, of: items.count))
                            .frame(width: 10, height: 10)
                        Text(s.category).font(VouchType.body).foregroundStyle(theme.ink)
                            .lineLimit(1)
                        Spacer(minLength: Space.s)
                        Text("\(percent(s.amount, of: sum))%")
                            .font(VouchType.figure).monospacedDigit()
                            .foregroundStyle(theme.inkDim)
                            .frame(width: 40, alignment: .trailing)
                        Text(Figure.string(s.amount))
                            .font(VouchType.figure).monospacedDigit()
                            .foregroundStyle(theme.ink)
                            .frame(width: 78, alignment: .trailing)
                    }
                    .padding(.vertical, 9)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(s.category), \(Figure.string(s.amount)), "
                                        + "\(percent(s.amount, of: sum)) percent")
                    Rectangle().fill(theme.rule).frame(height: Space.hairline)
                }
            }
        }
    }

    private func percent(_ a: Decimal, of t: Decimal) -> Int {
        guard t > 0 else { return 0 }
        var raw = (a / t) * 100, out = Decimal()
        NSDecimalRound(&out, &raw, 0, .plain)
        return NSDecimalNumber(decimal: out).intValue
    }
}

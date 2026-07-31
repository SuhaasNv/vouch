import SwiftUI

/// Money as a screen reader should say it — `"1,880 dollars 20 cents"`, not
/// `"1,880 point 2 0"` (SPEC 6.7: VoiceOver on every amount).
///
/// Dollar wording is correct for the statement set as it stands: every account
/// observed is SGD or USD (D-018). A non-dollar currency means extending this
/// one function, not every label that calls it.
enum Spoken {
    static func money(_ value: Decimal) -> String {
        let parts = Figure.parts(value)
        let cents = parts.cents.hasPrefix(".") ? String(parts.cents.dropFirst()) : parts.cents
        if cents.isEmpty || cents == "00" { return "\(parts.dollars) dollars" }
        return "\(parts.dollars) dollars \(cents) cents"
    }
}

/// The month's spend as one stacked bar, with a legend line beneath it
/// (SPEC 6.3).
///
/// **One bar. Never a pie, never a donut** — SPEC 2.4 rules those out and
/// reference `07` is the reason: two of them on one screen, both lying about
/// their small slices. A single bar reads at a glance and its segments are
/// comparable along one axis.
///
/// **Value-weighted, never count-weighted (D-016).** Measured across 499 real
/// transactions, 28.1% of rows are ~SGD 0.50 vending purchases worth 1.8% of
/// the money. A count-weighted bar would tell this user their life is a vending
/// machine habit. There is deliberately no initialiser here that takes counts,
/// and there should never be one.
///
/// **Nothing in this bar is violet.** `accent` means *proved* (CLAUDE.md rule
/// 6); a category is not a verdict. The bar is `ink-dim` throughout with at
/// most one segment stepped up to full `ink` — reference `08`'s discipline of
/// one emphasis used once — plus the semantic tokens where a segment genuinely
/// carries a semantic (`pending` for unreviewed, `credit` for an inflow).
public struct CategoryBar: View {

    /// Colour roles map to theme tokens. Callers never pass a `Color` — that is
    /// how two modes stay one line of work (SPEC 6.2, CLAUDE.md rule 7).
    ///
    /// There is no `transfers` role on purpose. Money moving between your own
    /// accounts must not reach a spend breakdown at all (SPEC 3.7) — reference
    /// `08` shipped a design with `Transfers 53%` sitting inside its expense
    /// groups, which is that bug rendered at full size.
    public enum Role: Sendable, Equatable, CaseIterable {
        /// The default. Near-monochrome is the point.
        case spend
        /// The one segment worth looking at this month, one step up in weight.
        case emphasis
        /// Uncategorised or awaiting review — including the payment aggregators
        /// that are uncategorisable by design (D-012).
        case unreviewed
        /// Money in, for a bar that shows both directions.
        case inflow
        /// The collapsed tail. Synthesised by the bar; rarely passed in.
        case other
    }

    public struct Slice: Sendable, Equatable, Identifiable {
        public let category: String
        /// A magnitude, always ≥ 0.
        public let amount: Decimal
        public let role: Role

        public var id: String { category }

        public init(category: String, amount: Decimal, role: Role = .spend) {
            self.category = category
            self.amount = amount
            self.role = role
        }
    }

    private let slices: [Slice]
    private let collapseBelowPercent: Decimal
    private let legendCount: Int
    private let height: CGFloat

    @Environment(\.vouch) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - slices: value-weighted, in any order. The bar sorts them itself,
    ///     largest first, so the reading order is always the money order.
    ///   - collapseBelowPercent: segments below this share of the total fold
    ///     into one `other` segment. A 1%-wide slice on a 335pt bar is three
    ///     points of colour that reads as a rounding error; collapsing it is
    ///     what stops the bar lying about small slices. Their value is not
    ///     discarded — it moves into `other` and is still in the total.
    ///   - legendCount: how many categories the legend names before it
    ///     summarises the rest as `+9`.
    public init(_ slices: [Slice],
                collapseBelowPercent: Decimal = 2,
                legendCount: Int = 2,
                height: CGFloat = 10) {
        self.slices = slices
        self.collapseBelowPercent = collapseBelowPercent
        self.legendCount = legendCount
        self.height = height
    }

    public var body: some View {
        let segments = self.segments
        let total = self.total

        VStack(alignment: .leading, spacing: Space.s) {
            GeometryReader { geo in
                // The separators come out of the drawable width first, so the
                // segments stay proportional to each other rather than to the
                // width minus a variable amount of nothing.
                let gaps = CGFloat(max(0, segments.count - 1)) * separator
                let usable = max(0, geo.size.width - gaps)

                HStack(spacing: separator) {
                    ForEach(segments) { segment in
                        Rectangle()
                            .fill(color(for: segment.role))
                            // No minimum width. Forcing a floor here would be
                            // the pie chart's lie in a straight line.
                            .frame(width: usable * fraction(segment.amount, of: total))
                            .accessibilityElement()
                            .accessibilityLabel(label(for: segment, of: total))
                    }
                }
            }
            .frame(height: height)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Spend by category. \(Spoken.money(total)) total.")
            // Width transition on data change, no entrance sweep (SPEC 6.6).
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: slices)

            legend
        }
    }

    // MARK: - Legend

    /// `Groceries 842 · Dining 611 · +9` (SPEC 6.3).
    ///
    /// Cents are dropped, never rounded up — the legend is a glance at
    /// magnitude and it will not state more money than there is. The exact
    /// figure is one VoiceOver swipe away, on the segment itself.
    private var legend: some View {
        let named = segments.prefix(legendCount)
        // `+9` counts categories, not segments — and a named `other` already
        // stands for the several it swallowed, so it counts for all of them.
        let represented = named.reduce(0) { $0 + max($1.collapsedCount, 1) }
        let remaining = max(0, positiveSlices.count - represented)
        var parts = named.map { "\($0.category) \(Figure.parts($0.amount).dollars)" }
        if remaining > 0 { parts.append("+\(remaining)") }

        return Text(parts.joined(separator: " · "))
            .font(VouchType.body)
            .monospacedDigit()
            .foregroundStyle(theme.inkDim)
            .lineLimit(1)
            .truncationMode(.tail)
            // Every segment already speaks its own exact figure; repeating a
            // rounded version of the same thing wastes a screen reader's time.
            .accessibilityHidden(true)
    }

    // MARK: - Segments

    private struct Segment: Identifiable, Equatable {
        let id: String
        let category: String
        let amount: Decimal
        let role: Role
        /// >0 only for the collapsed tail.
        let collapsedCount: Int
    }

    /// A stacked bar has no negative width, so a slice must arrive as a
    /// magnitude. A refund nets against its category before it gets here.
    private var positiveSlices: [Slice] { slices.filter { $0.amount > 0 } }

    private var total: Decimal {
        positiveSlices.reduce(Decimal(0)) { $0 + $1.amount }
    }

    private var segments: [Segment] {
        let total = self.total
        guard total > 0 else { return [] }

        // Largest first, name as the tiebreak so the order is deterministic
        // when two categories land on the same figure.
        let sorted = positiveSlices.sorted { a, b in
            a.amount == b.amount ? a.category < b.category : a.amount > b.amount
        }

        var kept: [Segment] = []
        var tail: [Slice] = []
        for slice in sorted {
            // The share test stays in `Decimal`. Money is never a `Double`,
            // including when it is only being compared (CLAUDE.md rule 1).
            if slice.amount * 100 >= total * collapseBelowPercent {
                kept.append(Segment(id: slice.category, category: slice.category,
                                    amount: slice.amount, role: slice.role,
                                    collapsedCount: 0))
            } else {
                tail.append(slice)
            }
        }

        if !tail.isEmpty {
            let amount = tail.reduce(Decimal(0)) { $0 + $1.amount }
            kept.append(Segment(id: "\u{2022}other", category: "Other",
                                amount: amount, role: .other,
                                collapsedCount: tail.count))
        }
        return kept
    }

    // MARK: - Geometry

    private var separator: CGFloat { 1 }

    /// Money never becomes a `Double`. A pixel width is not money — this is the
    /// one legitimate conversion, and it happens at the last possible step.
    private func fraction(_ amount: Decimal, of total: Decimal) -> CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(NSDecimalNumber(decimal: amount / total).doubleValue)
    }

    private func percent(_ amount: Decimal, of total: Decimal) -> Int {
        guard total > 0 else { return 0 }
        var raw = (amount / total) * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    private func color(for role: Role) -> Color {
        switch role {
        case .spend:      theme.inkDim
        case .emphasis:   theme.ink
        case .unreviewed: theme.pending
        case .inflow:     theme.credit
        // Quieter than `spend`, but still plainly a segment. `rule` — the
        // hairline tone — disappears into the surface in both modes, and a
        // tail you can't see is the same lie as a tail that isn't there.
        case .other:      theme.inkDim.opacity(0.45)
        }
    }

    private func label(for segment: Segment, of total: Decimal) -> String {
        let share = "\(percent(segment.amount, of: total)) percent"
        if segment.collapsedCount > 0 {
            return "\(segment.collapsedCount) smaller categories, "
                + "\(Spoken.money(segment.amount)), \(share)."
        }
        return "\(segment.category), \(Spoken.money(segment.amount)), \(share)."
    }
}

import SwiftUI

/// Coverage — the screen that closes the loop (SPEC 6.3).
///
/// One row per `(account, currency)`, because that is the proof unit (D-018) —
/// a single PDF carries more than one account and more than one currency, and a
/// row that mixes them is a row that cannot be proved.
///
/// **The marks are statement periods, not calendar months.** A card on a
/// 15th→14th cycle draws its own offsets. Faking the row into a calendar grid
/// would make it tidier and would be a lie about what was proved, which is the
/// one trade this product never makes. That is why a period carries its own
/// label and its own date range instead of an index into a year.
///
/// **Form carries the state; colour only marks position.** References `09` and
/// `20` in `docs/inspiration/` arrived at this shape independently — filled,
/// hollow-dashed, bare dot, and exactly one ringed. Solid / dashed / dot / ring
/// survive greyscale and every form of colour blindness (SPEC 6.7), which is
/// the same reason the proof strip is three shapes rather than three colours.
public struct CoverageGrid: View {

    /// A missing statement: named, dated, and priced in dollars. Never an
    /// accusation — "April missing", not "you forgot April" (SPEC 6.4).
    public struct Gap: Sendable, Equatable {
        /// "April" — the period, in words.
        public let name: String
        /// The two figures that don't meet, in the user's language:
        /// "Mar closing and May opening".
        public let between: String
        /// Δ, in dollars. The whole point: an unimported month is priced.
        public let delta: Decimal

        public init(name: String, between: String, delta: Decimal) {
            self.name = name
            self.between = between
            self.delta = delta
        }
    }

    public enum PeriodState: Sendable, Equatable {
        /// Level 1 passes and the chain links to the prior statement.
        case vouched
        /// The first-ever statement for this account. **Not a gap** — don't
        /// accuse the user of losing a statement that predates the app
        /// (SPEC 1.2).
        case head
        /// Future, or before this account's history began. Not an error, and
        /// never rendered as one.
        case notYetImported
        /// Level 1 passes but the chain is broken.
        case gap(Gap)
    }

    public struct Period: Sendable, Equatable, Identifiable {
        public let id: String
        /// The mark's label — "Apr", or "15 Apr" for an off-calendar cycle.
        public let label: String
        /// The period in full, spoken and shown in the detail block:
        /// "1–30 Apr 2026".
        public let dateRange: String
        public let state: PeriodState

        public init(id: String, label: String, dateRange: String, state: PeriodState) {
            self.id = id
            self.label = label
            self.dateRange = dateRange
            self.state = state
        }
    }

    public struct Row: Sendable, Equatable, Identifiable {
        public let id: String
        /// "DBS Live Fresh".
        public let account: String
        /// Never hardcode SGD — a USD section exists and was silently skipped
        /// by every early analysis pass (D-018).
        public let currency: String
        public let periods: [Period]
        /// Shown when the row is complete: "Complete, Jan – Jul."
        public let note: String?

        public init(id: String, account: String, currency: String,
                    periods: [Period], note: String? = nil) {
            self.id = id
            self.account = account
            self.currency = currency
            self.periods = periods
            self.note = note
        }
    }

    private let rows: [Row]
    private let showsKey: Bool
    private let onImport: ((Row, Gap) -> Void)?

    @Environment(\.vouch) private var theme

    /// - Parameters:
    ///   - onImport: nil hides the `Import` affordance. Passing it is what
    ///     turns a diagnosis into the two-tap fix in SPEC 5.6.
    ///   - showsKey: the four states are carried by shape, so the shapes need
    ///     naming once on the screen.
    public init(_ rows: [Row],
                showsKey: Bool = true,
                onImport: ((Row, Gap) -> Void)? = nil) {
        self.rows = rows
        self.showsKey = showsKey
        self.onImport = onImport
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                CoverageRow(row, onImport: onImport.map { handler in
                    { gap in handler(row, gap) }
                })
                Rectangle().fill(theme.rule).frame(height: Space.hairline)
            }
            if showsKey { key }
        }
    }

    private var key: some View {
        HStack(spacing: Space.m) {
            keyItem(.filled, "Vouched")
            keyItem(.dashed, "Gap")
            keyItem(.dot, "No statement yet")
        }
        .padding(.horizontal, Space.gutter)
        .padding(.vertical, Space.m)
        // Every mark already announces its own state in words.
        .accessibilityHidden(true)
    }

    private func keyItem(_ form: CoverageMark.Form, _ label: String) -> some View {
        HStack(spacing: 6) {
            CoverageMark(form).frame(width: 16)
            Text(label).vouchEyebrow().foregroundStyle(theme.inkDim)
        }
    }
}

// MARK: - One account, one currency

/// A single `(account, currency)` timeline: heading, marks, verdict strip, and
/// the priced detail for anything missing.
public struct CoverageRow: View {

    private let row: CoverageGrid.Row
    private let onImport: ((CoverageGrid.Gap) -> Void)?

    @Environment(\.vouch) private var theme

    public init(_ row: CoverageGrid.Row,
                onImport: ((CoverageGrid.Gap) -> Void)? = nil) {
        self.row = row
        self.onImport = onImport
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("\(row.account) · \(row.currency)")
                .vouchEyebrow()
                .foregroundStyle(theme.inkDim)
                .accessibilityLabel("\(row.account), \(row.currency)")

            marks

            // The same signature element as everywhere else: solid when the
            // chain holds, broken at the position of the first missing period.
            ProofStrip(strip)

            if gaps.isEmpty {
                if let note = row.note {
                    Text(note)
                        .font(VouchType.body)
                        .foregroundStyle(theme.ink)
                }
            } else {
                ForEach(Array(gaps.enumerated()), id: \.offset) { _, item in
                    gapBlock(item.period, item.gap)
                }
            }
        }
        .padding(.horizontal, Space.gutter)
        .padding(.vertical, Space.l)
    }

    // MARK: Marks

    private var marks: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(row.periods) { period in
                VStack(spacing: 6) {
                    CoverageMark(state: period.state)
                    Text(period.label)
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(theme.inkDim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                // The marks are read-only. An interactive cell would need a
                // 44pt target (SPEC 6.7) and twelve of those do not fit at
                // 375pt — the affordance lives on the gap block instead.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(voiceOverLabel(period))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(row.account), \(row.currency), statement periods")
    }

    /// "April, gap, 1,880 dollars 20 cents unaccounted."
    private func voiceOverLabel(_ period: CoverageGrid.Period) -> String {
        switch period.state {
        case .vouched:
            "\(period.label), \(period.dateRange), vouched."
        case .head:
            "\(period.label), \(period.dateRange), first statement. "
                + "The start of this account's history, not a gap."
        case .notYetImported:
            "\(period.label), no statement yet."
        case .gap(let gap):
            "\(gap.name), gap, \(Spoken.money(gap.delta)) unaccounted. "
                + "\(period.dateRange) missing."
        }
    }

    // MARK: The gap, priced

    private func gapBlock(_ period: CoverageGrid.Period,
                          _ gap: CoverageGrid.Gap) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("\(gap.name) missing · \(period.dateRange)")
                .font(VouchType.body)
                .foregroundStyle(theme.ink)

            // Never "transactions may be missing" — say which check failed and
            // by how much (SPEC 6.4).
            Text("Δ \(Figure.string(gap.delta)) between \(gap.between).")
                .font(VouchType.body)
                .monospacedDigit()
                .foregroundStyle(theme.inkDim)
                .accessibilityLabel(
                    "\(Spoken.money(gap.delta)) between \(gap.between)."
                )

            if let onImport {
                // The word for the action is the same throughout (SPEC 6.4).
                Button { onImport(gap) } label: {
                    Text("Import")
                        .font(VouchType.body)
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, Space.m)
                        .frame(minHeight: 44)
                        .overlay(
                            Rectangle().stroke(theme.accent, lineWidth: Space.hairline * 3)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Import \(gap.name)")
            }
        }
        .padding(.top, Space.xs)
    }

    // MARK: Derived state

    private var gaps: [(period: CoverageGrid.Period, gap: CoverageGrid.Gap)] {
        row.periods.compactMap { period in
            if case .gap(let gap) = period.state { return (period, gap) }
            return nil
        }
    }

    /// One strip for the row. The delta is everything unaccounted across the
    /// row; the break sits at the first missing period, because the strip is a
    /// timeline and the detail blocks below enumerate the rest.
    private var strip: ProofStrip.State {
        guard !gaps.isEmpty else { return .vouched }
        let total = gaps.reduce(Decimal(0)) { $0 + $1.gap.delta }
        let count = max(row.periods.count, 1)
        let firstIndex = row.periods.firstIndex { if case .gap = $0.state { true } else { false } } ?? 0
        let at = (Double(firstIndex) + 0.5) / Double(count)
        return .gap(delta: total, at: at)
    }
}

// MARK: - The mark

/// Four states, four shapes. Colour is redundant here by design — remove it and
/// the row still reads (SPEC 6.7, reference `09`).
struct CoverageMark: View {

    /// The shape, named separately from the state so the key can draw a mark
    /// without inventing a transaction's worth of fake data to do it.
    enum Form {
        case filled
        case ringed
        case dashed
        case dot
    }

    let form: Form

    @Environment(\.vouch) private var theme

    private var height: CGFloat { 10 }
    /// Reserved so the head's ring never shifts the row it sits in.
    private var slot: CGFloat { 16 }

    init(_ form: Form) { self.form = form }

    init(state: CoverageGrid.PeriodState) {
        switch state {
        case .vouched:        self.form = .filled
        case .head:           self.form = .ringed
        case .gap:            self.form = .dashed
        case .notYetImported: self.form = .dot
        }
    }

    var body: some View {
        ZStack {
            switch form {
            case .filled:
                RoundedRectangle(cornerRadius: 2).fill(theme.accent)
                    .frame(height: height)

            case .ringed:
                RoundedRectangle(cornerRadius: 2).fill(theme.accent)
                    .frame(height: height)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(theme.accent, lineWidth: 1)
                            .padding(-3)
                    )

            case .dashed:
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(theme.pending,
                                  style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .frame(height: height)

            case .dot:
                // Absence, not failure. A bare dot in the hairline tone — the
                // same weight as the rules on the page.
                Circle().fill(theme.rule).frame(width: 3, height: 3)
            }
        }
        .frame(height: slot)
    }
}

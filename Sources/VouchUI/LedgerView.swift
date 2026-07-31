import SwiftUI

// MARK: - View model

/// One month of the ledger, in the shape the view needs it.
///
/// A plain value type on purpose: `VouchUI` never imports `VouchStore` or
/// SwiftData, so the Ledger renders in a preview, in `vouch-gallery`, and in a
/// headless `ImageRenderer` pass without a model container anywhere near it.
/// The app layer maps one `(account, currency)` period — a `StatementImport`
/// plus its `[Transaction]` — onto this.
///
/// Months arrive in the order they should render (newest first). This type
/// never sorts, filters or merges: the ledger shows what it is handed, and
/// dropping a row is the one thing this product may never do.
public struct LedgerMonth: Sendable, Equatable, Identifiable {

    /// Stable across renders — the scroll anchor's identity. `"2026-07"`.
    public let id: String
    /// The month break / sticky bar label. `"July 2026"`.
    public let title: String
    /// The hero's eyebrow. Prefer the **statement period** — `"1 – 31 Jul 2026"` —
    /// because periods are what actually got proved, and because repeating
    /// `title` two lines under the sticky bar reads as a rendering bug.
    /// Falls back to `title` when nil.
    public let periodLabel: String?
    /// Money out for the month. Already `Decimal`; never a `Double`.
    public let total: Decimal
    public let currency: String
    /// The proved transaction count — the statement's own figure, which is what
    /// the header is claiming. If it disagrees with `rows.count`, that is a
    /// finding, not something to paper over.
    public let count: Int
    public let account: String
    public let proof: ProofStrip.State
    /// Newest first. Presentation grouping happens in the view; these rows are
    /// the real rows and stay the real rows.
    public let rows: [LedgerRow.Model]

    public init(id: String, title: String, periodLabel: String? = nil,
                total: Decimal, currency: String = "SGD", count: Int,
                account: String, proof: ProofStrip.State, rows: [LedgerRow.Model]) {
        self.id = id
        self.title = title
        self.periodLabel = periodLabel
        self.total = total
        self.currency = currency
        self.count = count
        self.account = account
        self.proof = proof
        self.rows = rows
    }

    var heroEyebrow: String { periodLabel ?? title }
}

// MARK: - The Ledger

/// The home screen (SPEC 6.3).
///
/// **One continuous table across all months** (D-008), not a month-at-a-time
/// silo. Every month lives in the same scroll view and the same `LazyVStack`,
/// so scrolling past 1 July into 30 June just works — no pagination, no
/// segmented control, no wall. The month header is a pinned scroll anchor: it
/// sits inline in the flow as a month-break divider and becomes sticky the
/// moment it reaches the top. One component, both jobs.
///
/// The balance column is a posture, not a fixture (D-025) — reading mode omits
/// it so merchant names are legible at 375pt, reconcile mode turns it on so the
/// list can be checked against the paper statement line by line. The toggle
/// lives in the toolbar because it is a reading posture, not a setting.
public struct LedgerView: View {

    private let months: [LedgerMonth]

    @State private var showBalance: Bool
    /// Ids of the collapsed groups the user has opened. Presentation state and
    /// nothing else — no row is created, merged or destroyed by it (D-016).
    @State private var expandedGroups: Set<String> = []

    @Environment(\.vouch) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameter showBalance: the initial reading posture. Defaults to
    ///   reading mode (balance column off) per D-025.
    public init(months: [LedgerMonth], showBalance: Bool = false) {
        self.months = months
        _showBalance = State(initialValue: showBalance)
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0,
                           pinnedViews: [.sectionHeaders]) {
                    ForEach(months) { month in
                        Section {
                            monthBody(month)
                        } header: {
                            monthBreak(month, proxy: proxy)
                        }
                    }
                    if months.isEmpty { emptyState }
                }
            }
            .background(theme.surface)
            .toolbar { postureToggle }
        }
    }

    // MARK: Month break — inline divider and sticky anchor

    /// `═══ JUNE 2026 · Vouched ═══` (SPEC 6.3).
    ///
    /// Rendered as the section header of a pinned `LazyVStack`, so it is an
    /// inline month break while it sits in the flow and a sticky anchor once it
    /// reaches the top. Opaque `surface` behind it — never glass, because rows
    /// scroll underneath and a translucent verdict is a hedged verdict
    /// (SPEC 6.5).
    ///
    /// Tapping it scrolls that month to the top: the month is an anchor and a
    /// filter, never a wall.
    private func monthBreak(_ month: LedgerMonth, proxy: ScrollViewProxy) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                proxy.scrollTo(month.id, anchor: .top)
            }
        } label: {
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(spacing: Space.s) {
                    Text(month.title).vouchEyebrow()
                        .foregroundStyle(theme.inkDim)
                    Text("·").font(VouchType.eyebrow)
                        .foregroundStyle(theme.inkDim)
                        .accessibilityHidden(true)
                    // The one word per state, plus the delta when there is one.
                    ProofLabel(month.proof)
                }
                .padding(.horizontal, Space.gutter)

                // Full bleed: the strip is the divider rule, and it carries the
                // verdict in its form rather than only in its colour.
                ProofStrip(month.proof, height: 2)
            }
            .padding(.top, Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(month.id)
        .accessibilityHint("Jumps to the start of \(month.title)")
    }

    // MARK: Month body

    @ViewBuilder
    private func monthBody(_ month: LedgerMonth) -> some View {
        MonthHeader(month: month.heroEyebrow,
                    total: month.total,
                    currency: month.currency,
                    count: month.count,
                    account: month.account,
                    proof: month.proof)

        columnHeader

        ForEach(LedgerGroup.groups(in: month.rows)) { group in
            groupView(group)
        }
    }

    /// `DATE  DESCRIPTION  AMOUNT  BAL` — the statement's own column strip
    /// (SPEC 6.3). Hidden from VoiceOver: every row already announces itself in
    /// full, so this would only add noise.
    private var columnHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Text("Date").vouchEyebrow()
                .frame(width: LedgerColumn.date, alignment: .leading)
            Text("Description").vouchEyebrow()
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Amount").vouchEyebrow()
                .frame(width: LedgerColumn.amount, alignment: .trailing)
            if showBalance {
                Text("Bal").vouchEyebrow()
                    .frame(width: LedgerColumn.balance, alignment: .trailing)
            }
        }
        .foregroundStyle(theme.inkDim)
        .lineLimit(1)
        .padding(.horizontal, Space.gutter)
        .padding(.bottom, Space.s)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.rule).frame(height: Space.hairline)
        }
        .accessibilityHidden(true)
    }

    // MARK: Rows and groups

    @ViewBuilder
    private func groupView(_ group: LedgerGroup) -> some View {
        if group.rows.count == 1 {
            LedgerRow(group.rows[0], showBalance: showBalance)
        } else {
            let isOpen = expandedGroups.contains(group.id)

            Button {
                withAnimation(expandMotion) {
                    if isOpen {
                        expandedGroups.remove(group.id)
                    } else {
                        expandedGroups.insert(group.id)
                    }
                }
            } label: {
                // The summary stays visible while the group is open — it is the
                // affordance to close it again, and the `×N` badge keeps it
                // legible as a subtotal rather than a seventh transaction.
                LedgerRow(group.collapsed, showBalance: showBalance)
                    .overlay(alignment: .trailing) { disclosure(isOpen) }
                    // The whole row is the target; the chevron sits in the
                    // right gutter and is decoration.
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isOpen
                ? "Collapses these \(group.rows.count) transactions"
                : "Expands \(group.rows.count) transactions")

            if isOpen {
                // The real rows — the same ones that were always there. The
                // group was a way of drawing them, never a way of storing them.
                VStack(spacing: 0) {
                    ForEach(group.rows) { row in
                        LedgerRow(row, showBalance: showBalance)
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private func disclosure(_ isOpen: Bool) -> some View {
        // Under Reduce Motion the glyph swaps instead of rotating.
        Image(systemName: reduceMotion && isOpen ? "chevron.down" : "chevron.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(theme.inkDim)
            .rotationEffect(.degrees(!reduceMotion && isOpen ? 90 : 0))
            .padding(.trailing, 6)
            .accessibilityHidden(true)
    }

    /// Group expand/collapse: height + opacity, ~0.25s, **no spring** — ledgers
    /// don't bounce (SPEC 6.6). Reduce Motion collapses it to a short crossfade.
    private var expandMotion: Animation {
        reduceMotion ? .linear(duration: 0.12) : .easeInOut(duration: 0.25)
    }

    // MARK: Reading / reconcile posture

    /// D-025: the balance column is a mode, not a fixture, and the toggle
    /// belongs in the toolbar rather than in Settings — it is a reading
    /// posture, not a preference.
    ///
    /// No animation on the flip. A figure may appear or disappear whole; what
    /// it may never do is animate its value (SPEC 6.6), and easing a width
    /// change across every visible row buys nothing.
    @ToolbarContentBuilder
    private var postureToggle: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showBalance.toggle()
            } label: {
                Label(showBalance ? "Reconcile" : "Reading",
                      systemImage: "tablecells")
                    .labelStyle(.titleAndIcon)
                    .font(VouchType.eyebrow)
            }
            // Not `accent`: violet means proved, and a reading posture is not a
            // verdict or a primary action (CLAUDE.md rule 6).
            .foregroundStyle(showBalance ? theme.ink : theme.inkDim)
            .accessibilityLabel("Balance column")
            .accessibilityValue(showBalance ? "On, reconcile mode" : "Off, reading mode")
            .accessibilityHint("Shows the running balance beside every row, so the list can be checked against the paper statement")
        }
    }

    // MARK: Empty

    /// An empty screen is an invitation, not a mood (SPEC 6.4).
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("No statements yet").vouchEyebrow()
                .foregroundStyle(theme.inkDim)
            Text("Import a statement to see a month you can prove.")
                .font(VouchType.body)
                .foregroundStyle(theme.ink)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.vertical, Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Columns

/// Mirrors `LedgerRow`'s fixed columns so the eyebrow strip sits over the right
/// figures. Keep in sync with `LedgerRow` — these are the same three columns.
private enum LedgerColumn {
    static let date: CGFloat = 46
    static let amount: CGFloat = 92
    static let balance: CGFloat = 78
}

// MARK: - Presentation grouping (D-016)

/// A run of consecutive rows the list draws as one line.
///
/// **Presentation only.** 28% of real rows are ~SGD 0.50 vending purchases
/// worth 1.8% of the money (D-016), and an honest one-row-per-transaction list
/// is unreadable. So the *drawing* collapses. The rows do not: every one of
/// them still exists, still counts, still proves. Merging them in storage is
/// D-005's bug wearing a different hat.
private struct LedgerGroup: Identifiable {
    /// The first row's id — unique across the ledger already.
    let id: String
    let rows: [LedgerRow.Model]
    /// The single line drawn when the group is closed.
    let collapsed: LedgerRow.Model

    /// Consecutive same-merchant, same-day, same-direction rows form a group.
    ///
    /// Consecutive is deliberate: it never reorders the ledger, so the list
    /// still reads in the statement's own sequence and can be checked against
    /// the paper line by line.
    static func groups(in rows: [LedgerRow.Model]) -> [LedgerGroup] {
        var out: [LedgerGroup] = []
        out.reserveCapacity(rows.count)

        var run: [LedgerRow.Model] = []

        func flush() {
            guard let first = run.first else { return }
            out.append(LedgerGroup(id: first.id, rows: run,
                                   collapsed: collapse(run)))
            run = []
        }

        for row in rows {
            if let last = run.last, !joins(last, row) { flush() }
            run.append(row)
        }
        flush()
        return out
    }

    private static func joins(_ a: LedgerRow.Model, _ b: LedgerRow.Model) -> Bool {
        a.dateLabel == b.dateLabel
            && a.merchant == b.merchant
            && a.isCredit == b.isCredit
    }

    private static func collapse(_ run: [LedgerRow.Model]) -> LedgerRow.Model {
        guard let first = run.first else {
            // Unreachable: `flush` guards on a non-empty run. No force unwrap.
            return LedgerRow.Model(id: "", dateLabel: "", merchant: "", amount: 0)
        }
        guard run.count > 1 else { return first }

        // Exact `Decimal` addition. The subtotal on a collapsed line is a real
        // figure and is held to the same standard as every other one.
        let subtotal = run.reduce(Decimal(0)) { $0 + $1.amount }

        return LedgerRow.Model(
            id: first.id,
            dateLabel: first.dateLabel,
            merchant: first.merchant,
            amount: subtotal,
            isCredit: first.isCredit,
            // Rows read newest first, so the run's first row is the last of the
            // group to post — its running balance is the balance after the
            // whole group cleared, which is the figure that matches the paper.
            balanceAfter: first.balanceAfter,
            groupCount: run.count
        )
    }
}

// MARK: - Previews

#if DEBUG
private func previewDecimal(_ s: String) -> Decimal {
    Decimal(string: s) ?? 0
}

private let previewMonths: [LedgerMonth] = [
    LedgerMonth(
        id: "2026-07",
        title: "July 2026",
        periodLabel: "1 – 31 Jul 2026",
        total: previewDecimal("3412.80"),
        count: 87,
        account: "DBS Multiplier",
        proof: .vouched,
        rows: [
            .init(id: "j1", dateLabel: "28 Jul", merchant: "SHENG SIONG",
                  amount: previewDecimal("42.30"), balanceAfter: previewDecimal("863.70")),
            .init(id: "j2", dateLabel: "28 Jul", merchant: "LE TACH VENDING",
                  amount: previewDecimal("0.50"), balanceAfter: previewDecimal("906.00")),
            .init(id: "j3", dateLabel: "28 Jul", merchant: "LE TACH VENDING",
                  amount: previewDecimal("0.50"), balanceAfter: previewDecimal("906.50")),
            .init(id: "j4", dateLabel: "28 Jul", merchant: "LE TACH VENDING",
                  amount: previewDecimal("0.50"), balanceAfter: previewDecimal("907.00")),
            .init(id: "j5", dateLabel: "27 Jul", merchant: "BUS/MRT 877402919",
                  amount: previewDecimal("4.22"), balanceAfter: previewDecimal("909.00")),
            .init(id: "j6", dateLabel: "27 Jul", merchant: "NORTHWIND ANALYTICS PTE LTD",
                  amount: previewDecimal("2400.00"), isCredit: true,
                  balanceAfter: previewDecimal("913.22")),
        ]),
    LedgerMonth(
        id: "2026-06",
        title: "June 2026",
        periodLabel: "1 – 30 Jun 2026",
        total: previewDecimal("2988.14"),
        count: 74,
        account: "DBS Multiplier",
        proof: .unvouched(delta: previewDecimal("340.00")),
        rows: [
            .init(id: "n1", dateLabel: "30 Jun", merchant: "KOPITIAM @ LAU PA SAT",
                  amount: previewDecimal("7.30"), balanceAfter: previewDecimal("1105.09")),
            .init(id: "n2", dateLabel: "29 Jun", merchant: "NTUC FP - TAMPINES HUB",
                  amount: previewDecimal("155.20"), balanceAfter: previewDecimal("1112.39")),
        ]),
]

/// Every mode, side by side, at 375pt. A screen isn't done until it has been
/// looked at in both (SPEC 6.7) — so the preview iterates `allCases` rather
/// than naming one, which is also the only reason a mode is mentioned in this
/// file at all. No colour is ever branched on it.
private struct LedgerPreview: View {
    let showBalance: Bool
    var body: some View {
        HStack(spacing: 0) {
            ForEach(VouchMode.allCases, id: \.self) { mode in
                LedgerView(months: previewMonths, showBalance: showBalance)
                    .frame(width: 375)
                    .vouchTheme(mode)
            }
        }
    }
}

#Preview("Ledger — reading") { LedgerPreview(showBalance: false) }

#Preview("Ledger — reconcile") { LedgerPreview(showBalance: true) }
#endif

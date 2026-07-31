import SwiftUI

/// One transaction in the ledger (SPEC 6.3).
///
/// Ruled paper: a full-bleed hairline underneath, square corners, no shadow,
/// no card. Amounts hard-right so decimal points align down the column.
public struct LedgerRow: View {

    public struct Model: Sendable, Equatable, Identifiable {
        public let id: String
        public let dateLabel: String       // "28 Jul"
        public let merchant: String
        public let amount: Decimal
        public let isCredit: Bool
        public let balanceAfter: Decimal?
        /// >1 renders as a collapsed group (D-016).
        public let groupCount: Int

        public init(id: String, dateLabel: String, merchant: String, amount: Decimal,
                    isCredit: Bool = false, balanceAfter: Decimal? = nil, groupCount: Int = 1) {
            self.id = id; self.dateLabel = dateLabel; self.merchant = merchant
            self.amount = amount; self.isCredit = isCredit
            self.balanceAfter = balanceAfter; self.groupCount = groupCount
        }
    }

    private let model: Model
    private let showBalance: Bool
    @Environment(\.vouch) private var theme

    /// `showBalance` defaults **off**.
    ///
    /// The balance column is the most on-thesis element in the product — it
    /// mirrors the source document so the list can be checked against the paper
    /// statement line by line. But at 375pt it costs ~78pt, and with the date
    /// and amount columns that starves merchant names down to about 45pt, which
    /// truncates `SHENG SIONG` to `SH…`. A ledger you can't read the merchants
    /// in is worse than one you can't eyeball-reconcile.
    ///
    /// So it becomes a mode, not a permanent fixture: off for reading, on for
    /// reconciling. See `DECISIONS.md` D-025.
    public init(_ model: Model, showBalance: Bool = false) {
        self.model = model
        self.showBalance = showBalance
    }

    private var amountColor: Color { model.isCredit ? theme.credit : theme.debit }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(model.dateLabel)
                    .font(VouchType.figure).monospacedDigit()
                    .foregroundStyle(theme.inkDim)
                    .lineLimit(1)
                    // 52, not 46: "30 Jun" is wider than "28 Jul" and truncated
                    // to "30 J…". Jun/Jan/Feb/Nov/Dec all hit this.
                    .frame(width: 52, alignment: .leading)

                HStack(spacing: 6) {
                    Text(model.merchant)
                        .font(VouchType.body)
                        .foregroundStyle(theme.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if model.groupCount > 1 {
                        // Presentation only — the rows still exist, still count,
                        // still prove. Never merged in storage (D-005).
                        Text("×\(model.groupCount)")
                            .font(VouchType.eyebrow)
                            .foregroundStyle(theme.inkDim)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(theme.accentSunken, in: RoundedRectangle(cornerRadius: 3))
                            .fixedSize()
                    }
                }
                // Merchant takes whatever the fixed columns leave, and truncates
                // there. SPEC 6.7: never truncate the amount to fit the
                // merchant — truncate the merchant.
                .frame(maxWidth: .infinity, alignment: .leading)

                // Fixed-width, right-aligned so decimal points align down the
                // column, and `fixedSize` so an amount can never wrap.
                amountView
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: 92, alignment: .trailing)

                if showBalance, let bal = model.balanceAfter {
                    // Mirrors the source document so the list can be checked
                    // against the paper statement by eye.
                    Text(Figure.string(bal))
                        .font(VouchType.figure).monospacedDigit()
                        .foregroundStyle(theme.inkDim)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(width: 78, alignment: .trailing)
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.vertical, 11)

            Rectangle().fill(theme.rule).frame(height: Space.hairline)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(voiceOverLabel)
    }

    /// Dollars at full weight, cents dimmed and a step down — the eye reads
    /// magnitude first, which is how people actually scan a statement.
    private var amountView: some View {
        let p = Figure.parts(model.amount)
        // One concatenated Text, not an HStack — a single run cannot wrap
        // between the dollars and the cents.
        return (
            Text(model.isCredit ? "+" : "−").font(VouchType.figure).monospacedDigit()
            + Text(p.dollars).font(VouchType.figure).monospacedDigit()
            + Text(p.cents).font(.system(size: 13)).monospacedDigit()
                .foregroundColor(amountColor.opacity(0.72))
        )
        .foregroundColor(amountColor)
        .lineLimit(1)
    }

    private var voiceOverLabel: String {
        let dir = model.isCredit ? "credit" : "debit"
        let count = model.groupCount > 1 ? "\(model.groupCount) transactions, " : ""
        return "\(model.dateLabel). \(count)\(model.merchant). \(Figure.string(model.amount)), \(dir)."
    }
}

/// The month total and its verdict (SPEC 6.3).
public struct MonthHeader: View {
    private let month: String
    private let total: Decimal
    private let currency: String
    private let count: Int
    private let account: String
    private let proof: ProofStrip.State
    @Environment(\.vouch) private var theme

    public init(month: String, total: Decimal, currency: String = "SGD",
                count: Int, account: String, proof: ProofStrip.State) {
        self.month = month; self.total = total; self.currency = currency
        self.count = count; self.account = account; self.proof = proof
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(month).vouchEyebrow().foregroundStyle(theme.inkDim)
                .padding(.bottom, Space.s)

            // The currency symbol appears once, here — never on every row.
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(currency).font(.system(size: 20, design: .serif))
                    .foregroundStyle(theme.inkDim)
                Text(Figure.string(total))
                    .font(VouchType.hero()).monospacedDigit()
                    .foregroundStyle(theme.ink)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Figure.string(total)) \(currency) spent in \(month)")

            Text("\(count) transactions · \(account)")
                .font(VouchType.body)
                .foregroundStyle(theme.inkDim)
                .padding(.top, Space.xs)

            ProofStrip(proof).padding(.top, Space.m)
            ProofLabel(proof).padding(.top, Space.s)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.vertical, Space.l)
    }
}

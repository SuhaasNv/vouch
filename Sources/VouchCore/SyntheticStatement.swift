import Foundation

/// Generates synthetic statements in the exact shape PDFKit produces (D-020).
///
/// Why this exists: golden fixtures need to be committable. Real statements
/// carry real spending — merchant, amount and running balance for every
/// transaction — and redacting identity does not redact behaviour. Synthetic
/// fixtures keep the *structure* that the parser and proof engine actually
/// exercise, with invented merchants and amounts.
///
/// The generated arithmetic is exact: every running balance follows from the
/// one before it, and the stated totals agree with the rows. A fixture that
/// didn't reconcile would prove nothing.
public struct SyntheticStatement: Sendable {

    public struct Row: Sendable {
        public let day: Int
        public let type: String
        public let merchant: String
        public let amount: Decimal
        public let isCredit: Bool
        public init(day: Int, type: String = "Debit Card Transaction",
                    merchant: String, amount: Decimal, isCredit: Bool = false) {
            self.day = day; self.type = type; self.merchant = merchant
            self.amount = amount; self.isCredit = isCredit
        }
    }

    public let month: Int, year: Int
    public let currency: String
    public let opening: Decimal
    public let rows: [Row]

    public init(month: Int, year: Int, currency: String = "SGD", opening: Decimal, rows: [Row]) {
        self.month = month; self.year = year; self.currency = currency
        self.opening = opening; self.rows = rows
    }

    public var closing: Decimal {
        rows.reduce(opening) { $1.isCredit ? $0 + $1.amount : $0 - $1.amount }
    }
    public var totalWithdrawals: Decimal {
        rows.filter { !$0.isCredit }.reduce(0) { $0 + $1.amount }
    }
    public var totalDeposits: Decimal {
        rows.filter(\.isCredit).reduce(0) { $0 + $1.amount }
    }

    private func dd(_ d: Int) -> String { String(format: "%02d/%02d/%04d", d, month, year) }
    private static let monthNames = ["JAN","FEB","MAR","APR","MAY","JUN",
                                     "JUL","AUG","SEP","OCT","NOV","DEC"]

    /// Emits the fixture text. `pageEvery` forces page breaks so the fixture
    /// exercises the per-page B/F / C/F repetition that broke early analysis.
    public func render(pageEvery: Int = 14) -> String {
        var out: [String] = []
        var page = 1
        var balance = opening

        out.append("### PAGE \(page)")
        out.append("Transaction Details")
        out.append("as at \(lastDay()) \(Self.monthNames[month - 1].capitalized) \(year)")
        out.append("My Account (XXXXXXXXX) Account No. 000-000000-0")
        out.append("Date Description Withdrawal (-) Deposit (+) Balance")
        out.append("CURRENCY: SINGAPORE DOLLAR")
        // The date on the B/F line belongs to the FIRST transaction — PDFKit
        // merges it there. Keeping that quirk is the point of this fixture.
        out.append("\(dd(rows.first?.day ?? 1)) Balance Brought Forward \(currency) \(Money.string(opening))")

        for (i, row) in rows.enumerated() {
            if i > 0 && i % pageEvery == 0 {
                out.append("Balance Carried Forward \(currency) \(Money.string(balance))")
                out.append("Page \(page) of \(pageCount(pageEvery))")
                page += 1
                out.append("### PAGE \(page)")
                out.append("My Account (XXXXXXXXX) Account No. 000-000000-0")
                out.append("Date Description Withdrawal (-) Deposit (+) Balance")
                out.append("Balance Brought Forward \(currency) \(Money.string(balance))")
            }
            balance = row.isCredit ? balance + row.amount : balance - row.amount
            out.append("\(dd(row.day)) \(row.type)")
            out.append("\(row.merchant) SI SGP \(String(format: "%02d", max(1, row.day - 2)))\(Self.monthNames[month - 1])")
            if row.type == "Debit Card Transaction" { out.append("0000-0000-0000-0000") }
            out.append("\(Money.string(row.amount)) \(Money.string(balance))")
        }

        out.append("Balance Carried Forward \(currency) \(Money.string(balance))")
        out.append("Total Balance Carried Forward in \(currency): "
                   + "\(Money.string(totalWithdrawals)) \(Money.string(totalDeposits)) \(Money.string(closing))")
        out.append("Transaction Details as of \(lastDay()) \(Self.monthNames[month - 1].capitalized) \(year)")
        return out.joined(separator: "\n") + "\n"
    }

    private func pageCount(_ every: Int) -> Int { max(1, (rows.count + every - 1) / every) }
    private func lastDay() -> Int {
        var c = DateComponents(); c.year = year; c.month = month
        let cal = Calendar(identifier: .gregorian)
        guard let d = cal.date(from: c),
              let r = cal.range(of: .day, in: .month, for: d) else { return 28 }
        return r.count
    }
}

/// The committed fixture set. Deterministic, arithmetically exact, and chained
/// month to month so Level 2 has something real to walk.
public enum SyntheticFixtures {

    /// Must go through `Money.parse`. `Decimal(string:)` silently truncates at
    /// the first comma — `Decimal(string: "1,436.69")` is `1`, not 1436.69.
    static func d(_ s: String) -> Decimal { Money.parse(s)! }

    /// January — includes a foreign-currency block and a salary credit.
    public static func january() -> SyntheticStatement {
        var rows: [SyntheticStatement.Row] = [
            .init(day: 3, merchant: "MERIDIAN COFFEE HOUSE", amount: d("7.30")),
            .init(day: 3, merchant: "MERIDIAN COFFEE HOUSE", amount: d("5.00")),
            .init(day: 4, merchant: "HARBOURSIDE GROCERS", amount: d("42.15")),
            .init(day: 5, merchant: "CITY TRANSIT NETWORK", amount: d("2.20")),
            .init(day: 6, merchant: "NORTHGATE PHARMACY", amount: d("18.40")),
            .init(day: 8, merchant: "CITY TRANSIT NETWORK", amount: d("4.22")),
            .init(day: 9, type: "Advice Point-Of-Sale Transaction or Proceeds",
                  merchant: "QR PAYMENT TO STALL 12", amount: d("6.50")),
            .init(day: 12, merchant: "ORCHID BOOKSHOP", amount: d("31.90")),
            .init(day: 15, type: "GIRO Salary", merchant: "NORTHWIND ANALYTICS PTE LTD",
                  amount: d("2,400.00"), isCredit: true),
            .init(day: 16, merchant: "HARBOURSIDE GROCERS", amount: d("63.75")),
            .init(day: 18, merchant: "LANTERN NOODLE BAR", amount: d("14.80")),
            .init(day: 20, type: "Advice FAST Payment / Receipt",
                  merchant: "TO: A FRIEND", amount: d("120.00")),
            .init(day: 22, merchant: "CITY TRANSIT NETWORK", amount: d("2.20")),
            .init(day: 24, merchant: "SUMMIT ELECTRONICS", amount: d("249.00")),
            .init(day: 26, merchant: "MERIDIAN COFFEE HOUSE", amount: d("7.30")),
            .init(day: 28, type: "ATM Transaction", merchant: "CASHPOINT CENTRAL 4", amount: d("200.00")),
        ]
        // Six identical same-day micro-charges — the D-005 regression case.
        // Real data had 118 of these in one month at ~0.50 each.
        for _ in 0..<6 { rows.append(.init(day: 29, merchant: "ATRIUM VENDING CO", amount: d("0.50"))) }
        rows.append(.init(day: 30, merchant: "LANTERN NOODLE BAR", amount: d("22.60")))
        // Opening must stay ahead of withdrawals: the statement format has no
        // representation for a negative running balance, and `Money.parse`
        // rejects a leading minus by design. An overdraft account would need a
        // profile change — none of the 10 real statements ever went negative.
        return SyntheticStatement(month: 1, year: 2026, opening: d("500.00"), rows: rows)
    }

    /// February — chains from January's closing balance.
    public static func february() -> SyntheticStatement {
        let rows: [SyntheticStatement.Row] = [
            .init(day: 2, merchant: "MERIDIAN COFFEE HOUSE", amount: d("8.95")),
            .init(day: 4, merchant: "HARBOURSIDE GROCERS", amount: d("55.20")),
            .init(day: 6, merchant: "CITY TRANSIT NETWORK", amount: d("2.20")),
            .init(day: 9, merchant: "ATRIUM VENDING CO", amount: d("0.50")),
            .init(day: 11, merchant: "LANTERN NOODLE BAR", amount: d("17.40")),
            .init(day: 13, type: "Advice FAST Payment / Receipt",
                  merchant: "TO: UTILITIES BOARD", amount: d("88.30")),
            .init(day: 15, merchant: "NORTHGATE PHARMACY", amount: d("24.05")),
            .init(day: 19, merchant: "CITY TRANSIT NETWORK", amount: d("4.22")),
            .init(day: 21, merchant: "ORCHID BOOKSHOP", amount: d("12.60")),
            .init(day: 25, merchant: "HARBOURSIDE GROCERS", amount: d("38.15")),
            .init(day: 26, type: "Advice Advice", merchant: "PROMOTIONAL CREDIT",
                  amount: d("18.00"), isCredit: true),
        ]
        return SyntheticStatement(month: 2, year: 2026, opening: january().closing, rows: rows)
    }

    /// June — long, vending-heavy, mirrors the real month's shape.
    public static func june() -> SyntheticStatement {
        var rows: [SyntheticStatement.Row] = []
        for i in 0..<9 { rows.append(.init(day: 2 + i / 3, merchant: "ATRIUM VENDING CO", amount: d("0.50"))) }
        rows += [
            .init(day: 5, merchant: "HARBOURSIDE GROCERS", amount: d("71.05")),
            .init(day: 7, merchant: "CITY TRANSIT NETWORK", amount: d("2.20")),
            .init(day: 8, merchant: "LANTERN NOODLE BAR", amount: d("19.90")),
            .init(day: 10, type: "GIRO Salary", merchant: "NORTHWIND ANALYTICS PTE LTD",
                  amount: d("2,400.00"), isCredit: true),
            .init(day: 12, merchant: "SUMMIT ELECTRONICS", amount: d("129.00")),
            .init(day: 14, type: "Advice Point-Of-Sale Transaction or Proceeds",
                  merchant: "QR PAYMENT TO STALL 7", amount: d("8.50")),
            .init(day: 17, merchant: "MERIDIAN COFFEE HOUSE", amount: d("6.80")),
            .init(day: 20, merchant: "NORTHGATE PHARMACY", amount: d("33.25")),
            .init(day: 23, type: "ATM Transaction", merchant: "CASHPOINT CENTRAL 4", amount: d("300.00")),
            .init(day: 27, merchant: "HARBOURSIDE GROCERS", amount: d("47.60")),
        ]
        for i in 0..<7 { rows.append(.init(day: 28 + i / 4, merchant: "ATRIUM VENDING CO", amount: d("0.50"))) }
        return SyntheticStatement(month: 6, year: 2026, opening: d("1,436.69"), rows: rows)
    }

    /// A USD section — D-018. Proved independently of SGD, never converted.
    public static func octoberUSD() -> SyntheticStatement {
        SyntheticStatement(month: 10, year: 2025, currency: "USD", opening: d("0.00"), rows: [
            .init(day: 15, type: "Advice", merchant: "INBOUND TRANSFER", amount: d("196.20"), isCredit: true)
        ])
    }

    public static func octoberSGD() -> SyntheticStatement {
        SyntheticStatement(month: 10, year: 2025, opening: d("309.98"), rows: [
            .init(day: 3, merchant: "MERIDIAN COFFEE HOUSE", amount: d("7.30")),
            .init(day: 8, merchant: "HARBOURSIDE GROCERS", amount: d("52.40")),
            .init(day: 14, merchant: "CITY TRANSIT NETWORK", amount: d("2.20")),
            .init(day: 19, merchant: "LANTERN NOODLE BAR", amount: d("16.75")),
            .init(day: 25, merchant: "ORCHID BOOKSHOP", amount: d("21.30")),
        ])
    }

    /// October's fixture carries two currency sections in one document.
    public static func octoberCombined() -> String {
        octoberSGD().render() + octoberUSD().render()
    }

    public static let files: [(name: String, text: String)] = [
        ("jan_Statement", january().render()),
        ("feb_Statement", february().render()),
        ("jun_Statement", june().render()),
        ("oct_Statement", octoberCombined()),
    ]
}

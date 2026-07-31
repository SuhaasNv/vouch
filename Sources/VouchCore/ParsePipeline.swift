import Foundation

/// Balance-anchored parser (SPEC 3.3, D-020).
///
/// The grammar, measured against real PDFKit output:
/// ```
/// TRANSACTION := [DATE] DESC_LINE* AMOUNT_LINE
/// AMOUNT_LINE := ^<amount> <balance>$        always exactly 2 numbers
/// ```
/// The amount line is the record separator. That segments variable-height rows
/// for free — a card transaction is 3 lines, a PayNow is 5 — without the parser
/// needing to understand any row's internal structure.
///
/// Direction is **not** recoverable from the text: PDFKit collapses the
/// Withdrawal and Deposit columns, so a deposit and a withdrawal are
/// byte-identical in shape. It comes from the balance delta instead, and the
/// parsed amount cell is kept as an independent cross-check.
public struct ParsePipeline: Sendable {

    private let profile: BankProfile

    public init(profile: BankProfile = .dbsSavings) { self.profile = profile }

    // ── line classifiers ────────────────────────────────────────────────

    /// `2.50 1,434.19` — the record separator.
    static func amountPair(_ text: String) -> (amount: Decimal, balance: Decimal)? {
        let parts = text.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 2,
              let a = Money.parse(parts[0]),
              let b = Money.parse(parts[1]) else { return nil }
        return (a, b)
    }

    /// Strips a leading `dd/MM/yyyy ` and returns it with the remainder.
    static func leadingDate(_ text: String, formatter: DateFormatter) -> (date: Date, rest: String)? {
        guard text.count >= 10 else { return nil }
        let head = String(text.prefix(10))
        guard let d = formatter.date(from: head) else { return nil }
        let rest = String(text.dropFirst(10)).trimmingCharacters(in: .whitespaces)
        return (d, rest)
    }

    /// `Balance Brought Forward SGD 1,436.69` → (`SGD`, amount)
    func balanceLine(_ text: String, label: String) -> (currency: String, amount: Decimal)? {
        guard let r = text.range(of: label) else { return nil }
        let tail = text[r.upperBound...].trimmingCharacters(in: .whitespaces)
        let parts = tail.split(separator: " ")
        guard parts.count >= 2, parts[0].count == 3, parts[0].allSatisfy(\.isUppercase),
              let amt = Money.parse(parts[1]) else { return nil }
        return (String(parts[0]), amt)
    }

    /// `Total Balance Carried Forward in SGD: 1,959.46 1,301.50 778.73`
    func sectionTotals(_ text: String) -> (currency: String, w: Decimal, d: Decimal, closing: Decimal)? {
        guard let r = text.range(of: profile.sectionTotalsLabel) else { return nil }
        let tail = text[r.upperBound...].trimmingCharacters(in: .whitespaces)
        guard let colon = tail.firstIndex(of: ":") else { return nil }
        let ccy = String(tail[tail.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
        let nums = tail[tail.index(after: colon)...].split(separator: " ").compactMap { Money.parse($0) }
        guard ccy.count == 3, nums.count == 3 else { return nil }
        return (ccy, nums[0], nums[1], nums[2])
    }

    // ── main pass ───────────────────────────────────────────────────────

    public func parse(lines: [SourceLine], sourceHash: String, pageCount: Int) throws -> ParsedStatement {
        let fmt = profile.dateFormatter()
        let asAt = Self.asAtDate(in: lines) ?? Date()

        var sections: [StatementSection] = []
        var builder: SectionBuilder?
        var accountLabel = "", accountNumber = ""

        // The most recent posting date seen anywhere, carried across lines.
        //
        // This must live outside the builder. PDFKit merges a transaction's date
        // cell into whichever line shares its y-position, and for the first row
        // of a section that is the `Balance Brought Forward` line — so the row
        // itself arrives with no date at all. Peeling the date off every line
        // before classifying it is what keeps that row from being dropped.
        var lastSeenDate: Date?

        for line in lines {
            var text = line.text

            // Peel a leading date off ANY line, whatever it turns out to be.
            if let (d, rest) = Self.leadingDate(text, formatter: fmt) {
                lastSeenDate = d
                text = rest
                if text.isEmpty { continue }
            }

            // Account header — starts a new account context.
            if text.contains(profile.accountHeaderMarker),
               let parsed = Self.accountHeader(text, marker: profile.accountHeaderMarker) {
                accountLabel = parsed.label
                accountNumber = parsed.number
                continue
            }

            // Section totals close the current (account, currency) section.
            if let t = sectionTotals(text) {
                if var b = builder, b.currency == t.currency {
                    b.statedWithdrawals = t.w; b.statedDeposits = t.d; b.statedClosing = t.closing
                    sections.append(b.build())
                    builder = nil
                }
                continue
            }

            // Balance Brought Forward — first one opens a section; the rest are
            // page repeats (D-015) and are skipped.
            if let bf = balanceLine(text, label: profile.openingBalanceLabel) {
                if builder == nil || builder?.currency != bf.currency {
                    if let b = builder { sections.append(b.build()) }
                    builder = SectionBuilder(
                        accountLabel: accountLabel, accountNumber: accountNumber,
                        currency: bf.currency, opening: bf.amount
                    )
                    // Seed with the date just peeled off the B/F line — it belongs
                    // to the first transaction, not to the balance.
                    builder?.lastDate = lastSeenDate
                }
                continue
            }

            // Page-level Carried Forward — chrome.
            if balanceLine(text, label: profile.pageClosingLabel) != nil { continue }
            if profile.isChrome(text) { continue }
            guard builder != nil else { continue }

            // Amount pair closes a transaction.
            if let pair = Self.amountPair(text) {
                if var b = builder {
                    b.pendingDate = b.pendingDate ?? lastSeenDate
                    b.close(with: pair, at: line, formatter: fmt)
                    builder = b
                }
                continue
            }

            builder?.buffer.append((text, line))
        }

        if let b = builder { sections.append(b.build()) }
        return ParsedStatement(sourceHash: sourceHash, asAtDate: asAt, pageCount: pageCount, sections: sections)
    }

    // ── helpers ─────────────────────────────────────────────────────────

    static func accountHeader(_ text: String, marker: String) -> (label: String, number: String)? {
        guard let r = text.range(of: marker) else { return nil }
        let label = String(text[text.startIndex..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
        let number = String(text[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !number.isEmpty else { return nil }
        return (label, number)
    }

    static func asAtDate(in lines: [SourceLine]) -> Date? {
        // D-017: period comes from the `as at` header, never the filename.
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Singapore")
        for l in lines {
            guard let r = l.text.range(of: "as at ") ?? l.text.range(of: "as of ") else { continue }
            let tail = String(l.text[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            let candidate = tail.split(separator: " ").prefix(3).joined(separator: " ")
            if let d = f.date(from: candidate) { return d }
        }
        return nil
    }
}

/// Accumulates one `(account, currency)` section while walking the lines.
private struct SectionBuilder {
    let accountLabel: String
    let accountNumber: String
    let currency: String
    let opening: Decimal

    var statedWithdrawals: Decimal?
    var statedDeposits: Decimal?
    var statedClosing: Decimal?

    var buffer: [(String, SourceLine)] = []
    var pendingDate: Date?
    var lastDate: Date?
    var running: Decimal
    var transactions: [ParsedTransaction] = []
    var rejected: [RejectedLine] = []

    init(accountLabel: String, accountNumber: String, currency: String, opening: Decimal) {
        self.accountLabel = accountLabel
        self.accountNumber = accountNumber
        self.currency = currency
        self.opening = opening
        self.running = opening
    }

    mutating func close(with pair: (amount: Decimal, balance: Decimal), at line: SourceLine, formatter: DateFormatter) {
        let date = pendingDate ?? lastDate
        guard let date else {                       // an amount pair with no date anywhere
            rejected.append(RejectedLine(page: line.page, lineIndex: line.index,
                                         text: line.text, reason: .noPattern))
            buffer.removeAll(); pendingDate = nil
            return
        }

        // Direction and amount from the balance delta — the only surviving
        // signal once PDFKit collapses the columns (D-020).
        let delta = pair.balance - running
        let direction: Direction = delta < 0 ? .debit : .credit
        let derived = delta < 0 ? -delta : delta

        let typeLabel = buffer.first?.0 ?? ""
        let descLines = buffer.count > 1 ? buffer.dropFirst().map(\.0) : []
        let anchor = buffer.first?.1 ?? line

        transactions.append(ParsedTransaction(
            rowIndex: transactions.count,
            postedDate: date,
            typeLabel: typeLabel,
            descriptionLines: Array(descLines),
            statedAmount: pair.amount,
            balanceAfter: pair.balance,
            derivedAmount: derived,
            direction: direction,
            sourcePage: anchor.page,
            sourceLineIndex: anchor.index
        ))

        running = pair.balance
        lastDate = date
        pendingDate = nil
        buffer.removeAll()
    }

    func build() -> StatementSection {
        StatementSection(
            accountLabel: accountLabel, accountNumber: accountNumber, currency: currency,
            openingBalance: opening,
            statedWithdrawals: statedWithdrawals, statedDeposits: statedDeposits,
            statedClosing: statedClosing,
            transactions: transactions, rejectedLines: rejected
        )
    }
}

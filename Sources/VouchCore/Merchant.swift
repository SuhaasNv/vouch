import Foundation

/// Turns a statement description into a stable merchant key.
///
/// Patterns come from `docs/VOCABULARY.md` §1, observed across 817 real
/// transactions. Everything stripped here is *derived* — `rawDescription` and
/// `sourceLineText` keep the verbatim original (SPEC 1.3).
public enum Merchant {

    /// Payment processors. When you pay a hawker by QR the statement records
    /// the processor, not the shop, so what you bought is simply not in the
    /// document. These route to review with an honest label and the model is
    /// never asked to guess (D-012).
    public static let aggregators = ["FOMO PAY", "LIQUID PAY", "NETS"]

    public static func normalize(_ description: String) -> String {
        var s = description.uppercased()

        // Card number, present on every debit-card row.
        s = s.replacing(#/\b\d{4}-\d{4}-\d{4}-\d{4}\b/#, with: " ")
        // Foreign original appended to the card line: "USD20.00", "AED2.00".
        s = s.replacing(#/\b[A-Z]{3}\d+\.\d{2}\b/#, with: " ")
        // Locale + transaction date: "SI SGP 30MAY", "SH ARE 31DEC", "AN USA 05JAN".
        s = s.replacing(#/\s+[A-Z]{2}\s+[A-Z]{3}\s+\d{2}[A-Z]{3}\b/#, with: " ")
        s = s.replacing(#/\s+[A-Z]{3}\s+\d{2}[A-Z]{3}\b/#, with: " ")
        // Bare trailing transaction date.
        s = s.replacing(#/\s+\d{2}[A-Z]{3}\b/#, with: " ")
        // Long reference numbers.
        s = s.replacing(#/\b\d{7,}\b/#, with: " ")
        // DBS transaction-class prefix on POS rows.
        s = s.replacing(#/^BAT\s+/#, with: "")
        // Payee marker on transfers.
        s = s.replacing(#/^TO:\s*/#, with: "")

        // Collapse whitespace and trailing punctuation.
        s = s.replacing(#/\s+/#, with: " ")
        return s.trimmingCharacters(in: CharacterSet(charactersIn: " .,-*|"))
    }

    /// True when the merchant is a payment processor and the real merchant
    /// cannot be recovered from the document.
    public static func isAggregator(_ normalized: String) -> Bool {
        aggregators.contains { normalized.contains($0) }
    }

    /// The bank-assigned type label is more reliable than merchant matching,
    /// because the bank assigns it rather than the merchant choosing it
    /// (`VOCABULARY.md` §1).
    public static func categoryFromTypeLabel(_ typeLabel: String) -> String? {
        let t = typeLabel.uppercased()
        if t.contains("GIRO SALARY") { return "income" }
        if t.contains("ATM TRANSACTION") { return "transfers" }        // cash out, not spend (Q14)
        if t.contains("CASH ACCEPTING") { return "transfers" }
        if t.contains("FUNDS TRANSFER") { return "transfers" }
        if t.contains("MEPS") { return "transfers" }
        if t.contains("TELEGRAPHIC TRANSFER") { return "transfers" }
        return nil
    }
}

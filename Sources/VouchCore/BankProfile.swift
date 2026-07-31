import Foundation

/// Per-bank parsing rules. Adding a bank = adding one profile + one golden
/// fixture (SPEC Part 4).
///
/// Patterns are plain strings compiled once, not `Regex` literals, so a profile
/// stays data rather than code and could eventually be loaded from JSON.
public struct BankProfile: Sendable {
    public let bankCode: String
    public let displayName: String

    /// Detects which bank a document belongs to.
    public let headerSignatures: [String]

    /// `dd/MM/yyyy` for DBS. Parsed with a fixed locale and Singapore timezone.
    public let dateFormat: String

    public let openingBalanceLabel: String       // "Balance Brought Forward"
    public let pageClosingLabel: String          // "Balance Carried Forward"
    public let sectionTotalsLabel: String        // "Total Balance Carried Forward in"
    public let accountHeaderMarker: String       // "Account No."

    /// Lines matching any of these are chrome and never become transactions.
    /// D-019: the December interest block carries numbers and must be excluded.
    public let ignoreFragments: [String]

    public static let dbsSavings = BankProfile(
        bankCode: "DBS",
        displayName: "DBS/POSB Savings",
        headerSignatures: ["Consolidated Statement", "Transaction Details", "POSB"],
        dateFormat: "dd/MM/yyyy",
        openingBalanceLabel: "Balance Brought Forward",
        pageClosingLabel: "Balance Carried Forward",
        sectionTotalsLabel: "Total Balance Carried Forward in",
        accountHeaderMarker: "Account No.",
        ignoreFragments: [
            "Total Interest",                 // D-019 year-end block, carries numbers
            "Total Credit Interest",
            "Total Debit Interest",
            "Interest Adjustment",
            "Messages For",
            "Transaction Details as of",
            "Account Summary",
            "Page ",
            "PDS_",
            "S/N:",
            "CURRENCY:",
            "Summary of Currency Breakdown",
            "ADDRESS FOR UPDATING",
            "Service Charge for",
            "Cheque Issuance Fee",
            "Clients Residing in",
            "With effect from",
            "As a valued customer",
            "Date Description",               // column header row
        ]
    )

    public static let all: [BankProfile] = [.dbsSavings]

    /// Picks a profile by header signature. Never guesses (SPEC 5.9).
    public static func detect(in text: String) -> BankProfile? {
        all.first { profile in
            profile.headerSignatures.contains { text.contains($0) }
        }
    }

    public func isChrome(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return true }
        return ignoreFragments.contains { t.contains($0) }
    }

    public func dateFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = dateFormat
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Singapore")
        return f
    }
}

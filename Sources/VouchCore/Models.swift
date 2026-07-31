import Foundation

public enum Direction: String, Sendable, Equatable {
    case debit, credit
}

/// A single parsed transaction, before it reaches persistence.
///
/// Carries both derivations of amount/direction so the proof can compare them
/// (SPEC 3.3). `statedAmount` comes from the amount cell; `derivedAmount` comes
/// from the running-balance delta. Agreement is what makes confidence 1.0.
public struct ParsedTransaction: Sendable, Equatable {
    public let rowIndex: Int
    public let postedDate: Date
    public let typeLabel: String
    /// Verbatim description lines, never mutated. Provenance (SPEC 1.3).
    public let descriptionLines: [String]
    public let statedAmount: Decimal
    public let balanceAfter: Decimal
    public let derivedAmount: Decimal
    public let direction: Direction
    public let sourcePage: Int
    public let sourceLineIndex: Int

    /// True when the amount cell and the balance delta agree exactly.
    public var derivationsAgree: Bool { statedAmount == derivedAmount }

    /// The merchant/payee line — first description line that isn't chrome.
    public var merchantLine: String { descriptionLines.first ?? "" }

    public var sourceLineText: String {
        ([typeLabel] + descriptionLines).joined(separator: " | ")
    }
}

/// One `(account, currency)` section of a statement — the proof unit (D-018).
public struct StatementSection: Sendable, Equatable {
    public let accountLabel: String
    public let accountNumber: String
    public let currency: String
    public let openingBalance: Decimal
    /// From `Total Balance Carried Forward in <CCY>: <w> <d> <closing>`.
    public let statedWithdrawals: Decimal?
    public let statedDeposits: Decimal?
    public let statedClosing: Decimal?
    public let transactions: [ParsedTransaction]
    /// Lines that looked transaction-shaped but could not be classified.
    public let rejectedLines: [RejectedLine]

    public var parsedWithdrawals: Decimal {
        transactions.filter { $0.direction == .debit }.reduce(0) { $0 + $1.derivedAmount }
    }
    public var parsedDeposits: Decimal {
        transactions.filter { $0.direction == .credit }.reduce(0) { $0 + $1.derivedAmount }
    }
}

public struct RejectedLine: Sendable, Equatable {
    public enum Reason: String, Sendable { case noPattern, ambiguousDirection, unparsableAmount }
    public let page: Int
    public let lineIndex: Int
    public let text: String
    public let reason: Reason
}

/// A whole statement document — one PDF, N sections.
public struct ParsedStatement: Sendable, Equatable {
    public let sourceHash: String
    public let asAtDate: Date
    public let pageCount: Int
    public let sections: [StatementSection]
}

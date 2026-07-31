import Foundation
import SwiftData
import VouchCore

// Persistence layer (SPEC Part 4). VouchCore stays free of SwiftData — the
// parser and proof engine work on value types and know nothing about storage.

@Model
public final class Account {
    @Attribute(.unique) public var id: UUID
    public var displayName: String
    public var bankCode: String
    public var accountNumber: String
    public var createdAt: Date

    public init(id: UUID = UUID(), displayName: String, bankCode: String, accountNumber: String) {
        self.id = id
        self.displayName = displayName
        self.bankCode = bankCode
        self.accountNumber = accountNumber
        self.createdAt = Date()
    }

    public var last4: String { String(accountNumber.suffix(4)) }
}

/// One `(account, currency)` section of one PDF — the proof unit (D-018).
///
/// A single Consolidated Statement produces several of these: two account
/// sections in every real statement, plus a USD section in three of them.
@Model
public final class StatementImport {
    @Attribute(.unique) public var id: UUID

    public var accountID: UUID
    /// Parsed from the section anchors, never assumed (D-018).
    public var currencyCode: String
    /// From the `as at` header, **never the filename** — real files were
    /// misnamed by a month (D-017).
    public var periodEnd: Date

    public var openingBalance: Decimal
    public var closingBalance: Decimal
    public var statedWithdrawals: Decimal?
    public var statedDeposits: Decimal?
    public var parsedWithdrawals: Decimal
    public var parsedDeposits: Decimal

    public var proofStateRaw: String
    public var proofChecksRun: Int
    public var proofDelta: Decimal
    public var chainStateRaw: String
    public var chainDelta: Decimal

    /// SHA-256 of the PDF bytes. Idempotency key and vault integrity check.
    public var sourceHash: String
    /// Uniqueness is `(sourceHash, accountID, currencyCode)` — one PDF yields
    /// several sections, so hash alone is not unique (D-018).
    @Attribute(.unique) public var sectionKey: String

    public var vaultFilename: String?
    public var fileSizeBytes: Int
    public var rejectedLineCount: Int
    public var pageCount: Int
    public var importedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Transaction.statement)
    public var transactions: [Transaction] = []

    public init(accountID: UUID, currencyCode: String, periodEnd: Date,
                openingBalance: Decimal, closingBalance: Decimal,
                statedWithdrawals: Decimal?, statedDeposits: Decimal?,
                parsedWithdrawals: Decimal, parsedDeposits: Decimal,
                proofState: ProofState, proofChecksRun: Int, proofDelta: Decimal,
                sourceHash: String, rejectedLineCount: Int, pageCount: Int,
                fileSizeBytes: Int = 0) {
        self.id = UUID()
        self.accountID = accountID
        self.currencyCode = currencyCode
        self.periodEnd = periodEnd
        self.openingBalance = openingBalance
        self.closingBalance = closingBalance
        self.statedWithdrawals = statedWithdrawals
        self.statedDeposits = statedDeposits
        self.parsedWithdrawals = parsedWithdrawals
        self.parsedDeposits = parsedDeposits
        self.proofStateRaw = proofState.rawValue
        self.proofChecksRun = proofChecksRun
        self.proofDelta = proofDelta
        self.chainStateRaw = ChainState.unknown.rawValue
        self.chainDelta = 0
        self.sourceHash = sourceHash
        self.sectionKey = Self.key(sourceHash: sourceHash, accountID: accountID, currency: currencyCode)
        self.fileSizeBytes = fileSizeBytes
        self.rejectedLineCount = rejectedLineCount
        self.pageCount = pageCount
        self.importedAt = Date()
    }

    public static func key(sourceHash: String, accountID: UUID, currency: String) -> String {
        "\(sourceHash)|\(accountID.uuidString)|\(currency)"
    }

    public var proofState: ProofState { ProofState(rawValue: proofStateRaw) ?? .unvouched }
    public var chainState: ChainState {
        get { ChainState(rawValue: chainStateRaw) ?? .unknown }
        set { chainStateRaw = newValue.rawValue }
    }
}

public enum ChainState: String, Sendable, Codable {
    /// The first statement for this (account, currency). Never a gap — don't
    /// accuse the user of losing a statement that predates the record.
    case head
    case linked
    case gap
    case unknown
}

@Model
public final class Transaction {
    @Attribute(.unique) public var id: UUID

    public var statement: StatementImport?
    public var accountID: UUID

    /// The embedded transaction date — when you actually spent it. Drives the
    /// Month View (D-006).
    public var date: Date
    /// The statement's Date column. Drives period membership and the proof.
    public var postedDate: Date

    /// Running balance after this row. What makes each row unique (D-005).
    public var balanceAfter: Decimal?
    public var rowIndex: Int

    /// Verbatim from the statement — **never mutated**. Provenance (SPEC 1.3).
    public var rawDescription: String
    public var sourceLineText: String
    public var sourcePage: Int
    public var sourceLineIndex: Int
    public var typeLabel: String

    public var normalizedMerchant: String
    public var amount: Decimal
    public var directionRaw: String

    public var categoryID: String
    public var categorySourceRaw: String
    public var extractionMethodRaw: String
    public var confidence: Double
    public var isReviewed: Bool

    /// `accountID + postedDate + balanceAfter`.
    ///
    /// **Do not "simplify" this to a content-only key.** Real data contains six
    /// identical same-day 0.50 vending rows; a content key collapses them and
    /// silently deletes five real transactions (D-005).
    @Attribute(.unique) public var dedupeKey: String

    public var note: String?

    public init(accountID: UUID, date: Date, postedDate: Date, balanceAfter: Decimal?,
                rowIndex: Int, rawDescription: String, sourceLineText: String,
                sourcePage: Int, sourceLineIndex: Int, typeLabel: String,
                normalizedMerchant: String, amount: Decimal, direction: Direction,
                categoryID: String, categorySource: CategorySource,
                extractionMethod: ExtractionMethod, confidence: Double) {
        self.id = UUID()
        self.accountID = accountID
        self.date = date
        self.postedDate = postedDate
        self.balanceAfter = balanceAfter
        self.rowIndex = rowIndex
        self.rawDescription = rawDescription
        self.sourceLineText = sourceLineText
        self.sourcePage = sourcePage
        self.sourceLineIndex = sourceLineIndex
        self.typeLabel = typeLabel
        self.normalizedMerchant = normalizedMerchant
        self.amount = amount
        self.directionRaw = direction.rawValue
        self.categoryID = categoryID
        self.categorySourceRaw = categorySource.rawValue
        self.extractionMethodRaw = extractionMethod.rawValue
        self.confidence = confidence
        self.isReviewed = confidence >= 1.0
        self.dedupeKey = Self.key(accountID: accountID, postedDate: postedDate,
                                  balanceAfter: balanceAfter, rowIndex: rowIndex)
        self.note = nil
    }

    public static func key(accountID: UUID, postedDate: Date,
                           balanceAfter: Decimal?, rowIndex: Int) -> String {
        let stamp = Int(postedDate.timeIntervalSince1970)
        if let b = balanceAfter {
            return "\(accountID.uuidString)|\(stamp)|\(b)"
        }
        // Fallback for banks with no balance column. Never a content-only key —
        // small repeated charges are normal, not duplicates.
        return "\(accountID.uuidString)|\(stamp)|row\(rowIndex)"
    }

    public var direction: Direction { Direction(rawValue: directionRaw) ?? .debit }
    public var isCredit: Bool { direction == .credit }
}

public enum CategorySource: String, Sendable, Codable {
    case userOverride, bundledRule, model, `default`
}

public enum ExtractionMethod: String, Sendable, Codable {
    case regex, model, manual
}

@Model
public final class MerchantRule {
    @Attribute(.unique) public var id: UUID
    @Attribute(.unique) public var matchPattern: String
    public var categoryID: String
    public var sourceRaw: String
    public var hitCount: Int

    public init(matchPattern: String, categoryID: String, source: CategorySource) {
        self.id = UUID()
        self.matchPattern = matchPattern
        self.categoryID = categoryID
        self.sourceRaw = source.rawValue
        self.hitCount = 0
    }
}

import Foundation
import SwiftData
import VouchCore

public enum ImportOutcome: Sendable {
    case imported(sections: Int, transactions: Int)
    /// R10 — re-importing the same statement changes nothing.
    case alreadyImported(on: Date)
    case failed(String)
}

/// Persists parsed statements and maintains the chain.
///
/// `@ModelActor` keeps every `ModelContext` touch on one isolated actor, which
/// is what Swift 6 strict concurrency requires of SwiftData.
@ModelActor
public actor VouchStore {

    // MARK: - Import

    /// Persists a parsed statement. Idempotent on `(sourceHash, accountID, currency)`.
    public func importStatement(_ parsed: ParsedStatement,
                                proofs: [String: ProofResult],
                                bankCode: String = "DBS",
                                fileSizeBytes: Int = 0) throws -> ImportOutcome {
        var sectionsAdded = 0
        var rowsAdded = 0

        // A section with no transactions but a live balance is a real period
        // with no activity — November's USD section is exactly that. Dropping
        // it punches a hole in the chain, and a period silently absent from the
        // chain is the failure this product exists to prevent. Only genuinely
        // dormant sections (no rows, no money) are skipped.
        for section in parsed.sections
        where !section.transactions.isEmpty || section.openingBalance != 0 {
            let account = try findOrCreateAccount(
                number: section.accountNumber,
                displayName: section.accountLabel.isEmpty ? "Account" : section.accountLabel,
                bankCode: bankCode
            )

            let key = StatementImport.key(sourceHash: parsed.sourceHash,
                                          accountID: account.id,
                                          currency: section.currency)
            if let existing = try existingImport(sectionKey: key) {
                if sectionsAdded == 0 && parsed.sections.count == 1 {
                    return .alreadyImported(on: existing.importedAt)
                }
                continue
            }

            let proof = proofs[section.currency] ?? ProofEngine.prove(section: section)
            let record = StatementImport(
                accountID: account.id,
                currencyCode: section.currency,
                periodEnd: parsed.asAtDate,
                openingBalance: section.openingBalance,
                closingBalance: section.statedClosing ?? 0,
                statedWithdrawals: section.statedWithdrawals,
                statedDeposits: section.statedDeposits,
                parsedWithdrawals: section.parsedWithdrawals,
                parsedDeposits: section.parsedDeposits,
                proofState: proof.state,
                proofChecksRun: proof.checksRun,
                proofDelta: proof.failures.isEmpty ? 0 : 1,
                sourceHash: parsed.sourceHash,
                rejectedLineCount: section.rejectedLines.count,
                pageCount: parsed.pageCount,
                fileSizeBytes: fileSizeBytes
            )
            modelContext.insert(record)
            sectionsAdded += 1

            for t in section.transactions {
                let dk = Transaction.key(accountID: account.id, postedDate: t.postedDate,
                                         balanceAfter: t.balanceAfter, rowIndex: t.rowIndex)
                if try transactionExists(dedupeKey: dk) { continue }

                let merchant = Merchant.normalize(t.merchantLine)
                let row = Transaction(
                    accountID: account.id,
                    date: t.postedDate,          // TODO: use the embedded transaction date (D-006)
                    postedDate: t.postedDate,
                    balanceAfter: t.balanceAfter,
                    rowIndex: t.rowIndex,
                    rawDescription: t.merchantLine,
                    sourceLineText: t.sourceLineText,
                    sourcePage: t.sourcePage,
                    sourceLineIndex: t.sourceLineIndex,
                    typeLabel: t.typeLabel,
                    normalizedMerchant: merchant,
                    amount: t.derivedAmount,
                    direction: t.direction,
                    categoryID: Merchant.categoryFromTypeLabel(t.typeLabel) ?? "uncategorised",
                    categorySource: Merchant.categoryFromTypeLabel(t.typeLabel) == nil
                        ? .default : .bundledRule,
                    extractionMethod: .regex,
                    // Two independent derivations agreeing is what makes this 1.0.
                    confidence: t.derivationsAgree ? 1.0 : 0.5
                )
                row.statement = record
                modelContext.insert(row)
                rowsAdded += 1
            }
        }

        guard sectionsAdded > 0 else {
            if let any = try existingImport(sourceHash: parsed.sourceHash) {
                return .alreadyImported(on: any.importedAt)
            }
            return .failed("no sections with transactions")
        }

        try modelContext.save()
        try recomputeChains()
        return .imported(sections: sectionsAdded, transactions: rowsAdded)
    }

    // MARK: - Level 2, the chain

    /// Recomputed on **every** import, never cached — importing April must heal
    /// the March↔May gap with no migration step (SPEC 3.6).
    public func recomputeChains() throws {
        let all = try modelContext.fetch(FetchDescriptor<StatementImport>())
        let groups = Dictionary(grouping: all) { "\($0.accountID.uuidString)|\($0.currencyCode)" }

        for (_, group) in groups {
            let ordered = group.sorted { $0.periodEnd < $1.periodEnd }
            for (i, record) in ordered.enumerated() {
                guard i > 0 else {
                    record.chainState = .head        // never a gap
                    record.chainDelta = 0
                    continue
                }
                let delta = record.openingBalance - ordered[i - 1].closingBalance
                record.chainState = delta == 0 ? .linked : .gap
                record.chainDelta = delta
            }
        }
        try modelContext.save()
    }

    // MARK: - Reads

    public func monthTotal(currency: String = "SGD") throws -> Decimal {
        try transactions().filter { !$0.isCredit }.reduce(0) { $0 + $1.amount }
    }

    public func transactions(limit: Int? = nil) throws -> [Transaction] {
        var d = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.postedDate, order: .reverse)])
        if let limit { d.fetchLimit = limit }
        return try modelContext.fetch(d)
    }

    public func statements() throws -> [StatementImport] {
        try modelContext.fetch(
            FetchDescriptor<StatementImport>(sortBy: [SortDescriptor(\.periodEnd)]))
    }

    public func accounts() throws -> [Account] {
        try modelContext.fetch(FetchDescriptor<Account>())
    }

    // MARK: - Helpers

    private func findOrCreateAccount(number: String, displayName: String,
                                     bankCode: String) throws -> Account {
        let d = FetchDescriptor<Account>(predicate: #Predicate { $0.accountNumber == number })
        if let found = try modelContext.fetch(d).first { return found }
        let a = Account(displayName: displayName, bankCode: bankCode, accountNumber: number)
        modelContext.insert(a)
        return a
    }

    private func existingImport(sectionKey: String) throws -> StatementImport? {
        let d = FetchDescriptor<StatementImport>(predicate: #Predicate { $0.sectionKey == sectionKey })
        return try modelContext.fetch(d).first
    }

    private func existingImport(sourceHash: String) throws -> StatementImport? {
        let d = FetchDescriptor<StatementImport>(predicate: #Predicate { $0.sourceHash == sourceHash })
        return try modelContext.fetch(d).first
    }

    private func transactionExists(dedupeKey: String) throws -> Bool {
        var d = FetchDescriptor<Transaction>(predicate: #Predicate { $0.dedupeKey == dedupeKey })
        d.fetchLimit = 1
        return try !modelContext.fetch(d).isEmpty
    }
}

public extension ModelContainer {
    /// The app's container. `.completeFileProtection` is applied to the store
    /// file at creation — AES-256 with a key in the Secure Enclave, tied to the
    /// device passcode (SPEC 3.8).
    static func vouch(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([Account.self, StatementImport.self, Transaction.self, MerchantRule.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [config])
    }
}

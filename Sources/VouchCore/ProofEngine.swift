import Foundation

/// The Proof (SPEC 1.2, 3.6). This is the product; everything else is a list view.
///
/// **Tolerance is zero.** Not one cent. If the parser is off by rounding, the
/// parser is wrong — never widen the goalposts to turn the light green.
/// `Decimal` compares exactly, which is why `Double` is banned everywhere.
public enum ProofFailure: Sendable, Equatable {
    case rowBalance(rowIndex: Int, expected: Decimal, stated: Decimal)
    case rowDerivationConflict(rowIndex: Int, fromCell: Decimal, fromBalance: Decimal)
    case balanceEquation(delta: Decimal)
    case withdrawalTotal(delta: Decimal)
    case depositTotal(delta: Decimal)
    case chainBreak(delta: Decimal)
}

public enum ProofState: String, Sendable {
    case vouched, unvouched, gap
}

public struct ProofResult: Sendable {
    public let state: ProofState
    public let checksRun: Int
    public let checksAvailable: Int
    public let failures: [ProofFailure]
    public var passed: Bool { failures.isEmpty }
}

public enum ProofEngine {

    /// Levels 0 and 1 for one `(account, currency)` section.
    ///
    /// Level 0 runs first. If every row reconciles against its neighbour and the
    /// last equals the stated closing, Level 1 is arithmetically redundant — so
    /// it serves as an independent cross-check rather than the primary
    /// mechanism, which is a much stronger position.
    public static func prove(section: StatementSection) -> ProofResult {
        var failures: [ProofFailure] = []
        var checksRun = 0
        let available = 4

        // ── Level 0: per row ────────────────────────────────────────────
        var running = section.openingBalance
        for t in section.transactions {
            let expected = t.direction == .debit ? running - t.derivedAmount : running + t.derivedAmount
            if expected != t.balanceAfter {
                failures.append(.rowBalance(rowIndex: t.rowIndex, expected: expected, stated: t.balanceAfter))
            }
            // The two independent derivations must agree (SPEC 3.3).
            if t.statedAmount != t.derivedAmount {
                failures.append(.rowDerivationConflict(rowIndex: t.rowIndex,
                                                       fromCell: t.statedAmount,
                                                       fromBalance: t.derivedAmount))
            }
            running = t.balanceAfter
        }
        checksRun += 1

        // ── Level 1: the section's own stated figures ───────────────────
        if let closing = section.statedClosing {
            let computed = section.openingBalance - section.parsedWithdrawals + section.parsedDeposits
            if computed != closing { failures.append(.balanceEquation(delta: computed - closing)) }
            checksRun += 1

            if running != closing {
                failures.append(.balanceEquation(delta: running - closing))
            }
        }
        if let w = section.statedWithdrawals {
            if section.parsedWithdrawals != w {
                failures.append(.withdrawalTotal(delta: section.parsedWithdrawals - w))
            }
            checksRun += 1
        }
        if let d = section.statedDeposits {
            if section.parsedDeposits != d {
                failures.append(.depositTotal(delta: section.parsedDeposits - d))
            }
            checksRun += 1
        }

        return ProofResult(state: failures.isEmpty ? .vouched : .unvouched,
                           checksRun: checksRun, checksAvailable: available, failures: failures)
    }

    /// Level 2 — the chain. Sections must be for the same account *and* the same
    /// currency (D-018), ordered by period.
    ///
    /// The first section in a series is `.head`, not a gap: never accuse the user
    /// of losing a statement that predates the record.
    public static func chain(_ ordered: [(label: String, section: StatementSection)]) -> [(String, ProofState, Decimal)] {
        var out: [(String, ProofState, Decimal)] = []
        guard let first = ordered.first else { return out }
        out.append((first.label, .vouched, 0))       // head

        for (prev, next) in zip(ordered, ordered.dropFirst()) {
            guard let prevClosing = prev.section.statedClosing else {
                out.append((next.label, .gap, 0)); continue
            }
            let delta = next.section.openingBalance - prevClosing
            out.append((next.label, delta == 0 ? .vouched : .gap, delta))
        }
        return out
    }
}

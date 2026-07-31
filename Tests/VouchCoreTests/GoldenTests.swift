import XCTest
@testable import VouchCore

/// Golden-file tests over redacted real statements (SPEC 3.9).
///
/// These are the safety net for the entire product thesis. A change that makes
/// any of them fail does not ship, regardless of what else it fixes.
final class GoldenTests: XCTestCase {

    static let fixtureNames = ["jan_Statement", "feb_Statement", "jun_Statement", "oct_Statement"]

    func fixture(_ name: String) throws -> [SourceLine] {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "txt"),
            "missing fixture \(name).txt — regenerate with: vouch fixtures"
        )
        return TextLayer.lines(fromFixture: try String(contentsOf: url, encoding: .utf8))
    }

    func parse(_ name: String) throws -> ParsedStatement {
        try ParsePipeline().parse(lines: try fixture(name), sourceHash: name, pageCount: 1)
    }

    // ── the core guarantee ──────────────────────────────────────────────

    func testGolden_everySectionProves() throws {
        for name in Self.fixtureNames {
            let statement = try parse(name)
            XCTAssertFalse(statement.sections.isEmpty, "\(name): no sections parsed")
            for section in statement.sections {
                let result = ProofEngine.prove(section: section)
                XCTAssertTrue(result.passed,
                              "\(name) [\(section.currency)] failed: \(result.failures)")
            }
        }
    }

    func testGolden_fourOfFourChecksAvailable() throws {
        // D-015: the statement prints its own totals, so all four Level-1 checks run.
        let statement = try parse("jun_Statement")
        let active = try XCTUnwrap(statement.sections.first { !$0.transactions.isEmpty })
        XCTAssertEqual(ProofEngine.prove(section: active).checksRun, 4)
    }

    func testDualDerivation_agreesOnEveryRow() throws {
        // SPEC 3.3: the amount cell and the balance delta are independent.
        for name in Self.fixtureNames {
            for section in try parse(name).sections {
                for t in section.transactions {
                    XCTAssertTrue(t.derivationsAgree,
                                  "\(name) row \(t.rowIndex): cell \(t.statedAmount) vs balance \(t.derivedAmount)")
                }
            }
        }
    }

    // ── the regressions that cost real money ────────────────────────────

    func testDedupe_sixIdenticalRowsSurvive() throws {
        // D-005: the real statements contained 118 consecutive identical
        // vending rows at 0.50 in a single month. A content-only dedupe key
        // collapses them and silently deletes real transactions — the exact
        // failure this product exists to prevent. The fixture reproduces the
        // shape with a synthetic merchant.
        let statement = try parse("jan_Statement")
        let section = try XCTUnwrap(statement.sections.first { !$0.transactions.isEmpty })
        let vending = section.transactions.filter { $0.merchantLine.contains("ATRIUM VENDING") }
        XCTAssertGreaterThan(vending.count, 5, "expected 6 identical vending rows in the fixture")

        // The naive key would collapse these...
        let naive = Set(vending.map { "\($0.postedDate)|\($0.derivedAmount)|\($0.merchantLine.prefix(20))" })
        XCTAssertLessThan(naive.count, vending.count, "fixture must contain genuine same-day duplicates")

        // ...the real key, which includes balanceAfter, must not.
        let real = Set(vending.map { "\($0.postedDate)|\($0.balanceAfter)" })
        XCTAssertEqual(real.count, vending.count, "balanceAfter must make every row unique")
    }

    func testProof_detectsInjectedDrop() throws {
        // Removing one row must break the arithmetic. Loudly.
        let statement = try parse("feb_Statement")
        let original = try XCTUnwrap(statement.sections.first { $0.transactions.count > 3 })
        var kept = original.transactions
        kept.remove(at: kept.count / 2)

        let damaged = StatementSection(
            accountLabel: original.accountLabel, accountNumber: original.accountNumber,
            currency: original.currency, openingBalance: original.openingBalance,
            statedWithdrawals: original.statedWithdrawals, statedDeposits: original.statedDeposits,
            statedClosing: original.statedClosing, transactions: kept, rejectedLines: []
        )
        XCTAssertFalse(ProofEngine.prove(section: damaged).passed,
                       "dropping a row must fail the proof")
    }

    func testProof_localisesInjectedError() throws {
        // Level 0's whole point: name the row, not just the statement.
        let statement = try parse("feb_Statement")
        let original = try XCTUnwrap(statement.sections.first { $0.transactions.count > 3 })
        var rows = original.transactions
        let target = 2
        let t = rows[target]
        rows[target] = ParsedTransaction(
            rowIndex: t.rowIndex, postedDate: t.postedDate, typeLabel: t.typeLabel,
            descriptionLines: t.descriptionLines,
            statedAmount: t.statedAmount + 10,        // corrupt the cell only
            balanceAfter: t.balanceAfter, derivedAmount: t.derivedAmount,
            direction: t.direction, sourcePage: t.sourcePage, sourceLineIndex: t.sourceLineIndex
        )
        let damaged = StatementSection(
            accountLabel: original.accountLabel, accountNumber: original.accountNumber,
            currency: original.currency, openingBalance: original.openingBalance,
            statedWithdrawals: original.statedWithdrawals, statedDeposits: original.statedDeposits,
            statedClosing: original.statedClosing, transactions: rows, rejectedLines: []
        )
        let failures = ProofEngine.prove(section: damaged).failures
        guard case .rowDerivationConflict(let idx, _, _)? = failures.first else {
            return XCTFail("expected a localised row conflict, got \(failures)")
        }
        XCTAssertEqual(idx, rows[target].rowIndex)
    }

    func testProof_zeroTolerance() throws {
        // One cent must fail. Never round it away (SPEC 3.6).
        let statement = try parse("feb_Statement")
        let original = try XCTUnwrap(statement.sections.first { $0.transactions.count > 3 })
        let damaged = StatementSection(
            accountLabel: original.accountLabel, accountNumber: original.accountNumber,
            currency: original.currency, openingBalance: original.openingBalance,
            statedWithdrawals: (original.statedWithdrawals ?? 0) + Decimal(string: "0.01")!,
            statedDeposits: original.statedDeposits, statedClosing: original.statedClosing,
            transactions: original.transactions, rejectedLines: []
        )
        XCTAssertFalse(ProofEngine.prove(section: damaged).passed, "one cent must fail")
    }

    // ── structure ───────────────────────────────────────────────────────

    func testMultiCurrency_sectionsAreSeparate() throws {
        // D-018: October carries a USD section alongside SGD.
        let statement = try parse("oct_Statement")
        let currencies = Set(statement.sections.map(\.currency))
        XCTAssertTrue(currencies.contains("SGD"))
        XCTAssertTrue(currencies.contains("USD"), "USD section must not be silently skipped")
        for section in statement.sections {
            XCTAssertTrue(ProofEngine.prove(section: section).passed)
        }
    }

    func testChain_linksAcrossMonths() throws {
        // Level 2, on the SGD account: Jan closing must equal Feb opening.
        func sgd(_ name: String) throws -> StatementSection {
            try XCTUnwrap(parse(name).sections.first { $0.currency == "SGD" && !$0.transactions.isEmpty })
        }
        let states = ProofEngine.chain([("Jan", try sgd("jan_Statement")),
                                        ("Feb", try sgd("feb_Statement"))])
        XCTAssertEqual(states.count, 2)
        XCTAssertEqual(states[0].1, .vouched, "first statement is head, never a gap")
        XCTAssertEqual(states[1].1, .vouched, "Jan C/F must equal Feb B/F")
        XCTAssertEqual(states[1].2, 0)
    }

    func testProvenance_everyRowKeepsItsSource() throws {
        for section in try parse("jun_Statement").sections {
            for t in section.transactions {
                XCTAssertFalse(t.typeLabel.isEmpty, "row \(t.rowIndex) lost its type label")
                XCTAssertGreaterThan(t.sourcePage, 0)
            }
        }
    }

    // ── the leak guard ──────────────────────────────────────────────────

    func testFixturesContainNoPAN() throws {
        // D-007. This is what stops a 2am commit putting a card number in git
        // history permanently.
        for name in Self.fixtureNames {
            let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "txt"))
            let text = try String(contentsOf: url, encoding: .utf8)
            XCTAssertFalse(Redactor.containsLikelyPII(text), "\(name) contains unredacted PII")
        }
    }

    func testRedactor_preservesLengthAndAmounts() {
        let r = Redactor(names: ["JANE MARY DOE"])
        let line = "03/06/2026 Debit Card Transaction 1234-5678-9012-3456 JANE MARY DOE 7.30 1,105.09"
        let out = r.redactLine(line)
        XCTAssertEqual(out.count, line.count, "redaction must preserve column positions")
        XCTAssertTrue(out.contains("7.30"), "amounts must survive")
        XCTAssertTrue(out.contains("1,105.09"), "balances must survive")
        XCTAssertTrue(out.contains("03/06/2026"), "dates must survive")
        XCTAssertFalse(out.contains("JANE"))
        XCTAssertFalse(out.contains("1234-5678"))
    }
}

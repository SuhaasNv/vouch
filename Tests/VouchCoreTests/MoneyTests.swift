import XCTest
@testable import VouchCore

final class MoneyTests: XCTestCase {

    func testParsesGroupedDecimal() {
        XCTAssertEqual(Money.parse("1,436.69"), Decimal(string: "1436.69"))
        XCTAssertEqual(Money.parse("0.50"), Decimal(string: "0.50"))
        XCTAssertEqual(Money.parse("2,699.40"), Decimal(string: "2699.40"))
    }

    func testRejectsAnythingElse() {
        // A lenient money parser is how wrong numbers enter a ledger.
        for bad in ["", "abc", "1436", "1,436.6", "1.436,69", "SGD 1.00", "1..00", "-1.00", "1,436.690"] {
            XCTAssertNil(Money.parse(bad), "should reject \(bad)")
        }
    }

    func testExactArithmetic() {
        // The reason Double is banned: this must be exact.
        var b = Money.parse("1,112.39")!
        for amt in ["7.30","5.00","7.60","155.20","6.62","8.57","2.90","0.80",
                    "4.50","6.50","4.00","15.00","0.50","19.90","4.30"] {
            b -= Money.parse(amt)!
        }
        XCTAssertEqual(b, Money.parse("863.70"), "real June statement page must reconcile exactly")
    }
}

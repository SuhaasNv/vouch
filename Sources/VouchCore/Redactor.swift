import Foundation

/// Strips PII from extracted statement text so golden fixtures can be committed.
///
/// D-007: replacements are **identical in length and character class** to the
/// originals, so column positions and regex behaviour are unchanged. Amounts,
/// dates and balances are never touched — the fixtures must stay arithmetically
/// real or they prove nothing.
///
/// Names are supplied at call time and never stored in the repo.
public struct Redactor: Sendable {

    /// The canonical dummy card number. `testFixturesContainNoPAN` permits this
    /// exact value and fails on anything else card-shaped.
    public static let dummyPAN = "0000-0000-0000-0000"
    public static let dummyAccount = "000-000000-0"

    private let names: [String]

    public init(names: [String] = []) {
        // Longest first, so "VIJAYA SUHAAS" is replaced before "SUHAAS".
        self.names = names
            .flatMap { [$0] + $0.components(separatedBy: " ") }
            .filter { $0.count >= 3 }
            .sorted { $0.count > $1.count }
    }

    public func redact(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map(redactLine)
            .joined(separator: "\n")
    }

    public func redactLine(_ line: String) -> String {
        var s = line

        // Card numbers: 4-4-4-4 digits.
        s = s.replacing(#/\b\d{4}-\d{4}-\d{4}-\d{4}\b/#, with: Self.dummyPAN)

        // DBS account numbers: 3-6-1 digits.
        s = s.replacing(#/\b\d{3}-\d{6}-\d\b/#, with: Self.dummyAccount)

        // Long bare reference numbers (>= 12 digits) — same length, zeroed.
        s = s.replacing(#/\b\d{12,}\b/#) { m in String(repeating: "0", count: m.output.count) }

        // Statement serial numbers.
        s = s.replacing(#/\bEN\d{10,}\b/#) { m in "EN" + String(repeating: "0", count: m.output.count - 2) }

        // Supplied names, case-insensitive, same length.
        for name in names {
            guard !name.isEmpty else { continue }
            var searchRange = s.startIndex..<s.endIndex
            while let r = s.range(of: name, options: .caseInsensitive, range: searchRange) {
                let replacement = String(repeating: "X", count: s.distance(from: r.lowerBound, to: r.upperBound))
                s.replaceSubrange(r, with: replacement)
                let next = s.index(r.lowerBound, offsetBy: replacement.count)
                guard next < s.endIndex else { break }
                searchRange = next..<s.endIndex
            }
        }
        return s
    }

    /// Serialises lines to the fixture format, preserving page boundaries.
    public func fixture(from lines: [SourceLine]) -> String {
        var out: [String] = []
        var currentPage = 0
        for l in lines {
            if l.page != currentPage {
                currentPage = l.page
                out.append("### PAGE \(currentPage)")
            }
            out.append(redactLine(l.text))
        }
        return out.joined(separator: "\n") + "\n"
    }

    /// True if the text still contains anything card- or NRIC-shaped that isn't
    /// the known dummy. Backs `testFixturesContainNoPAN`.
    public static func containsLikelyPII(_ text: String) -> Bool {
        for m in text.matches(of: #/\b\d{4}-\d{4}-\d{4}-\d{4}\b/#) where String(m.output) != dummyPAN {
            return true
        }
        for m in text.matches(of: #/\b\d{3}-\d{6}-\d\b/#) where String(m.output) != dummyAccount {
            return true
        }
        // Singapore NRIC/FIN shape.
        if text.firstMatch(of: #/\b[STFGM]\d{7}[A-Z]\b/#) != nil { return true }
        return false
    }
}

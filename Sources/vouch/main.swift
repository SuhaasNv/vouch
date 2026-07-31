import Foundation
import VouchCore
#if canImport(CryptoKit)
import CryptoKit
#endif

// vouch — weekend 1 CLI. Real PDF in, proved ledger out. No UI (SPEC Part 7).

func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func usage() -> Never {
    print("""
    usage:
      vouch prove <statement.pdf> [more.pdf ...]     parse + prove, chain across files
      vouch fixtures <out-dir> <name,...> <pdf ...>  redacted golden fixtures (D-007)
      vouch synth <out-dir>                          synthetic committable fixtures
    """)
    exit(2)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { usage() }

switch command {

case "prove":
    let paths = Array(args.dropFirst())
    guard !paths.isEmpty else { usage() }

    struct Row {
        let label: String, asAt: Date, section: StatementSection, result: ProofResult
        /// The proof unit: one account, one currency (D-018).
        var key: String { "\(section.accountNumber)|\(section.currency)" }
    }
    func pad(_ s: String, _ n: Int, right: Bool = false) -> String {
        s.count >= n ? String(s.prefix(n))
                     : (right ? String(repeating: " ", count: n - s.count) + s
                              : s + String(repeating: " ", count: n - s.count))
    }

    var seenHashes: [String: String] = [:]
    var proved: [Row] = []

    for path in paths {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        let data: Data
        do { data = try Data(contentsOf: url) } catch { print("  \(name): cannot read"); continue }
        let hash = sha256(data)

        // R10 idempotency — real data contained two duplicate pairs (D-017).
        if let original = seenHashes[hash] {
            print("DUPLICATE  \(name)  is byte-identical to \(original) — skipped")
            continue
        }
        seenHashes[hash] = name

        do {
            let (lines, pages) = try TextLayer.extract(url: url)
            let statement = try ParsePipeline().parse(lines: lines, sourceHash: hash, pageCount: pages)
            let stamp = DateFormatter()
            stamp.dateFormat = "MMM yyyy"
            stamp.locale = Locale(identifier: "en_US_POSIX")

            for section in statement.sections {
                let result = ProofEngine.prove(section: section)
                proved.append(Row(label: stamp.string(from: statement.asAtDate),
                                  asAt: statement.asAtDate, section: section, result: result))
            }
        } catch {
            print("  \(name): \(error)")
        }
    }

    // Sections with no transactions and a zero balance are dormant accounts —
    // real, provable, and pure noise in a report. Fold them into a count.
    let dormant = proved.filter { $0.section.transactions.isEmpty && $0.section.openingBalance == 0 }
    let active = proved.filter { !($0.section.transactions.isEmpty && $0.section.openingBalance == 0) }

    print("")
    print(pad("period", 10) + pad("acct", 9) + pad("ccy", 5)
          + pad("opening", 12, right: true) + pad("withdrawn", 13, right: true)
          + pad("deposited", 13, right: true) + pad("closing", 12, right: true)
          + pad("rows", 7, right: true) + "  proof")
    print(String(repeating: "-", count: 95))

    for p in active.sorted(by: { ($0.key, $0.asAt) < ($1.key, $1.asAt) }) {
        let s = p.section
        let verdict = p.result.passed
            ? "VOUCHED \(p.result.checksRun)/\(p.result.checksAvailable)"
            : "UNVOUCHED — \(p.result.failures.count) failure(s)"
        print(pad(p.label, 10)
              + pad(s.accountNumber.isEmpty ? "-" : String(s.accountNumber.suffix(7)), 9)
              + pad(s.currency, 5)
              + pad(Money.string(s.openingBalance), 12, right: true)
              + pad(Money.string(s.parsedWithdrawals), 13, right: true)
              + pad(Money.string(s.parsedDeposits), 13, right: true)
              + pad(Money.string(s.statedClosing ?? 0), 12, right: true)
              + pad("\(s.transactions.count)", 7, right: true)
              + "  " + verdict)
        for f in p.result.failures.prefix(3) { print("          ↳ \(f)") }
    }
    if !dormant.isEmpty { print("\n(\(dormant.count) dormant account-sections with no activity, all proved)") }

    // Level 2 — chain per (account, currency), ordered by period.
    for key in Set(active.map(\.key)).sorted() {
        let series = active.filter { $0.key == key }.sorted { $0.asAt < $1.asAt }
        guard series.count > 1 else { continue }
        let head = series[0].section
        print("\nCHAIN — account …\(head.accountNumber.suffix(7)) \(head.currency)")
        for (i, (label, state, delta)) in ProofEngine.chain(series.map { ($0.label, $0.section) }).enumerated() {
            let mark = i == 0 ? "HEAD (opens at \(Money.string(series[0].section.openingBalance)))"
                              : (state == .vouched ? "LINKED" : "GAP \(Money.string(delta))")
            print("  " + pad(label, 10) + mark)
        }
    }

    let allPassed = proved.allSatisfy(\.result.passed)
    print("\nsections: \(proved.count)   all proved: \(allPassed)")
    exit(allPassed ? 0 : 1)

case "fixtures":
    guard args.count >= 4 else { usage() }
    let outDir = URL(fileURLWithPath: args[1])
    let names = args[2].components(separatedBy: ",").filter { !$0.isEmpty }
    let redactor = Redactor(names: names)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    for path in args.dropFirst(3) {
        let url = URL(fileURLWithPath: path)
        do {
            let (lines, _) = try TextLayer.extract(url: url)
            let text = redactor.fixture(from: lines)
            guard !Redactor.containsLikelyPII(text) else {
                print("REFUSED  \(url.lastPathComponent) — PII survived redaction")
                continue
            }
            let out = outDir.appendingPathComponent(
                url.deletingPathExtension().lastPathComponent
                    .replacingOccurrences(of: " ", with: "") + ".txt")
            try text.write(to: out, atomically: true, encoding: .utf8)
            print("wrote \(out.lastPathComponent)  (\(lines.count) lines)")
        } catch {
            print("  \(url.lastPathComponent): \(error)")
        }
    }

case "synth":
    guard args.count >= 2 else { usage() }
    let outDir = URL(fileURLWithPath: args[1])
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    for file in SyntheticFixtures.files {
        // A fixture that doesn't reconcile proves nothing — verify before writing.
        let lines = TextLayer.lines(fromFixture: file.text)
        let parsed = try ParsePipeline().parse(lines: lines, sourceHash: file.name, pageCount: 1)
        var ok = true
        for section in parsed.sections where !ProofEngine.prove(section: section).passed {
            print("REFUSED  \(file.name) [\(section.currency)] does not reconcile")
            ok = false
        }
        guard ok, !Redactor.containsLikelyPII(file.text) else { continue }

        let out = outDir.appendingPathComponent(file.name + ".txt")
        try file.text.write(to: out, atomically: true, encoding: .utf8)
        let rows = parsed.sections.reduce(0) { $0 + $1.transactions.count }
        print("wrote \(out.lastPathComponent)  \(parsed.sections.count) section(s), \(rows) rows, all proved")
    }

default:
    usage()
}

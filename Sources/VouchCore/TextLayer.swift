import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

/// One extracted line, keeping its page and index for provenance (SPEC 1.3).
public struct SourceLine: Sendable, Equatable {
    public let page: Int          // 1-indexed
    public let index: Int         // 0-indexed within the page
    public let text: String

    public init(page: Int, index: Int, text: String) {
        self.page = page; self.index = index; self.text = text
    }
}

public enum TextLayerError: Error, Sendable {
    case cannotOpen(String)
    case locked
    case emptyTextLayer
}

/// PDF → lines.
///
/// D-020: build against PDFKit's layout, not any other extractor's. PDFKit puts
/// the amount pair on its own line *after* the description block.
public enum TextLayer {

    #if canImport(PDFKit)
    /// Opens a statement, trying an empty password first.
    ///
    /// D-015: real DBS eStatements are owner-locked only — they open with `""`,
    /// so the common case needs no password prompt.
    public static func extract(url: URL, password: String? = nil) throws -> (lines: [SourceLine], pageCount: Int) {
        guard let doc = PDFDocument(url: url) else { throw TextLayerError.cannotOpen(url.lastPathComponent) }

        if doc.isLocked {
            let attempts = [password, ""].compactMap { $0 }
            var unlocked = false
            for candidate in attempts where doc.unlock(withPassword: candidate) { unlocked = true; break }
            guard unlocked else { throw TextLayerError.locked }
        }

        var out: [SourceLine] = []
        for p in 0..<doc.pageCount {
            let raw = doc.page(at: p)?.string ?? ""
            for (i, line) in raw.components(separatedBy: .newlines).enumerated() {
                let t = line.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { out.append(SourceLine(page: p + 1, index: i, text: t)) }
            }
        }
        guard !out.isEmpty else { throw TextLayerError.emptyTextLayer }
        return (out, doc.pageCount)
    }
    #endif

    /// Builds lines from already-extracted text — used by golden-file tests so
    /// the suite never needs a real PDF (D-007).
    public static func lines(fromFixture text: String) -> [SourceLine] {
        var out: [SourceLine] = []
        var page = 1, idx = 0
        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("### PAGE ") {
                page = Int(line.dropFirst(9).trimmingCharacters(in: .whitespaces)) ?? page
                idx = 0
                continue
            }
            let t = line.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { out.append(SourceLine(page: page, index: idx, text: t)) }
            idx += 1
        }
        return out
    }
}

import SwiftUI

/// Provenance — the second half of trust (SPEC 1.3).
///
/// The Proof says the month is complete. This says *this row is real*: the
/// verbatim line the parser read, where on the page it was, which pass produced
/// it, and how confident that pass was. Three extra fields, and it is the
/// difference between an app that asserts and an app that shows its work.
///
/// **The source line is never wrapped and never touched.** `rawDescription` and
/// `sourceLineText` are never mutated (CLAUDE.md rule 4) — normalisation and
/// categorisation are derived fields sitting *next to* the original, never on
/// top of it. Wrapping it would be a second, quieter form of editing it, so it
/// scrolls horizontally instead.
///
/// **This is the one correct use of a monospaced face** (`VouchType.source`,
/// SPEC 6.2). Everywhere else a mono font makes a ledger read as terminal
/// output; here the content *is* machine output, and the texture is honest.
public struct ProvenanceView: View {

    /// Which pass produced the row. Mirrors `Transaction.extractionMethod`
    /// (SPEC Part 4) without VouchUI importing the persistence layer.
    public enum Method: String, Sendable, Equatable, CaseIterable {
        case regex
        case model
        case manual
    }

    public struct Model: Sendable, Equatable {
        /// Verbatim, exactly as the parser read it. Empty for a manual entry.
        public let sourceLine: String
        /// 1-indexed, as printed.
        public let page: Int
        /// 0-indexed within the page.
        public let lineIndex: Int
        public let method: Method
        /// 1.00 when the amount cell and the balance delta agreed exactly
        /// (D-004). `Decimal`, so `1.00` is `1.00` and not `0.99999…`.
        public let confidence: Decimal

        public init(sourceLine: String, page: Int, lineIndex: Int,
                    method: Method, confidence: Decimal) {
            self.sourceLine = sourceLine
            self.page = page
            self.lineIndex = lineIndex
            self.method = method
            self.confidence = confidence
        }
    }

    private let model: Model

    @Environment(\.vouch) private var theme

    public init(_ model: Model) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(isManual ? "Manual" : "Raw")
                .vouchEyebrow().foregroundStyle(theme.inkDim)

            if isManual {
                // A genuinely confusing edge, and SPEC Part 4 asks for it in
                // one line of copy: cash you typed in is not something the bank
                // knows about, so it is excluded from the statement's proof.
                Text("Manual entry. No source line — you typed this one in, "
                     + "so it sits outside the statement's proof.")
                    .font(VouchType.body)
                    .foregroundStyle(theme.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                sourceLine
                Text("The bank's own words, unmodified.")
                    .font(VouchType.body)
                    .foregroundStyle(theme.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            meta
        }
    }

    // MARK: - The line itself

    private var sourceLine: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(model.sourceLine)
                // SPEC 6.2 lists `rule` for this line. `rule` is the hairline
                // token — roughly 1.3:1 on `surface`, which fails the 4.5:1
                // floor in 6.7, and 6.7 outranks it. The verbatim line is the
                // evidence; it gets `ink` on a sunken well.
                .font(VouchType.source)
                .foregroundStyle(theme.ink)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, Space.s)
                .padding(.vertical, 10)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(theme.surfaceSunken)
        .accessibilityElement()
        .accessibilityLabel("Source line, verbatim: \(model.sourceLine)")
    }

    // MARK: - Page, line, method, confidence

    private var meta: some View {
        HStack(spacing: 0) {
            Text(metaText)
                .font(VouchType.eyebrow)
                .monospacedDigit()
                .foregroundStyle(theme.inkDim)
            Text(" · confidence \(confidenceText)")
                .font(VouchType.eyebrow)
                .monospacedDigit()
                // 1.00 means two independent derivations agreed exactly
                // (D-004) — an agreeing figure, which is what `accent` is for
                // (CLAUDE.md rule 6). Anything less is `pending`.
                .foregroundStyle(isCertain ? theme.accent : theme.pending)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metaVoiceOver)
    }

    private var metaText: String {
        isManual
            ? "entered by you"
            : "page \(model.page) · line \(model.lineIndex) · \(methodWord)"
    }

    private var metaVoiceOver: String {
        let confidence = "Confidence \(confidenceText)."
            + (isCertain
               ? " The amount cell and the balance delta agree exactly."
               : " Below one — this row was flagged for review.")
        if isManual { return "Entered by you. \(confidence)" }
        return "Page \(model.page), line \(model.lineIndex). "
            + "Extracted by \(methodSpoken). \(confidence)"
    }

    /// The Proof sheet's own footer reads `82 regex · 4 model · 1 you`
    /// (SPEC 6.3). One word per thing, everywhere.
    private var methodWord: String {
        switch model.method {
        case .regex:  "regex"
        case .model:  "model"
        case .manual: "you"
        }
    }

    private var methodSpoken: String {
        switch model.method {
        case .regex:  "a regular expression"
        case .model:  "the on-device model"
        case .manual: "you"
        }
    }

    private var isManual: Bool {
        model.method == .manual || model.sourceLine.isEmpty
    }

    private var isCertain: Bool { model.confidence >= 1 }

    /// Two fraction digits, always — `1.00`, not `1`. A confidence that renders
    /// at a different width row to row is a column that can't be scanned.
    private var confidenceText: String {
        var value = model.confidence
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .plain)
        let parts = Figure.parts(rounded)
        return parts.dollars + (parts.cents.isEmpty ? ".00" : parts.cents)
    }
}

// MARK: - The disclosure

/// `▸ Source` — the tap that opens provenance on a transaction detail
/// (SPEC 5.4).
///
/// The panel opens in place; it does not push a screen (reference `20`). Height
/// and opacity, ~0.25s, no spring — ledgers don't bounce (SPEC 6.6). Under
/// Reduce Motion it changes state instantly and stays entirely legible, because
/// nothing here was ever carried by the movement.
///
/// The review queue does **not** use this — there the raw line is shown without
/// being asked for, because that is the moment the user is deciding whether to
/// believe the app, and hiding the evidence behind a tap is the wrong instinct
/// exactly once (SPEC 6.3).
public struct ProvenanceDisclosure: View {

    private let model: ProvenanceView.Model
    private let title: String

    @State private var isExpanded: Bool
    @Environment(\.vouch) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ model: ProvenanceView.Model,
                title: String = "Source",
                initiallyExpanded: Bool = false) {
        self.model = model
        self.title = title
        self._isExpanded = State(initialValue: initiallyExpanded)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Button {
                if reduceMotion {
                    isExpanded.toggle()
                } else {
                    withAnimation(.easeOut(duration: 0.25)) { isExpanded.toggle() }
                }
            } label: {
                HStack(spacing: Space.s) {
                    // A shape, not just a rotation — the state is readable in a
                    // still frame and in greyscale.
                    Text(isExpanded ? "▾" : "▸")
                        .font(VouchType.body)
                        .foregroundStyle(theme.inkDim)
                    Text(title).vouchEyebrow().foregroundStyle(theme.ink)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Shows the line the parser read, verbatim.")

            if isExpanded {
                ProvenanceView(model)
                    .transition(.opacity)
            }

            Rectangle().fill(theme.rule).frame(height: Space.hairline)
        }
    }
}

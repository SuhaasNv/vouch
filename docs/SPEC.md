# Vouch — Product & Technical Specification

**Product:** Vouch
**Former codename:** PaperTrail
**Owner:** Suhaas NV
**Platform:** iOS 26+ (iPhone only)
**Status:** v0.2 spec, pre-build
**Doc date:** 31 July 2026

---

## 0. Scope firewall (read this before anything else)

This is a single consolidated spec, not five documents. A one-person, one-user app does not need a PRD/TRD split — that split exists so a PM and an engineering lead can sign off on each other's work, and here they're the same person. It stays one file for the same reason.

**The one-line thesis:** *Import a statement, get a month you can prove.*

Anything that does not serve that sentence is out of v1. The Non-Goals section is the most important section in this document. When you're four weekends in and tempted, re-read it.

---

# PART 1 — THE SELLING FEATURE

Everything in Part 1 is the answer to "why would anyone use this instead of Copilot." Read it before Part 2, because Part 2 is just how it gets built.

## 1.1 What every other tracker cannot tell you

Ask any personal finance app one question: **"Is this month complete?"**

None of them can answer. Not because they're badly built — because of where their data comes from. Aggregators (Plaid, Salt Edge, Finicity) hand the app a *feed*. A feed has no edges. When a connection silently drops for six days, or the bank rate-limits, or a pending charge settles under a different description, the app shows you a number that looks exactly as confident as a correct one. The failure mode of a feed is a plausible lie.

Manual and SMS-based trackers fail the same question for the opposite reason: they only ever had the rows you happened to give them.

**A statement has edges.** It states its own period, its own opening balance, its own closing balance, and — usually — its own totals. It is a closed system that publishes its own checksum. That is the entire opportunity, and it is available to any app willing to read a document instead of consume an API.

## 1.2 The Proof

Vouch's differentiator is a single feature with a name, a screen, and a verdict: **the Proof**.

It runs at four levels, because the DBS savings eStatement turned out to publish a running balance on every row (confirmed against a real June 2026 statement — see `DECISIONS.md` D-004).

### Level 0 — Row proof (the one that changes everything)

```
balance[n]  ==  balance[n−1] − withdrawal[n] + deposit[n]     for every n
```

Verified end to end on real data: `Balance Brought Forward 1,112.39` → 15 rows → `Balance Carried Forward 863.70`, every intermediate balance exact, zero drift.

This is a different class of guarantee from statement-level reconciliation. It means:

- **Errors are located, not just detected.** Not "something is wrong across 87 rows" — "row 43 is wrong."
- **Amount and direction are derivable twice, independently.** Once by parsing the Withdrawal/Deposit cells, once from the balance delta. Agreement → confidence 1.0. Disagreement → that one row is flagged. **The parse verifies itself.**
- **The language model is now irrelevant to the numbers.** Not barred by policy — unnecessary. Arithmetic is better at this than a 3B model will ever be.
- **A dropped page is caught.** Each page closes with `Balance Carried Forward` and the next opens with `Balance Brought Forward` at the same figure.

### Level 1 — Statement proof (within one statement)

```
statedOpeningBalance − Σdebits + Σcredits  ==  statedClosingBalance   ?
statedTotalDebits                          ==  Σ(parsed debits)       ?
statedTotalCredits                         ==  Σ(parsed credits)      ?
statedTransactionCount                     ==  parsed row count       ?   (where printed)
```

If the parser drops a $340 row, the arithmetic breaks and the app says so in dollars. It is not possible for Vouch to quietly lose a transaction from within a statement it has read.

### Level 2 — Chain proof (across statements)

```
thisStatement.openingBalance  ==  previousStatement.closingBalance   ?
```

This is the part no competitor can do at all, and it's nearly free once Level 1 exists.

If March closes at 3,084.75 and May opens at 1,204.55, there is an April, you don't have it, and **Δ 1,880.20 of your life is unaccounted for.** Vouch names that gap, prices it, dates it, and puts an `Import` button next to it. An aggregator app in the same situation shows you a tidy chart with a hole in it and no indication the hole exists.

The chain is what turns "this statement parsed correctly" into "**my records are complete**." That's the sentence worth building an app around.

### The verdict

Every statement and every account carries one of exactly three states. No fourth state, no partial credit, no percentage.

| State | Meaning | Colour |
|-------|---------|--------|
| **Vouched** | Level 1 passes and Level 2 links to the prior statement | `credit` — solid rule |
| **Unvouched** | Level 1 fails. Delta shown in dollars, rows still imported but flagged everywhere they appear | `pending` — dashed rule |
| **Gap** | Level 1 passes but the chain is broken. The missing period is named and priced | `pending` — broken rule |

A first-ever statement for an account is `.head`, not a gap. Don't accuse the user of losing a statement that predates the app.

## 1.3 Provenance — the second half of trust

The Proof tells you the month is complete. Provenance tells you *any individual row is real*.

Every transaction retains the **verbatim line it came from**, the page it was on, and which pass produced it. One tap on any row shows:

```
  RAW  28JUL  NETS QR PAYMENT TO 88 HAWKER CTR   8.50
       page 3, line 41 · regex · confidence 1.00
```

`rawDescription` is never mutated. Normalisation, categorisation, and merchant cleanup are all *derived* fields sitting next to the original, never on top of it. If Vouch ever shows you something you don't recognise, you can get back to the bank's own words in one tap.

This is cheap — three extra fields — and it is the difference between an app that asserts and an app that shows its work.

## 1.4 Nothing is silently rewritten

An import is an **event**, not a merge. Every row knows which import created it. Any import can be undone, and undoing it removes exactly the rows it created and nothing else. Your merchant rules survive; your history doesn't get quietly rewritten underneath you.

Aggregator apps mutate history constantly — descriptions change when a charge settles, amounts change on partial refunds, rows vanish on re-sync — and they never tell you. Vouch's history is append-only and every change is attributable.

## 1.5 Positioning

**Be honest about what's new here.** Reconciliation is not a novel idea — it is a thirty-year-old accounting ritual, and Quicken, YNAB and Actual Budget all ship it. But in every one of them it is **manual**: you sit down with the statement and tick rows off by hand until the numbers agree. That chore is precisely why almost nobody does it.

Vouch's contribution is not the concept. It's that **the machine reads the statement, so the tick happens automatically** — and then chains the result across months, which no one does at all.

|  | Aggregator trackers<br>(Copilot, Monarch) | PDF converters<br>(App Store, ~10 of them) | Desktop reconcilers<br>(YNAB, Quicken, Actual) | **Vouch** |
|---|---|---|---|---|
| Source of truth | A vendor's API feed | The statement | The statement (you type/import it) | The statement |
| Reconciles at all? | No | No — it's a converter | **Yes, by hand** | **Yes, automatically** |
| Detects a missing month? | No | No | No | **Yes — balance chain, priced in dollars** |
| Keeps a ledger? | Yes | No — one-shot CSV export | Yes | Yes |
| Row traceable to source? | No source exists | n/a | No | **Verbatim line, page, method** |
| History stable? | Silently mutated on re-sync | n/a | Manual edits | Append-only, per-import undo |
| Data leaves the device | Every transaction | Several are cloud-backed despite "privacy-first" copy | Varies | **Never — no networking code in the binary** |
| Ongoing cost | USD 8–15/mo | One-off / IAP | USD 9–15/mo | Nothing |

SMS-parsing trackers (Axio, Money View) aren't in the table because the mechanism doesn't exist on iOS — see 2.1.

The four categories fail at four different points: aggregators have no edges, converters have no ledger, desktop reconcilers make a human do the work, and SMS trackers can't run here. Vouch is the intersection, and the intersection happens to be small enough for one person to build in four weekends.

**The honest trade Vouch makes: it is not real-time.** You get a complete, provable month roughly a week after it ends, instead of an approximate day that might be wrong. For understanding where money goes, that is the better trade. State it plainly rather than hiding it — it's the reason the guarantee is possible.

**A quiet second advantage of statements:** they contain only settled transactions. There is no pending/cleared ambiguity to model, no authorisation that later settles at a different amount, no state machine. Every competitor consuming a live feed has to build one and explain it to the user. Vouch simply doesn't have the problem — and shouldn't invent a `pending` transaction state to look more like the others.

## 1.6 On the name

`PaperTrail` collides with SolarWinds Papertrail (log management), and it describes the input rather than the output.

**Vouch** is the audit term for tracing a recorded entry back to its supporting document to confirm it's real — which is precisely, literally what the app does. It works colloquially ("I'd vouch for that number") and as a status word ("July 2026 · Vouched"). One syllable, verb and noun, no collision in consumer finance.

*Alternatives, if you want them:* **Tickmark** (the auditor's mark against a verified figure — best visual fit with the stationery design language) and **Attest** (most precise, coldest). Swapping is a find-replace across `docs/` plus the bundle display name; do it before weekend 2 or don't do it.

---

# PART 2 — PRD

## 2.1 Problem

Card and UPI/PayNow transactions land across multiple issuers with no single readable monthly view, and the automated capture methods that solve this elsewhere are unavailable on iOS in Singapore:

- **No Apple Pay transaction API.** Apple Pay is a tokenisation layer; the transaction record lives at the issuing bank.
- **No FinanceKit access.** The entitlement requires App Store distribution in the US or UK, and covers Apple Card/Cash/Savings plus UK open-banking institutions. Singapore banks are not in scope.
- **No SMS reading on iOS.** The mechanism that makes Indian trackers (Axio/Walnut, Money View) work does not exist on this platform.
- **No notification interception.** Third-party apps cannot read other apps' notifications.

**What is left is the statement.** It is authoritative, complete, machine-readable, and legally yours. Every automated approach is a lossy approximation of the document Vouch reads directly — and, per Part 1, the only one of them that can prove its own completeness.

## 2.2 Users

**Primary (v1): you.** n = 1. Singapore resident, DBS/POSB primary account, one or two credit cards, iPhone with Apple Intelligence enabled, comfortable downloading a monthly eStatement PDF.

**Secondary (v2, gated — see 2.7): 3–5 friends** on Singapore retail banks. Not "friends of friends." Not the App Store.

Designing for the secondary user in v1 is the single most likely cause of this project dying. Don't.

## 2.3 Goals

| # | Goal | Why it matters |
|---|------|----------------|
| G1 | Turn a statement PDF into categorised transactions in under 3 minutes | If it takes longer than manual entry, you'll stop |
| G2 | Never silently lose or invent a transaction | Trust is binary in a finance tool; one phantom row and you never open it again |
| G3 | Prove completeness, don't assert it | This is the product. See Part 1 |
| G4 | Zero network egress | No backend, no PDPA exposure, no hosting bill, no auth screen |
| G5 | Corrections stick | Categorising "SHENG SIONG" once should mean never doing it again |

## 2.4 Non-goals (v1)

Explicitly **not** building, and not designing hooks for:

- Budgets, savings goals, forecasting, net worth
- Bill reminders, subscription detection, renewal alerts
- Multi-user, accounts, login, sync, iCloud
- Bill splitting or anything social
- Investment, CPF, insurance, or SGFinDex integration
- Charts beyond a single monthly category breakdown
- Android, iPad, watchOS, widgets, Live Activities
- Receipt scanning
- Bank API/screen-scraping integrations of any kind

**Amended 31 Jul 2026:** "any AI chat interface over your finances" was previously on this list. It's now **v1.5, specified in Part 9** — under constraints that make it serve the thesis rather than dilute it. It does not start before weekend 4's gate passes.

**Note on the Proof:** it is tempting to grow it — trend lines of reconciliation health, statement-vs-statement diffing, a proof history. Don't. The Proof is one sheet with one verdict. Its power is that it's boring and always right.

## 2.5 Requirements

### P0 — v1 ships without these only if it doesn't ship

| ID | Requirement | Acceptance |
|----|-------------|------------|
| R1 | Import a password-protected PDF statement from Files or Share Sheet | DBS eStatement opens with user-supplied password; password never persisted |
| R2 | Extract transactions: date, description, amount, direction | ≥95% line-item recall on a 3-statement golden set |
| R3 | **Level 1 proof** — reconcile parsed totals against the statement's own stated totals | Mismatch blocks the import with a clear dollar diff, never a silent pass |
| R4 | **Level 2 proof** — chain this statement's opening balance to the prior statement's closing balance for the same account | Break is surfaced as a named, dated, dollar-priced gap. First statement for an account is `.head`, not a gap |
| R5 | **Provenance** — every transaction retains verbatim source line, page number, line index, and extraction method | One tap from any row to the bank's own words. `rawDescription` never mutated |
| R6 | Surface every low-confidence row in a review queue before the data is trusted | No row enters the ledger unreviewed on first import of a new bank |
| R7 | Auto-categorise by merchant, user-correctable | 12 fixed categories, one tap to change |
| R8 | Persist merchant→category overrides, applied retroactively | Same merchant auto-resolves on the next import; past rows update, count shown |
| R9 | Month view: total spend, per-category breakdown, transaction list, proof state | One screen |
| R10 | Duplicate detection across overlapping statements | Re-importing the same statement changes nothing |
| R11 | Undo import | Removes exactly the rows that import created. Merchant rules survive |
| R12 | Coverage view — per-account statement timeline showing vouched / gap / missing periods | Every gap is priced and has an `Import` affordance |
| R13 | Manual entry for cash | Under 10 seconds |

### P1 — after v1 works

- Second and third bank format (OCBC, UOB)
- Month-over-month category delta
- CSV export (with provenance columns — that's the version nobody else can produce)
- Search / filter by merchant

### P2 — probably never, listed to keep it out of your head

- Email alert ingestion via Gmail API (real-time, but breaks G4 — needs its own decision)
- Multi-currency
- Recurring-charge detection

## 2.6 Success metrics

Usage metrics only. Downloads and "does it work" are not metrics.

| Metric | Target | Measured how |
|--------|--------|--------------|
| M1 Consecutive months imported | 3 | You, honestly, at day 90 |
| M2 Median import→reviewed time | < 3 min | Stopwatch, weekend 4 |
| M3 Extraction recall on golden set | ≥ 95% | Automated test |
| M4 Proof false-pass rate | 0 | Automated test (Level 1 and Level 2) |
| M5 Rows needing manual correction, month 3 | < 5% | In-app counter |
| M6 Months in `.vouched` state at day 90 | 3 of 3 | Coverage view |

**M1 is the only one that matters.** The others are how you get there.

## 2.7 Kill gates

Honest exits, decided now while you're unattached:

- **End of weekend 1 — the load-bearing gate.** If you cannot extract structured transactions from one real DBS statement that pass Level 1, stop. Everything after this is decoration on a broken foundation.
- **End of weekend 4.** If it isn't on your phone, stop.
- **Day 60.** If you have not imported a second month unprompted, archive it. Write up the extraction and proof architecture as a post — that was always the transferable output — and move on without guilt.
- **Sharing gate.** Do not write a single line of multi-user code before day 60. When you do share: TestFlight only, ≤5 people, and understand you are then holding other people's financial records.

## 2.8 Release

TestFlight internal testing. No App Store submission. This avoids the Finance category, the FinanceKit entitlement question, and full App Review. Cost: Apple Developer Program, ~USD 99/yr.

---

# PART 3 — TRD

## 3.1 Architecture

```
┌──────────────────────────────────────────────────────┐
│                    iPhone (only)                     │
│                                                      │
│  Share Sheet / Files                                 │
│         │                                            │
│         ▼                                            │
│  ┌─────────────┐   password    ┌──────────────────┐  │
│  │ ImportGate  │──────────────▶│ PDFKit unlock    │  │
│  └─────────────┘               └────────┬─────────┘  │
│                                         ▼            │
│                            ┌────────────────────────┐│
│                            │ TextLayer              ││
│                            │ PDFKit text → fallback ││
│                            │ Vision OCR if empty    ││
│                            │ (page + line index     ││
│                            │  retained per line)    ││
│                            └────────┬───────────────┘│
│                                     ▼                │
│              ┌──────────────────────────────────────┐│
│              │ ParsePipeline                        ││
│              │  1. BankProfile detect               ││
│              │  2. Deterministic regex pass         ││
│              │  3. LLM pass on residual lines only  ││
│              └────────┬─────────────────────────────┘│
│                       ▼                              │
│              ┌──────────────────────────────────────┐│
│              │ ProofEngine                          ││
│              │  L1 intra-statement arithmetic       ││
│              │  L2 chain vs prior StatementImport   ││
│              └────────┬─────────────────────────────┘│
│                       ▼                              │
│              ┌────────────────┐   ┌────────────────┐ │
│              │ ReviewQueue    │──▶│ SwiftData store│ │
│              └────────────────┘   └────────────────┘ │
│                                                      │
│   NO NETWORK CODE ANYWHERE IN THE TARGET             │
└──────────────────────────────────────────────────────┘
```

## 3.2 Stack

**Every line is a first-party Apple framework. Zero third-party dependencies.** That is not minimalism for its own sake — it's what makes "no networking code in the binary" (3.8) an auditable claim rather than a promise. A dependency you didn't write is a dependency whose transitive imports you have to keep checking.

| Layer | Choice | Note |
|-------|--------|------|
| Language | Swift 6, strict concurrency | Actor isolation on the parse pipeline |
| Min target | iOS 26 | FoundationModels and the current SwiftData behaviour both require it |
| UI | SwiftUI | iPhone only. Two colour modes, Part 6 |
| State | Observation (`@Observable`) | Sufficient at this scale. No TCA, no Redux — one user, four screens |
| Persistence | SwiftData | SQLite underneath. ~21,600 rows after a decade (D-013). Drop to GRDB only on a real wall |
| Encryption at rest | `.completeFileProtection` | AES-256, key in the Secure Enclave, tied to device passcode. Covers the store *and* the PDF vault |
| Device gate | LocalAuthentication | `LAContext` + `.deviceOwnerAuthentication` — Face ID with passcode fallback |
| PDF | PDFKit | `PDFDocument(url:)` + `unlock(withPassword:)` |
| OCR fallback | Vision `VNRecognizeTextRequest` | Genuine fallback only — the DBS eStatement has a text layer (D-003) |
| Parsing | Swift Regex / `RegexBuilder` | Typed captures, compile-time checked. Anchored on the balance column, 3.3 |
| Hashing | CryptoKit `SHA256` | `sourceHash` — idempotency key and vault integrity check |
| Money | `Decimal` only | Never `Double`. Not once, not for display. Exact equality in the proof |
| On-device LLM | FoundationModels | `@Generable` + `Tool`. ~3B, 4,096-token context, free, offline |
| Agent (v1.5) | Custom Swift tool loop behind a `LanguageBackend` protocol | Part 9. The protocol keeps D-009 reversible at near-zero cost |
| Import | UniformTypeIdentifiers, Share Extension | Security-scoped URLs; nothing copied unencrypted |
| Tests | XCTest + golden fixtures | Redacted real statements committed to the repo (D-007) |
| Distribution | TestFlight | No App Store. ~USD 99/yr |

### Deliberately not using

| Not using | Decision |
|-----------|----------|
| Any backend — Postgres, Redis, Railway, workers | D-013. 12 MB after ten years; a server buys nothing and costs the entire thesis |
| OpenAI, LangChain, LangGraph | D-009. No iOS runtime, and it exports other people's card numbers offshore |
| `URLSession`, `Network`, Alamofire | There is no transit. The absence is the feature |
| Analytics, crash reporting, Firebase | 3.8 |
| CloudKit / iCloud sync | Not in v1. If sync ever ships it's CloudKit's end-to-end encrypted private DB, never a host — Part 10.4 |
| Core Data | SwiftData supersedes it here |
| Any SPM or CocoaPods dependency | Adding one requires auditing what it links, not reading its README |

## 3.3 Balance-anchored parsing

**Do not throw the whole statement at the model.** A bank statement is a fixed-template document. For a fixed template, a deterministic parser is faster, free, exactly reproducible, and testable. The on-device model is none of those things.

For this format specifically, there's something better than a line regex. **Anchor on the balance column.**

The DBS savings statement has variable-height rows — a debit card transaction is 3 lines, a PayNow transfer is 5 — so "one line = one transaction" is wrong from the start. But every transaction has exactly one balance figure, and balances form a strictly ordered arithmetic sequence from `Balance Brought Forward` to `Balance Carried Forward`.

```
1. Find Balance Brought Forward  → the anchor
2. Find every balance figure in the Balance column, in order
3. Each balance closes one transaction. Row n spans the text between balance n−1 and balance n
4. amount    = |balance[n] − balance[n−1]|        ← exact, no parsing
   direction = balance[n] < balance[n−1] ? .debit : .credit
5. Parse the Withdrawal/Deposit cell independently → cross-check against step 4
6. Everything else in the span is description; parse merchant, dates, refs from it
7. Last balance must equal Balance Carried Forward
```

**Step 4 and step 5 derive the same fact two independent ways.** When they agree, confidence is 1.0 and no human ever sees the row. When they disagree, you know precisely which row and by how much. This is what a self-verifying parser looks like, and it's only possible because the document publishes its own intermediate state.

It also solves row segmentation for free — the hardest part of parsing a variable-height table — because the balance sequence tells you where each row ends without needing to understand the row's internal structure.

**The model's remaining job is small and non-numeric:** cleaning a merchant name out of `KOPITIAM @ LAU PA SAT SI SGP 30MAY / 4628-4507-6331-7741`, and classifying an unseen merchant into one of 12 categories. It touches no amount, no balance, no date, no direction.

**Fallback for banks with no balance column:** revert to line-pattern matching with the model on residual lines, as originally specced. Note it loudly in that bank's profile — the proof drops from four levels to three and every row's confidence comes from parsing alone.

**Every discarded line is counted and retained for the import session.** `rejectedLineCount` is shown when the proof fails, and the rejected lines themselves are viewable — a mismatch you can't inspect is just a scarier version of a silent failure.

**This is also the part of the build that is worth writing up.** "I used an LLM to parse PDFs" is a tutorial. "I used deterministic parsing where the format was stable, reserved the model for the residual, then proved both against the document's own checksum and chained the checksums across documents" is engineering.

## 3.4 Guided generation contract

Design the Swift type first; the model fills a contract you defined rather than returning prose you reverse-engineer.

```swift
@Generable
struct ExtractedTransaction {
    @Guide(description: "Transaction date as it appears, format DD MMM")
    let dateText: String

    @Guide(description: "Merchant or description, excluding reference numbers")
    let description: String

    @Guide(description: "Amount as a positive decimal string, no currency symbol or commas")
    let amountText: String

    @Guide(.anyOf(["debit", "credit"]))
    let direction: String

    @Guide(description: "true if this line continues a previous transaction")
    let isContinuation: Bool
}
```

Notes:

- **Strings, not `Decimal`.** Let the model produce text; parse and validate in Swift. Never let a 3B model do arithmetic you can do exactly.
- **The model never touches the totals.** Opening balance, closing balance, and stated totals are regex-only, always. If the model could influence both sides of the proof, the proof would be worthless. This is the single most important constraint in the pipeline.
- **One line (or one small block) per session.** The on-device context window is small; a full statement will not fit, and stuffing it degrades quality before it errors.
- Keep `includeSchemaInPrompt` on — the model has not seen your type.
- Fresh session per extraction unit. Multi-turn context buys nothing here and leaks earlier rows into later ones.

## 3.5 Model availability

`SystemLanguageModel.default.availability` must be checked, not assumed. Devices without Apple Intelligence, or with it disabled, are real.

| State | Behaviour |
|-------|-----------|
| `.available` | Full pipeline |
| unavailable (device / disabled / not downloaded) | Regex pass only; every residual line goes to the review queue as manual entry. **The app still works, just with more taps** |

Never block the import on model availability. The deterministic path is the floor — and because the model is barred from the totals (3.4), the proof is exactly as strong with the model off as with it on.

> **This is not a hypothetical branch — it is a real, testable configuration.** The user has two devices: an iPhone 15 (A16, model permanently `.unavailable`) and an iPhone Air (A19 Pro, `.available`). See `DECISIONS.md` D-022.
>
> **Build and test the unavailable path first**, and verify every feature on the iPhone 15 before calling it done. Most projects have to simulate this branch and it rots untested — here it can be checked on real hardware, and TestFlight friends' devices can't be predicted anyway.

## 3.6 ProofEngine

This is the feature. Everything else is a list view.

### Level 0 — row

```swift
enum ProofFailure {
    case rowBalance(rowIndex: Int, expected: Decimal, stated: Decimal)
    case rowDerivationConflict(rowIndex: Int, fromCells: Decimal, fromBalance: Decimal)
    case pageBoundary(page: Int, carriedForward: Decimal, broughtForward: Decimal)
    case balanceEquation(delta: Decimal)   // opening − debits + credits ≠ closing
    case debitTotal(delta: Decimal)
    case creditTotal(delta: Decimal)
    case countMismatch(stated: Int, parsed: Int)
}
```

Run Level 0 first. It's exact, it's free, and a Level 0 pass makes Level 1 arithmetically redundant — if every row reconciles against its neighbour and the last equals `Balance Carried Forward`, the statement totals cannot be wrong. Level 1 then serves as an independent cross-check rather than the primary mechanism, which is a much stronger place to be.

A row that fails Level 0 goes to the review queue **with the delta pre-computed**, not just marked "low confidence." The user is being asked to arbitrate a specific disagreement between two derivations, not to re-read a statement.

### Level 1 — statement

Run every check the statement supports. Skip a check only when the bank doesn't print the figure — and record which checks were skipped, because a statement proved on two of four checks is weaker evidence than one proved on four, and the Proof sheet should say so.

**Tolerance is zero.** Not one cent. If your parser is off by rounding, the parser is wrong — do not widen the goalposts to make the light turn green. Compare `Decimal` values with exact equality; this is why 3.2 forbids `Double`.

### Level 2 — chain

For each account, statements sort by `periodStart`. For each adjacent pair:

```
prior.closingBalance == next.openingBalance   →  .linked
otherwise                                     →  .gap(delta:, from: prior.periodEnd, to: next.periodStart)
```

- The earliest statement for an account is `.head`. Not a gap, not an error.
- The latest statement has no successor. Not a gap.
- Chain state is **recomputed on every import**, never cached — importing April must heal the March↔May gap automatically, with no migration step.

**Credit cards use the same arithmetic with different labels:** `previousBalance − payments&credits + newCharges = newBalance`. One `BankProfile` field maps the labels; the engine is identical.

**Cycle-aware, not calendar-aware.** Card statements run on cycles (e.g. 15th→14th), not calendar months. Coverage and chaining operate on **statement periods**; the Month View aggregates by **transaction date** regardless of which statement a row came from. Conflating these is the bug that will eat a weekend — a cycle-boundary transaction belongs to the calendar month it occurred in and the statement period that reported it, and those are different keys.

### Outcomes

- **All checks pass + chain links** → `.vouched`. Solid rule. Data is trustworthy.
- **Level 1 fails** → `.unvouched`. Dashed amber. Show the delta in dollars and the count of rejected lines. Data enters the store but is flagged everywhere it appears.
- **Level 1 passes, chain breaks** → `.gap`. Broken rule. The statement itself is sound; the record is not.
- **Never** silently accept a mismatch, and never round it away.

A tracker that quietly loses a $340 transaction is worse than no tracker, because you'll make decisions on it.

## 3.7 Categorisation

Three tiers, checked in order:

1. **User override table** — exact normalised merchant match. Always wins.
2. **Bundled rules** — ~150 seeded Singapore merchants (NTUC, Sheng Siong, Grab, ComfortDelGro, Foodpanda, Shopee, SimplyGo, Circles.Life, etc.). Ships as JSON, no model call.
3. **Model classification** — only for unseen merchants, with `@Guide(.anyOf(categories))` to constrain output to the fixed 12.

Every model classification is provisional and appears in the review queue. Every user correction writes tier 1. By month three, tiers 1 and 2 should handle nearly everything and the model should barely run.

**Categorisation never affects the proof.** The proof is arithmetic over amounts and directions; categories are a view on top. A miscategorised row is a cosmetic bug. A dropped row is an existential one. Keep the two failure classes separate in your head and in the code.

**Fixed categories (12, not extensible in v1):**
Groceries · Dining · Transport · Bills & Utilities · Shopping · Health · Entertainment · Travel · Education · Transfers · Income · Uncategorised

`Transfers` exists so money moving between your own accounts doesn't inflate spend. This is the mistake nearly every naive tracker makes.

## 3.8 Privacy and encryption

The statement contains full legal name, account number, and an unmasked card number on every debit-card row. Treat the whole document as the most sensitive thing on the phone, because it is.

**At rest**

- **`.completeFileProtection` on the SwiftData store.** This is not a checkbox — it is AES-256 with a key derived from the device passcode and held in the Secure Enclave, and the file is *cryptographically inaccessible* while the device is locked. It is the strongest at-rest guarantee iOS offers and it comes free.
- **Biometric gate on launch and on return from background.** `LAContext` with `.deviceOwnerAuthentication` so it falls back to passcode. Financial data behind Face ID is table stakes.
- The database file is the only persistent artifact. There is no cache, no export directory, no log file.

**The Vault — statements are kept, not discarded**

*Changed 1 Aug 2026. v0.2 said "parse and discard"; the requirement is now retention plus re-export.*

Statements are archived so you can open the original document from any transaction and export it later. The rule that makes this safe:

> **Store the original encrypted bytes exactly as the bank issued them. Never store a decrypted copy.**

- The file goes into the vault **byte-identical**, still protected by the bank's own password, inside a `.completeFileProtection` directory. Two independent layers: the bank's encryption and the device's.
- Decryption happens in memory, per view, per export. There is never a plaintext PDF on disk — not in a cache, not in a temp dir, not for a moment.
- `sourceHash` still verifies against the stored bytes, so the archive is provably the document that produced the ledger. That is what makes provenance mean something: not just "here's the line I parsed," but "here's the bank's original, unmodified, and here's its hash."
- **Export shares the original file.** It leaves the app still password-protected, exactly as received. Do not offer a "decrypted copy" export; it would be the one operation in the app that manufactures an unprotected financial document.
- Deleting an import deletes its vault file. Storage is shown in Settings with a per-statement breakdown — a year of statements is a few MB, but say so rather than letting it be a mystery.

**Password handling**

The statement password lives in a `String` for the duration of the import and is never written to Keychain, `UserDefaults`, or disk. Do not add a "remember password" toggle; it converts a memory-only secret into a stored one for four seconds of convenience a month.

*The one defensible exception, and it's a real trade:* re-opening an archived statement requires the password again, every time. If that proves annoying enough to matter, store it in Keychain with `.whenUnlockedThisDeviceOnly` + `.biometryCurrentSet` — behind Face ID, non-syncing, invalidated if biometrics change. Make it opt-in per account, off by default, and never for the import path. Decide it at day 60 with real usage, not now.
- Card numbers and account numbers are stripped during normalisation. They survive in `rawDescription` and `sourceLineText` by design — provenance requires verbatim text — which is precisely why the store is encrypted rather than the fields being individually protected.

**In transit**

There is no transit. See 3.8.1.

**Never**

No analytics, no crash reporting SDK, no third-party dependency that links `URLSession` or `Network`. Adding any dependency requires checking what it links, not what its README claims.

**Golden fixtures are the leak risk nobody plans for.** Committed test files come from real statements. Redact name, account number and card number to dummy values of identical length before the first commit, and keep `testFixturesContainNoPAN` in the suite so a 2am commit can't put a card number in git history permanently. See `DECISIONS.md` D-007.

## 3.9 Testing

Golden-file tests are the backbone. Redact account numbers and names in a committed fixture set; keep the amounts and structure real.

| Test | Asserts |
|------|---------|
| `testDBSGolden_recall` | ≥95% of known transactions extracted |
| `testDBSGolden_exactAmounts` | Zero amount-parsing errors |
| `testRowProof_everyRowReconciles` | B/F → each row → C/F, exact, on the real June fixture |
| `testRowProof_localisesInjectedError` | Corrupt one amount → that **row index** is reported, not just a statement-level delta |
| `testDualDerivation_agrees` | Cell-parsed amount == balance-delta amount for every row on a clean statement |
| `testPageBoundary_detectsDroppedPage` | Removing a whole page fails at the C/F → B/F seam |
| `testDedupe_sixIdenticalRowsSurvive` | Six identical `LE TACH VENDING` 0.50 rows import as **six**, not one. Regression guard for D-005 |
| `testVault_storesOriginalBytes` | Archived file hashes to `sourceHash`; still password-protected |
| `testVault_neverWritesPlaintext` | No decrypted PDF touches disk on any path, including throws |
| `testFixturesContainNoPAN` | No card-number or NRIC shape anywhere in the fixture directory |
| `testProof_detectsInjectedDrop` | Removing one row fails Level 1 |
| `testProof_detectsInjectedDuplicate` | Duplicating one row fails Level 1 |
| `testProof_zeroTolerance` | A one-cent delta fails, does not round to pass |
| `testProof_skippedChecksAreReported` | A statement without stated totals proves on fewer checks and says so |
| `testChain_detectsMissingMonth` | Mar + May imported, April absent → `.gap` with exact delta |
| `testChain_headIsNotAGap` | First-ever statement for an account is `.head` |
| `testChain_healsOnBackfill` | Importing April clears the Mar↔May gap with no migration |
| `testChain_creditCardLabels` | Card `previousBalance`/`newBalance` chains identically |
| `testProvenance_everyRowHasSourceLine` | No transaction persists without page + line index |
| `testUndoImport_isExact` | Undo removes exactly that import's rows; merchant rules survive |
| `testDuplicateImport_isIdempotent` | Same file twice → zero new rows |
| `testMultilineDescription` | Wrapped descriptions merge correctly |
| `testForeignCurrencyRow` | SGD amount taken, not the foreign one |
| `testNoModel_stillImports` | Pipeline completes with model unavailable |
| `testNoModel_proofIsIdentical` | Proof result identical with model on and off |

---

# PART 4 — DATA SCHEMA

SwiftData models. All local.

### `Account`

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID | PK |
| `displayName` | String | "DBS Multiplier" |
| `bankCode` | String | `DBS`, `OCBC`, `UOB` — selects BankProfile |
| `accountType` | Enum | `.savings` `.credit` |
| `last4` | String | Display disambiguation only |
| `createdAt` | Date | |

### `StatementImport`

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID | PK |
| `accountID` | UUID | FK → Account |
| `currencyCode` | String | `SGD`, `USD`, … **Parsed from the section anchors, never assumed** |
| `periodStart` / `periodEnd` | Date | Parsed from the `as at` header. **Never from the filename** — real files were misnamed by a month |
| `openingBalance` / `closingBalance` | Decimal | As stated by the bank, in `currencyCode` |
| `statedTotalDebits` / `statedTotalCredits` | Decimal? | Nil if the bank doesn't print them |
| `statedTransactionCount` | Int? | Nil if not printed |
| `parsedTotalDebits` / `parsedTotalCredits` | Decimal | Computed by parser |
| `proofState` | Enum | `.vouched` `.unvouched` `.gap` `.reviewing` |
| `proofChecksRun` | Int | How many of the 4 Level-1 checks the statement supported |
| `proofDelta` | Decimal | 0 when Level 1 passes |
| `chainState` | Enum | `.linked` `.head` `.gap` `.unknown` |
| `chainDelta` | Decimal | 0 when linked or head |
| `sourceHash` | String | SHA-256 of the PDF bytes — idempotency key *and* archive integrity check |
| `vaultFilename` | String | Filename within the encrypted vault directory. The bytes are the bank's original, still password-protected |
| `fileSizeBytes` | Int | For the storage breakdown in Settings |
| `rejectedLineCount` | Int | Lines the parser could not classify |
| `pageCount` | Int | |
| `importedAt` | Date | |

*Unique index on **`(sourceHash, accountID)`**, not `sourceHash` alone — see below. Index on `(accountID, periodStart)`; the chain walk depends on it.*

> ### One PDF contains several accounts — and several currencies
>
> DBS issues a **Consolidated Statement**: page 1 is an Account Summary listing every account, and the transaction pages are segmented by account, then by currency. All ten real statements contained two account sections; three also contained a **USD** section alongside SGD.
>
> **The proof unit is `(account, currency)`, not `account`.** Each currency section has its own `Balance Brought Forward <CCY>`, its own `Total Balance Carried Forward in <CCY>:` totals, and its own independent chain. Verified: the USD section chains Oct→Nov→Dec exactly, separately from SGD.
>
> **Parse the currency code. Never hardcode `SGD`.** Every analysis pass that assumed SGD silently skipped an entire account — correct results, incomplete coverage, which is exactly the failure this product exists to prevent.
>
> **Never convert and never aggregate across currencies inside the proof.** The Month View's SGD total excludes foreign sections rather than adding them at an invented rate. A converted figure is not a proved figure.
>
> **One PDF therefore produces N `StatementImport` rows — one per account-currency section — sharing a `sourceHash`.** Unique index is `(sourceHash, accountID, currencyCode)`. Re-importing is still idempotent; it just checks a triple.
>
> Parse order: detect account sections **first**, then pages within a section, then rows. `Balance Brought Forward` appears at the top of every *page* as well as every *account section*, so a naive "first B/F, last C/F" read silently mixes two different accounts and produces a chain that looks broken when it isn't. This exact mistake was made during analysis on 1 Aug 2026 — see `DECISIONS.md` D-015.
>
> The account's true period totals come from `Total Balance Carried Forward in SGD: <withdrawals> <deposits> <closing>`, not from the last per-page C/F.

### `Transaction`

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID | PK |
| `importID` | UUID | FK → StatementImport. Undo cascades on this |
| `accountID` | UUID | FK → Account |
| `date` | Date | **Transaction** date — the embedded `30MAY`. Drives the Month View |
| `postedDate` | Date | The statement's `Date` column. Drives statement membership and the proof |
| `balanceAfter` | Decimal? | Running balance after this row. Nil only for banks without a balance column |
| `rowIndex` | Int | Ordinal within the statement. Preserves order and disambiguates identical rows |
| `rawDescription` | String | Verbatim from the statement — **never mutated** |
| `sourceLineText` | String | The full source line, verbatim, including the amount |
| `sourcePage` | Int | 1-indexed |
| `sourceLineIndex` | Int | 0-indexed within the page |
| `normalizedMerchant` | String | Uppercased, punctuation and ref-numbers stripped |
| `amount` | Decimal | Always positive |
| `direction` | Enum | `.debit` `.credit` |
| `categoryID` | String | FK → Category |
| `categorySource` | Enum | `.userOverride` `.bundledRule` `.model` `.default` |
| `extractionMethod` | Enum | `.regex` `.model` `.manual` |
| `confidence` | Double | 1.0 for regex and manual |
| `isReviewed` | Bool | |
| `dedupeKey` | String | `accountID + postedDate + balanceAfter` — see the warning below |
| `note` | String? | |

*Indices: `(accountID, date)`, `(accountID, postedDate)`, `dedupeKey`, `isReviewed`, `importID`.*

> ### ⚠ The dedupe key was silently lossy in v0.2. Do not revert it.
>
> The old key was `date + amount + first 20 chars of normalizedMerchant`. Real DBS data contains **six identical rows** — `LE TACH VENDING SINGAPORE`, same day, same merchant, `0.50` each. That's one key for six transactions. **Five real transactions would have been discarded as duplicates**, silently, by the deduplication logic — the exact failure this entire product exists to prevent, hiding in the one place nobody thinks to look.
>
> The running balance is what makes rows unique: six identical charges leave six different balances behind them. Hence `balanceAfter` in the key.
>
> For a bank with no balance column, use `accountID + postedDate + amount + rowIndex`. Never a key built only from content — small repeated charges are normal, not duplicates.
>
> Level 0 would have caught this anyway (six rows dropped to one breaks the balance chain immediately), which is a decent argument for the proof being worth more than the parser. But don't rely on that. Fix the key.

Manual entries (`.manual`) have no source line. They carry `sourcePage = 0`, `sourceLineIndex = -1`, and are **excluded from the proof arithmetic** — cash you typed in is not something the bank knows about, and folding it into the reconciliation would break every statement. Manual rows appear in the Month View total but never in a statement's proof. Say this in the UI; it is a genuinely confusing edge and worth one line of copy.

### `Category`

Static, seeded, not user-editable in v1. `id`, `displayName`, `colorToken`, `sfSymbol`, `sortOrder`.

### `MerchantRule`

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID | PK |
| `matchPattern` | String | Normalised merchant, exact or prefix |
| `categoryID` | String | FK → Category |
| `source` | Enum | `.bundled` `.user` |
| `hitCount` | Int | Cheap signal for which rules are earning their keep |

Merchant rules are **not** owned by an import and survive undo.

### `RejectedLine`

Retained only for the duration of an unvouched import, so "see what didn't parse" has something to show. Deleted when the import is re-proved or undone.

| Field | Type |
|-------|------|
| `importID` | UUID |
| `page` / `lineIndex` | Int |
| `text` | String |
| `reason` | Enum — `.noPattern` `.modelDeclined` `.ambiguousDirection` |

### `BankProfile` — not persisted, bundled as code

```swift
struct BankProfile {
    let bankCode: String
    let accountType: AccountType               // card and savings are different profiles
    let headerSignature: Regex<Substring>      // detects which bank a PDF is
    let transactionPattern: Regex<...>         // the deterministic workhorse
    let dateFormat: String
    let openingBalancePattern: Regex<...>      // "PREVIOUS BALANCE" on cards
    let closingBalancePattern: Regex<...>      // "NEW BALANCE" on cards
    let statedTotalsPattern: Regex<...>?
    let statedCountPattern: Regex<...>?
    let ignorePatterns: [Regex<Substring>]     // footers, marketing, page numbers
}
```

Adding a bank = adding one `BankProfile` + one golden fixture. That is the extensibility story, and it's the right one. Record each profile's findings in `docs/DECISIONS.md` as you build it.

---

# PART 5 — USER FLOWS

## 5.1 First run

```
Launch
  └─▶ Welcome ("Import a statement. Nothing leaves your phone.")
       └─▶ Add account: name, bank, type, last 4
            └─▶ Import statement  ─────────────────┐
                                                   ▼
                                            [see 5.2]
```

No account creation. No login. No permissions requested. First screen to first import: two taps.

## 5.2 Import (the core flow)

```
Files / Share Sheet → Vouch
  │
  ├─ PDF encrypted? ──yes──▶ Password prompt ──fail──▶ Retry (3) ──▶ Abort, nothing saved
  │                              │
  │                            unlock
  ▼                              ▼
Detect BankProfile from header signature
  │
  ├─ no match ──▶ "Statement format not recognised."
  │                Offer: pick bank manually / cancel
  ▼
Extract text (PDFKit → Vision fallback if empty), retaining page + line index
  │
  ▼
Regex pass ──▶ residual lines ──▶ Model pass (if available)
  │            (unparsed → RejectedLine)
  ▼
Dedupe against existing transactions by dedupeKey
  │
  ▼
PROOF — Level 1
  ├─ pass ──▶ continue
  └─ fail ──▶ .unvouched, delta shown, import continues flagged
  │
  ▼
PROOF — Level 2 (chain, recomputed for the whole account)
  ├─ links / head ──▶ .vouched
  └─ break ────────▶ .gap, missing period named and priced
  │
  ▼
Review queue: everything with confidence < 1.0, or categorySource == .model,
              or direction ambiguous
  │  (swipe right = confirm · tap = edit · swipe left = delete)
  ▼
Queue empty ──▶ Proof sheet ──▶ Month view
```

**Design rule for this flow:** the user reviews *exceptions*, never the whole list. If the review queue routinely contains most of the statement, the parser is broken — fix the parser, don't make the human work.

## 5.3 Monthly recurring

```
Download eStatement from bank app
  └─▶ Share ──▶ Vouch
       └─▶ Password ──▶ [pipeline] ──▶ Review queue (should be short by month 3)
            └─▶ Month view: "SGD 3,412.80 · 87 transactions · Vouched"
```

## 5.4 Inspecting a row (provenance)

```
Month view ──▶ tap row ──▶ detail
  ├─ category picker
  ├─ note
  └─ ▸ Source
       └─▶ verbatim line, page N line M, extraction method, confidence
            └─▶ "From the DBS statement imported 3 Aug 2026"  [ See the Proof ]
```

## 5.5 Correcting a category

```
Month view ──▶ tap transaction ──▶ category picker ──▶ select
  └─▶ "Always categorise SHENG SIONG as Groceries?"  [Just this one] [Always]
       └─▶ Always → write MerchantRule(source: .user)
            └─▶ Retroactively apply to all matching past transactions, show count
```

The retroactive apply is what makes the app feel like it's learning. Don't skip it.

## 5.6 Closing a gap

```
Coverage ──▶ tap gap ("April 2026 missing · Δ 1,880.20")
  └─▶ [ Import April statement ]
       └─▶ [pipeline] ──▶ chain recomputed
            └─▶ Gap closes. "March–July 2026 vouched." ← the payoff moment
```

This is the flow that sells the app. Make the transition from broken rule to solid rule the one animated moment in the product.

## 5.7 Manual cash entry

```
Month view ──▶ + ──▶ amount pad (opens focused) ──▶ merchant ──▶ category ──▶ Save
```

Target: under 10 seconds. Amount field is focused on open. Category defaults to the last one used. A one-line note in the sheet: *"Cash entries aren't on any statement, so they sit outside the proof."*

## 5.8 Undoing an import

```
Coverage / Proof sheet ──▶ ⋯ ──▶ Undo import
  └─▶ "Removes 87 transactions from 1–31 Jul. Your merchant rules stay."  [Cancel] [Undo]
       └─▶ Chain recomputed — July becomes a gap again, honestly
```

## 5.9 Error states

| Situation | Behaviour |
|-----------|-----------|
| Wrong password ×3 | Abort cleanly, nothing written |
| Unknown bank format | Name it plainly, offer manual bank selection, never guess |
| Text layer empty (scanned) | Fall back to Vision OCR, warn that accuracy is lower |
| Level 1 fails | Show delta in dollars + rejected line count, with the rejected lines viewable. Options: import flagged / cancel. Never a silent pass |
| Level 2 breaks | Name the missing period, price it, offer `Import`. The current statement is still `.vouched` on its own terms — say so |
| Statement predates all others for the account | `.head`. No gap. No warning |
| Duplicate statement | "Already imported on 3 June. No changes made." |
| Bank prints no stated totals | Prove on the balance equation alone; Proof sheet shows "2 of 4 checks" |
| Model unavailable | Import proceeds regex-only, longer review queue, one-line explanation. Proof unaffected |

---

# PART 6 — UI/UX

Visual references and a take/reject list live in `docs/inspiration/`. This section is canonical; that folder is context.

## 6.1 Direction

The subject is a bank statement — so the design comes from statement stationery: carbon-copy ledgers, hairline rules, right-aligned tabular figures, the flat ink of impact printing. Not fintech-neon, not a pastel budgeting app.

### On violet

It's the right call, and for a better reason than brand preference.

Before photocopiers, **a duplicated document was purple.** Spirit duplicators and indelible copying pencils used aniline violet — which is why every carbon-era ledger slip, requisition form and mimeographed sheet came out in that colour. Vouch's entire job is producing a faithful copy of a bank document and proving it matches the original. Ditto violet is, historically and literally, the colour of a copy you can trust. That is the thesis in a hue, not a skin on top of it.

**But it only earns that if it stays scarce.** The rule:

> **Violet means proved.**

The proof strip is violet when vouched. The agreeing figures on the Proof sheet are violet. The primary action is violet. **Nothing else is.** Not the tab bar, not the balance card, not every button, not the category bar. Reference `04-unity-dashboard-purple.png` in the inspiration folder for the failure mode — violet on every surface, which means violet signifies nothing. This app has exactly one thing worth signalling.

**Semantics outrank brand.** Debits stay red, credits stay green. In a ledger, colour carries meaning before it carries identity, and purple-the-brand does not get to overwrite red-the-debit.

### Two modes, both first-class

Not a dark app with a light setting bolted on. The two modes are the same object at two stages:

| Mode | It is | Surface | Figures |
|------|-------|---------|---------|
| **Paper** | The original document | Warm off-white stock | Dark violet-black ink |
| **Carbon** | The copy | Near-black, violet-cast | Paper-white |

Follows the system setting by default, with a manual override in Settings. Neither is the "real" one — a statement is dark ink on light paper, so if anything Paper is the more honest expression of the thesis and should be designed first.

**The cost is real:** two palettes to tune, and every screen QA'd twice. It's affordable only because every token below is semantic and no component ever names a hex. Break that rule and light mode becomes a permanent tax.

### The one type risk worth taking

A serif on the *figures*, not the headlines. Statements have always set amounts in the most authoritative face on the page. Inverting the usual "serif headline / sans data" convention makes the number the hero, which is what this app is actually about.

### The signature element

The **proof strip** — a 3pt hairline bar pinned under the month header, carrying the verdict in its own **form**, not in a label:

```
════════════════   solid     accent    Vouched
╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌   dashed    pending   Unvouched — Level 1 failed
═════   ═══════    broken    pending   Gap — the break sits where the gap is
```

It is the product's entire thesis rendered as one line. Nothing else in the UI competes with it. A user should learn to read the strip in a week and never need the words again.

Note that the strip is legible with colour removed entirely — solid, dashed and broken are three different shapes. That's deliberate; see 6.5.

## 6.2 Tokens

**Colour**

Eleven semantic tokens, two values each. Anything not on this list doesn't ship.

| Token | Paper (light) | Carbon (dark) | Use |
|-------|---------------|---------------|-----|
| `surface` | `#F4F1EA` | `#14111C` | App background — statement stock / carbon black |
| `surface-raised` | `#FFFFFF` | `#1D1929` | Cards, sheets, the Proof |
| `surface-sunken` | `#E7E2D8` | `#0E0C14` | Keypad wells, scrims behind sheets |
| `ink` | `#1A1626` | `#EAE6F2` | Primary text and figures |
| `ink-dim` | `#5C556B` | `#9A93AD` | Eyebrows, labels, metadata |
| `rule` | `#D6D0C4` | `#2C2638` | Hairlines, dividers, table rules |
| `accent` | `#5B3FBF` | `#9B7DF5` | **Proved.** Proof strip, agreeing figures, primary action |
| `accent-sunken` | `#EDE7FB` | `#221B38` | Accent-tinted fills and tracks |
| `debit` | `#B03A2E` | `#E06A5E` | Debit amounts, destructive actions |
| `credit` | `#2A6B58` | `#4CA88C` | Credit amounts |
| `pending` | `#A9761B` | `#E0A94A` | Unvouched, gap, unreviewed, low confidence |

Rules:

- **Semantic names only.** No component references a hex or a mode. Changing the accent is one line in one file; if it isn't, the token layer is wrong.
- **Neither palette is a filter of the other.** `debit` is not the same red made lighter — dark-mode reds need more lightness and less chroma to avoid vibrating against a near-black surface. Tune each mode by eye at 375pt, don't generate one from the other.
- **Surfaces carry a violet cast, not a neutral grey one.** `#14111C` rather than `#141A22`. It's a two-degree hue shift nobody will consciously notice and everybody will feel.
- **Contrast floors, verified not assumed:** `ink` on `surface` ≥ 12:1. `ink-dim`, `accent`, `debit`, `credit`, `pending` on `surface` ≥ 4.5:1. Both modes. Check them; three of these are close.

*Token rename from v0.1:* the old `ink`/`paper` pair meant surface/text, which inverts confusingly across two modes. `surface`/`ink` now mean what they say.

**Type**

| Role | Face | Setting |
|------|------|---------|
| Figures — hero | Instrument Serif | 48/52, tabular figures on |
| Figures — rows | SF Mono | 15, tabular, right-aligned |
| Body / UI | SF Pro Text | 15/22 |
| Eyebrow / labels | SF Pro Text | 11, uppercase, tracking +0.08em |
| Source line (provenance) | SF Mono | 12, `rule` colour, never wrapped — scrolls horizontally |

Tabular figures are non-negotiable — proportional digits make a column of amounts unreadable, and this app is a column of amounts. Worth knowing: **no major banking app currently uses tabular digits**, per the transaction-list teardown in `docs/inspiration/README.md`. It is a one-line fix that visibly beats Monzo, Starling and Revolut at their own core screen. Take the free win.

**Amount rendering** — three rules, all cheap, all borrowed from that teardown:

1. **No currency symbol in the list.** A single-account ledger has no ambiguity; `−42.30` not `−SGD 42.30`. The symbol appears once, on the month hero.
2. **Dollars outweigh cents.** `−42` at full `ink`, `.30` at `ink-dim` and one step down in optical size. The eye reads magnitude first, which is how people actually scan a statement.
3. **Progressive disclosure by row type.** A plain domestic row shows date, merchant, amount — nothing else. A foreign-currency row earns one dim subline with the original amount and rate. A reversal earns a marker. Don't pad every row to the width of the most complex one; that's the mistake that makes Starling's list harder to scan than Monzo's.

**Merchant logos are out**, and it costs us something real — they're the single biggest scannability aid in modern banking apps. We're giving them up because fetching them requires a network and bundling them requires a licence deal. Compensate with typographic hierarchy, not with an icon set of our own invention.

**Layout**

8pt grid. Full-bleed hairline rules between rows, no card shadows, no rounded transaction rows. Amounts hard-right against a consistent margin so decimal points align down the column.

**Instrument Serif across two modes:** it's a high-contrast display face, so its thin strokes will read lighter on `Paper` than on `Carbon` — dark-on-light always does. Compensate optically (a slightly larger optical size or +1pt on Paper), never by swapping the face. Verify the hero figure at 375pt in both modes before locking the type scale.

## 6.3 Screens

**The Ledger** — the home screen

**One continuous table across all months**, not a month-at-a-time silo. The month header is a sticky scroll anchor and a filter, never a wall. Scrolling past 1 July into 30 June just works.

```
┌──────────────────────────────────────┐
│  JULY 2026  ▾                 ⚙︎    │  ← sticky; tap to jump months
│                                      │
│  SGD 3,412.80                        │  ← Instrument Serif, 48pt
│  87 transactions · DBS Multiplier    │
│  ════════════════════════════════    │  ← proof strip: solid = vouched
│  Vouched                        ›    │  ← tap → Proof sheet
│                                      │
│  ▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░░░░      │  ← single stacked category bar
│  Groceries 842 · Dining 611 · +9     │
│                                      │
│  DATE    DESCRIPTION    AMOUNT  BAL  │  ← eyebrow, matches the statement
│  ──────────────────────────────────  │
│  28 Jul  SHENG SIONG   −42.30  863.70│
│  ──────────────────────────────────  │
│  28 Jul  GRAB *TRIP    −11.80  906.00│
│  ──────────────────────────────────  │
│  27 Jul  SALARY     +6,500.00 917.80 │  ← credit colour
│  ──────────────────────────────────  │
│  ═══ JUNE 2026 · Vouched ═══════════ │  ← inline month break, no scroll jump
│  ──────────────────────────────────  │
│  30 Jun  KOPITIAM       −7.30 1,105.09│
│  ──────────────────────────────────  │
│                                      │
│              [ + ]      [ Import ]   │
└──────────────────────────────────────┘
```

**The balance column ships in the UI.** It mirrors the source document, so the app's list can be checked against the paper statement line by line, by eye. That is the most on-thesis thing in the product — and it costs one column. Dim it (`ink-dim`) so the amount still leads.

**Repeated rows collapse into groups.** Real measurement across 499 transactions: **28% of all rows are ~SGD 0.50 vending purchases worth 1.8% of the money** (D-016). An honest one-row-per-transaction list is unreadable.

```
│  ──────────────────────────────────  │
│  28 Jul  LE TACH VENDING ×6   −3.00 ›│  ← tap expands to all six
│  ──────────────────────────────────  │
```

Consecutive same-merchant, same-day rows render as one expandable group. **The underlying rows are never merged** — they persist individually, count individually, and prove individually. This is presentation only. Merging them in storage is D-005's bug wearing a different hat.

Corollary: **the category bar is value-weighted and must stay that way.** By row count this ledger looks like a vending-machine habit; by value it's 1.8%. Never offer a count-weighted breakdown.

Overlapping statement uploads are a non-event: rows merge into one ordered ledger, and the `dedupeKey` in Part 4 resolves genuine duplicates without collapsing genuinely repeated charges.

One stacked bar, not a pie or a donut. It reads at a glance and it doesn't lie about small slices.

**The Proof** — the screen that is the product

```
┌──────────────────────────────────────┐
│  ✕              THE PROOF            │
│                                      │
│  DBS Multiplier · 1–31 Jul 2026      │
│  ════════════════════════════════    │
│                                      │
│                BANK SAYS     VOUCH   │
│  Opening        1,204.55   1,204.55 ✓│
│  Debits       − 3,412.80 − 3,412.80 ✓│
│  Credits      + 6,500.00 + 6,500.00 ✓│
│  ──────────────────────────────────  │
│  Closing        4,291.75   4,291.75 ✓│
│  Count                87         87 ✓│
│                                      │
│  4 of 4 checks                       │
│                                      │
│  CHAIN                               │
│  Jun closing    1,204.55             │
│  Jul opening    1,204.55            ✓│
│  No gap.                             │
│                                      │
│  87 rows · 82 regex · 4 model · 1 you │
│                              ⋯       │
└──────────────────────────────────────┘
```

Two columns — the bank's figure and yours — side by side, in the same face, at the same size. The whole argument of the app is that those two columns are identical, so show them identical. Don't summarise this into a green badge; the badge is on the Month View, and this is where you come to check it.

*Unvouched variant:* the failing row's tick becomes `Δ 340.00` in `pending`, the strip goes dashed, and the footer becomes `[ See the 3 lines that didn't parse ]`.

**Coverage** — the screen that closes the loop

```
┌──────────────────────────────────────┐
│  ‹  COVERAGE                         │
│                                      │
│  DBS LIVE FRESH                      │
│  2026   J F M A M J J A S O N D      │
│         ▪ ▪ ▪ ▫ ▪ ▪ ▪ · · · · ·      │
│                 ↑                    │
│  ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌ │
│  April missing.                      │
│  Δ 1,880.20 between Mar closing      │
│  and May opening.        [ Import ]  │
│                                      │
│  DBS MULTIPLIER                      │
│  2026   J F M A M J J A S O N D      │
│         ▪ ▪ ▪ ▪ ▪ ▪ ▪ · · · · ·      │
│  ══════════════════════════════════  │
│  Complete, Jan – Jul.                │
│                                      │
└──────────────────────────────────────┘
```

`▪` vouched · `▫` gap · `·` no statement yet (future or pre-history — not an error)

Rows are **statement periods**, not calendar months — a card on a 15th→14th cycle draws its own grid offset accordingly. Don't fake it into calendar months to make the row look tidy; the tidiness would be a lie about what was proved.

**Review Queue** — the screen that earns trust

```
┌──────────────────────────────────────┐
│  Review              4 of 11         │
│                                      │
│  ┌────────────────────────────────┐  │
│  │  14 Jul                        │  │
│  │  NETS QR PAYMENT               │  │
│  │  TO 88 HAWKER CENTRE           │  │
│  │                                │  │
│  │  −8.50                         │  │  ← Instrument Serif, large
│  │                                │  │
│  │  Suggested: Dining      ▾      │  │
│  │  ⚠︎ Low confidence · model     │  │
│  │  ──────────────────────────────│  │
│  │  RAW  14JUL NETS QR PAYMENT    │  │  ← provenance, always visible here
│  │       TO 88 HAWKER CTR   8.50  │  │
│  │       p3 l41                   │  │
│  └────────────────────────────────┘  │
│                                      │
│   ← delete      tap edit    confirm →│
│                                      │
│  ○○○●○○○○○○○                        │
└──────────────────────────────────────┘
```

One card at a time. Swipe to confirm, tap to edit. The raw line is shown here without being asked for — this is the moment the user is deciding whether to believe the app, and hiding the evidence behind a tap is the wrong instinct exactly once.

This is the screen you'll spend the most time in during month one and almost none by month three — which is exactly the trajectory to design for.

**Import Result**

```
┌──────────────────────────────────────┐
│  DBS Multiplier                      │
│  1 Jul – 31 Jul 2026                 │
│                                      │
│  ✓ Vouched                           │
│  ════════════════════════════════    │
│                                      │
│  87 transactions                     │
│  82 matched automatically            │
│  5 need review                       │
│                                      │
│  Every figure agrees with the bank.  │
│  Chain intact since March.           │
│                                      │
│  [ See the Proof ]  [ Review 5 rows ]│
└──────────────────────────────────────┘
```

## 6.4 Copy rules

- Errors state what happened and what to do. No apologies, no vagueness. "Statement format not recognised. Pick your bank to try again."
- Empty month: "No statement for July yet." + `Import`. An empty screen is an invitation, not a mood.
- The word for the action is the same throughout: **Import** on the button, "Importing…", "Imported."
- The word for the state is the same throughout: **Vouched**, **Unvouched**, **Gap**. Never "verified", "reconciled", "confirmed", "synced". One word per state, everywhere, forever.
- Never say "transactions may be missing." Say `Δ 340.00 unaccounted across 3 rejected lines.`
- Never say "we couldn't verify." Say which check failed and by how much.
- A gap is stated as a fact, not an accusation: "April missing. Δ 1,880.20." Not "You forgot to import April."

## 6.5 Liquid Glass — navigation only, never content

**Availability, verified 1 Aug 2026:** Liquid Glass shipped in **iOS 26**, not 27. `.glassEffect()`, `GlassEffectContainer`, `.buttonStyle(.glass)` and `.glassEffectID(_:in:)` all compile against the iOS 26.5 SDK already installed. Nothing here waits on a future OS, and the deployment target stays iOS 26 (`DECISIONS.md` D-023).

### The tension, stated plainly

Glass is about depth, translucency and refraction. Vouch's design language is flat statement stationery — hairline rules, no shadows, no elevation (6.2 Layout). Applied to content, glass would dissolve the paper metaphor completely and make the app look like every other iOS 26 redesign.

Apple's own layer model resolves it, and the resolution happens to be exactly what this product wants:

> **Glass belongs to the navigation layer — things that float *above* content. Content stays opaque.**

So the rule is:

| Layer | Material |
|-------|----------|
| **Navigation** — toolbar, month picker, floating `Import` / `+`, sheet chrome, tab bar | **Glass** |
| **Content** — transaction rows, figures, hairline rules, the category bar, the Proof sheet's table | **Opaque paper. Never glass.** |

### Where it earns its place

- **The floating action pair** (`+` and `Import`). Grouped in a `GlassEffectContainer` so they blend as one material instead of two stacked panes, with `.glassEffect(.regular.interactive())` for the press response.
- **The toolbar and month picker**, so the ledger scrolls beneath them — which is what glass is *for*, and it reinforces that the ledger is a continuous document (6.3).
- **The Proof sheet rising over the ledger.** This is the one place glass carries meaning rather than decoration: it says *this is a temporary layer above your data*, which is true. Reference `09-workout-mono-sheet.mov` in `docs/inspiration/` shows the motion.

### Where it is forbidden

- **The proof strip. Never.** It is the product's entire thesis rendered as one line (6.1), and its legibility is load-bearing. A translucent verdict is a hedged verdict.
- **Any amount, anywhere.** Figures sit on opaque surfaces so the contrast floor in 6.6 is a fixed guarantee, not a function of what happens to be scrolling underneath.
- **Transaction rows.** They are ruled paper. Rules and glass are contradictory metaphors.

### Non-negotiable conditions

1. **Honour Reduce Transparency.** When it's on, every glass surface becomes opaque `surface-raised`. Check `accessibilityReduceTransparency`; do not ship glass as the only path.
2. **Contrast is measured over the worst case.** Glass takes its colour from what's behind it, and a ledger scrolling underneath is not a fixed background. If any text over glass can drop below 4.5:1, it goes on an opaque surface instead. The floor in 6.6 is not negotiable for a material choice.
3. **Use `GlassEffectContainer` whenever two glass elements are near each other.** Independent glass views stack and muddy; a container merges them into one material.
4. **Both modes.** Glass reads very differently on `Paper` than on `Carbon` — verify both at 375pt.

**Taste note:** the restraint is the point. Reference `08` and `09` in `docs/inspiration/` are the two strongest references in the folder precisely because they use one effect in one place. Glass on every surface is the iOS 26 equivalent of the 3D blobs in reference `04` — instantly dated, and it would bury the one line that matters.

## 6.6 Quality floor

**WCAG 2.1 AA is the floor, not the target.** It's the baseline every regulated finance app is now held to (the European Accessibility Act extended it to digital financial services), and a TestFlight app that can't clear it isn't a portfolio piece.

- 4.5:1 on all text, both modes. Verify, don't assume — see the token contrast floors in 6.2.
- 44×44pt minimum tap targets. The review queue's swipe actions need a tap equivalent.
- Dynamic Type to XXL. The transaction row must not truncate the amount to fit the merchant; truncate the merchant.
- Reduced motion respected. Visible focus.

**VoiceOver on every amount:** `"42 dollars 30 cents, debit, Sheng Siong"`. **The proof strip needs a real label, not a decoration role** — `"Vouched. Every figure agrees with the bank."` / `"Gap. April missing, 1,880 dollars 20 cents unaccounted."` The signature element cannot be the one thing a screen reader can't see.

**Colour is never the only signal.** Direction is carried by the `−`/`+` sign, proof state by the strip's *form* (solid / dashed / broken). Both survive greyscale and every form of colour blindness. This falls out of the design rather than being bolted on — do not regress it by, say, making the strip a solid bar in three colours.

Both modes ship at the same quality. A screen is not done until it's been looked at in Paper and Carbon at 375pt.

---

# PART 7 — BUILD ORDER

| Weekend | Deliverable | Gate |
|---------|-------------|------|
| **1** | `ParsePipeline` + `ProofEngine` Level 1, as a command-line target. Real DBS PDF in, proved `[Transaction]` printed to console. **No UI.** | **Proves or the project dies** |
| **2** | SwiftData layer + Month View + chain (Level 2) + Proof sheet. Import via Files picker | Month total matches what you know you spent, and two consecutive statements chain |
| **3** | Review queue, categorisation tiers, MerchantRule persistence + retroactive apply, Coverage view | Second month import has a shorter queue than the first |
| **4** | Share Sheet extension, manual entry, undo import, encrypted vault + export, biometric gate, TestFlight to your own device | It's on your phone |
| **5–6** | *(only after day 60)* Ask + Insights — Part 9 | You asked it something you actually wanted to know |

Weekend 1 is 60% of the risk and 20% of the work. Do not start SwiftUI before it passes.

**Both colour modes land in weekend 2**, with the token layer, before there are screens to retrofit. Two palettes cost about an hour when the tokens are semantic from the first commit and about a weekend when they aren't — build the token layer before the first `View`, and never let a hex reach a component. Visual QA in both modes is part of each weekend's gate, not a pass at the end.

**Level 2 is deliberately weekend 2, not weekend 1.** It's roughly 40 lines given the schema, and it needs two statements and a persistence layer to mean anything. Don't let its cheapness tempt you into building it before Level 1 proves — Level 1 is the gate, and a chain of unproved statements proves nothing.

---

# PART 8 — OPEN QUESTIONS

Answers go in `docs/DECISIONS.md` as you resolve them. Q1–Q3 are load-bearing for weekend 1.

1. **Does your DBS eStatement have a text layer, or is it rasterised?** Check before weekend 1 — it changes the extraction path and roughly doubles weekend 1 if it's OCR.
2. **Does DBS print stated total debits/credits, or only a closing balance?** If only the balance, Level 1 proves on the balance equation alone and the Proof sheet reads "2 of 4 checks." Still valid, weaker evidence. Verify before you build the proof UI.
3. **Does the statement print an opening balance at all?** On savings statements, yes. On card statements it's `PREVIOUS BALANCE`. If a format prints neither, Level 2 chaining is impossible for that format and you need to know that now, not in weekend 2.
4. **Credit card statements have a different template to savings statements.** Two `BankProfile`s per bank, not one. Pick which one you're doing in v1 — probably the card, since that's where the discretionary spend is.
5. **Cycle vs calendar.** Confirm your card's cycle dates. The Month View aggregates by transaction date; Coverage aggregates by statement period. Make sure you can actually get both out of one statement header.
6. **Instrument Serif** — two things. (a) Confirm SIL OFL terms cover app bundling before you build the type system around it. (b) Check it at 48pt on `Paper` as well as `Carbon`; it's a high-contrast display face and its thin strokes may not hold up dark-on-light. If it fails on Paper, the fallback is a lower-contrast serif, not a per-mode face swap.
7. **Do refunds/reversals appear as credits on a card statement, or as negative debits?** Affects both direction parsing and whether the debit-total check will ever pass.
8. **Deferred, not decided:** email-alert ingestion. It's the only real-time path available in Singapore, and it breaks both the zero-network property and the provability that make this app defensible. Revisit at day 60, not before.

---

# PART 9 — INSIGHTS (ships everywhere) & ASK (Apple Intelligence devices only)

> ## Device split, decided 1 Aug 2026 — `DECISIONS.md` D-022
>
> | Device | Chip | FoundationModels |
> |---|---|---|
> | iPhone 15 (base) | A16 | **`.unavailable`, permanently** |
> | iPhone Air | A19 Pro | `.available` |
>
> **9.5 Insights ships on both** — it is deterministic by design.
> **9.1–9.4 Ask runs only where the model exists.** Build it, gate it, never depend on it.
>
> **Build and test the unavailable path first.** On the iPhone 15 it is the only path, and TestFlight friends' devices cannot be predicted. A feature that only works on the Air does not exist for half the install base.

Natural-language questions over your own ledger. **Starts after weekend 4's gate passes, not before.**

## 9.1 Why this doesn't break the thesis

The obvious version of this feature — ship your transactions to a cloud LLM — would destroy the product. Every claim in Part 1.5 depends on data not leaving the device, and the moment this is on TestFlight you are holding other people's account numbers and card numbers.

The version that works runs entirely on-device, and it turns out to be the *more interesting* engineering anyway.

**Decided 1 Aug 2026 (`DECISIONS.md` D-009): on-device agent in Swift.** LangGraph and LangChain are Python/JS — they cannot run on iOS, and adopting them means a hosted backend, auth, key management and PDPA exposure, which converts a four-weekend project into a multi-month one and deletes the differentiator on the way. FoundationModels on iOS 26 supports native tool calling, which gives the same agent architecture — plan, call tools, synthesise — locally and free.

## 9.2 Architecture

```
Question ("where did I spend the most in July?")
   │
   ▼
FoundationModels session + registered Swift tools
   │
   ├─▶ model plans and calls tools
   │      │
   │      ▼
   │   Swift executes exact queries over SwiftData
   │   ── all arithmetic happens here, in Decimal ──
   │      │
   │      ▼
   │   structured results returned to the session
   ▼
Model composes a sentence with placeholders
   │
   ▼
Swift substitutes the figures  ──▶  Answer + provenance + proof state
```

**The single hard rule: the model never emits a number.**

It plans, it selects tools, it phrases. Every figure in every answer is computed in Swift from `Decimal` values and templated into the model's sentence. A 3B model that hallucinates `$847` instead of `$842` in a finance app is not a rough edge, it's a product-ending bug — and this architecture makes it structurally impossible rather than unlikely.

This is the same discipline as Part 3.3: deterministic where the format is stable, model only on the genuinely ambiguous part. There, the model doesn't touch amounts. Here, it doesn't touch answers.

## 9.3 The tool surface

```swift
queryTransactions(dateRange:categories:merchants:direction:minAmount:) -> [TransactionRef]
sumByCategory(period:)                                                 -> [(Category, Decimal)]
compareCategoryAcrossPeriods(category:periodA:periodB:)                -> Delta
topMerchants(period:limit:)                                            -> [(String, Decimal, Int)]
largestTransactions(period:limit:)                                     -> [TransactionRef]
newMerchantsThisPeriod(period:comparedTo:)                             -> [String]
coverageState(period:)                                                 -> ProofSummary
```

Small and closed on purpose. A tool the model can't reach is a question the app answers honestly with "I can't work that out" instead of plausibly and wrongly.

## 9.4 Proof-aware answers — the part nobody else can build

`coverageState` is called on **every** query, automatically, whether or not the question mentions it. This is not optional and not a setting.

An AI assistant over aggregator data cannot tell you whether the data behind its answer is complete, because its source has no edges (Part 1.1). Vouch can. That makes the difference between:

```
  Copilot / Monarch / any cloud tracker
  "You spent $1,204 on dining in Q2."

  Vouch
  "$1,204 on dining across 31 transactions, April–June.
   ⚠ April is a gap — this is missing roughly $1,880 of
   spending. The real figure is higher.        [ Import April ]"
```

The second answer is worth having. The first is a guess wearing a confident voice.

**Rules:**

- Every answer states the proof state of the data it drew on, in the answer itself, not in a footnote.
- An answer over any `.unvouched` or `.gap` period leads with that, before the figure.
- Every answer is tappable through to the exact rows it came from. Provenance already exists (Part 1.3) — an answer is just a query result with a sentence on top.
- If no tool fits the question, say so. Never improvise.

## 9.5 Insights — mostly not AI at all

"Where did I spend the most" is arithmetic, not intelligence. Don't burn a model call on it.

A small set of deterministic cards on the Month View: top categories, biggest month-over-month movers, largest single transactions, merchants new this month, and unusually large charges at a familiar merchant (`SHENG SIONG is usually ~$40; this one was $340`) — all computed in Swift, all instant, all exact, all working with Apple Intelligence switched off.

The model writes the sentence around them and nothing else. Most of what ships as "AI analysis" in this category is a `GROUP BY` with good copy; be honest about which parts are which.

## 9.6 Availability and degradation

| State | Behaviour |
|-------|-----------|
| Model available | Ask + Insights |
| Model unavailable | **Insights still work** — they're deterministic. Ask is hidden, with a one-line explanation |

Same principle as Part 3.5: the deterministic path is the floor, and nothing important depends on the model being there.

## 9.7 Tests

| Test | Asserts |
|------|---------|
| `testAsk_neverEmitsUngroundedNumber` | Every figure in an answer traces to a tool result |
| `testAsk_alwaysReportsProofState` | No answer renders without a coverage check |
| `testAsk_gapLeadsTheAnswer` | A query spanning a gap surfaces it before the figure |
| `testAsk_refusesOutOfScope` | No tool fits → refusal, not improvisation |
| `testInsights_noModelRequired` | All insight cards compute with the model unavailable |

---

# PART 10 — FUTURE DEVELOPMENTS

Ordered by horizon. Everything here is **after** the day-60 gate in Part 2.7 — if month two never gets imported, none of this matters and the honest move is still to archive it.

## 10.1 Near — v2, once a second bank exists

- **OCBC and UOB profiles.** The extensibility test. If bank #2 takes an afternoon, the `BankProfile` abstraction was right; if it takes a weekend, it wasn't.
- **Statement reminder.** "July's statement is usually available around 5 Aug. Not imported yet." Local notification, no network, derived from your own import history. This directly serves M1 — the only metric that matters — and it's about twenty lines.
- **Export with provenance.** CSV/JSON carrying source line, page, extraction method and proof state per row. **Nobody else can produce this file**, because nobody else has the source document. Genuinely useful at tax time and the cleanest demonstration of the whole architecture.
- **Search and filter** across the continuous ledger.

## 10.2 Medium — v3

- **Multi-account consolidated view**, with one rule that makes it worth having: **a combined figure refuses to display unless every contributing account is `.vouched` for the period.** A net position that hides rather than lies. That inverts what every other tracker does and is the natural extension of the thesis.
- **Foreign currency**, properly — the statement prints both the SGD amount and the original (`USD5.00` on the card line). Store both; report in SGD; show the original on the row detail.
- **Recurring-charge detection** from actual history rather than heuristics — with three or four vouched months you can identify subscriptions with near-certainty, and more usefully, spot the ones that changed price.

## 10.3 Long — only if it's still being used at month six

- **Community bank profiles.** A `BankProfile` is data, not code. A debug screen that dumps an unrecognised statement's structure would let anyone write a profile for their own bank and send it as a small file — no PRs, no accounts, no backend.
- **The writeup.** This was always the transferable output: self-verifying parsing anchored on a document's own published intermediate state, a four-level proof, and an on-device agent that is structurally incapable of inventing a figure. That's a substantially rarer story than "I wired an LLM to a PDF," and it's worth more than the app.

## 10.4 Parked, with reasons

| Idea | Why not |
|------|---------|
| Real-time transaction capture | Impossible on iOS in Singapore (Part 2.1). Not a roadmap item, a platform fact |
| Cloud sync / multi-device | Deletes the zero-network claim. iCloud with end-to-end encryption is the only version worth considering, and not before month six |
| Budgets, goals, forecasting | A different product. Vouch reports what happened; it doesn't tell you what to do |
| Anything social | No |
| Cloud LLM | Decided against, D-009. Revisit only if the on-device model proves genuinely insufficient — and then as an opt-in, redacted, per-query escape hatch, never as the default |

## 10.5 The failure mode to watch

Everything in Part 10 is more fun to build than weekend 3's review queue. That's exactly why it's at the end of the document and gated behind day 60.

The app that imports three consecutive months with a shrinking review queue is a success. The app with an agent, five banks and a consolidated net position that you stopped importing in month two is a failure with better screenshots.

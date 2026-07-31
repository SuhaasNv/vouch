# Vouch — cold-start handoff

**Read this first, then `SPEC.md`.** Written 1 Aug 2026 at the end of the specification phase, before any Swift was committed. If you are an agent picking this project up with no prior context, everything you need is below or linked from it.

---

## 1. What this is, in one paragraph

**Vouch** is an iOS 26 app that imports a DBS/POSB bank statement PDF and produces a categorised, *provably complete* month. The differentiator is the **Proof**: it reconciles the parsed transactions against the statement's own printed figures at four levels (row → page → statement → month-to-month chain), so it can answer a question no other personal finance app can — *"is this month complete?"* Everything runs on-device with zero network egress. One user, no backend, no accounts.

**Thesis sentence:** *Import a statement, get a month you can prove.*

---

## 2. File map — what is authoritative for what

```
CLAUDE.md ─────────────► build rules + 11 non-negotiables. Auto-loaded every session.
                         Points here and at the docs below.

docs/
├── HANDOFF.md ────────► you are here. Orientation only, never a source of truth.
├── SPEC.md ───────────► THE source of truth. Product, architecture, schema, flows, UI, AI, roadmap.
│                        Parts 1–10. If HANDOFF and SPEC disagree, SPEC wins.
├── DECISIONS.md ──────► D-001…D-021 + open questions. WHY things are the way they are.
│                        Read before re-litigating anything. Records what was measured.
├── VOCABULARY.md ─────► observed Singapore transaction vocabulary + merchant rules.
│                        Feeds BankProfile patterns and the bundled rules JSON.
└── inspiration/
    ├── README.md ─────► visual references + an explicit take/reject list.
    └── 01…05-*.png ───► the five reference kits. Present. Read the take/reject
                         list before copying anything from them.

.gitignore ────────────► protects real statements. Do not weaken.
statements_suhaas/ ────► 12 real PDFs (10 unique). GITIGNORED. Real PII. Never commit.
```

### Cross-reference graph

| If you are working on… | Read | Then check |
|---|---|---|
| The parser | `SPEC.md` 3.3 (balance-anchored) | `DECISIONS.md` D-004, **D-020** (the PDFKit grammar), `VOCABULARY.md` §1 |
| The proof engine | `SPEC.md` 1.2, 3.6 | `DECISIONS.md` D-004, D-015, D-018 |
| Data schema | `SPEC.md` Part 4 | `DECISIONS.md` D-005 (dedupe), D-006 (dates), D-018 (currency) |
| Categorisation | `SPEC.md` 3.7 | `VOCABULARY.md` §2–4, `DECISIONS.md` D-011, D-012, D-016 |
| Any UI screen | `SPEC.md` Part 6 | `inspiration/README.md`, `DECISIONS.md` D-008, D-016 |
| Colour / type tokens | `SPEC.md` 6.2 | — |
| Import flow | `SPEC.md` 5.2 | `DECISIONS.md` D-003, D-010, D-015 |
| Encryption / vault | `SPEC.md` 3.8 | `DECISIONS.md` D-010, D-014 |
| The AI feature (v1.5) | `SPEC.md` Part 9 | `DECISIONS.md` D-009 |
| "Should we add X?" | `SPEC.md` 2.4 non-goals | `DECISIONS.md` D-009, D-013, D-014 — the answer is usually already no |

---

## 3. What has been PROVEN on real data

This is not speculation. All of it was measured on 10 real statements during the spec phase. **Do not re-derive it; do not contradict it without new measurement.**

### The proof works — 10 consecutive months, Sep 2025 → Jun 2026

`Balance Brought Forward − withdrawals + deposits == Balance Carried Forward` held **exactly** on all 10 months. Every closing balance equalled the next opening balance, **zero drift**. Sep 2025 opens at `0.00` — the account's origin, so the entire history is provable end to end. 817 transactions, 13 account-currency sections, all PASS.

### The PDFKit grammar (D-020) — build against this, not the Python exploration

PDFKit lays out text differently from pdfplumber. **Verified by running real Swift:**

```
31/05/2026 Advice Point-Of-Sale Transaction or Proceeds     ← date + type label
NETS QR PAYMENT 615108253775961                             ← description lines
TO: E COFFEE 826A
VALUE DATE : 01/06/2026
2.50 1,434.19                                               ← amount + balance, own line
```

```
TRANSACTION := DATE_LINE DESC_LINE* AMOUNT_LINE
DATE_LINE   := ^DD/MM/YYYY <typeLabel>$
DESC_LINE   := matches neither of the others
AMOUNT_LINE := ^<amount> <balance>$        ← ALWAYS exactly 2 numbers

direction   := balance < prevBalance ? .debit : .credit
amount      := |balance − prevBalance|     cross-checked vs parsed <amount>
```

**The single most important measured fact: every number-only line is exactly two numbers — 95 of 95 in one statement.** A deposit (`1,490.00 1,547.27`) is structurally identical to a withdrawal (`2.50 1,434.19`). **PDFKit discards the column that says which direction money moved.** The running balance is the only surviving signal, which makes the balance-delta derivation mandatory, not optional.

### Other measured facts

| Fact | Source |
|---|---|
| Statements have a **text layer**. Vision OCR is a fallback, not the path | D-015 |
| Statements are **owner-locked only** — open with an empty password. Try `""` before prompting | D-015, D-020 |
| Stated totals ARE printed: `Total Balance Carried Forward in SGD: <w> <d> <closing>` → **4 of 4 checks** | D-015 |
| One PDF = **multiple accounts AND multiple currencies**. Proof unit is `(account, currency)` | D-018 |
| **28% of rows are ~$0.50 vending machines worth 1.8% of value** → rows must collapse in the UI | D-016 |
| Payment aggregators (`FOMO PAY`, NETS QR) are **12% of rows and uncategorisable by design** | D-012 |
| No refund/reversal exists in 817 transactions. Handle defensively, don't design around a guess | D-019 |
| December has an interest **summary block** with numbers that must be ignored, not parsed | D-019 |

---

## 4. The 11 non-negotiables

Violating any of these breaks the product, not just a test. Each one exists because of something measured — the `DECISIONS.md` entry in brackets is the evidence.

*(A local `CLAUDE.md` carries the same rules with build-command detail. It is deliberately not in the repo; this section is self-sufficient without it.)*

1. **The proof is sacred** — never widen a tolerance to make a check pass. `Decimal`, exact equality.
2. **The model never touches the totals** — balances and stated totals are regex-only.
3. **No networking code in the target** — absent, not disabled.
4. **`rawDescription` / `sourceLineText` never mutated.**
5. **Never silently drop or invent a row.** No "balance adjustment" escape hatch.
6. **Violet means proved** — `accent` is the proof strip and primary action only.
7. **No hex in a component** — semantic tokens resolving per mode (Paper/Carbon).
8. **Anchor on the balance column** — two independent derivations, never collapsed into one.
9. **`dedupeKey` includes `balanceAfter`** — real data has six identical rows in one day (D-005).
10. **The model never emits a number** — Swift computes, model phrases.
11. **Never store a decrypted PDF** — vault holds the bank's original encrypted bytes.

---

## 5. Stack — decided, see `SPEC.md` 3.2

Swift 6 strict concurrency · SwiftUI · SwiftData · PDFKit · Vision (fallback) · Swift Regex · CryptoKit · LocalAuthentication · FoundationModels (v1.5) · XCTest.

**Zero third-party dependencies. No backend. No Postgres, Redis, or Railway (D-013). No OAuth (D-014). No OpenAI/LangChain (D-009).** Running cost: $99/yr Apple Developer Program.

---

## 6. Where the build actually is

**Nothing is committed yet.** No Swift package, no Xcode project. The spec phase is complete and the risky assumptions are retired.

### Next step: weekend 1 (`SPEC.md` Part 7)

A SwiftPM package — library + CLI target + tests. **No UI.** Real PDF in, proved `[Transaction]` printed to console.

1. **`Redactor` first** — strips name / account no. / card no. at *identical length* so column positions and regex behaviour are unchanged. Golden fixtures must never contain real PII (D-007).
2. `BankProfile` for DBS/POSB savings.
3. `TextLayer` — PDFKit extraction, try empty password first.
4. `ParsePipeline` — the grammar in §3, segmenting by account then currency then page.
5. `ProofEngine` — Levels 0/1/2.
6. Tests against all 10 statements + `testDedupe_sixIdenticalRowsSurvive` + `testFixturesContainNoPAN`.

**Gate: it proves, or the project dies.** That gate is already substantially satisfied by the measurements in §3 — this is a port, not an exploration.

### Toolchain — verified 1 Aug 2026

**Xcode 26.6 installed and active.** iOS 26.5 SDK, iOS 26.5 simulators (iPhone 17 Pro / Pro Max). SwiftUI, SwiftData, PDFKit and FoundationModels all confirmed to compile against `iphonesimulator26.5`.

Everything is drivable from the command line — `swift build`, `swift test`, `xcodebuild`, `xcrun simctl` (boot / install / launch / **screenshot**). Xcode.app itself is only needed for live Previews, the view debugger, Instruments, and TestFlight signing.

### Target devices — `DECISIONS.md` D-022

| Device | Chip | FoundationModels |
|---|---|---|
| iPhone 15 (base) | A16 | **`.unavailable`, permanently** |
| iPhone Air | A19 Pro | `.available` |

**Build and test the model-unavailable path first, and check every feature on the iPhone 15 before calling it done.** Parsing, all four proof levels, categorisation tiers 1–2 and Insights are unaffected by model availability — by design.

A useful trick proven during the spec phase: **SwiftUI renders headlessly to PNG via `ImageRenderer`** — no Simulator required — which makes design iteration possible from a CLI target. Note `MainActor.assumeIsolated` is needed under Swift 6 strict concurrency.

---

## 7. Open items, in priority order

| # | Item | Notes |
|---|---|---|
| — | **July 2026 statement missing** | Not blocking. It's a live fixture for the gap detector — a real unforced example of the condition no competitor can detect |
| Q7 | Refunds/reversals — Deposit column or negative Withdrawal? | Unseen in 817 transactions |
| Q12 | Interest / fee / GST transaction rows | Unseen. Only summary text blocks exist |
| Q13 | `DBS VISA DEBIT CASHBACK` → `Income` or spend offset? | Decide once, apply consistently |
| Q14 | `ATM Transaction` → `Transfers` | Strongly implied; categorising as spend double-counts cash |
| Q6b | Instrument Serif at 48pt on `Paper` (dark-on-light) | Visual check. OFL licensing already cleared |
| — | Category list still provisional | Fix it after 3 months of real imports (D-011). `Education` already cut — zero rows in 10 months |

---

## 8. Traps that will bite you

- **Never trust a filename.** Real files were misnamed by a month and two pairs were byte-identical duplicates. Period comes from the `as at` header; identity comes from `sourceHash` (D-017).
- **`Balance Brought Forward` appears per *page* AND per *account section*.** Reading "first B/F, last C/F" mixes two accounts and makes a perfectly good chain look broken. This mistake was made during analysis — see D-015.
- **Never hardcode `SGD`.** A USD account section exists and was silently skipped by every early analysis pass (D-018).
- **Don't collapse duplicate rows in storage.** Six identical $0.50 vending charges in one day are six real transactions. Group them in the *view* only (D-005, D-016).
- **Investigate parser anomalies, don't filter them.** The one row that revealed an entire hidden currency account was 0.12% of the data (D-018).
- **A 150-screen design kit will smuggle scope in through the mockups.** Cross-check `SPEC.md` 2.4 before building any screen (`inspiration/README.md`).

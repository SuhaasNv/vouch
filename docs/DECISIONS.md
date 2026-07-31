# Decision Log

Answers to `docs/SPEC.md` Part 8, plus anything else decided during the build that the spec doesn't already say.

**Rules for this file:**
- One entry per decision. Date it. Say what you actually observed, not what you assumed.
- A decision that changes the spec gets recorded here *and* the spec gets edited. This file is not a second source of truth.
- "Still unknown" is a valid entry. Write it down so you don't re-investigate it in three weeks.

---

## D-001 · Name locked: Vouch — 31 Jul 2026

Alternatives Tickmark / Attest / PaperTrail declined. Bundle display name and Swift module name at project creation.

## D-002 · v1 target: DBS/POSB savings account — 31 Jul 2026

Savings profile first, not credit card. Calendar-month periods, no cycle-vs-calendar trap in v1. `BankProfile(bankCode: "DBS", accountType: .savings)`. Card profile becomes the second fixture, P1.

---

## D-003 · Source document is the monthly eStatement, NOT Transaction History — 31 Jul 2026

Two DBS documents were compared. They are not interchangeable.

| | Transaction History export | **Monthly eStatement** |
|---|---|---|
| Period opening balance | No | **`Balance Brought Forward`** |
| Period closing balance | No | **`Balance Carried Forward`** |
| Running balance per row | No | **Yes, every row** |
| Withdrawal / Deposit columns | No — one signed amount | **Yes, two separate columns** |
| Balance figures present | `Available` / `Ledger`, as of *today* — unrelated to the period | Period-correct |
| Level-1 checks available | **0 of 4** | **4 of 4, plus per-row** |

**Decision:** v1 imports the eStatement only. The Transaction History export cannot support the Proof and is not an input.

**Correction to a round-1 answer:** "rasterised" was judged from a screenshot of the PDF, which is an image by definition. The eStatement renders as clean vector text. **Vision OCR drops back to a genuine fallback**, as originally specced. Weekend 1 is back to its original scope.

---

## D-004 · The balance column makes the proof per-row — 31 Jul 2026

**This is the most important finding in the project and it upgrades the product.**

The eStatement prints a running balance on every row. Verified against a real June 2026 page: `Balance Brought Forward 1,112.39` → 15 transaction rows → `Balance Carried Forward 863.70`, and **every intermediate balance reconciles exactly**. Zero drift across 15 rows.

Consequences:

1. **Proof gains a Level 0 — per row.** `balance[n] == balance[n−1] − withdrawal[n] + deposit[n]` for every n. The proof no longer says "something is wrong across 87 rows", it says "row 43 is wrong."
2. **Amount and direction are derivable twice, independently.** Once from the Withdrawal/Deposit cells, once from the balance delta. Agreement → confidence 1.0. Disagreement → that exact row is flagged. A self-verifying parse.
3. **The model is now barred from amounts entirely** — not by policy, but because it's unnecessary. Arithmetic does it better.
4. **Pages chain too.** Every page ends `Balance Carried Forward` and the next begins `Balance Brought Forward` with the same figure. A dropped *page* is caught, not just a dropped row.

The proof is now four levels: row → page → statement → month-to-month chain.

## D-005 · The v0.2 dedupe key was silently lossy — fixed — 31 Jul 2026

**Found while reading the Transaction History export.** It contained **six identical rows**: `BAT LE TACH VENDING SINGAPORE ... SGD - 0.50`, same date, same merchant, same amount.

The spec's `dedupeKey` was `date + amount + first 20 chars of normalizedMerchant`. Those six rows produce **one key**. Five real transactions would have been silently discarded — the exact failure the entire product exists to prevent, hiding inside the deduplication logic.

**Decision:** `dedupeKey = accountID + postedDate + balanceAfter`. The running balance is what makes each row unique; six identical vending charges leave six different balances behind them. Where a statement has no balance column, fall back to `accountID + postedDate + amount + rowIndexWithinStatement`.

**Consequence:** `SPEC.md` Part 4 updated. New test `testDedupe_sixIdenticalRowsSurvive` using this real case as a fixture. This one is worth writing up — it's a good example of a correctness bug that only surfaces when you look at real data.

## D-006 · Month View keys on transaction date; proof keys on posting date — 31 Jul 2026

Rows carry both. `03/06/2026 | KOPITIAM @ LAU PA SAT SI SGP 30MAY` — posted 3 June, spent 30 May.

**Decision:** the embedded transaction date drives the Month View; the `Date` column (posting date) drives statement-period membership and the proof. Store both.

**Why:** you spent it on 30 May, and a tracker that files it under June is wrong in the way users notice. But the bank's arithmetic runs on posting date, so the proof must too.

## D-007 · Golden fixtures must be redacted before commit — 31 Jul 2026

The statement prints the full card number `4628-4507-6331-7741` on every debit-card row, plus account number `272-647965-3` and full legal name.

**Decision:** no fixture is committed without a redaction pass. Replace name, account number and card number with dummy values of **identical length and shape** so column positions and regex behaviour are unchanged. Keep every amount, date and balance real.

**Consequence:** write the redactor before the first fixture. `testFixturesContainNoPAN` greps the fixture directory for card-number and NRIC shapes and fails the suite. Cheap, and it's what stops a 2am commit putting a card number in git history permanently.

## D-008 · One continuous ledger, not month silos — 31 Jul 2026

**User decision.** Transactions render as a single continuous table across all months with sticky month headers, mirroring the statement's own layout including the running balance column. The month is a scroll anchor and a filter, not a wall.

**Why it's the right call:** overlapping statement uploads become a non-event — rows merge into one ordered ledger and D-005's key resolves duplicates. It also means the app's list can be checked against the paper statement line by line, which is very on-thesis.

## D-009 · AI stack: on-device agent in Swift, not OpenAI + LangGraph — 1 Aug 2026

**Question:** OpenAI + LangChain/LangGraph was requested for an agentic Ask feature.

**What I checked:** LangGraph/LangChain are Python/JS — no iOS runtime, so adopting them requires a hosted backend, auth and key management. Apple's FoundationModels on iOS 26 supports native tool calling with framework-guaranteed structural correctness of tool calls. Context window is **4,096 tokens** (`contextSize` / `tokenCount(for:)` APIs added in 26.4). ~3B model benchmarking above Phi-3-mini, Mistral-7B, Gemma-7B and Llama-3-8B; 0.6ms time-to-first-token, ~30 tok/s on iPhone 15 Pro. Apple states it is built for summarisation, entity extraction and text understanding — **explicitly not a general-knowledge chatbot.**

**Decision:** on-device agent in Swift. Cloud LLM rejected for v1.5.

**Reasoning:**
- Sharing to 3–5 friends is still planned, so any cloud path means exporting other people's full name, account number and unmasked card number offshore. Real PDPA obligation, not a formality.
- The 4,096-token window makes the naive approach impossible anyway — a single month is 87+ transactions and would not fit. The tool architecture in Part 9.2 isn't a preference, it's the only design that works, and it happens to reduce the model's job to exactly what Apple built the model for.
- The model's remaining job — route a question to one of 7 tools, phrase one sentence — is entity extraction plus short generation. The frontier-model gap barely applies to a task this narrow.
- No round trip means on-device is likely **faster** here than a cloud call, not slower.

**Consequence:** `SPEC.md` Part 9. Non-goal in Part 2.4 amended. **Define a `LanguageBackend` protocol** so the provider is a single conformance — this keeps the decision reversible at near-zero cost if on-device measurably fails on real questions.

**Where on-device is genuinely weaker, tracked honestly:**

- **Raw capability.** 3B vs frontier is a real gap (MMLU ~68% vs high-80s). The argument for on-device is that the *task* is narrow, not that the models are comparable.
- **Multi-turn conversation.** 4,096 tokens is the whole transcript, and tool definitions consume ~800 before the first word. A flowing back-and-forth hits the ceiling after a handful of exchanges. **Design Ask as one-shot Q&A, not a chat.** If a real conversation is ever the requirement, that is the point to revisit the cloud escape hatch.
- **Compound questions** ("dining in months I travelled") and unusual phrasing.
- **World knowledge for unseen merchants** — `RTL_USS_THEDINOSTORE` → Universal Studios. Decays fast; by month three the override table handles nearly everything (Part 3.7).

**This decision is a prediction, not a measurement. Validate it before building Part 9 out:**

Write 20 questions you would genuinely ask your own finances. Build the on-device agent (~2 days; the `LanguageBackend` protocol means the work survives either outcome). Score how many route to the correct tool *and* phrase the result correctly.

| Result | Action |
|--------|--------|
| ≥ 18/20 | On-device is settled. Close this decision |
| 14–17/20 | Fix the tool surface or the instructions first — a bad route is usually a bad tool boundary, not a weak model |
| < 14/20 | The prediction failed. Revisit the opt-in redacted cloud escape hatch, with D-009's PDPA constraints still binding |

Record the actual score here when it exists. A decision this load-bearing should not stay a guess.

## D-010 · Statements are archived, not discarded — 1 Aug 2026

**User requirement:** statements stored securely, re-downloadable.

**Decision:** store the **bank's original encrypted bytes, byte-identical**, in a `.completeFileProtection` vault. Never store a decrypted copy; decrypt in memory per view/export. Export shares the original, still password-protected.

**Why this shape:** two independent encryption layers (bank password + device passcode/Secure Enclave), `sourceHash` still verifies the archive against the ledger, and there is no code path that manufactures an unprotected financial document.

**Consequence:** `SPEC.md` Part 3.8 rewritten; `StatementImport` gains `vaultFilename`, `fileSizeBytes`. Reverses v0.2's "parse and discard".

## D-011 · Category list is derived from real data, then fixed — 1 Aug 2026

**Decision:** the 12 categories in Part 3.7 are **provisional** until `docs/VOCABULARY.md` holds three months of real statements. Tally what actually appears, fix the list, then constrain the model with `@Guide(.anyOf(...))`.

**Why:** the list was written before any data existed. Fixing it still matters — a constrained enum is what stops the model inventing categories — it just shouldn't be fixed on a guess. A category capturing <1% of rows over three months is noise in the picker; cut it.

**Consequence:** `docs/VOCABULARY.md` created as the living data file. Open questions recorded there: transit vs transport, vending/incidentals, and Singapore-specific candidates (CPF, Insurance, Rent, Hawker).

## D-012 · Payment aggregators are uncategorisable by design — 1 Aug 2026

**What I checked:** the June statement contains `Advice FAST Payment / Receipt · PAYNOW TRANSFER · TO: FOMO PAY PTE. LTD. · SGD 0.50`.

FOMO Pay is a payment service provider. When you pay a hawker or small merchant by QR, the statement records **the processor, not the merchant**. The information about what was bought does not exist in the document. This is more common in Singapore than most markets.

**Decision:** maintain an explicit aggregator list (`FOMO PAY`, `LIQUID PAY`, `NETS`). Those rows route straight to the review queue labelled *"Payment processor. The original merchant isn't on the statement."* **The model is never asked to guess a category for them** — a confident wrong answer here is precisely the trust-destroying behaviour the product exists to prevent.

**Consequence:** `docs/VOCABULARY.md` §3.

## D-013 · No backend. No Postgres, no Redis, no Railway — 1 Aug 2026

**Question:** should the DB / cache / hosting live on Railway?

**Scale, computed from the real June statement** (12 pages × ~15 rows):

| | |
|---|---|
| Transactions per month | ~180 |
| Per year | ~2,160 |
| **After ten years** | **~21,600 rows ≈ 12 MB** |
| PDF vault, ten years | ~60 MB (120 statements) |

A decade of complete financial history is smaller than one photo from the phone that took it. SQLite answers indexed queries over 21,600 rows in well under a millisecond.

**Decision:** SwiftData on device, full stop. There is no server component in this product.

**Why each piece is rejected:**

| Component | Why not |
|-----------|---------|
| Postgres / hosted DB | The dataset is 12 MB after ten years. SQLite is not a compromise here, it's correct |
| **Redis** | Caches exist to avoid expensive repeated work under concurrency. There is one user, no concurrency, and no query slow enough to cache. Serialising to a cache would cost more than recomputing |
| Railway / any host | Buys nothing user-visible, and costs: a bill, auth, key management, a deploy pipeline, uptime, **network code in the binary** (kills 3.8), and PDPA liability the moment a friend uses it |
| Job queue / workers | Parsing one PDF takes seconds on-device and is inherently interactive. There is no background work to queue |

**The load-bearing point:** the moment a backend exists, G4 dies, the Part 1.5 positioning dies, and the four-weekend build order becomes fiction. Every claim that makes this product defensible depends on there being nothing to host.

**When a backend would genuinely be justified — and what it should be:**

- **Multi-device sync.** The answer is **CloudKit private database**, not Railway. End-to-end encrypted, free, Apple-native, and Apple cannot read it either — so the privacy claim survives, restated honestly. Not before month six.
- A web version, or the cloud-LLM path rejected in D-009. Neither is on the roadmap.

**On the portfolio argument:** adding infrastructure a problem doesn't need reads as a *negative* signal to a senior reviewer — it shows the instinct to reach for tooling before understanding scale. "I shipped zero backend, here is the arithmetic showing why" is the stronger story. If Railway/Postgres/Redis experience is the goal, build it where the problem actually calls for it — the separate agentic project floated in D-009 is the natural home.

## D-014 · No Google Sign-In, no OAuth, no accounts — 1 Aug 2026

**Question:** should authentication use Google?

**The category error worth naming:** authentication answers *"who are you?"* **to a server**. Vouch has no server (D-013). There is nothing to authenticate to. What the app needs is a **lock on local data**, not an identity — and the lock is already specced and is strictly stronger.

**Decision:** LocalAuthentication (Face ID, passcode fallback) + `.completeFileProtection`. No OAuth provider, no account system, no login screen.

**Why Google Sign-In would be worse, not just unnecessary:**

| Dimension | Effect |
|-----------|--------|
| Security | **Adds none.** OAuth is an identity assertion, not a key. It encrypts nothing; at-rest protection stays exactly as it was |
| Availability | Requires network. **No internet → cannot open your own archived statements.** Unacceptable failure mode for an offline app |
| Dependencies | GoogleSignIn SDK links `URLSession`, breaking the zero-dependency and "no networking code in the binary" properties (3.8) |
| Privacy | Creates a third-party record that this user runs a finance app |

**What we have instead:** the store key is derived from the device passcode and held in the Secure Enclave. While the device is locked the database is *cryptographically inaccessible*, not merely permission-denied. Face ID gates launch and foreground return.

**The cases that look like they need auth, and don't:**

- **Multi-device sync** → CloudKit, using the Apple ID already on the device. Zero auth UI, end-to-end encrypted. Google would require a backend to sync *to* — D-013 again.
- **Recovery** → nothing to recover. Data is local, backed up by encrypted iCloud device backup, and the bank re-issues the source PDFs indefinitely.
- **Friends on TestFlight** → each has their own device and their own local store. No shared server, so no shared identity.

**If identity is ever genuinely required**, it is Sign in with Apple, not Google — and it would be the only network call in an app whose pitch is that it makes none. Revisit only alongside a decision that already introduces a server.

## D-015 · The weekend-1 gate PASSED on real data, before any Swift — 1 Aug 2026

*Extended to 10 statements the same day.* **Every load-bearing assumption in Part 1 held, across the account's entire history.**

**Level 1 — exact on all 10 months, SGD:**

| period | B/F | withdrawn | deposited | C/F | |
|--------|----:|----------:|----------:|----:|---|
| Sep 2025 | **0.00** | 1,202.32 | 1,512.30 | 309.98 | PASS |
| Oct 2025 | 309.98 | 1,130.50 | 1,006.45 | 185.93 | PASS |
| Nov 2025 | 185.93 | 185.22 | 7.00 | 7.71 | PASS |
| Dec 2025 | 7.71 | 178.26 | 286.59 | 116.04 | PASS |
| Jan 2026 | 116.04 | 1,806.69 | 2,699.40 | 1,008.75 | PASS |
| Feb 2026 | 1,008.75 | 398.58 | 4.51 | 614.68 | PASS |
| Mar 2026 | 614.68 | 790.96 | 1,500.00 | 1,323.72 | PASS |
| Apr 2026 | 1,323.72 | 495.74 | 30.10 | 858.08 | PASS |
| May 2026 | 858.08 | 957.75 | 1,536.36 | 1,436.69 | PASS |
| Jun 2026 | 1,436.69 | 1,959.46 | 1,301.50 | 778.73 | PASS |

**Level 2 — nine consecutive links, zero drift**, Sep 2025 → Jun 2026.

**Sep 2025 opens at 0.00 — the account's origin.** This is the `.head` case in Part 1.2, and it means the entire life of the account is provable end to end. A complete, unbroken, arithmetically verified financial history with no missing periods.

817 transactions parsed across the 10 statements. **13 account-currency sections proved, all PASS** (see D-018).

**Open questions resolved:**

| # | Question | Answer |
|---|----------|--------|
| Q1b | Text layer? | **Yes.** Clean vector text. **Vision OCR is a genuine fallback, not the path.** The earlier "rasterised" reading was from a screenshot |
| Q2b | Stated totals printed? | **Yes** — `Total Balance Carried Forward in SGD: <withdrawals> <deposits> <closing>`. **All 4 Level-1 checks available** |
| Q3b | B/F and C/F present? | **Yes**, per account *and* per page |
| Q5b | Running balance per row? | **Yes**, every row |
| Q11 | Does text extraction preserve the Withdrawal/Deposit columns? | **No — they collapse.** A row yields two numbers with no way to tell which column the first came from. **The balance-delta derivation (3.3) is therefore load-bearing, not merely elegant** |

**Also:** the statements are **owner-locked only — they open with an empty user password.** The import flow should try `""` first and prompt only on failure, so the common case needs no password prompt. Keep the prompt path for other banks and download routes.

## D-016 · Micro-transactions dominate by count, vanish by value — 1 Aug 2026

Measured across 499 transactions, Feb–Jun:

| Bucket | Rows | % rows | Value | % value |
|--------|-----:|-------:|------:|--------:|
| Vending machines | 140 | **28.1%** | SGD 83.30 | **1.8%** |
| BUS/MRT transit | 71 | 14.2% | SGD 297.21 | 6.5% |
| Everything else | 288 | 57.7% | SGD 4,221.98 | 91.7% |

`LE TACH VENDING` alone is 118 rows — nearly a quarter of everything — at roughly SGD 0.50 each.

**This is a UI problem, not a taxonomy problem, and it invalidates two design assumptions:**

1. **The review queue would be swamped.** 140 rows the user does not care about. **Rule:** once a merchant has N confirmed rows and an active `MerchantRule`, stop queueing it entirely regardless of confidence.
2. **The transaction list is 28% noise.** **Decision: collapse consecutive same-merchant same-day rows into one expandable group** — `LE TACH VENDING × 6 · −3.00 ›`. Every row still exists, is still counted, still proves; the list just stops being unreadable. **Never merge the underlying rows** — that is D-005's mistake in a different costume.
3. The category bar is already value-weighted, which is correct. **Never offer a count-weighted breakdown** — by count this user's finances look like a vending machine habit.

**Consequence:** `SPEC.md` Part 6.3 gains row grouping. Part 3.7 gains the merchant-confidence rule.

## D-017 · The statement set is Jan–Jun; July missing, May duplicated — 1 Aug 2026

Verified by SHA-256 over the supplied files:

- `may_ Statement.pdf` and `jun_Statement.pdf` are **byte-identical** (`fbd96ca33aa6…`). One upload, two names.
- Filenames are offset from content. Truth is the `as at` header: `jul_Statement.pdf` is the **June** statement (`as at 30 Jun 2026`).
- Actual coverage: **January – June 2026. July is absent.**

**Both detection mechanisms fired on real data before any code existed:**

- `sourceHash` idempotency (R10) catches the duplicate — the second import would be a no-op.
- The Level 2 chain would flag a missing month independently.

**Never trust the filename.** Period comes from the `as at` header, always. Identity comes from `sourceHash`, always.

## D-018 · Statements are multi-currency. The proof unit is (account, currency) — 1 Aug 2026

**Found by chasing a parser anomaly.** A row typed `Advice` in October looked like a regex misfire. It wasn't:

```
Balance Brought Forward USD 0.00
15/10/2025 Advice 196.20 196.20
0352 FT251015WP00504749
WHOOP
Total Balance Carried Forward in USD: 0.00 196.20 196.20
```

**There is a USD-denominated section.** Every earlier analysis had regex'd on `SGD` explicitly and silently skipped it — the results were correct but incomplete, which is precisely the failure mode this product exists to prevent, occurring in the analysis of the product.

**The USD account chains too:**

| period | ccy | B/F | withdrawn | deposited | C/F | |
|--------|-----|----:|----------:|----------:|----:|---|
| Oct 2025 | USD | 0.00 | 0.00 | 196.20 | 196.20 | PASS |
| Nov 2025 | USD | 196.20 | 0.00 | 0.00 | 196.20 | PASS |
| Dec 2025 | USD | 196.20 | 196.20 | 0.00 | 0.00 | PASS |

**Decision: the proof unit is `(account, currency)`, not `account`.** A currency section has its own B/F, its own totals, its own C/F, and its own chain. Never convert; never aggregate across currencies inside the proof.

**Consequences:**
- `StatementImport` gains `currencyCode`. Unique index becomes `(sourceHash, accountID, currencyCode)`.
- `Account` may have several currency sections; the chain walk partitions on currency.
- Anchors are `Balance Brought Forward <CCY> <amt>` and `Total Balance Carried Forward in <CCY>:` — **parse the currency, never hardcode SGD.**
- Part 10.2's "multi-currency, properly" is no longer a future item. It's in the data now.
- The Month View's SGD total must **exclude** foreign-currency sections rather than adding them at some invented rate. A converted figure is not a proved figure.

**Lesson worth keeping:** the anomaly was 1 row in 817 (0.12%). It was a whole account. Investigate parser oddities rather than filtering them — this is exactly why `rejectedLineCount` is surfaced rather than swallowed (3.3).

## D-019 · Interest and fees exist as text blocks, not transactions — 1 Aug 2026

Resolves Q12. Across 817 transactions in 10 months there are **no interest, fee, or GST transaction rows.** But December carries a year-end summary block:

```
Messages For Total Interest For Current Year
(A) Total Credit Interest 0.00
(B) Total Debit Interest 0.00
Total Interest Adjustment For Current Year
```

**These lines contain numbers and must be in `ignorePatterns`.** A parser looking for "text then amount" will happily invent transactions from them. `Service Charge for Savings Accounts` and `Cheque Issuance Fee` also appear — as marketing notices about waivers, not charges.

**Q7 (refunds/reversals) remains unanswered after 817 transactions.** Ten months with no refund is strong evidence this account simply doesn't have one yet. Handle defensively; do not design around a guess.

**Also identified:** `Advice Advice` type with description `CASA NTB PROMO` — an 18.00 new-to-bank promotional credit. Real type label, not a parse error.

## D-020 · PDFKit's layout differs from pdfplumber — and it settles the architecture — 1 Aug 2026

**Verified by running real Swift against the real statements** (Swift 6.3.2, PDFKit, macOS CLI).

PDFKit opens the statements with **no password** (`isEncrypted: true, isLocked: false`) — confirming the owner-lock finding on the real API, not just in Python.

But it lays text out completely differently. pdfplumber puts date, type, amount and balance on one line. **PDFKit puts the amounts last, on their own line, after the description block:**

```
31/05/2026 Advice Point-Of-Sale Transaction or Proceeds     ← date + type
NETS QR PAYMENT 615108253775961                             ← description
TO: E COFFEE 826A
VALUE DATE : 01/06/2026
2.50 1,434.19                                               ← amount + balance
```

**The decisive measurement: every number-only line in the January statement is exactly two numbers. 95 of 95, no exceptions.** A deposit renders `1,490.00 1,547.27`; a withdrawal renders `2.50 1,434.19`. **They are structurally indistinguishable.**

**This closes Q11 and settles the architecture.** PDFKit's extraction discards the column that says whether money came in or went out. The running balance is the only surviving signal. So the balance-delta derivation in 3.3 is not an optimisation or an elegance — **without it, direction is unrecoverable and the statement is unparseable.** D-004 was load-bearing and is now proven so on the real API.

**The grammar is therefore:**

```
TRANSACTION := DATE_LINE DESC_LINE* AMOUNT_LINE
DATE_LINE   := ^DD/MM/YYYY <typeLabel>$
DESC_LINE   := anything matching neither of the others
AMOUNT_LINE := ^<amount> <balance>$          (always exactly 2 numbers)

direction   := balance < prevBalance ? .debit : .credit
amount      := |balance − prevBalance|       cross-checked against parsed <amount>
```

Clean, deterministic, self-verifying, and it segments variable-height rows for free.

**Also newly visible under PDFKit:** `VALUE DATE : DD/MM/YYYY` lines, and the B/F line carries a date prefix (`31/05/2026 Balance Brought Forward SGD 1,436.69`). Neither appeared in the pdfplumber output. **Build the parser against PDFKit output, never against the Python exploration** — the Python work proved the data, not the parsing.

## D-021 · Xcode is not needed for weekend 1 — 1 Aug 2026

| Phase | Toolchain | Status |
|-------|-----------|--------|
| Weekend 1 — `ParsePipeline` + `ProofEngine`, CLI target | Swift 6.3.2 CLT + SwiftPM + PDFKit | **Available now.** Verified by running real code against real statements |
| Weekends 2–4 — SwiftUI, SwiftData, simulator, TestFlight | **Xcode required** | Only Command Line Tools installed. ~15 GB from the App Store |
| TestFlight | Apple Developer Program | ~USD 99/yr, needed at weekend 4 |

**Weekend 1 can start immediately.** Install Xcode before weekend 2, not before weekend 1 — which conveniently matches the build order's own instruction not to touch SwiftUI until the pipeline proves.

## D-022 · Two target devices, split on Apple Intelligence. Both paths are first-class — 1 Aug 2026

The user has **two** devices, and they land on opposite sides of the Apple Intelligence line:

| Device | Chip | Apple Intelligence | FoundationModels |
|--------|------|-------------------|------------------|
| iPhone 15 (base) | A16 Bionic | **No** — requires A17 Pro or newer | `.unavailable`, permanently. Silicon, not software |
| iPhone Air | A19 Pro | **Yes** | `.available` |

iOS 26 runs on both, so the deployment target is unaffected.

**Decision: Part 9 (Ask) stays on the roadmap** — it runs on the Air. **But the unavailable path is built and tested first**, because on the iPhone 15 it is the only path.

**This is a better position than having one eligible device.** Most developers have to simulate the degraded path and it rots untested. Here both configurations exist on real hardware, so `SPEC.md` 3.5's promise — *"the app still works, just with more taps"* — gets verified for real rather than assumed. It also matters for the TestFlight friends in Part 2.2, whose devices will vary and cannot be predicted.

**Testing rule: every feature is checked on the iPhone 15 before it is called done.** If it only works on the Air, it is a feature that does not exist for half the install base.

### What this does and does not break

| | Status on iPhone 15 |
|---|---|
| PDF text extraction, parsing | **Unaffected** — PDFKit + Swift Regex |
| Amount and direction | **Unaffected** — balance arithmetic, never the model (D-004, D-020) |
| All four proof levels | **Unaffected** — pure `Decimal` |
| Categorisation tier 1 (user overrides) | **Unaffected** |
| Categorisation tier 2 (bundled SG rules) | **Unaffected** |
| Insights cards (`SPEC.md` 9.5) | **Unaffected** — specced as deterministic from the start |
| Categorisation tier 3 (model, unseen merchants) | **Unavailable** |
| Ask, the conversational feature (Part 9.1–9.4) | **Unavailable** |

**Decision: `SPEC.md` 9.5 Insights is promoted ahead of 9.1–9.4 Ask.** Top categories, biggest month-over-month movers, largest transactions, new merchants, and unusual-amount detection at a known merchant — all `GROUP BY` and arithmetic, all instant, all exact, all working on an A16. This was always where most of the perceived value of "AI analysis" lived. Ship it first, on both devices; Ask follows on the Air.

**Tier 3's loss is small and measurable.** Across 817 real transactions roughly 30 merchant patterns cover the overwhelming majority (`VOCABULARY.md` §2), and the top four alone — vending, transit, PayNow, NETS QR — are over half of all rows. Tiers 1 and 2 were always going to carry this; the spec itself predicted the model would "barely run by month three."

### The wider point

This retroactively validates three earlier decisions that were made on correctness grounds and turn out to be hardware-compatibility ones:

- **The model never touches numbers** (3.4, D-004) → parsing is fully intact on ineligible hardware.
- **The deterministic path is the floor** (3.5) → the app degrades to "fewer conveniences", never to "broken".
- **Insights specified as non-AI** (9.5) → the analysis feature survives entirely.

Had the model been load-bearing anywhere in the pipeline, half the install base would have been left with a broken app.

**Do not reach for a cloud LLM to close the gap on the iPhone 15.** D-009's PDPA and zero-network reasoning is unchanged, and the degraded path is a handful of missing conveniences, not a broken product.

## D-023 · Liquid Glass on the navigation layer only — 1 Aug 2026

**Premise corrected:** Liquid Glass shipped in **iOS 26**, not iOS 27. Verified by compiling `.glassEffect()`, `GlassEffectContainer`, `.buttonStyle(.glass)` and `.glassEffectID(_:in:)` against the installed iOS 26.5 SDK — all fine. No iOS 27 SDK is installed and none is needed. **Deployment target stays iOS 26**; raising it to 27 would exclude devices for no gain, and the iPhone 15 in D-022 runs 26.

**The conflict:** glass is depth, translucency and refraction. Vouch is flat statement stationery — hairline rules, no shadows, no elevation (`SPEC.md` 6.2). Glass on content would dissolve the paper metaphor and make the app indistinguishable from every other iOS 26 redesign.

**Decision — adopt Apple's own layer split, which happens to be exactly what this product needs:**

| Layer | Material |
|-------|----------|
| Navigation — toolbar, month picker, floating `Import`/`+`, sheet chrome | **Glass** |
| Content — rows, figures, hairline rules, category bar, Proof table | **Opaque. Never glass** |

**Forbidden outright:**
- **The proof strip.** Its legibility is load-bearing; a translucent verdict is a hedged verdict.
- **Any amount.** Figures sit on opaque surfaces so the 4.5:1 floor is a fixed guarantee rather than a function of whatever is scrolling underneath.
- **Transaction rows** — ruled paper and glass are contradictory metaphors.

**Conditions:** honour `accessibilityReduceTransparency` with an opaque fallback; measure contrast against the worst-case backdrop, not a still screenshot; wrap adjacent glass elements in `GlassEffectContainer` so they merge rather than stack; verify in both Paper and Carbon.

**Where it genuinely earns its place:** the Proof sheet rising over the ledger. There, translucency *means* something — this is a temporary layer above your data — rather than being decoration.

**Consequence:** `SPEC.md` 6.5 added; former 6.5 renumbered to 6.6.

## D-024 · App lock: Face ID + a 6-digit app PIN — 1 Aug 2026

**Requested:** Face ID to open the app, with a 4–6 digit PIN set during onboarding.

**Decision: build it, at 6 digits, and describe it accurately.**

**What it is not.** The database key is derived from the *device* passcode via `.completeFileProtection` in the Secure Enclave. An app PIN is a **UI gate on top of that**, not a second layer of encryption. It does not make the file harder to decrypt, and no doc or copy may imply otherwise. Overstating a security control is worse than not having it — the user makes decisions based on the claim.

**What it genuinely buys.** Separation from the device passcode. Someone who can unlock the phone — partner, family — still can't open the finance app. That is a real threat model and the reason every banking app does this.

**Six digits, not four.** 10,000 combinations versus 1,000,000. Costs the user two taps a day.

**A hand-rolled PIN is easy to get wrong.** Requirements in `SPEC.md` 3.8.1: PBKDF2-derived hash with a random per-install salt (≥100k iterations, CryptoKit), Keychain `.whenUnlockedThisDeviceOnly`, exponential backoff, lockout after 10 failures clearable only by device authentication, constant-time comparison, and a persisted attempt counter so a force-quit doesn't reset it. Without backoff, a million combinations falls in minutes — the Secure Enclave provides all of this for free and we are reimplementing it.

**No bypass.** A "forgot PIN" flow that wipes and re-prompts makes the lock decoration. Reset requires device-passcode authentication.

**Consequence:** adds one screen to the two-tap onboarding in 5.1 — the only screen added, placed after account setup. Lock cannot be disabled in Settings; biometry can be toggled, the lock cannot.

**This does not reopen D-014.** There is still no account, no OAuth, no server, and nothing to authenticate *to*. This is a local lock on local data.

## D-025 · The balance column is a mode, not a fixture — 1 Aug 2026

**Found by building it.** `SPEC.md` 6.3 says the balance column ships in the UI because it mirrors the source document and lets the list be checked against the paper statement line by line. Rendered at 375pt, the arithmetic doesn't work:

```
375 − 40 gutters − 46 date − 92 amount − 78 balance − spacing ≈ 45pt for the merchant
```

45pt truncates `SHENG SIONG` to `SH…`. **A ledger you can't read the merchants in is worse than one you can't eyeball-reconcile.**

**Decision: `showBalance` defaults off.** Reading mode omits the balance and merchants get ~180pt. Reconcile mode turns it on and accepts truncated merchants — which is fine, because when you're matching against paper you're reading *figures*, not names.

Verified by rendering both variants side by side (`vouch-gallery`). The tradeoff is real in both directions, which is exactly why it's a toggle rather than a decision made once for everyone.

**Consequence:** `SPEC.md` 6.3 needs the mode noted. The toggle belongs in the toolbar, not buried in Settings — it's a reading posture, not a preference.

## D-026 · Q6b resolved — the system serif clears the bar — 1 Aug 2026

**What I checked:** rendered `SGD 3,412.80` and `1,008.75` at 48pt in both Paper and Carbon using the system serif (New York), via `ImageRenderer` at 2× — no Simulator required.

**Result: it holds up in both modes.** The concern behind Q6b was that a high-contrast display serif would go thin and weak dark-on-light. New York doesn't, because it's a *text* serif with moderate stroke contrast, not a display face.

**Recommendation: default to the system serif, and make Instrument Serif prove it's better before bundling it.** The system face wins on three counts that aren't close:

| | System serif (New York) | Instrument Serif |
|---|---|---|
| Dynamic Type | Free | Needs `relativeTo:` wiring, easy to get wrong |
| Tabular figures | Guaranteed | Must be verified |
| Weights | Full range | One (regular + italic) |
| Bundle size | Zero | ~100 KB+ |

`VouchType.heroSerifName` is `nil`, which selects the system serif. Setting it to a bundled family name is a one-line change if Instrument Serif turns out to be materially better — but "materially better" now has to beat a face that costs nothing and can't be misconfigured.

**This doesn't abandon the concept.** `SPEC.md` 6.1's one type risk — a serif on the *figures*, not the headlines — is intact and rendering. Only the specific face is now open.

---

## Open — blocking weekend 1

**None. All weekend-1 questions resolved by D-015.** Q1b, Q2b, Q3b, Q5b and Q11 are answered against six real statements.

One caveat carried forward: the analysis above used **pdfplumber**, not PDFKit. The extraction *shape* will differ. Re-verify on device that PDFKit yields per-line text with the balance figure intact — if it doesn't, `PDFSelection` bounds give x-positions and the columnar read is still available. The balance-delta derivation is unaffected either way.

## Open — blocking weekend 2

| # | Question | Status |
|---|----------|--------|
| Q7 | Refunds/reversals: Deposit column, or negative Withdrawal? | **Unanswered — none in six months.** May not exist in this account's history. Handle defensively; don't design around a guess |
| Q12 | Interest, fee, GST rows | **Unanswered — none observed in six months.** Same treatment |
| Q13 | `DBS VISA DEBIT CASHBACK` — `Income`, or a spend offset? | Decide once, apply consistently. 2 occurrences |
| Q14 | `ATM Transaction` → `Transfers`, confirmed? | Strongly implied — cash withdrawn re-enters as manual entries, so categorising it as spend double-counts. Confirm at implementation |

## Open — before the type system

| # | Question | Status |
|---|----------|--------|
| Q6a | Instrument Serif SIL OFL covers app bundling? | **Resolved — yes.** OFL 1.1 permits bundling in software including commercial. Don't sell the font standalone; respect Reserved Font Names |
| Q6b | Does Instrument Serif hold at 48pt on `Paper` (dark-on-light)? | Unanswered — visual check |

## Deferred

| # | Question | Revisit |
|---|----------|---------|
| Q8 | Email-alert ingestion via Gmail API | Day 60. Breaks zero-network *and* provability |
| Q10 | Transaction History as a mid-month freshness source alongside eStatement proof | P2. Useful, definitionally unprovable. Never blur the two in one ledger without a visible distinction |

---

## Bank profile findings

### DBS/POSB — savings — monthly eStatement

Sighted from a real June 2026 statement, pages 2–3 of 12.

| Item | Finding |
|------|---------|
| Text layer | **Yes** — clean vector text |
| Header signature | `DBS` + `POSB` logos; `My Account (<nickname>)` banner with `Account No. <nnn-nnnnnn-n>` right-aligned |
| Column headers | `Date · Description · Withdrawal (-) · Deposit (+) · Balance` |
| Period anchors | `Balance Brought Forward` / `Balance Carried Forward`, both with `SGD ` prefix |
| **Page anchors** | Every page opens with B/F and closes with C/F. Page N's C/F == page N+1's B/F |
| Date format | `DD/MM/YYYY` — `03/06/2026` = 3 June 2026 |
| Row height | **Variable.** Debit card rows are 3 lines; FAST/PayNow rows are 5 |
| Debit card row | `Debit Card Transaction` / `<MERCHANT> <LOCALE> <DDMMM>` / `<card-number>` |
| PayNow row | `Advice FAST Payment / Receipt` / `PAYNOW TRANSFER <ref>` / `TO: <PAYEE>` / `<long-ref>` / `OTHER` |
| Foreign currency | Original amount appended to the card-number line: `4628-4507-6331-7741 USD5.00`. SGD amount is in the Withdrawal column. **Take the column, never the description** |
| Direction | Two separate columns, not a sign. Also derivable from balance delta — see D-004 |
| Footer chrome | `Transaction Details as of <DD Mon YYYY>`, `Page N of M`, `PDS_MMCON_LOC_ONSH_<id>` |
| Sidebar chrome | Vertical rotated text, company/GST reg numbers. Ignore pattern needed |
| Volume | 12 pages for one month; many sub-$1 rows |
| Level-1 checks available | **B/F + C/F + per-row balance confirmed.** Stated totals unsighted |

### DBS/POSB — savings — Transaction History export

Not an input document — see D-003. Row-level notes retained in case Q10 is ever revisited: date is a **group header row**, not a per-row field; amount is `SGD - 4.22` with the sign as a separate token; type sublabel `Point-of-Sale Transaction · POS` is a free categorisation signal; `BAT` prefix on POS rows.

### Next bank — not yet profiled

Copy the DBS table above and fill it in. If a bank prints no running balance, note it loudly — the proof drops from four levels to three.

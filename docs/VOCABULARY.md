# Singapore transaction vocabulary

**Status: derived from 6 real DBS/POSB Consolidated Statements, Jan–Jun 2026. 499 transactions analysed (Feb–Jun; January excluded from merchant analysis — the account holder was in the UAE and those merchants aren't representative).**

Everything here is **observed**, not assumed. It feeds the `BankProfile` patterns and the bundled merchant rules JSON.

**How to extend:** drop a statement in, re-run the extractor, add anything new with the date first seen. Never add a merchant you haven't seen — a guessed rule that fires wrongly silently miscategorises instead of asking.

---

## 1. Structural vocabulary — DBS/POSB Consolidated Statement

### Document shape (this is not a single-account statement)

```
Page 1     Account Summary — lists EVERY account and its closing balance
Pages 2..n Transaction Details, segmented BY ACCOUNT
             each account: Balance Brought Forward → rows → Total Balance Carried Forward
             each PAGE also opens with B/F and closes with C/F
Last page  Chrome / notices
```

**Two account sections were present in every statement:** `My Account (<nickname>)` and a second `My Account (My Account)`. The parser must segment by account before anything else. See `DECISIONS.md` D-015.

### Period anchors — confirmed on all 6 statements

| String | Role |
|--------|------|
| `Balance Brought Forward SGD <amt>` | Opens each **page** *and* each **account section** |
| `Balance Carried Forward SGD <amt>` | Closes each **page**. Page N's C/F == page N+1's B/F |
| `Total Balance Carried Forward in SGD: <withdrawals> <deposits> <closing>` | **The account's true totals.** Three figures on one line |
| `as at <D MMM YYYY>` | Statement period end |
| `Account Summary` / `Transaction Details` | Section markers |

**The `Total Balance Carried Forward` line gives all four Level-1 checks.** Verified: `B/F − withdrawals + deposits == closing`, exactly, on all six statements.

### Column headers

`Date · Description · Withdrawal (-) · Deposit (+) · Balance`

⚠ **Text extraction collapses Withdrawal and Deposit into indistinguishable positions.** A row yields two numbers and you cannot tell from text order which column the first one came from. Direction comes from the balance delta — see `SPEC.md` 3.3.

### Transaction type labels — complete observed set (817 rows, 10 months)

| Count | Label | Category implication |
|------:|-------|---------------------|
| 682 | `Debit Card Transaction` | Real spend — categorise by merchant |
| 72 | `Advice FAST Payment / Receipt` | PayNow/FAST. Person → `Transfers`; company → purchase |
| 45 | `Advice Point-Of-Sale Transaction or Proceeds` | NETS QR. **Usually an aggregator — see §3** |
| 6 | `Advice Funds Transfer` | `Transfers` |
| 3 | `GIRO Salary` | **`Income`.** Reliable — bank-assigned |
| 2 | `Cash Accepting Machine Deposit` | Cash deposited at ATM. `Transfers` |
| 2 | `ATM Transaction` | Cash withdrawal. **Not spend** — see §4 |
| 2 | `Advice MEPS Receipt` | MEPS = MAS Electronic Payment System (SG RTGS). Incoming transfer |
| 1 | `Advice Outward Telegraphic Transfer` | International transfer out |
| 1 | `Advice Advice` | Real label, not a parse error. Seen with `CASA NTB PROMO` — an 18.00 new-to-bank credit |
| 1 | `Advice` | **USD account section.** See §1.1 — this one row revealed a whole currency |

The type label is **bank-assigned and more reliable than merchant matching.** Use it as tier 0, ahead of the merchant rules.

### 1.1 Multi-currency — the statement is not SGD-only

October–December 2025 contain a **USD account section** with its own anchors:

```
Balance Brought Forward USD 0.00
Total Balance Carried Forward in USD: 0.00 196.20 196.20
```

**Parse the currency code; never hardcode `SGD`.** The proof unit is `(account, currency)` — each currency section has its own B/F, totals, C/F and chain. See `DECISIONS.md` D-018. `CURRENCY: SINGAPORE DOLLAR` is the in-section marker.

### 1.2 Number-bearing lines that are NOT transactions

December carries a year-end interest summary. These lines contain amounts and **must be in `ignorePatterns`**, or the parser will invent transactions from them:

```
Messages For Total Interest For Current Year
(A) Total Credit Interest 0.00
(B) Total Debit Interest 0.00
Total Interest Adjustment For Current Year
```

Also present as pure notice text: `Service Charge for Savings Accounts`, `Cheque Issuance Fee`, `Clients Residing in Australia…`. All marketing about waivers, none are charges.

### Description sub-structure

```
Debit Card Transaction                    ← type
KOPITIAM @ LAU PA SAT  SI SGP 30MAY       ← merchant · locale · TRANSACTION date
4628-4507-6331-7741                       ← card number  (STRIP + REDACT)
```
```
Debit Card Transaction                    ← foreign variant
CLAUDE.AI SUBSCRIPTION AN USA 05JAN
4628-4507-6331-7741 USD20.00              ← foreign original appended here
```
```
Advice FAST Payment / Receipt
PAYNOW TRANSFER 6021817
TO: FOMO PAY PTE. LTD.
QY03022026060530705263
OTHER
```

| Token | Meaning |
|-------|---------|
| `SI SGP` | Singapore. Other locales seen: `SH ARE`, `DU ARE`, `AN USA` (city + ISO-3 country) |
| `30MAY` | **Transaction date**, distinct from the posting date in the Date column (D-006) |
| `AED2.00` / `USD20.00` | Foreign original on the card line. **Always take the Withdrawal column instead** |
| `TO: ` | Payee marker on transfers |
| `OTHER` | PayNow purpose code |

### Chrome to ignore

`Transaction Details as of <date>` · `Page N of M` · `PDS_MMCON_SPEC_ONSH_<id>` · `S/N: <id>` · `CURRENCY: SINGAPORE DOLLAR` · `Summary of Currency Breakdown` · `ADDRESS FOR UPDATING`

**Two extraction hazards:**
- **Rotated sidebar text extracts reversed** — `A84108825 .oN geR ziB BSOP` is "POSB Biz Reg No…" backwards. Ignore lines that are mostly reversed tokens.
- **Some page-1 text extracts as `(cid:44)(cid:13)(cid:34)…`** — a font encoding that doesn't map to Unicode. Harmless (it's the address block) but must not be treated as a transaction.

---

## 2. Merchant vocabulary — observed, Feb–Jun 2026

### The finding that changes the UI

| Bucket | Rows | % of rows | Value | % of value |
|--------|-----:|----------:|------:|-----------:|
| **Vending machines** | 140 | **28.1%** | SGD 83.30 | **1.8%** |
| **BUS/MRT transit** | 71 | 14.2% | SGD 297.21 | 6.5% |
| Everything else | 288 | 57.7% | SGD 4,221.98 | 91.7% |

**Vending machines are 28% of every row and 1.8% of the money.** Design consequences in `DECISIONS.md` D-016 — this is the single most actionable thing the real data produced.

### Vending / micro-transactions ⚠ high count, negligible value
`LE TACH VENDING SINGAPORE` (118) · `YHS(SINGAPORE) SINGAPORE` (14) · `COCA-COLA SINGAPORE BE` (6) · `ATLASVENDING SINGAPORE` (2)

### Transport
`BUS/MRT` (71 — SimplyGo transit) · `GRAB*` (2, ride-hailing — note the `GRAB* <ref>` shape) · `RAILWAY RAILWAY.COM` (4, foreign rail)

### Dining
`KOPITIAM @ LAU PA SAT` (27) · `MCDONALD'S (OTH)` (20) · `JOLLIBEE-CENTURY SQUAR` (18) · `JOLLIBEE NUS SINGAPORE` (15) · `RM FOOD MANUFACTURING` (16) · `NUS FOODCOURT NUS - ST` (9) · `EATRICH SINGAPORE` (6) · `OLD CHANG KEE SINGAPORE` (3) · `BURGER KING` (2)

### Groceries
`NTUC FP - TAMPINES HUB` (19) · `U STARS PTE LTD SINGAPORE` (6) · `7-ELEVEN -TAMPINES AVE` (2)

### Bills & subscriptions
`M1LTD RECURRING SINGAPORE` (5, telco) · `CURSOR USAGE` / `CURSOR, AI POWERED IDE` (7) · `CLAUDE.AI SUBSCRIPTION` (2) · `PYU*AMAZON SELLER SERV` (3)

### Shopping
`LAZADA SG SINGAPORE` (3)

### Health & recreation
`MYACTIVESG PLUS SINGAPORE` (3)

### Income
`ERNST & YOUNG ADVISORY PTE LTD` (3) — pairs with the `GIRO Salary` type label. Type label is the reliable signal, not the name.

### Uncategorisable — see §3
`PAYNOW TRANSFER` (39) · `NETS QR PAYMENT` (22)

### Bank-generated
`DBS VISA DEBIT CASHBACK` (2) — a credit. `Income`, or arguably a spend offset. Pick one and stay consistent.

---

## 3. The payment-aggregator problem — 61 of 499 rows (12%)

`PAYNOW TRANSFER` (39) and `NETS QR PAYMENT` (22) together are **12% of all transactions**, and for many of them the merchant is a payment processor, not the shop.

Observed: `TO: FOMO PAY PTE. LTD.`, `TO: BK F&B MANGEMENT ELM`.

When you pay a hawker by QR, the statement records the processor. **The information about what you bought does not exist in the document** — no rule, no model, nothing can recover it.

**Handling:** maintain an aggregator list (`FOMO PAY`, `LIQUID PAY`, `NETS`). Those rows route to review labelled *"Payment processor. The original merchant isn't on the statement."* **Never let the model guess.** A confident wrong answer here is exactly the trust-destroying behaviour the product exists to prevent.

Payee shape is a decent first pass: a `TO:` naming a person is usually a genuine transfer; a `TO:` naming a company is usually a purchase.

---

## 4. Categories — now derivable from real data

`SPEC.md` Part 3.7's provisional 12 were written before data existed. Six months in, here's what the evidence says:

**Confirmed as real and load-bearing:** Dining (large), Groceries, Transport, Bills & Utilities, Shopping, Income, Transfers.

**Open, with the data now available to decide:**

- **Vending/micro-purchases.** 28% of rows, 1.8% of value. Almost certainly folds into `Dining` by value — but the **list and review queue must not be dominated by them**. This is a UI problem more than a taxonomy problem. See D-016.
- **Transit vs Transport.** 71 BUS/MRT rows vs 2 Grab. Daily transit is a fixed cost of living; ride-hailing is discretionary. A case for splitting, but the row counts say transit would swamp the category either way.
- **`ATM Transaction` is not spend.** Cash withdrawn re-enters as manual entries. Categorising an ATM withdrawal as spending **double-counts it**. It belongs in `Transfers` — same principle that keeps own-account movements out of the spend total (Part 3.7).
- **`DBS VISA DEBIT CASHBACK`** — `Income` or a spend offset. Decide once.
- **`Education`** — zero rows in six months. **Cut it.** It fails the <1% rule.
- **`Health`** — only `MYACTIVESG PLUS` (3). Marginal; keep for now, review at month nine.
- **Not observed, so not needed yet:** CPF, Insurance, Rent.

**Rule reaffirmed:** a category under ~1% of rows *and* under ~1% of value over six months is noise in the picker. Cut it.

---

## 5. Still to collect

- [x] ~~Salary / GIRO credit~~ — `GIRO Salary`, 3 seen
- [x] ~~ATM withdrawal~~ — `ATM Transaction`, 2 seen
- [x] ~~Stated totals~~ — `Total Balance Carried Forward in SGD:` line, all 4 checks available
- [ ] A **refund or reversal** — still unseen. Resolves Q7 (Deposit column, or negative Withdrawal?)
- [ ] **Interest credit** and any **fee / GST** row — not observed in six months
- [ ] **July 2026** — missing from the set (see D-017)
- [ ] A **credit card** statement — the second `BankProfile`

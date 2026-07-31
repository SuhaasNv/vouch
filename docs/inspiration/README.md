# Visual references

Five references collected 31 July 2026.

**The image files are local-only and gitignored** — they are third-party design kits and aren't ours to redistribute. The take/reject analysis below is the part that matters and stands on its own without them.

| File | What it is |
|------|------------|
| `01-smarta-fintech-green.png` | Smarta — dark fintech/payments kit, green accent, 150+ screens |
| `02-fitness-lime-dark.png` | Fitness app — dark cards on lime, big-number stat tiles |
| `03-fitness-orange-dark.png` | Fitness app — dark + orange, image-led cards |
| `04-unity-dashboard-purple.png` | "Elegant Dark Theme" dashboard kit — violet, 3D illustration |
| `05-banking-coral-neumorph.png` | Banking app — coral on charcoal, soft-glow / neumorphic |

These are third-party design kits kept for reference only. Nothing here is copied verbatim — see the take/reject lists below.

---

## The thing to notice about all five

Every one of them is selling **excitement**. Big saturated accent, glow, energy, momentum. That's the correct choice for a payments app fighting for daily opens and for a fitness app selling motivation.

**Vouch sells certainty.** It is the only app in this space that can prove your month is complete, and certainty does not look like energy. If Vouch adopts this visual rhetoric wholesale it will read as the eleventh identical tracker, and the proof strip — the single thing no competitor has — will land as decoration.

So the rule for using this folder:

> **Adopt their craft. Reject their rhetoric.**

**Craft, take all of it:** spacing discipline, type hierarchy, list density, tap-target sizing, the quality of empty states, restraint in motion, how a primary action anchors the bottom of the screen.

**Rhetoric, take none of it:** glow, gradients on surfaces, 3D blobs, drop shadows on rows, saturation as a substitute for hierarchy, an accent colour applied to everything.

---

## Per-reference

### 01 — Smarta (green fintech)

The strongest craft reference of the five. Closest thing to a peer.

**Take**
- The balance card: one high-contrast filled block near the top carrying the single most important figure. Vouch's month total wants exactly this weight.
- List density and the full-width row rhythm in "All Activity" — merchant left, amount hard-right, timestamp as a dim subline. This is close to what Part 6.3 already specifies.
- Notification screen's `Unread` / `Read` grouping with a coloured leading dot. Reusable as-is for the Review Queue's confidence grouping.
- The two-button row (`Top Up` / `Send`) as a horizontal pair under the hero card → becomes `Import` / `+` for us.
- Onboarding: one sentence, one illustration, one action. Ours is two screens, not four.

**Reject**
- The green. It's a payments-app green — go, send, success. Vouch's green is reserved for *credits* only, and if the brand were also green the ledger would stop reading.
- The card mockup on the splash screen. We're not selling a card.
- Roughly two-thirds of these screens are flows we explicitly don't have (QR, transfer, PIN, bank picker, country select). Don't let a 150-screen kit smuggle scope in through the design. Cross-check `SPEC.md` Part 2.4 before building any screen inspired by this file.

### 02 — Fitness (lime on dark)

**Take**
- The stat tile: label small and dim, figure enormous, unit/target dim and trailing (`11 000` / `16 000`). This is exactly the treatment for the Proof sheet's two-column figures.
- Segmented pill tabs (`Workouts` / `Fitness` / `Plans`) — the pattern for Month View's category filter if we ever add one (P1).
- The full-bleed number overlay (`10` over the photo) is a good reminder that a figure can be the layout rather than sit inside it. Relevant to the month hero.

**Reject**
- The lime. Entirely.
- Photography-led cards. Vouch has no imagery and shouldn't invent any.
- The floating centre `+` in the tab bar. Ours has two actions and a flat bar.

### 03 — Fitness (orange on dark)

Least useful of the five — image-led, and the orange occupies the same perceptual slot as our `pending` amber, which would collide badly with the unvouched state.

**Take:** the detail-screen structure — hero, title, meta row, then a stacked list of sub-items with a persistent bottom CTA. Maps cleanly onto the transaction detail screen (row → meta → provenance → `See the Proof`).

**Reject:** everything else.

### 04 — Unity dashboard (violet)

The colour reference, and the one to be most careful with.

**Take**
- The violet range itself, as a starting point — deep violets against near-black read as considered rather than loud.
- Dashboard density: a lot of information per screen without feeling cramped. The Coverage screen wants this.
- Sidebar/nav restraint — accent used only on the active item.

**Reject**
- The 3D blob illustrations. Hard no. They are the single most dated element in the set and they contradict a document-derived product.
- Card elevation and shadow. Vouch separates with hairline rules, not depth. See `SPEC.md` Part 6.2 Layout.
- Purple applied to *everything* — cards, charts, buttons, illustrations. This is the failure mode our accent rule exists to prevent: **violet means proved, and nothing else.**
- The rounded, floaty card language. Our transaction rows are square and ruled.

### 05 — Banking (coral, neumorphic)

**Take**
- The balance card with the diagonal cut and the card-network mark bottom-right — good precedent for putting account identity on the hero without a second row of chrome.
- `Expense` / `Income` as two figures side by side with directional arrows. Directly applicable to the Proof sheet's debit/credit rows.
- The history chart's point callout (`$6,482` pinned to the peak).

**Reject**
- The glow and soft-shadow neumorphism. It reads as 2021 and it destroys the hairline language.
- Coral. Same slot as our `debit` red.
- The line chart. `SPEC.md` Part 2.4 rules out charts beyond one stacked category bar, and that stays ruled out.

---

---

## Shipping banking apps — what the real ones get right and wrong

Dribbble shots don't survive contact with 800 transactions. These notes come from teardowns of apps that actually ship.

### The transaction list

Scott Herrington's teardown of Monzo, Starling and Revolut's transaction lists is the most directly useful thing found, because the transaction list *is* Vouch's home screen. Four takeaways, all adopted into `SPEC.md` Part 6.2:

1. **No major banking app uses tabular digits.** Not Monzo, not Starling, not Revolut. It is a one-line typographic fix that makes a column of amounts scannable, and the entire category has missed it. Vouch already mandated tabular figures for its own reasons — this makes it a free competitive edge on the screen users look at most.
2. **Drop the currency symbol** inside a single-account list. `£` on every row is noise where there's no ambiguity. Keep it on the hero figure only.
3. **Weight the pounds over the pence.** Magnitude is what the eye is scanning for; the cents are a rounding detail. Dim and slightly shrink them.
4. **Adapt the row to the transaction type.** Monzo shows extra fields only when they matter (FX rate, bank reference); Starling renders every row identically and pushes you into a detail page for basics. Monzo's is the better read — "less is more, until it's not."

### Merchant logos

The one genuine advantage the big apps have that Vouch is choosing to forgo. Logos are the fastest scannability aid in a transaction list, and we can't have them without a network call or a licensing deal — both of which break the product's core claim. Compensate with typography. Do not substitute a home-made icon set; generic category glyphs on every row are worse than clean text.

### Reconciliation already exists — and it's a chore

Quicken, YNAB and Actual Budget all ship reconciliation, and it's the closest existing analog to the Proof. In all three it works the same way: a cleared/uncleared flag per row, and **you** sit with the paper statement ticking rows until the numbers agree. YNAB literally documents it as a periodic ritual with a "balance adjustment" escape hatch for when you give up.

Two conclusions:

- **Don't claim reconciliation is a new idea.** It isn't, and anyone with an accounting background will notice. See `SPEC.md` Part 1.5 — the claim is that Vouch *automates the tick*, and chains it across months, which none of them do.
- **The escape hatch is the anti-pattern.** YNAB's "balance adjustment" plugs a reconciliation gap with a made-up transaction so the user can move on. It is exactly the silent-lie failure mode `SPEC.md` Part 3.6 forbids. Vouch shows the delta and leaves it showing.

### State language

Consistent advice across sources: name states after what the system actually does, not after simplified marketing terms, and keep one label per state everywhere. Validates the copy rule in `SPEC.md` Part 6.4 — **Vouched / Unvouched / Gap**, never "verified", "synced" or "confirmed".

Related, and in Vouch's favour: statements contain only settled transactions, so there is no pending/cleared state machine to build or explain. Every feed-based competitor has to. Don't invent one for symmetry.

### Accessibility is regulatory, not optional

WCAG 2.1 AA is the baseline for financial apps — 4.5:1 text contrast, 44×44pt targets, full screen-reader support — and the European Accessibility Act has extended it to digital financial services. Folded into `SPEC.md` Part 6.5 as the quality floor.

### Navigation

Revolut carries 30+ products without a cluttered home screen by surfacing frequency and burying depth. Vouch has four screens, so the lesson is inverted: **resist adding a fifth.** If a nav bar ever needs more than Month / Coverage / Settings, something got past Part 2.4.

**Sources:**
- [Designing a Better Bank Transaction List — Scott Herrington](https://www.scottherrington.com/blog/designing-a-better-bank-app-transaction-list/)
- [Reconciling Accounts in YNAB](https://support.ynab.com/en_us/getting-started-with-reconciling-accounts-an-overview-Sy3JWx4Js) · [Balance Adjustments in YNAB](https://support.ynab.com/en_us/balance-adjustments-a-guide-rko4OwILs) · [Actual Budget — Reconciliation](https://actualbudget.org/docs/accounts/reconciliation/)
- [Banking App UI Design: Principles & Best Practices 2026 — Lollypop](https://lollypop.design/blog/2026/june/banking-app-ui-design/) · [Banking App Design 2026 — Purrweb](https://www.purrweb.com/blog/banking-app-design/) · [Banking App UX Design Guide — Orbix](https://www.orbix.studio/blogs/banking-app-ux-design-guide)
- [Banking Onboarding: Revolut, Nubank, Monzo — Craft Innovations](https://craftinnovations.global/banking-onboarding-best-practices-revolut-nubank-monzo/) · [Design System Analysis: Revolut](https://getdesign.md/revolut/design-md)

### On the App Store "PDF statement converter" category

About ten of these exist ([example](https://apps.apple.com/us/app/convert-pdf-bank-statements/id6753217986)). Worth knowing they're **not** competitors: they convert a PDF to CSV and stop — no ledger, no categories, no reconciliation, no history. Several also send extracted text to a cloud service for formatting while marketing themselves as privacy-first, which is worth reading their privacy policies to confirm before repeating.

They do establish that PDF statement parsing on iOS is tractable. That's reassuring for weekend 1.

---

## Where this lands

The reconciled direction — statement stationery, ditto violet, Paper and Carbon modes — is in `SPEC.md` Part 6. That file is canonical. This one is context for why the tokens look the way they do, and a checklist of what *not* to copy when a screen from one of these kits looks tempting at 1am.

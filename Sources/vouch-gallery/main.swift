import SwiftUI
import AppKit
import VouchUI

// Renders full SCREENS to PNG in both modes — no Simulator needed.
// Screens, not a parts catalogue: the Ledger is rendered at realistic length
// so scrolling behaviour and month breaks can actually be judged.

func d(_ s: String) -> Decimal { Decimal(string: s.replacingOccurrences(of: ",", with: ""))! }

// Shaped from the real statements: vending clusters, transit, a salary credit.
func julyRows() -> [LedgerRow.Model] {
    [
        .init(id: "j1", dateLabel: "28 Jul", merchant: "SHENG SIONG", amount: d("42.30"), balanceAfter: d("863.70")),
        .init(id: "j2", dateLabel: "28 Jul", merchant: "ATRIUM VENDING CO", amount: d("3.00"), balanceAfter: d("906.00"), groupCount: 6),
        .init(id: "j3", dateLabel: "27 Jul", merchant: "BUS/MRT 877402919", amount: d("4.22"), balanceAfter: d("909.00")),
        .init(id: "j4", dateLabel: "27 Jul", merchant: "NORTHWIND ANALYTICS PTE LTD", amount: d("2400.00"), isCredit: true, balanceAfter: d("913.22")),
        .init(id: "j5", dateLabel: "26 Jul", merchant: "NTUC FP - TAMPINES HUB", amount: d("155.20"), balanceAfter: d("1487.78")),
        .init(id: "j6", dateLabel: "24 Jul", merchant: "KOPITIAM @ LAU PA SAT", amount: d("7.30"), balanceAfter: d("1642.98")),
        .init(id: "j7", dateLabel: "22 Jul", merchant: "GRAB *TRIP", amount: d("11.80"), balanceAfter: d("1650.28")),
        .init(id: "j8", dateLabel: "21 Jul", merchant: "NETS QR PAYMENT", amount: d("8.50"), balanceAfter: d("1662.08")),
    ]
}

func juneRows() -> [LedgerRow.Model] {
    [
        .init(id: "n1", dateLabel: "30 Jun", merchant: "JOLLIBEE-CENTURY SQUAR", amount: d("19.90"), balanceAfter: d("778.73")),
        .init(id: "n2", dateLabel: "29 Jun", merchant: "ATRIUM VENDING CO", amount: d("2.00"), balanceAfter: d("798.63"), groupCount: 4),
        .init(id: "n3", dateLabel: "28 Jun", merchant: "M1LTD RECURRING", amount: d("38.00"), balanceAfter: d("800.63")),
        .init(id: "n4", dateLabel: "27 Jun", merchant: "MCDONALD'S (OTH)", amount: d("12.40"), balanceAfter: d("838.63")),
        .init(id: "n5", dateLabel: "25 Jun", merchant: "BUS/MRT 861394621", amount: d("4.30"), balanceAfter: d("851.03")),
    ]
}

let months: [LedgerMonth] = [
    .init(id: "2026-07", title: "July 2026", periodLabel: "1 – 31 Jul 2026",
          total: d("3412.80"), count: 87, account: "DBS Multiplier",
          proof: .vouched, rows: julyRows()),
    .init(id: "2026-06", title: "June 2026", periodLabel: "1 – 30 Jun 2026",
          total: d("1959.46"), count: 135, account: "DBS Multiplier",
          proof: .vouched, rows: juneRows()),
]

let coverage: [CoverageGrid.Row] = [
    .init(id: "sgd", account: "DBS Multiplier", currency: "SGD",
          periods: [
            .init(id: "s25-09", label: "Sep", dateRange: "1–30 Sep 2025", state: .head),
            .init(id: "s25-10", label: "Oct", dateRange: "1–31 Oct 2025", state: .vouched),
            .init(id: "s25-11", label: "Nov", dateRange: "1–30 Nov 2025", state: .vouched),
            .init(id: "s25-12", label: "Dec", dateRange: "1–31 Dec 2025", state: .vouched),
            .init(id: "s26-01", label: "Jan", dateRange: "1–31 Jan 2026", state: .vouched),
            .init(id: "s26-02", label: "Feb", dateRange: "1–28 Feb 2026", state: .vouched),
            .init(id: "s26-03", label: "Mar", dateRange: "1–31 Mar 2026", state: .vouched),
            .init(id: "s26-04", label: "Apr", dateRange: "1–30 Apr 2026", state: .vouched),
            .init(id: "s26-05", label: "May", dateRange: "1–31 May 2026", state: .vouched),
            .init(id: "s26-06", label: "Jun", dateRange: "1–30 Jun 2026", state: .vouched),
            // The real one — July hasn't been downloaded yet.
            .init(id: "s26-07", label: "Jul", dateRange: "1–31 Jul 2026",
                  state: .gap(.init(name: "July 2026", between: "Jun closing and Aug opening",
                                    delta: d("1880.20")))),
            .init(id: "s26-08", label: "Aug", dateRange: "1–31 Aug 2026", state: .notYetImported),
          ]),
    .init(id: "usd", account: "DBS Multiplier", currency: "USD",
          periods: [
            .init(id: "u25-10", label: "Oct", dateRange: "1–31 Oct 2025", state: .head),
            .init(id: "u25-11", label: "Nov", dateRange: "1–30 Nov 2025", state: .vouched),
            .init(id: "u25-12", label: "Dec", dateRange: "1–31 Dec 2025", state: .vouched),
          ], note: "Complete, Oct – Dec."),
]

let slices: [CategoryBar.Slice] = [
    .init(category: "Groceries", amount: d("842.15")),
    .init(category: "Dining", amount: d("611.40")),
    .init(category: "Transport", amount: d("297.21")),
    .init(category: "Bills", amount: d("188.00")),
    .init(category: "Shopping", amount: d("155.20")),
    .init(category: "Vending", amount: d("83.30")),
]

// MARK: - Screens

struct LedgerScreen: View {
    let mode: VouchMode
    let showBalance: Bool
    var body: some View {
        LedgerView(months: months, showBalance: showBalance)
            .frame(width: 375)
            .vouchTheme(mode)
    }
}

struct CoverageScreen: View {
    let mode: VouchMode
    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("Coverage").vouchEyebrow().foregroundStyle(VouchTheme.of(mode).inkDim)
                .padding(.horizontal, Space.gutter).padding(.top, Space.l)
            CoverageGrid(coverage, onImport: { _, _ in })
            Spacer(minLength: Space.l)
        }
        .frame(width: 375, alignment: .leading)
        .vouchTheme(mode)
    }
}

/// What the user actually asked for: upload → expenses, with a category chart.
struct ExpensesScreen: View {
    let mode: VouchMode
    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text("July 2026").vouchEyebrow().foregroundStyle(VouchTheme.of(mode).inkDim)
                Text("Where your money went").font(.system(size: 22))
                    .foregroundStyle(VouchTheme.of(mode).ink)
            }
            PieChart(slices.map { .init(category: $0.category, amount: $0.amount) })
        }
        .padding(Space.gutter)
        .frame(width: 375, alignment: .leading)
        .vouchTheme(mode)
    }
}

struct PartsScreen: View {
    let mode: VouchMode
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            VStack(alignment: .leading, spacing: Space.m) {
                Text("Category bar — value weighted").vouchEyebrow()
                    .foregroundStyle(VouchTheme.of(mode).inkDim)
                CategoryBar(slices)
            }
            VStack(alignment: .leading, spacing: Space.m) {
                Text("Provenance — show your work").vouchEyebrow()
                    .foregroundStyle(VouchTheme.of(mode).inkDim)
                ProvenanceView(.init(
                    sourceLine: "28/07/2026 Debit Card Transaction NTUC FP - TAMPINES HUB SI SGP 26JUL 0000-0000-0000-0000",
                    page: 3, lineIndex: 41, method: .regex, confidence: 1.0))
            }
            VStack(alignment: .leading, spacing: Space.m) {
                Text("Proof strip — three states").vouchEyebrow()
                    .foregroundStyle(VouchTheme.of(mode).inkDim)
                ProofStrip(.vouched); ProofLabel(.vouched)
                ProofStrip(.unvouched(delta: d("340.00"))); ProofLabel(.unvouched(delta: d("340.00")))
                ProofStrip(.gap(delta: d("1880.20"), at: 0.45)); ProofLabel(.gap(delta: d("1880.20"), at: 0.45))
            }
        }
        .padding(Space.gutter)
        .frame(width: 375, alignment: .leading)
        .vouchTheme(mode)
    }
}

/// `ImageRenderer` cannot rasterise a `ScrollView` — even a plain `VStack`
/// inside one comes out blank. Screens go through `NSHostingView` +
/// `cacheDisplay` instead, sized tall enough that nothing needs to scroll.
@MainActor
func renderHosted<V: View>(_ v: V, _ path: String, width: CGFloat = 375, height: CGFloat) {
    let host = NSHostingView(rootView: v)
    host.frame = NSRect(x: 0, y: 0, width: width, height: height)
    host.layoutSubtreeIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
        print("render failed: \(path)"); return
    }
    host.cacheDisplay(in: host.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)  \(Int(width))x\(Int(height))pt")
}

/// Flat stacks (no ScrollView) can still go through ImageRenderer, which
/// auto-sizes to content.
@MainActor
func render<V: View>(_ v: V, _ path: String) {
    let r = ImageRenderer(content: v)
    r.scale = 2
    guard let img = r.nsImage, let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("render failed: \(path)"); return
    }
    try? png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)  \(Int(img.size.width))x\(Int(img.size.height))pt")
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

MainActor.assumeIsolated {
    for mode in VouchMode.allCases {
        // Tall enough that the ScrollView shows the whole ledger at once.
        renderHosted(LedgerScreen(mode: mode, showBalance: false),
                     "\(out)/screen-ledger-\(mode.rawValue).png", height: 1180)
        renderHosted(CoverageScreen(mode: mode),
                     "\(out)/screen-coverage-\(mode.rawValue).png", height: 620)
        // Hosted, not ImageRenderer — the provenance well is a horizontal
        // ScrollView and renders empty otherwise.
        renderHosted(PartsScreen(mode: mode), "\(out)/screen-parts-\(mode.rawValue).png", height: 500)
        renderHosted(ExpensesScreen(mode: mode), "\(out)/screen-expenses-\(mode.rawValue).png", height: 660)
    }
    renderHosted(LedgerScreen(mode: .carbon, showBalance: true),
                 "\(out)/screen-ledger-reconcile.png", height: 1180)
    // 812pt — an actual iPhone viewport, so the fold is visible.
    renderHosted(LedgerScreen(mode: .carbon, showBalance: false),
                 "\(out)/screen-ledger-viewport.png", height: 812)
}

import SwiftUI
import AppKit
import VouchUI

// Renders the component gallery to PNG in both modes — no Simulator needed.
// Lets the visual system be reviewed before any of it is wired to data.

func d(_ s: String) -> Decimal { Decimal(string: s.replacingOccurrences(of: ",", with: ""))! }

let rows: [LedgerRow.Model] = [
    .init(id: "1", dateLabel: "28 Jul", merchant: "SHENG SIONG", amount: d("42.30"), balanceAfter: d("863.70")),
    .init(id: "2", dateLabel: "28 Jul", merchant: "ATRIUM VENDING CO", amount: d("3.00"),
          balanceAfter: d("906.00"), groupCount: 6),
    .init(id: "3", dateLabel: "27 Jul", merchant: "BUS/MRT 877402919", amount: d("4.22"), balanceAfter: d("909.00")),
    .init(id: "4", dateLabel: "27 Jul", merchant: "NORTHWIND ANALYTICS PTE LTD", amount: d("2400.00"),
          isCredit: true, balanceAfter: d("913.22")),
    .init(id: "5", dateLabel: "26 Jul", merchant: "NTUC FP - TAMPINES HUB", amount: d("155.20"),
          balanceAfter: d("1487.78")),
]

struct Gallery: View {
    let mode: VouchMode
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MonthHeader(month: "July 2026", total: d("3412.80"), count: 87,
                        account: "DBS Multiplier", proof: .vouched)
            Rectangle().fill(Color.clear).frame(height: Space.s)
            Text("Reading mode — balance column off").vouchEyebrow()
                .foregroundStyle(VouchTheme.of(mode).inkDim)
                .padding(.horizontal, Space.gutter).padding(.bottom, Space.s)
            ForEach(rows) { LedgerRow($0) }

            Text("Reconcile mode — balance column on").vouchEyebrow()
                .foregroundStyle(VouchTheme.of(mode).inkDim)
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.l).padding(.bottom, Space.s)
            ForEach(rows) { LedgerRow($0, showBalance: true) }

            VStack(alignment: .leading, spacing: Space.m) {
                Text("Proof strip — three states").vouchEyebrow()
                    .foregroundStyle(VouchTheme.of(mode).inkDim)
                ProofStrip(.vouched)
                ProofLabel(.vouched)
                ProofStrip(.unvouched(delta: d("340.00")))
                ProofLabel(.unvouched(delta: d("340.00")))
                ProofStrip(.gap(delta: d("1880.20"), at: 0.45))
                ProofLabel(.gap(delta: d("1880.20"), at: 0.45))
            }
            .padding(.horizontal, Space.gutter)
            .padding(.vertical, Space.l)
        }
        .frame(width: 375, alignment: .leading)
        .vouchTheme(mode)
    }
}

@MainActor
func render<V: View>(_ view: V, to path: String) {
    let r = ImageRenderer(content: view)
    r.scale = 2
    guard let img = r.nsImage, let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("render failed: \(path)"); return
    }
    try? png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)  \(Int(img.size.width))x\(Int(img.size.height))pt")
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

MainActor.assumeIsolated {
    for mode in VouchMode.allCases {
        render(Gallery(mode: mode), to: "\(outDir)/gallery-\(mode.rawValue).png")
    }

    // Q6b: the hero figure at 48pt, both modes, side by side.
    struct SerifCheck: View {
        var body: some View {
            HStack(spacing: 0) {
                ForEach(VouchMode.allCases, id: \.self) { mode in
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text(mode.rawValue).vouchEyebrow()
                            .foregroundStyle(VouchTheme.of(mode).inkDim)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("SGD").font(.system(size: 20, design: .serif))
                                .foregroundStyle(VouchTheme.of(mode).inkDim)
                            Text("3,412.80").font(VouchType.hero()).monospacedDigit()
                                .foregroundStyle(VouchTheme.of(mode).ink)
                        }
                        Text("1,008.75").font(VouchType.hero()).monospacedDigit()
                            .foregroundStyle(VouchTheme.of(mode).ink)
                    }
                    .padding(Space.l)
                    .frame(width: 340, alignment: .leading)
                    .vouchTheme(mode)
                }
            }
        }
    }
    render(SerifCheck(), to: "\(outDir)/q6b-serif.png")
}

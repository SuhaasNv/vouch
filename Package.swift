// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Vouch",
    platforms: [.macOS(.v14), .iOS(.v18)],
    products: [
        .library(name: "VouchCore", targets: ["VouchCore"]),
        .library(name: "VouchUI", targets: ["VouchUI"]),
        .executable(name: "vouch", targets: ["vouch"]),
    ],
    targets: [
        // No third-party dependencies. Ever. See CLAUDE.md rule 3.
        .target(
            name: "VouchCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Design system. No hex or mode reaches a component — everything
        // resolves through VouchTheme, which is what makes two colour modes
        // cost an hour instead of a weekend.
        .target(
            name: "VouchUI",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "vouch",
            dependencies: ["VouchCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Renders the component gallery to PNG — reviews the visual system
        // without a Simulator.
        .executableTarget(
            name: "vouch-gallery",
            dependencies: ["VouchUI"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "VouchCoreTests",
            dependencies: ["VouchCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)

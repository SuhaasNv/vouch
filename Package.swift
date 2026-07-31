// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Vouch",
    platforms: [.macOS(.v14), .iOS(.v18)],
    products: [
        .library(name: "VouchCore", targets: ["VouchCore"]),
        .executable(name: "vouch", targets: ["vouch"]),
    ],
    targets: [
        // No third-party dependencies. Ever. See CLAUDE.md rule 3.
        .target(
            name: "VouchCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "vouch",
            dependencies: ["VouchCore"],
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

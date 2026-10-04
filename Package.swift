// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NameCards",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "NameCardsCore"),
        .executableTarget(name: "NameCards", dependencies: ["NameCardsCore"]),
        // Developer tool: OCR + parse card images from the command line.
        .executableTarget(name: "nc-scan", dependencies: ["NameCardsCore"]),
        .testTarget(name: "NameCardsCoreTests", dependencies: ["NameCardsCore"]),
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NameCards",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "NameCardsCore"),
        .executableTarget(name: "NameCards", dependencies: ["NameCardsCore"]),
        .testTarget(name: "NameCardsCoreTests", dependencies: ["NameCardsCore"]),
    ]
)

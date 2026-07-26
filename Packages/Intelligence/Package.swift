// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Intelligence",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "Intelligence", targets: ["Intelligence"])
    ],
    dependencies: [
        .package(path: "../Handwriting"),
        .package(path: "../InkCore"),
    ],
    targets: [
        .target(name: "Intelligence", dependencies: ["Handwriting", "InkCore"]),
        .testTarget(name: "IntelligenceTests", dependencies: ["Intelligence"]),
    ]
)

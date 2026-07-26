// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Handwriting",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "Handwriting", targets: ["Handwriting"])
    ],
    dependencies: [
        .package(path: "../InkCore")
    ],
    targets: [
        .target(name: "Handwriting", dependencies: ["InkCore"]),
        .testTarget(name: "HandwritingTests", dependencies: ["Handwriting"]),
    ]
)

// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "InkCore",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "InkCore", targets: ["InkCore"])
    ],
    targets: [
        .target(name: "InkCore"),
        .testTarget(name: "InkCoreTests", dependencies: ["InkCore"]),
    ]
)

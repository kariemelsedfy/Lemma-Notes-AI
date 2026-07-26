// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Analytics",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "Analytics", targets: ["Analytics"])
    ],
    targets: [
        .target(name: "Analytics"),
        .testTarget(name: "AnalyticsTests", dependencies: ["Analytics"]),
    ]
)

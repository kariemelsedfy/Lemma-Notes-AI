// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DocumentStore",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "DocumentStore", targets: ["DocumentStore"])
    ],
    targets: [
        .target(name: "DocumentStore"),
        .testTarget(name: "DocumentStoreTests", dependencies: ["DocumentStore"]),
    ]
)

// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "pilot-proxy",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ProxyAdmission", targets: ["ProxyAdmission"]),
        .executable(name: "pilot-proxy-server", targets: ["pilot-proxy-server"]),
    ],
    targets: [
        .systemLibrary(name: "CZlib", path: "Sources/CZlib"),
        .target(
            name: "ProxyAdmission",
            dependencies: ["CZlib"],
            linkerSettings: [.linkedLibrary("sqlite3", .when(platforms: [.macOS])), .linkedLibrary("z")]
        ),
        .executableTarget(name: "pilot-proxy-server", dependencies: ["ProxyAdmission"]),
        .testTarget(name: "ProxyAdmissionTests", dependencies: ["ProxyAdmission"]),
    ]
)

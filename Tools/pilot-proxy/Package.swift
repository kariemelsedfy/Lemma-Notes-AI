// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "pilot-proxy",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ProxyAdmission", targets: ["ProxyAdmission"])
    ],
    targets: [
        .target(
            name: "ProxyAdmission",
            linkerSettings: [.linkedLibrary("sqlite3"), .linkedLibrary("z")]
        ),
        .testTarget(name: "ProxyAdmissionTests", dependencies: ["ProxyAdmission"]),
    ]
)

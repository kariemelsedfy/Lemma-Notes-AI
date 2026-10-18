// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "pilot-proxy",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ProxyAdmission", targets: ["ProxyAdmission"]),
        .executable(name: "pilot-proxy-server", targets: ["pilot-proxy-server"]),
    ],
    dependencies: [
        // ADR-031: certificate-chain and signature verification for App Store transactions and App Attest.
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-asn1.git", from: "1.0.0"),
    ],
    targets: [
        .systemLibrary(name: "CZlib", path: "Sources/CZlib"),
        .target(
            name: "ProxyAdmission",
            dependencies: [
                "CZlib",
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "SwiftASN1", package: "swift-asn1"),
            ],
            linkerSettings: [.linkedLibrary("sqlite3", .when(platforms: [.macOS])), .linkedLibrary("z")]
        ),
        .executableTarget(name: "pilot-proxy-server", dependencies: ["ProxyAdmission"]),
        .testTarget(
            name: "ProxyAdmissionTests",
            dependencies: [
                "ProxyAdmission",
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "SwiftASN1", package: "swift-asn1"),
            ]),
    ]
)

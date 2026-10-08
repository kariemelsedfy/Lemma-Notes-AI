// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "bedrock-proxy",
    platforms: [.macOS(.v15)],
    products: [.library(name: "ProxyAdmission", targets: ["ProxyAdmission"])],
    targets: [
        .target(name: "ProxyAdmission"),
        .testTarget(name: "ProxyAdmissionTests", dependencies: ["ProxyAdmission"]),
    ]
)

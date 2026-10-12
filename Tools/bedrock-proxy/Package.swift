// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "bedrock-proxy",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ProxyAdmission", targets: ["ProxyAdmission"])
    ],
    dependencies: [
        .package(url: "https://github.com/awslabs/aws-sdk-swift.git", exact: "1.8.2")
    ],
    targets: [
        .target(
            name: "ProxyAdmission",
            dependencies: [.product(name: "AWSBedrockRuntime", package: "aws-sdk-swift")],
            linkerSettings: [.linkedLibrary("sqlite3"), .linkedLibrary("z")]
        ),
        .testTarget(name: "ProxyAdmissionTests", dependencies: ["ProxyAdmission"]),
    ]
)

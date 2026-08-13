// swift-tools-version: 6.2
import PackageDescription

// The eval CLI. Deliberately a separate package rather than a target inside `Intelligence`:
// `AI_PIPELINE.md` §9 wants it runnable from CI without building an app, and nothing that ships
// to a user should be able to import it.
let package = Package(
    name: "evalrunner",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../../Packages/Intelligence"),
        .package(path: "../../Packages/InkCore"),
    ],
    targets: [
        .executableTarget(
            name: "evalrunner",
            dependencies: [
                .product(name: "Intelligence", package: "Intelligence"),
                .product(name: "InkCore", package: "InkCore"),
            ]
        )
    ]
)

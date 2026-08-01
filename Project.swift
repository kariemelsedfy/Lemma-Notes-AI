import ProjectDescription

let project = Project(
    name: "Margin",
    packages: [
        .local(path: "Packages/DocumentStore"),
        .local(path: "Packages/Intelligence"),
        .local(path: "Packages/InkCore"),
        .local(path: "Packages/Analytics"),
    ],
    targets: [
        .target(
            name: "Margin",
            destinations: .iOS,
            product: .app,
            bundleId: "edu.bowdoin.margin",
            deploymentTargets: .iOS("26.0"),
            infoPlist: .extendingDefault(with: [
                "UILaunchScreen": [:]
            ]),
            sources: ["Apps/Margin/Sources/**"],
            resources: ["Apps/Margin/Resources/**"],
            dependencies: [
                .package(product: "DocumentStore"),
                .package(product: "Intelligence"),
                .package(product: "InkCore"),
                .package(product: "Analytics"),
            ],
            settings: .settings(base: [
                "TARGETED_DEVICE_FAMILY": "2"
            ])
        ),
        .target(
            name: "MarginTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "edu.bowdoin.margin.tests",
            deploymentTargets: .iOS("26.0"),
            infoPlist: .default,
            sources: ["Apps/Margin/Tests/**"],
            dependencies: [
                .target(name: "Margin"),
                .package(product: "DocumentStore"),
                .package(product: "Intelligence"),
                .package(product: "InkCore"),
                .package(product: "Analytics"),
            ]
        ),
    ]
)

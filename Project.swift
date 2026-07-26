import ProjectDescription

let project = Project(
    name: "Margin",
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
            settings: .settings(base: [
                "TARGETED_DEVICE_FAMILY": "2"
            ])
        )
    ]
)

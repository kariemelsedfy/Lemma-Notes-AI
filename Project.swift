import ProjectDescription

/// Signing for on-device builds, supplied by the environment so nobody's team ID or
/// bundle ID ends up in the repository.
///
///     export TUIST_DEVELOPMENT_TEAM=ABCDE12345
///     ./scripts/generate.sh
///
/// Unset, the project generates exactly as before and simulator builds keep working —
/// which is what CI does. A free Apple ID is enough for a device build; it gives 7-day
/// provisioning, which covers a device session but not TestFlight (that is M0-07).
let developmentTeam = Environment.developmentTeam.getString(default: "")

/// Free provisioning registers the bundle ID to your personal team, so it has to be
/// globally unique. Override it if `edu.bowdoin.margin` is already taken:
///
///     export TUIST_BUNDLE_ID_PREFIX=com.yourname
let bundleIDPrefix = Environment.bundleIdPrefix.getString(default: "edu.bowdoin")

let signingSettings: SettingsDictionary =
    developmentTeam.isEmpty
    ? [:]
    : [
        "DEVELOPMENT_TEAM": .string(developmentTeam),
        "CODE_SIGN_STYLE": .string("Automatic"),
    ]

let project = Project(
    name: "Margin",
    packages: [
        .local(path: "Packages/DocumentStore"),
        .local(path: "Packages/Intelligence"),
        .local(path: "Packages/Handwriting"),
        .local(path: "Packages/InkCore"),
        .local(path: "Packages/Analytics"),
        .local(path: "Packages/DesignSystem"),
    ],
    targets: [
        .target(
            name: "Margin",
            destinations: .iOS,
            product: .app,
            bundleId: "\(bundleIDPrefix).margin",
            deploymentTargets: .iOS("26.0"),
            infoPlist: .extendingDefault(with: [
                "UILaunchScreen": [:]
            ]),
            sources: ["Apps/Margin/Sources/**"],
            resources: ["Apps/Margin/Resources/**"],
            dependencies: [
                .package(product: "DocumentStore"),
                .package(product: "Intelligence"),
                .package(product: "Handwriting"),
                .package(product: "InkCore"),
                .package(product: "Analytics"),
                .package(product: "DesignSystem"),
            ],
            settings: .settings(
                base: signingSettings.merging(["TARGETED_DEVICE_FAMILY": "2"]) { current, _ in current }
            )
        ),
        .target(
            name: "MarginTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "\(bundleIDPrefix).margin.tests",
            deploymentTargets: .iOS("26.0"),
            infoPlist: .default,
            sources: ["Apps/Margin/Tests/**"],
            dependencies: [
                .target(name: "Margin"),
                .package(product: "DocumentStore"),
                .package(product: "Intelligence"),
                .package(product: "Handwriting"),
                .package(product: "InkCore"),
                .package(product: "Analytics"),
                .package(product: "DesignSystem"),
            ],
            settings: .settings(base: signingSettings)
        ),
    ]
)

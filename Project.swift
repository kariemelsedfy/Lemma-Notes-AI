import ProjectDescription

/// Signing for on-device builds, supplied by the environment so a personal team ID
/// or alternate bundle prefix is never committed.
///
///     export TUIST_DEVELOPMENT_TEAM=ABCDE12345
///     ./scripts/generate.sh
///
/// Unset, the project generates exactly as before and simulator builds keep working —
/// which is what CI does. A free Apple ID is enough for a device build; it gives 7-day
/// provisioning, which covers a device session but not TestFlight (that is M0-07).
let developmentTeam = Environment.developmentTeam.getString(default: "")

/// Free provisioning ties the bundle ID to the signing team. For a data-preserving
/// handoff, keep `edu.bowdoin.margin`: a different prefix creates a different app
/// without access to the installed app's notebooks or glyph bank. If signing rejects
/// this ID, fix the Xcode account/team or stop and ask the owner. Only an explicitly
/// approved clean-app test may use an alternate prefix.
let bundleIDPrefix = Environment.bundleIdPrefix.getString(default: "edu.bowdoin")

/// App Attest (ADR-031) needs a capability a free Apple ID cannot provision, so the entitlement is added only when
/// asked for: `TUIST_APP_ATTEST=development` for builds run from Xcode on a device, `production` for TestFlight and
/// the App Store. Unset, the project builds and signs exactly as before and the app simply has no install identity.
let appAttestEnvironment = Environment.appAttest.getString(default: "")
let appEntitlements: Entitlements? =
    ["development", "production"].contains(appAttestEnvironment)
    ? .dictionary(["com.apple.developer.devicecheck.appattest-environment": .string(appAttestEnvironment)])
    : nil

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
                "UILaunchScreen": [:],
                "CFBundleDisplayName": "Lemma Notes AI",
            ]),
            sources: ["Apps/Margin/Sources/**"],
            resources: ["Apps/Margin/Resources/**"],
            entitlements: appEntitlements,
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
    ],
    schemes: [
        // The shared scheme, with the local StoreKit configuration attached so purchases can be tried in the
        // Simulator and from Xcode without App Store Connect (`PREMIUM_AND_ONBOARDING_PLAN.md` §6).
        .scheme(
            name: "Margin",
            shared: true,
            buildAction: .buildAction(targets: ["Margin"]),
            testAction: .targets(["MarginTests"]),
            runAction: .runAction(
                configuration: .debug,
                executable: "Margin",
                options: .options(storeKitConfigurationPath: "Apps/Margin/StoreKit/Margin.storekit")
            )
        )
    ]
)

import Foundation
import XCTest

@testable import ProxyAdmission

final class InstallConfigurationTests: XCTestCase {
    private static let good: [String: String] = [
        "APPLE_APP_ID": "ABCDE12345.edu.bowdoin.margin",
        "APPLE_BUNDLE_ID": "edu.bowdoin.margin",
        "PREMIUM_PRODUCT_IDS": "lemmanotesai.premium.yearly, lemmanotesai.premium.monthly",
        "CHALLENGE_SECRET": String(repeating: "s", count: 32),
    ]

    func testWithoutAnAppIDTheInstallRoutesAreOff() throws {
        XCTAssertNil(try PilotServer.Configuration.installs([:]))
        XCTAssertNil(try PilotServer.Configuration.installs(["APPLE_APP_ID": ""]))
    }

    func testAFullConfigurationParses() throws {
        let installs = try XCTUnwrap(try PilotServer.Configuration.installs(Self.good))
        XCTAssertEqual(installs.appID, "ABCDE12345.edu.bowdoin.margin")
        XCTAssertEqual(installs.productIDs, ["lemmanotesai.premium.yearly", "lemmanotesai.premium.monthly"])
        XCTAssertFalse(installs.allowsDevelopment)
        var development = Self.good
        development["ALLOW_APP_ATTEST_DEVELOPMENT"] = "1"
        XCTAssertTrue(try XCTUnwrap(try PilotServer.Configuration.installs(development)).allowsDevelopment)
    }

    func testAHalfConfiguredDeploymentRefusesToStart() {
        for name in ["APPLE_BUNDLE_ID", "PREMIUM_PRODUCT_IDS", "CHALLENGE_SECRET"] {
            var environment = Self.good
            environment[name] = nil
            XCTAssertThrowsError(try PilotServer.Configuration.installs(environment), name) {
                XCTAssertEqual($0 as? PilotServer.ConfigurationError, .missing(name))
            }
        }
    }

    func testAWeakSecretOrAMalformedAppIDIsRefused() {
        var weak = Self.good
        weak["CHALLENGE_SECRET"] = "short"
        XCTAssertThrowsError(try PilotServer.Configuration.installs(weak)) {
            XCTAssertEqual($0 as? PilotServer.ConfigurationError, .invalid("CHALLENGE_SECRET"))
        }
        for appID in ["nodots", "TEAM.edu.bowdoin.margin", ".edu.bowdoin.margin"] {
            var environment = Self.good
            environment["APPLE_APP_ID"] = appID
            XCTAssertThrowsError(try PilotServer.Configuration.installs(environment), appID) {
                XCTAssertEqual($0 as? PilotServer.ConfigurationError, .invalid("APPLE_APP_ID"))
            }
        }
    }
}

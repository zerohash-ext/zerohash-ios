import XCTest

@testable import ZerohashSDK

/// Environment mapping tests, including the internal `.gating` case added for
/// the XCUITest e2e suite (AUTH-3839, mirrors Android's AUTH-3838).
final class EnvironmentTests: XCTestCase {

    // MARK: - cdnBaseURL

    func testCdnBaseURLPerEnvironment() {
        XCTAssertEqual(Environment.sandbox.cdnBaseURL, "https://sdk-cdn.cert.zerohash.com")
        XCTAssertEqual(Environment.production.cdnBaseURL, "https://sdk-cdn.zerohash.com")
        #if DEBUG
        XCTAssertEqual(Environment.dev.cdnBaseURL, "https://sdk-cdn.dev.0hash.com")
        XCTAssertEqual(Environment.gating.cdnBaseURL, "https://sdk-cdn.gating.0hash.com")
        #endif
    }

    // MARK: - toWebValue

    /// Internal envs pass their literal name through (matches
    /// zerohash-android's `Environment.toWebValue()`) so the mobile web app's
    /// Fund iframe resolves from the matching CDN host instead of collapsing
    /// to cert; partner-facing envs keep the production/sandbox vocabulary.
    func testToWebValuePassesInternalEnvsThrough() {
        XCTAssertEqual(Environment.sandbox.toWebValue, "sandbox")
        XCTAssertEqual(Environment.production.toWebValue, "production")
        #if DEBUG
        XCTAssertEqual(Environment.dev.toWebValue, "dev")
        XCTAssertEqual(Environment.gating.toWebValue, "gating")
        #endif
    }

    // MARK: - trustedHosts

    /// Every bridge message is gated on `trustedHosts` — if the gating host is
    /// missing, WebView messages are silently dropped and the e2e suite hangs.
    func testTrustedHostsContainTheHostTheWebViewLoads() {
        #if DEBUG
        let environments: [Environment] = [.sandbox, .production, .dev, .gating]
        #else
        let environments: [Environment] = [.sandbox, .production]
        #endif
        for environment in environments {
            let cdnHost = URL(string: environment.cdnBaseURL)?.host
            XCTAssertNotNil(cdnHost)
            XCTAssertTrue(
                environment.trustedHosts.contains(cdnHost ?? ""),
                "\(environment) trustedHosts must include its cdnBaseURL host \(cdnHost ?? "nil")"
            )
        }
    }

    #if DEBUG
    func testDevTrustedHostsAreScopedToDevOnly() {
        XCTAssertEqual(
            Environment.dev.trustedHosts,
            ["sdk-mobile.dev.0hash.com", "web-sdk.dev.0hash.com", "sdk-cdn.dev.0hash.com"]
        )
        XCTAssertFalse(Environment.production.trustedHosts.contains("sdk-mobile.dev.0hash.com"))
        XCTAssertFalse(Environment.sandbox.trustedHosts.contains("sdk-mobile.dev.0hash.com"))
    }

    func testGatingTrustedHostsAreScopedToGatingOnly() {
        XCTAssertEqual(
            Environment.gating.trustedHosts,
            ["sdk-mobile.gating.0hash.com", "web-sdk.gating.0hash.com", "sdk-cdn.gating.0hash.com"]
        )
        XCTAssertFalse(Environment.production.trustedHosts.contains("sdk-mobile.gating.0hash.com"))
        XCTAssertFalse(Environment.sandbox.trustedHosts.contains("sdk-mobile.gating.0hash.com"))
    }
    #endif
}
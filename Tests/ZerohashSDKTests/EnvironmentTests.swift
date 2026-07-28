import XCTest

@testable import ZerohashSDK

/// Environment mapping tests, including the internal `.gating` case added for
/// the XCUITest e2e suite (AUTH-3839, mirrors Android's AUTH-3838).
final class EnvironmentTests: XCTestCase {

    // MARK: - fundBaseURL

    func testFundBaseURLPerEnvironment() {
        XCTAssertEqual(Environment.sandbox.fundBaseURL, "https://sdk-cdn.cert.zerohash.com")
        XCTAssertEqual(Environment.production.fundBaseURL, "https://sdk-cdn.zerohash.com")
        #if DEBUG
        XCTAssertEqual(Environment.gating.fundBaseURL, "https://connect-sdk.gating.0hash.com")
        #endif
    }

    // MARK: - toWebValue

    /// The web vocabulary only has production/sandbox — `.gating` must send
    /// `sandbox`; the gating deployment's runtime env-config picks the hosts.
    func testToWebValueMapsGatingToSandbox() {
        XCTAssertEqual(Environment.sandbox.toWebValue, "sandbox")
        XCTAssertEqual(Environment.production.toWebValue, "production")
        #if DEBUG
        XCTAssertEqual(Environment.gating.toWebValue, "sandbox")
        #endif
    }

    // MARK: - trustedHosts

    /// Every bridge message is gated on `trustedHosts` — if the gating host is
    /// missing, WebView messages are silently dropped and the e2e suite hangs.
    func testTrustedHostsContainTheHostTheWebViewLoads() {
        #if DEBUG
        let environments: [Environment] = [.sandbox, .production, .gating]
        #else
        let environments: [Environment] = [.sandbox, .production]
        #endif
        for environment in environments {
            let fundHost = URL(string: environment.fundBaseURL)?.host
            XCTAssertNotNil(fundHost)
            XCTAssertTrue(
                environment.trustedHosts.contains(fundHost ?? ""),
                "\(environment) trustedHosts must include its fundBaseURL host \(fundHost ?? "nil")"
            )
        }
    }

    #if DEBUG
    func testGatingTrustedHostsAreScopedToGatingOnly() {
        XCTAssertEqual(Environment.gating.trustedHosts, ["connect-sdk.gating.0hash.com"])
        XCTAssertFalse(Environment.production.trustedHosts.contains("connect-sdk.gating.0hash.com"))
        XCTAssertFalse(Environment.sandbox.trustedHosts.contains("connect-sdk.gating.0hash.com"))
    }
    #endif
}
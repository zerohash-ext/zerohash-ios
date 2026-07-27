import XCTest
@testable import ZerohashSDK

final class ZerohashSDKTests: XCTestCase {
    @MainActor
    func testConfigureFundReturnsInactiveSession() throws {
        let session = ZerohashSDK.configureFund(jwt: "test-jwt")
        XCTAssertNotNil(session)
        XCTAssertFalse(session.isActive, "A freshly configured session must not be active until presented")
    }

    func testCoinbaseHostPolicyAllowlist() throws {
        // Trusted: coinbase.com and its subdomains, case-insensitive.
        XCTAssertTrue(CoinbaseHostPolicy.isTrusted("coinbase.com"))
        XCTAssertTrue(CoinbaseHostPolicy.isTrusted("www.coinbase.com"))
        XCTAssertTrue(CoinbaseHostPolicy.isTrusted("login.coinbase.com"))
        XCTAssertTrue(CoinbaseHostPolicy.isTrusted("WWW.COINBASE.COM"))
        XCTAssertTrue(CoinbaseHostPolicy.isTrusted(URL(string: "https://www.coinbase.com/home")))

        // Untrusted: unrelated hosts, and lookalike/suffix spoofs.
        XCTAssertFalse(CoinbaseHostPolicy.isTrusted("evil.com"))
        XCTAssertFalse(CoinbaseHostPolicy.isTrusted("challenges.cloudflare.com"))
        XCTAssertFalse(CoinbaseHostPolicy.isTrusted("notcoinbase.com"))      // suffix "coinbase.com" but not ".coinbase.com"
        XCTAssertFalse(CoinbaseHostPolicy.isTrusted("coinbase.com.evil.com")) // trusted string as a left label
        XCTAssertFalse(CoinbaseHostPolicy.isTrusted(nil as String?))
        XCTAssertFalse(CoinbaseHostPolicy.isTrusted(URL(string: "https://evil.com")))
    }
}

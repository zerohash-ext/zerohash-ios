import XCTest
@testable import ZerohashSDK

final class ZerohashSDKTests: XCTestCase {
    @MainActor
    func testConfigureFundReturnsInactiveSession() throws {
        let session = ZerohashSDK.configureFund(jwt: "test-jwt")
        XCTAssertNotNil(session)
        XCTAssertFalse(session.isActive, "A freshly configured session must not be active until presented")
    }

    @MainActor
    func testConfigureFundWithdrawalsReturnsInactiveSession() throws {
        let session = ZerohashSDK.configureFundWithdrawals(jwt: "test-jwt")
        XCTAssertNotNil(session)
        XCTAssertFalse(session.isActive, "A freshly configured session must not be active until presented")
    }

    func testFundWithdrawalsEventMapsTypedFieldsFromData() throws {
        let data: [String: Any] = [
            "externalAccountId": "ext-123",
            "assetSymbol": "USDC",
            "amount": "10.00",
            "extra": "kept",
        ]
        let event = FundWithdrawalsEvent(
            externalAccountId: data["externalAccountId"] as? String,
            assetSymbol: data["assetSymbol"] as? String,
            amount: data["amount"] as? String,
            data: data,
            jsonString: "{}"
        )
        XCTAssertEqual(event.externalAccountId, "ext-123")
        XCTAssertEqual(event.assetSymbol, "USDC")
        XCTAssertEqual(event.amount, "10.00")
        XCTAssertEqual(event.getString("extra"), "kept")
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

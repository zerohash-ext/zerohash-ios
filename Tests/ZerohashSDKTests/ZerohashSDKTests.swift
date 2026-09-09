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

    @MainActor
    func testConfigureCryptoDepositsReturnsInactiveSession() throws {
        let session = ZerohashSDK.configureCryptoDeposits(jwt: "test-jwt")
        XCTAssertNotNil(session)
        XCTAssertFalse(session.isActive, "A freshly configured session must not be active until presented")
    }

    func testCryptoDepositsEventMapsTypedFieldsFromData() throws {
        let data: [String: Any] = [
            "depositId": "dep-123",
            "assetSymbol": "USDC",
            "network": "ethereum",
            "amount": "25.00",
            "extra": "kept",
        ]
        let event = CryptoDepositsEvent(from: data, jsonString: "{}")
        XCTAssertEqual(event.depositId, "dep-123")
        XCTAssertEqual(event.assetSymbol, "USDC")
        XCTAssertEqual(event.network, "ethereum")
        XCTAssertEqual(event.amount, "25.00")
        XCTAssertEqual(event.getString("extra"), "kept")
    }

    /// crypto-deposits and fund both deliver the shared integrations status, so
    /// one payload shape has to satisfy both callbacks.
    func testCryptoDepositsAcceptsTheSharedIntegrationsDepositEvent() throws {
        var received: IntegrationsDepositEvent?
        let callbacks = CryptoDepositsCallbacks(onDeposit: { received = $0 })

        callbacks.onDeposit?(
            IntegrationsDepositEvent(
                from: [
                    "depositId": "dep-9",
                    "status": ["value": "PROCESSED", "details": "ok", "occurredAt": "now"],
                    "assetId": "USDC",
                    "networkId": "ethereum",
                    "amount": "25.00",
                ], jsonString: "{}"))

        XCTAssertEqual(received?.depositId, "dep-9")
        XCTAssertEqual(received?.status, "PROCESSED")
        XCTAssertEqual(received?.amount, "25.00")
        XCTAssertTrue(received?.success == true)
    }

    /// A business failure must reach onFailed, not onError — hosts render the two
    /// differently, and the web SDK stopped routing failures through onError.
    func testCryptoDepositsFailureReachesOnFailedNotOnError() throws {
        var failed: CryptoDepositsEvent?
        var errored = false
        let callbacks = CryptoDepositsCallbacks(
            onFailed: { failed = $0 },
            onError: { _ in errored = true })

        callbacks.onFailed?(
            CryptoDepositsEvent(
                from: ["depositId": "dep-7", "assetSymbol": "USDC", "network": "ethereum", "amount": "10.00"],
                jsonString: "{}"))

        XCTAssertEqual(failed?.depositId, "dep-7")
        XCTAssertEqual(failed?.amount, "10.00")
        XCTAssertFalse(errored, "A failed deposit must not also surface as an SDK error")
    }

    /// A pending status must not read as success — the host decides the outcome
    /// from `status`, and the deposit is still in flight here.
    func testIntegrationsDepositEventIsNotSuccessfulWhilePending() throws {
        let event = IntegrationsDepositEvent(
            from: ["status": ["value": "PENDING", "details": "", "occurredAt": "now"]],
            jsonString: "{}")
        XCTAssertFalse(event.success)
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

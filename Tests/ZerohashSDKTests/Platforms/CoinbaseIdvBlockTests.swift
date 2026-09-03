import XCTest
@testable import ZerohashSDK

final class CoinbaseIdvBlockTests: XCTestCase {

    func testTheIdvErrorCodesReachTheWireVerbatim() {
        XCTAssertEqual(AutomationWebViewError.platformThrew("IDV_PENDING").wire, "IDV_PENDING")
        XCTAssertEqual(AutomationWebViewError.platformThrew("IDV_FAILED").wire, "IDV_FAILED")
    }

    func testNeitherIdvErrorCodeIsTransient() {
        XCTAssertFalse(AutomationWebViewError.platformThrew("IDV_PENDING").retryable)
        XCTAssertFalse(AutomationWebViewError.platformThrew("IDV_FAILED").retryable)
    }

    @MainActor
    func testGetDepositAddressIsNeverAutoReIssued() {
        XCTAssertFalse(
            AutomationWebViewMessageRouter.isSafeToRetry(operation: "getDepositAddress"),
            "an IDV block is terminal at the exchange, and a retry also mints a fresh invoice"
        )
    }

    func testADepositRejectionShapeIsNoLongerAccepted() throws {
        XCTAssertThrowsError(
            try Coinbase.mapResult(
                ["state": "rejected", "reason": "idv_pending"],
                requestedAsset: "USDC",
                requestedNetwork: "base"
            ),
            "the deposit path reports the block as an error, so a state/reason object is a malformed scrape"
        )
    }

    func testStillResolvesASuccess() throws {
        let r = try Coinbase.mapResult(
            ["address": "0xabc"], requestedAsset: "USDC", requestedNetwork: "base")
        XCTAssertEqual(r.address, "0xabc")
        XCTAssertEqual(r.network, "base")
        XCTAssertEqual(r.asset, "USDC")
    }
}

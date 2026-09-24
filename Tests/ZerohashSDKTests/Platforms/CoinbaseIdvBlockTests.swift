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

    /// `getDepositAddress` IS re-issuable now, so an IDV block staying terminal rests
    /// entirely on the error being non-transient — the other half of `retryable`.
    @MainActor
    func testAnIdvBlockedDepositAddressIsNeverAutoReIssued() {
        XCTAssertTrue(AutomationWebViewMessageRouter.isSafeToRetry(operation: "getDepositAddress"))
        for code in ["IDV_PENDING", "IDV_FAILED"] {
            XCTAssertFalse(
                AutomationWebViewError.platformThrew(code).retryable
                    && AutomationWebViewMessageRouter.isSafeToRetry(operation: "getDepositAddress"),
                "an IDV block is terminal at the exchange — \(code) must not be auto-retried"
            )
        }
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

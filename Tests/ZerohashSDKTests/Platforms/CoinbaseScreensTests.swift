import XCTest
@testable import ZerohashSDK

/// AUTH-4657. The behaviour is covered by Tests/JSTests.
@MainActor
final class CoinbaseScreensTests: XCTestCase {

    func testTheRegistryIsBundledAndInjectedBeforeWithdraw() {
        XCTAssertNotNil(Coinbase.resourceBundle.url(forResource: "coinbase-screens", withExtension: "js"))
        for js in [Coinbase.startWithdrawJS, Coinbase.continueWithdrawJS, Coinbase.cancelWithdrawJS] {
            guard let registry = js.range(of: "window.__zhCoinbaseScreens = {"),
                  let flow = js.range(of: "window.__zhWithdraw = {")
            else {
                XCTFail("the registry or withdraw.js is missing from a withdraw bundle")
                continue
            }
            XCTAssertLessThan(registry.lowerBound, flow.lowerBound)
        }
    }

    func testSendUnavailableIsATerminalRejection() throws {
        let state = try Coinbase.mapWithdrawState(["state": "rejected", "reason": "send_unavailable"])
        XCTAssertEqual(state, .rejected(reason: WithdrawRejectReason.sendUnavailable, pendingTransfer: nil))
        XCTAssertTrue(state.endsSession)
    }

    func testReceiveUnavailableIsNotRetried() {
        XCTAssertFalse(AutomationWebViewError.platformThrew("RECEIVE_UNAVAILABLE").retryable)
    }
}

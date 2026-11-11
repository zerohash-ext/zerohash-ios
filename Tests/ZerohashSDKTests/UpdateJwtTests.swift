import XCTest

@testable import ZerohashSDK

/// An idle session has nothing to update, so it must refuse. The positive path needs a presented view controller.
@MainActor
final class UpdateJwtTests: XCTestCase {

    func testCryptoDepositsRefusesANewJwtBeforePresenting() {
        let session = ZerohashCryptoDepositsSession(jwt: "a.b.c")

        XCTAssertFalse(session.updateJwt("x.y.z"))
    }

    func testFundRefusesANewJwtBeforePresenting() {
        let session = ZerohashFundSession(jwt: "a.b.c")

        XCTAssertFalse(session.updateJwt("x.y.z"))
    }

    func testCryptoWithdrawalsRefusesANewJwtBeforePresenting() {
        let session = ZerohashCryptoWithdrawalsSession(jwt: "a.b.c")

        XCTAssertFalse(session.updateJwt("x.y.z"))
    }

    func testFundWithdrawalsRefusesANewJwtBeforePresenting() {
        let session = ZerohashFundWithdrawalsSession(jwt: "a.b.c")

        XCTAssertFalse(session.updateJwt("x.y.z"))
    }

    /// Every session refuses a new token once this flag is set, so a close from the web page must set it.
    func testControllerMarksItselfClosedWhenTheWebPageSendsClose() {
        var closeCalls = 0
        let controller = IntegrationsWebViewController(
            appIdentifier: "fund",
            jwt: "a.b.c",
            environment: .sandbox,
            theme: .light,
            appRedirectUrl: nil,
            callbacks: IntegrationsWebViewCallbacks(onClose: { closeCalls += 1 })
        )
        let handler = IntegrationsWebViewMessageHandler(
            jwt: "a.b.c", theme: .light, appRedirectUrl: nil, environment: .sandbox)

        XCTAssertFalse(controller.didFireClose)
        controller.messageHandlerDidReceiveClose(handler)

        XCTAssertTrue(controller.didFireClose)
        XCTAssertEqual(closeCalls, 1)
    }
}

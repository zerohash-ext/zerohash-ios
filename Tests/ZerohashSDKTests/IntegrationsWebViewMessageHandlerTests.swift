import WebKit
import XCTest

@testable import ZerohashSDK

/// WebKit only calls an optional delegate method when the delegate responds to its
/// Objective-C selector. A Swift method whose name only nearly matches the protocol
/// requirement compiles, but is never exposed to Objective-C, so WebKit skips it.
@MainActor
final class IntegrationsWebViewMessageHandlerTests: XCTestCase {

    func testRespondsToAuthenticationChallengeSelector() {
        let handler = IntegrationsWebViewMessageHandler(jwt: "", theme: .light, appRedirectUrl: nil, environment: .sandbox)

        XCTAssertTrue(
            handler.responds(to: #selector(WKNavigationDelegate.webView(_:didReceive:completionHandler:)))
        )
    }

    func testOpensBrowserSchemes() {
        XCTAssertTrue(IntegrationsWebViewMessageHandler.canOpenExternally(scheme: "https"))
        XCTAssertTrue(IntegrationsWebViewMessageHandler.canOpenExternally(scheme: "http"))
        XCTAssertTrue(IntegrationsWebViewMessageHandler.canOpenExternally(scheme: "tel"))
        XCTAssertTrue(IntegrationsWebViewMessageHandler.canOpenExternally(scheme: "mailto"))
        XCTAssertTrue(IntegrationsWebViewMessageHandler.canOpenExternally(scheme: "sms"))
    }

    func testRejectsSchemesTheBrowserMustNotReceive() {
        XCTAssertFalse(IntegrationsWebViewMessageHandler.canOpenExternally(scheme: "javascript"))
        XCTAssertFalse(IntegrationsWebViewMessageHandler.canOpenExternally(scheme: "file"))
        XCTAssertFalse(IntegrationsWebViewMessageHandler.canOpenExternally(scheme: "about"))
        XCTAssertFalse(IntegrationsWebViewMessageHandler.canOpenExternally(scheme: nil))
    }

    func testSchemeMatchIsCaseInsensitive() {
        XCTAssertTrue(IntegrationsWebViewMessageHandler.canOpenExternally(scheme: "HTTPS"))
    }

    /// The destination is not gated, so the source origin is the boundary.
    func testOpensPopupsFromATrustedOrigin() {
        XCTAssertTrue(
            IntegrationsWebViewMessageHandler.canOpenPopup(
                sourceHost: "sdk-cdn.cert.zerohash.com", scheme: "https", in: .sandbox))
    }

    func testBlocksPopupsFromAnUntrustedOrigin() {
        XCTAssertFalse(
            IntegrationsWebViewMessageHandler.canOpenPopup(
                sourceHost: "accounts.google.com", scheme: "https", in: .sandbox))
        XCTAssertFalse(
            IntegrationsWebViewMessageHandler.canOpenPopup(
                sourceHost: "", scheme: "https", in: .sandbox))
    }

    func testBlocksARefusedSchemeEvenFromATrustedOrigin() {
        XCTAssertFalse(
            IntegrationsWebViewMessageHandler.canOpenPopup(
                sourceHost: "sdk-cdn.cert.zerohash.com", scheme: "javascript", in: .sandbox))
    }
}

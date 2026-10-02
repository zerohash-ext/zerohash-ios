import WebKit
import XCTest

@testable import ZerohashSDK

/// WebKit only calls an optional delegate method when the delegate responds to its
/// Objective-C selector. A Swift method whose name only nearly matches the protocol
/// requirement compiles, but is never exposed to Objective-C, so WebKit skips it.
@MainActor
final class IntegrationsWebViewMessageHandlerTests: XCTestCase {

    func testRespondsToAuthenticationChallengeSelector() {
        let handler = IntegrationsWebViewMessageHandler(jwt: "", theme: .light, environment: .sandbox)

        XCTAssertTrue(
            handler.responds(to: #selector(WKNavigationDelegate.webView(_:didReceive:completionHandler:)))
        )
    }
}

import XCTest
@testable import ZerohashSDK

final class ZerohashSDKTests: XCTestCase {
    func testConfigureSessionReturnsValidSession() throws {
        let session = ZerohashSDK.configureSession()
        XCTAssertNotNil(session)
    }
}

import XCTest

@testable import ZerohashSDK

/// The in-app browser (`SubViewController`) must display zerohash's agreement /
/// legal links. Those live on the help-center (Zendesk) host and are
/// intentionally never part of `Environment.trustedHosts`, so they get their own
/// narrow allowlist.
final class AgreementHostPolicyTests: XCTestCase {

    func testAllowsKnownAgreementHosts() {
        XCTAssertTrue(AgreementHostPolicy.isAllowed("zerohash.zendesk.com"))
        XCTAssertTrue(AgreementHostPolicy.isAllowed("docs.zerohash.com"))
        XCTAssertTrue(AgreementHostPolicy.isAllowed("zerohash.com"))
    }

    func testIsCaseInsensitive() {
        XCTAssertTrue(AgreementHostPolicy.isAllowed("ZeroHash.Zendesk.Com"))
    }

    /// Exact-host match only — a different Zendesk tenant (or the bare apex) is
    /// not ours and must stay blocked, so the allowlist can't be used to load an
    /// arbitrary help center.
    func testRejectsOtherHosts() {
        XCTAssertFalse(AgreementHostPolicy.isAllowed("evil.zendesk.com"))
        XCTAssertFalse(AgreementHostPolicy.isAllowed("zendesk.com"))
        XCTAssertFalse(AgreementHostPolicy.isAllowed("zerohash.zendesk.com.evil.com"))
        XCTAssertFalse(AgreementHostPolicy.isAllowed(nil))
    }
}

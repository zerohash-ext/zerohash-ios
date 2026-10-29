import XCTest

@testable import ZerohashSDK

final class ExternalSchemePolicyTests: XCTestCase {

    func testAllowsStandardSchemes() {
        for scheme in ["https", "http", "tel", "mailto", "sms"] {
            XCTAssertTrue(ExternalSchemePolicy.isAllowed(scheme, walletSchemes: []), scheme)
        }
    }

    func testSnapshotCoversWalletsWithoutUniversalLink() {
        for scheme in ["imtokenv2", "okxwallet", "tpoutside", "tangem", "krakenwallet", "keplrwallet", "rabby", "robinhood-wallet", "argent"] {
            XCTAssertTrue(WalletSchemeSnapshot.schemes.contains(scheme), scheme)
            XCTAssertTrue(ExternalSchemePolicy.isAllowed(scheme), scheme)
        }
    }

    func testAllowsSchemesFromTheWalletBook() {
        XCTAssertTrue(ExternalSchemePolicy.isAllowed("newwallet", walletSchemes: ["newwallet"]))
        XCTAssertFalse(ExternalSchemePolicy.isAllowed("newwallet", walletSchemes: []))
    }

    func testReservedSchemesStayBlockedEvenWhenListed() {
        for scheme in ["javascript", "file", "data", "itms-services", "app-prefs", "shortcuts", "facetime"] {
            XCTAssertFalse(ExternalSchemePolicy.isAllowed(scheme, walletSchemes: [scheme]), scheme)
        }
    }

    func testIsCaseInsensitive() {
        XCTAssertTrue(ExternalSchemePolicy.isAllowed("OKXWallet"))
        XCTAssertTrue(ExternalSchemePolicy.isAllowed("HTTPS"))
    }

    func testRejectsUnknownSchemes() {
        XCTAssertFalse(ExternalSchemePolicy.isAllowed("javascript"))
        XCTAssertFalse(ExternalSchemePolicy.isAllowed("file"))
        XCTAssertFalse(ExternalSchemePolicy.isAllowed("data"))
        XCTAssertFalse(ExternalSchemePolicy.isAllowed("okxwallet.evil"))
        XCTAssertFalse(ExternalSchemePolicy.isAllowed(""))
        XCTAssertFalse(ExternalSchemePolicy.isAllowed(nil))
    }
}

import XCTest

@testable import ZerohashSDK

/// Tests the native pre-loader brand resolution (AUTH-4534 follow-up): the loader
/// must render Connect dots for the AUTH Standalone flows when the JWT enables
/// auth, and zerohash green otherwise — matching the web `ProcessingDots`.
final class LoaderBrandTests: XCTestCase {

    // MARK: - Helpers

    /// Base64url-encodes without padding, like a real JWT segment.
    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Builds a `header.payload.signature` JWT carrying `claims` as the payload.
    private func makeJWT(claims: [String: Any]) -> String {
        let header = base64URL(Data(#"{"alg":"HS256","typ":"JWT"}"#.utf8))
        let payloadData = try! JSONSerialization.data(withJSONObject: claims)
        return "\(header).\(base64URL(payloadData)).signature"
    }

    // MARK: - jwtHasAuthPolicyEnabled

    func testAuthPolicyEnabledTopLevelTrue() {
        let jwt = makeJWT(claims: ["auth_policy_enabled": true])
        XCTAssertTrue(LoaderBrand.jwtHasAuthPolicyEnabled(jwt))
    }

    func testAuthPolicyEnabledFalse() {
        let jwt = makeJWT(claims: ["auth_policy_enabled": false])
        XCTAssertFalse(LoaderBrand.jwtHasAuthPolicyEnabled(jwt))
    }

    func testAuthPolicyEnabledAbsent() {
        let jwt = makeJWT(claims: ["sub": "user-123"])
        XCTAssertFalse(LoaderBrand.jwtHasAuthPolicyEnabled(jwt))
    }

    func testAuthPolicyEnabledNestedUnderPayload() {
        let jwt = makeJWT(claims: ["payload": ["auth_policy_enabled": true]])
        XCTAssertTrue(LoaderBrand.jwtHasAuthPolicyEnabled(jwt))
    }

    func testAuthPolicyEnabledMalformedTokenIsFalse() {
        XCTAssertFalse(LoaderBrand.jwtHasAuthPolicyEnabled("not-a-jwt"))
        XCTAssertFalse(LoaderBrand.jwtHasAuthPolicyEnabled(""))
        XCTAssertFalse(LoaderBrand.jwtHasAuthPolicyEnabled("only.two"))
    }

    // MARK: - resolve

    func testAuthStandaloneFlowsWithAuthResolveConnect() {
        let jwt = makeJWT(claims: ["auth_policy_enabled": true])
        XCTAssertEqual(LoaderBrand.resolve(jwt: jwt, appIdentifier: "crypto-deposits"), .connect)
        XCTAssertEqual(LoaderBrand.resolve(jwt: jwt, appIdentifier: "crypto-withdrawals"), .connect)
    }

    func testAuthStandaloneFlowsWithoutAuthResolveZerohash() {
        let jwt = makeJWT(claims: ["auth_policy_enabled": false])
        XCTAssertEqual(LoaderBrand.resolve(jwt: jwt, appIdentifier: "crypto-deposits"), .zerohash)
        XCTAssertEqual(LoaderBrand.resolve(jwt: jwt, appIdentifier: "crypto-withdrawals"), .zerohash)
    }

    func testFundFlowsStayZerohashEvenWithAuth() {
        // Account Funding embeds auth but is zerohash-branded on the web, so the
        // pre-loader must not flash Connect for it.
        let jwt = makeJWT(claims: ["auth_policy_enabled": true])
        XCTAssertEqual(LoaderBrand.resolve(jwt: jwt, appIdentifier: "fund"), .zerohash)
        XCTAssertEqual(LoaderBrand.resolve(jwt: jwt, appIdentifier: "fund-withdrawals"), .zerohash)
    }
}

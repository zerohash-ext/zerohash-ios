import Foundation
import Testing
@testable import ZerohashSDK

@Suite("Coinbase.parseStatus (AUTH-4685)")
struct CoinbaseStatusParseTests {
    private let fictionalUserId = "8b0c2f4e-1a2b-4c3d-9e8f-0a1b2c3d4e5f"
    private let indeterminateError = "PROFILE_INDETERMINATE"
    private let incompleteError = "PROFILE_INCOMPLETE"

    private var fictionalProfile: [String: Any] {
        ["userId": fictionalUserId, "firstName": "Jane Mary", "lastName": "Doe"]
    }

    private func scriptFailure(error: String, reason: String) -> [String: Any] {
        ["loggedIn": true, "profileFailure": ["error": error, "reason": reason]]
    }

    private func failedStatus(error: String, reason: String) -> AuthStatusResult {
        AuthStatusResult(loggedIn: true, profileFailure: AuthProfileFailure(error: error, reason: reason))
    }

    @Test("signed out has no profile, even if the script sent one")
    func signedOut() throws {
        let r = try Coinbase.parseStatus(["loggedIn": false, "profile": fictionalProfile])
        #expect(r == AuthStatusResult(loggedIn: false))
    }

    @Test("signed in returns the profile unchanged")
    func signedIn() throws {
        let r = try Coinbase.parseStatus(["loggedIn": true, "profile": fictionalProfile])
        let expected = AuthProfile(userId: fictionalUserId, firstName: "Jane Mary", lastName: "Doe")
        #expect(r == AuthStatusResult(loggedIn: true, profile: expected))

        let padded: [String: Any] = ["userId": " \(fictionalUserId) ", "firstName": "Jane Mary", "lastName": "Doe"]
        let unchanged = try Coinbase.parseStatus(["loggedIn": true, "profile": padded])
        #expect(unchanged.profile?.userId == " \(fictionalUserId) ")
    }

    @Test("a broken probe is invalid JS return, not a profile error")
    func brokenProbe() {
        #expect(throws: PlatformError.invalidJSReturn) { try Coinbase.parseStatus(nil) }
        #expect(throws: PlatformError.invalidJSReturn) { try Coinbase.parseStatus(["profile": fictionalProfile]) }
    }

    @Test("the script's profileFailure is returned as the failure for its reason")
    func scriptProfileFailure() throws {
        let indeterminate = try Coinbase.parseStatus(scriptFailure(error: indeterminateError, reason: "graphql_error"))
        let incomplete = try Coinbase.parseStatus(scriptFailure(error: incompleteError, reason: "missing_field"))

        #expect(indeterminate == failedStatus(error: indeterminateError, reason: "graphql_error"))
        #expect(incomplete == failedStatus(error: incompleteError, reason: "missing_field"))
    }

    @Test("the failure error comes from the reason, and unknown reasons become invalid_response")
    func scriptProfileFailureIsNormalised() throws {
        let mismatched = try Coinbase.parseStatus(scriptFailure(error: indeterminateError, reason: "missing_field"))
        let unknown = try Coinbase.parseStatus(scriptFailure(error: incompleteError, reason: "Jane Doe"))
        let noReason = try Coinbase.parseStatus(["loggedIn": true, "profileFailure": ["error": incompleteError]])

        #expect(mismatched == failedStatus(error: incompleteError, reason: "missing_field"))
        #expect(unknown == failedStatus(error: indeterminateError, reason: "invalid_response"))
        #expect(noReason == failedStatus(error: indeterminateError, reason: "invalid_response"))
    }

    @Test("the script's profileFailure wins over a profile sent alongside it")
    func scriptProfileFailureWinsOverProfile() throws {
        var raw = scriptFailure(error: indeterminateError, reason: "timeout")
        raw["profile"] = fictionalProfile

        #expect(try Coinbase.parseStatus(raw) == failedStatus(error: indeterminateError, reason: "timeout"))
    }

    @Test("signed in with neither profile nor failure is indeterminate/invalid_response")
    func neither() throws {
        let r = try Coinbase.parseStatus(["loggedIn": true])

        #expect(r == failedStatus(error: indeterminateError, reason: "invalid_response"))
    }

    @Test("signed in with a blank, missing or non-string field is incomplete/missing_field")
    func incomplete() throws {
        var blankName = fictionalProfile
        blankName["lastName"] = "  "
        var missingName = fictionalProfile
        missingName["firstName"] = nil
        var nonStringId = fictionalProfile
        nonStringId["userId"] = 42

        for profile in [blankName, missingName, nonStringId] {
            let r = try Coinbase.parseStatus(["loggedIn": true, "profile": profile])

            #expect(r == failedStatus(error: incompleteError, reason: "missing_field"))
        }
    }

    @Test("log rows keep only allowlisted keys and dash nulls")
    func logRows() {
        let row: [String: Any] = ["attempt": 2, "outcome": "timeout", "http_status": NSNull(),
                                  "latency_ms": 4001, "firstName": "Jane"]
        #expect(Coinbase.describeProfileRow(row, keys: Coinbase.profileAttemptLogKeys)
                == "attempt=2 outcome=timeout http_status=- latency_ms=4001")
    }

    @Test("log rows print allowlisted values raw and dash missing keys")
    func logRowsPrintRawValues() {
        let row: [String: Any] = ["outcome": "Jane Doe", "attempts": 9, "total_ms": 1.5, "graphql_code": "Jane"]
        #expect(Coinbase.describeProfileRow(row, keys: Coinbase.profileResultLogKeys)
                == "outcome=Jane Doe attempts=9 total_ms=1.5 error=-")
    }

    @Test("status timeout covers detection plus three profile attempts")
    func timeout() {
        #expect(Coinbase.statusTimeoutMs == 30_000)
    }

    @Test("status arguments carry only the profile deadline, a margin before the runner timeout")
    func statusArgumentsCarryTheProfileDeadline() throws {
        let arguments = Coinbase.statusArguments(now: Date(timeIntervalSince1970: 1))
        let params = try #require(arguments["params"] as? [String: Any])
        #expect(Array(arguments.keys) == ["params"])
        #expect(Array(params.keys) == ["profileDeadlineMs"])
        #expect(params["profileDeadlineMs"] as? Int == 28_000)
    }

    @Test("a runner timeout on the login probe is a timeout profile failure")
    func loginProbeTimeoutReason() {
        #expect(Coinbase.loginProbeFailureReason(.timeout(stage: .initialLoad)) == "timeout")
    }

    @Test("a load failure or a lost navigation on the login probe is an http_error profile failure")
    func loginProbeTransientReason() {
        #expect(Coinbase.loginProbeFailureReason(.loadFailed("offline")) == "http_error")
        #expect(Coinbase.loginProbeFailureReason(.navigationLost) == "http_error")
    }

    @Test("a failed login probe after sign-in is a signed-in success with only a profile failure")
    func loginAfterProbeFailure() {
        let result = Coinbase.loginAfterProbeFailure(reason: "timeout")
        let failure = AuthProfileFailure(error: indeterminateError, reason: "timeout")
        #expect(result == AuthLoginResult(loggedIn: true, outcome: "success", profileFailure: failure))
    }

    @Test("the status script installs the shared dom helpers before auth-status.js")
    func statusScriptInstallsHelpersFirst() throws {
        let script = Coinbase.statusScript
        let helpers = try #require(script.range(of: "@generated by scraper-mobile-library"))
        let profileQuery = try #require(script.range(of: "operationName=userQuery"))
        #expect(helpers.lowerBound < profileQuery.lowerBound)
    }
}

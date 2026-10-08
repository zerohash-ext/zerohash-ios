import Foundation
import Testing
@testable import ZerohashSDK

@Suite("AuthProfile (AUTH-4685)")
struct AuthProfileTests {
    private let fictionalUserId = "8b0c2f4e-1a2b-4c3d-9e8f-0a1b2c3d4e5f"
    private let profileReasons: Set<String> = [
        "http_error", "invalid_response", "graphql_error", "timeout", "missing_field",
    ]
    private let expectedErrors = [
        "http_error": "PROFILE_INDETERMINATE",
        "invalid_response": "PROFILE_INDETERMINATE",
        "graphql_error": "PROFILE_INDETERMINATE",
        "timeout": "PROFILE_INDETERMINATE",
        "missing_field": "PROFILE_INCOMPLETE",
    ]

    private var fictionalProfile: AuthProfile {
        AuthProfile(userId: fictionalUserId, firstName: "Jane Mary", lastName: "Doe")
    }

    private func json(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("a signed-out status has neither profile nor profileFailure")
    func statusOmitsNilProfile() throws {
        #expect(Set(try json(AuthStatusResult(loggedIn: false)).keys) == ["loggedIn"])
    }

    @Test("a status with a profile carries exactly the three Compliance-approved fields")
    func statusCarriesProfile() throws {
        let o = try json(AuthStatusResult(loggedIn: true, profile: fictionalProfile))
        let p = try #require(o["profile"] as? [String: Any])
        #expect(Set(p.keys) == ["userId", "firstName", "lastName"])
        #expect(p["firstName"] as? String == "Jane Mary")
    }

    @Test("login omits provider and profile when nil, carries profile when set")
    func loginOptionalFields() throws {
        #expect(Set(try json(AuthLoginResult(loggedIn: false, outcome: "user-closed")).keys) == ["loggedIn", "outcome"])
        let ok = try json(AuthLoginResult(loggedIn: true, outcome: "success", profile: fictionalProfile))
        #expect(ok["profile"] != nil)
        #expect(ok["provider"] == nil)
    }

    @Test("descriptions never print profile values")
    func descriptionsAreRedacted() {
        var dumped = ""
        dump(fictionalProfile, to: &dumped)
        let texts = [
            String(describing: fictionalProfile),
            String(reflecting: fictionalProfile),
            dumped,
            String(describing: AuthStatusResult(loggedIn: true, profile: fictionalProfile)),
            String(describing: AuthLoginResult(loggedIn: true, outcome: "success", profile: fictionalProfile)),
        ]
        for t in texts {
            #expect(!t.contains("Jane"), "\(t)")
            #expect(!t.contains("Doe"), "\(t)")
            #expect(!t.contains("8b0c2f4e"), "\(t)")
        }
    }

    @Test("the failure error follows its reason")
    func failureErrorFollowsReason() {
        for (reason, error) in expectedErrors {
            #expect(AuthProfileFailure.forReason(reason) == AuthProfileFailure(error: error, reason: reason))
        }
    }

    @Test("an unknown, empty or missing reason becomes indeterminate/invalid_response")
    func unknownReasonBecomesInvalidResponse() {
        let invalidResponse = AuthProfileFailure(error: "PROFILE_INDETERMINATE", reason: "invalid_response")

        #expect(AuthProfileFailure.forReason("Jane Doe") == invalidResponse)
        #expect(AuthProfileFailure.forReason("") == invalidResponse)
        #expect(AuthProfileFailure.forReason(nil) == invalidResponse)
    }

    @Test("the failure encodes exactly error and reason")
    func failureJSON() throws {
        let o = try json(AuthProfileFailure.forReason("timeout"))

        #expect(Set(o.keys) == ["error", "reason"])
        #expect(o["error"] as? String == "PROFILE_INDETERMINATE")
        #expect(o["reason"] as? String == "timeout")
    }

    @Test("a status with a profile failure carries it instead of a profile")
    func statusCarriesProfileFailure() throws {
        let failure = AuthProfileFailure.forReason("graphql_error")

        let o = try json(AuthStatusResult(loggedIn: true, profileFailure: failure))
        let f = try #require(o["profileFailure"] as? [String: Any])

        #expect(Set(o.keys) == ["loggedIn", "profileFailure"])
        #expect(o["loggedIn"] as? Bool == true)
        #expect(Set(f.keys) == ["error", "reason"])
        #expect(f["error"] as? String == "PROFILE_INDETERMINATE")
        #expect(f["reason"] as? String == "graphql_error")
    }

    @Test("a login with a profile failure carries the outcome and the failure instead of a profile")
    func loginCarriesProfileFailure() throws {
        let failure = AuthProfileFailure.forReason("missing_field")

        let o = try json(AuthLoginResult(loggedIn: true, outcome: "success", profileFailure: failure))
        let f = try #require(o["profileFailure"] as? [String: Any])

        #expect(Set(o.keys) == ["loggedIn", "outcome", "profileFailure"])
        #expect(o["outcome"] as? String == "success")
        #expect(f["error"] as? String == "PROFILE_INCOMPLETE")
        #expect(f["reason"] as? String == "missing_field")
    }

    @Test("a result with a profile has no profileFailure key")
    func profileHasNoFailureKey() throws {
        let status = try json(AuthStatusResult(loggedIn: true, profile: fictionalProfile))
        let login = try json(AuthLoginResult(loggedIn: true, outcome: "success", profile: fictionalProfile))

        #expect(Set(status.keys) == ["loggedIn", "profile"])
        #expect(Set(login.keys) == ["loggedIn", "outcome", "profile"])
    }

    @Test("profile telemetry still accepts the same codes")
    func telemetryCodesUnchanged() {
        #expect(AuthProfileFailure.errorCodes == ["PROFILE_INDETERMINATE", "PROFILE_INCOMPLETE"])
        #expect(AuthProfileFailure.outcomes == profileReasons.union(["ok"]))
        #expect(AuthProfileFailure.reasons == profileReasons)
    }
}

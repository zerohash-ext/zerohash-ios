import Foundation
import XCTest

/// Gating JWT mint (AUTH-3839, mirrors Android AUTH-3838). Codes come only from
/// the runner env: `GATING_FUND_*` (auth platform) and `GATING_FUND_NOAUTH_*`
/// (non-auth, ENG-6631 config) — two distinct gating platforms, no codes in source.
enum Gating {

    static let managerHost = "https://kyc-mock-platform-server.gating.0hash.com"

    /// Permissions the auth-enabled platform is provisioned with.
    static let authPermissions = ["fwc", "crypto-deposits"]

    /// The non-auth platform only has `fwc` — requesting more gets rejected.
    static let nonAuthPermissions = ["fwc"]

    struct Codes {
        let platform: String
        let participant: String
    }

    enum GatingError: Error, CustomStringConvertible {
        case missingCredentials
        case mintFailed(status: Int, body: String)
        case malformedResponse(body: String)

        var description: String {
            switch self {
            case .missingCredentials:
                return "Missing gating credentials. Pass GATING_FUND_PLATFORM / "
                    + "GATING_FUND_PARTICIPANT (auth platform: fwc + crypto-deposits + "
                    + "auth_policy_enabled) and GATING_FUND_NOAUTH_PLATFORM / "
                    + "GATING_FUND_NOAUTH_PARTICIPANT (non-auth platform: fwc only) in "
                    + "the test runner environment. The dev codes (H552SV / ZHH1NA) are "
                    + "rejected by gating."
            case let .mintFailed(status, body):
                return "mintJwt returned \(status): \(body)"
            case let .malformedResponse(body):
                return "mintJwt response missing message.token: \(body)"
            }
        }
    }

    /// Resolves the code pair for the requested config. Each config maps to a
    /// distinct gating platform (auth vs non-auth provisioning).
    static func requireCodes(authEnabled: Bool) throws -> Codes {
        let env = ProcessInfo.processInfo.environment
        let platformKey = authEnabled ? "GATING_FUND_PLATFORM" : "GATING_FUND_NOAUTH_PLATFORM"
        let participantKey = authEnabled ? "GATING_FUND_PARTICIPANT" : "GATING_FUND_NOAUTH_PARTICIPANT"
        let platform = env[platformKey] ?? ""
        let participant = env[participantKey] ?? ""
        guard !platform.isEmpty, !participant.isEmpty else {
            throw GatingError.missingCredentials
        }
        return Codes(platform: platform, participant: participant)
    }

    /// Mints a real gating JWT. `authPolicyEnabled` selects the config: it keeps
    /// the `auth_policy_enabled` mint query (belt-and-suspenders with the
    /// platform-level provisioning) and the matching permission set.
    static func mintJwt(
        codes: Codes,
        authPolicyEnabled: Bool,
        permissions: [String]? = nil
    ) throws -> String {
        let permissions = permissions ?? (authPolicyEnabled ? authPermissions : nonAuthPermissions)
        let query = authPolicyEnabled ? "?auth_policy_enabled=true" : ""
        guard let url = URL(string: "\(managerHost)/manager/jwt\(query)") else {
            throw GatingError.mintFailed(status: -1, body: "invalid mint URL")
        }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(codes.platform, forHTTPHeaderField: "x-platform-code")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "platform_code": codes.platform,
            "participant_code": codes.participant,
            "permissions": permissions,
            "reference_id": UUID().uuidString,
        ])

        // XCTest specs are synchronous — block on the mint with a semaphore.
        let semaphore = DispatchSemaphore(value: 0)
        var result: (data: Data?, response: URLResponse?, error: Error?) = (nil, nil, nil)
        URLSession.shared.dataTask(with: request) { data, response, error in
            result = (data, response, error)
            semaphore.signal()
        }.resume()
        semaphore.wait()

        if let error = result.error {
            throw GatingError.mintFailed(status: -1, body: String(describing: error))
        }
        let status = (result.response as? HTTPURLResponse)?.statusCode ?? -1
        let body = String(data: result.data ?? Data(), encoding: .utf8) ?? ""
        guard (200...299).contains(status) else {
            throw GatingError.mintFailed(status: status, body: body)
        }
        guard
            let data = result.data,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = json["message"] as? [String: Any],
            let token = message["token"] as? String
        else {
            throw GatingError.malformedResponse(body: body)
        }
        return token
    }
}
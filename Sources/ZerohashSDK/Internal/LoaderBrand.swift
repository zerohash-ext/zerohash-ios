import Foundation

/// Brand of the native pre-loader dots, mirroring the web SDK's `ProcessingDots`.
///
/// The native loader is shown before the WebView is ready, so its brand is
/// resolved from the JWT (already in hand at session creation) rather than from
/// anything the web layer reports. This keeps the pre-loader's colors in sync
/// with the Connect / zerohash dots the web renders a moment later, removing the
/// green→Connect flash on the AUTH Standalone flows.
enum LoaderBrand {
    case zerohash
    case connect

    /// The AUTH Standalone flows front as Connect; Account Funding (`fund`,
    /// `fund-withdrawals`) stays zerohash even when the token embeds auth — the
    /// same split each web host makes (`useIntegrationsEnabled` for the
    /// standalone apps vs `useIsZeroHash` for Fund).
    private static let authStandaloneAppIdentifiers: Set<String> = [
        "crypto-deposits", "crypto-withdrawals",
    ]

    /// Resolves the pre-loader brand before the loader is shown. Connect only
    /// when the flow is AUTH Standalone AND the JWT has `auth_policy_enabled`;
    /// zerohash otherwise (including auth-disabled and every Fund flow).
    static func resolve(jwt: String, appIdentifier: String) -> LoaderBrand {
        guard authStandaloneAppIdentifiers.contains(appIdentifier),
            jwtHasAuthPolicyEnabled(jwt)
        else {
            return .zerohash
        }
        return .connect
    }

    /// Whether the JWT's payload has `auth_policy_enabled == true` — read either
    /// at the top level or nested under `payload`, mirroring the web's
    /// token-extraction. Any malformed/undecodable input returns `false`.
    static func jwtHasAuthPolicyEnabled(_ jwt: String) -> Bool {
        let segments = jwt.split(separator: ".")
        guard segments.count >= 2,
            let payloadData = base64URLDecode(String(segments[1])),
            let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        else {
            return false
        }

        if (json["auth_policy_enabled"] as? Bool) == true {
            return true
        }
        if let nested = json["payload"] as? [String: Any],
            (nested["auth_policy_enabled"] as? Bool) == true {
            return true
        }
        return false
    }

    /// Decodes a base64url segment (JWT parts are base64url, unpadded).
    private static func base64URLDecode(_ value: String) -> Data? {
        var base64 =
            value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}

import Foundation

/// Host allowlist for the in-app browser (`SubViewController`).
///
/// Agreement / legal links opened via `mobileTarget="in_app"` (the T&Cs step of
/// every SDK flow) point at zerohash's help center on Zendesk. That host is
/// third-party by design and is intentionally *not* in `Environment.trustedHosts`
/// — which gates the bridge-privileged WebView and must stay narrow. The in-app
/// browser has no bridge, so it gets this separate, explicit allowlist instead of
/// widening the bridge's trust boundary.
///
/// Matching is exact-host (no suffix wildcard) so a different Zendesk tenant
/// cannot be loaded. Add new legal/help hosts here as they appear.
///
/// These cover the *statically-known* agreement/disclosure links across the
/// SDKs. Some in-app links are server- or JWT-driven (the profile `Term.url`,
/// the JWT `platformAgreementLink`, block-explorer links), so their host is not
/// known at build time and cannot be allow-listed here.
enum AgreementHostPolicy {
    static let hosts: Set<String> = [
        "zerohash.zendesk.com",
        "docs.zerohash.com",
        "zerohash.com",
    ]

    static func isAllowed(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return hosts.contains(host)
    }
}

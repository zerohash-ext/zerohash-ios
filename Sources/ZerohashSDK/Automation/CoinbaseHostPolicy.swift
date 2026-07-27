import Foundation

/// Navigation host allowlist for the Coinbase automation WebViews.
///
/// These WebViews carry the user's live Coinbase session (a persistent
/// `WKWebsiteDataStore`) and inject scripts that type the withdrawal destination
/// address, relay the 2FA OTP, and click "Send now". They must only ever load
/// Coinbase-owned origins in the **main frame** — mirroring the navigation-trust
/// controls already applied to the login modal (`ModalHostPolicy`) and the Fund
/// WebView (`Environment.trustedHosts`). Sub-frames (e.g. the Cloudflare Turnstile
/// widget Coinbase embeds during a challenge) are third-party by design and are
/// not gated here.
enum CoinbaseHostPolicy {
    static func isTrusted(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "coinbase.com" || host.hasSuffix(".coinbase.com")
    }

    static func isTrusted(_ url: URL?) -> Bool {
        isTrusted(url?.host)
    }
}

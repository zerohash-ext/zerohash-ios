import Foundation

/// Hosts allowed to use the camera/mic: Coinbase and its liveness provider
/// (Onfido). Navigation and script injection stay Coinbase-only.
enum MediaCaptureHostPolicy {
    /// Coinbase's liveness provider. The camera runs in an Onfido iframe, so the
    /// request comes from the Onfido origin.
    static func isTrustedLivenessProvider(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "onfido.com" || host.hasSuffix(".onfido.com")
    }

    /// Allow the camera/mic for the exchange or the liveness provider.
    static func isTrusted(_ host: String?) -> Bool {
        CoinbaseHostPolicy.isTrusted(host) || isTrustedLivenessProvider(host)
    }
}

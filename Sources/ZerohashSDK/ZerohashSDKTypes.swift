import Foundation

public enum Environment {
    case sandbox
    case production

    #if DEBUG
        /// INTERNAL TESTING ONLY — pre-release gating environment for the XCUITest
        /// e2e suite (AUTH-3839). Compiled out of Release builds — partners never see it.
        case gating
    #endif

    var baseURL: String {
        switch self {
        case .sandbox:
            return "https://sdk-mobile.cert.zerohash.com/v1/"
        case .production:
            return "https://sdk-mobile.zerohash.com/v1/"
        #if DEBUG
            case .gating:
                return "https://connect-sdk.gating.0hash.com/v1/"
        #endif
        }
    }

    var cdnBaseURL: String {
        switch self {
        case .sandbox:
            return "https://sdk-cdn.cert.zerohash.com"
        case .production:
            return "https://sdk-cdn.zerohash.com"
        #if DEBUG
            case .gating:
                return "https://connect-sdk.gating.0hash.com"
        #endif
        }
    }

    /// Native vocabulary forwarded to the web app via the `jwt` message
    /// (`{ token, env }`). `.gating` sends `sandbox` — the web vocabulary only has
    /// production/sandbox; the gating deployment's runtime env-config picks the hosts.
    var toWebValue: String {
        switch self {
        case .sandbox: return "sandbox"
        case .production: return "production"
        #if DEBUG
            case .gating: return "sandbox"
        #endif
        }
    }

    /// Trusted origins for WebView message validation
    internal var trustedHosts: [String] {
        switch self {
        case .sandbox:
            return [
                "sdk-mobile.cert.zerohash.com", "web-sdk.cert.zerohash.com",
                "sdk-cdn.cert.zerohash.com",
            ]
        case .production:
            return ["sdk-mobile.zerohash.com", "web-sdk.zerohash.com", "sdk-cdn.zerohash.com"]
        #if DEBUG
            case .gating:
                return ["connect-sdk.gating.0hash.com"]
        #endif
        }
    }
}

// MARK: - Theme

public enum Theme: String {
    case light
    case dark
    case system

    var toWebValue: String {
        switch self {
        case .light: return "light"
        case .dark: return "dark"
        case .system: return "auto"
        }
    }
}

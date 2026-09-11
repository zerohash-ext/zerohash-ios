import Foundation

public enum Environment {
    case sandbox
    case production

    #if DEBUG
        /// INTERNAL TESTING ONLY — Zero Hash's dev environment. Compiled out of
        /// Release builds — partners never see it.
        case dev
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
            case .dev:
                return "https://sdk-mobile.dev.0hash.com/v1/"
            case .gating:
                return "https://sdk-mobile.gating.0hash.com/v1/"
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
            case .dev:
                return "https://sdk-cdn.dev.0hash.com"
            case .gating:
                return "https://sdk-cdn.gating.0hash.com"
        #endif
        }
    }

    /// Native vocabulary forwarded to the web app via the `jwt` message
    /// (`{ token, env }`). The mobile web app passes internal envs through as-is
    /// so the Fund iframe resolves from the matching CDN host (see `cdnBaseURL`)
    /// instead of collapsing to cert — matching zerohash-android's
    /// `Environment.toWebValue()`. Partner-facing envs keep the
    /// production/sandbox vocabulary.
    var toWebValue: String {
        switch self {
        case .sandbox: return "sandbox"
        case .production: return "production"
        #if DEBUG
            case .dev: return "dev"
            case .gating: return "gating"
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
            case .dev:
                return [
                    "sdk-mobile.dev.0hash.com", "web-sdk.dev.0hash.com",
                    "sdk-cdn.dev.0hash.com",
                ]
            case .gating:
                return [
                    "sdk-mobile.gating.0hash.com", "web-sdk.gating.0hash.com",
                    "sdk-cdn.gating.0hash.com",
                ]
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

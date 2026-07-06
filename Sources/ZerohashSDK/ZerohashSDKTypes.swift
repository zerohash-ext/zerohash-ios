import Foundation

public enum Environment {
    case sandbox
    case production

    var baseURL: String {
        switch self {
        case .sandbox:
            return "https://sdk-mobile.cert.zerohash.com/v1/"
        case .production:
            return "https://sdk-mobile.zerohash.com/v1/"
        }
    }

    var fundBaseURL: String {
        switch self {
        case .sandbox:
            return "https://sdk-cdn.cert.zerohash.com"
        case .production:
            return "https://sdk-cdn.zerohash.com"
        }
    }

    var toWebValue: String {
        switch self {
        case .sandbox: return "sandbox"
        case .production: return "production"
        }
    }

    /// Trusted origins for WebView message validation
    internal var trustedHosts: [String] {
        switch self {
        case .sandbox:
            return ["sdk-mobile.cert.zerohash.com", "web-sdk.cert.zerohash.com", "sdk-cdn.cert.zerohash.com"]
        case .production:
            return ["sdk-mobile.zerohash.com", "web-sdk.zerohash.com", "sdk-cdn.zerohash.com"]
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

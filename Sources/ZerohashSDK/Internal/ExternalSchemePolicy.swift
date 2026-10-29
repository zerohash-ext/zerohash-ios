import Foundation

enum ExternalSchemePolicy {
    static let standardSchemes: Set<String> = ["https", "http", "tel", "mailto", "sms"]

    // System and browser schemes a wallet book entry can never unlock.
    static let reservedSchemes: Set<String> = [
        "http", "https", "ws", "wss", "ftp", "file", "data", "blob", "about", "javascript",
        "tel", "sms", "mailto", "facetime", "facetime-audio",
        "itms", "itms-apps", "itms-services", "app-prefs", "prefs", "shortcuts",
        "content", "intent",
    ]

    static func isAllowed(_ scheme: String?, walletSchemes: Set<String> = WalletSchemeStore.shared.schemes) -> Bool {
        guard let scheme = scheme?.lowercased(), !scheme.isEmpty else { return false }
        if standardSchemes.contains(scheme) { return true }
        return !reservedSchemes.contains(scheme) && walletSchemes.contains(scheme)
    }
}

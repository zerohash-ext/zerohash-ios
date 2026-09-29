import Foundation

/// Whether this device can run the automation (scraping) integrations. They all
/// rely on a persistent `WKWebsiteDataStore(forIdentifier:)`, which is iOS 17+.
enum AutomationSupport {
    static let requiredVersionForAutomation = OperatingSystemVersion(majorVersion: 17, minorVersion: 0, patchVersion: 0)

    static var isSupported: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(requiredVersionForAutomation)
    }
}

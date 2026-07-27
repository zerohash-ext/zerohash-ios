import Foundation
import WebKit

@MainActor
final class SharedWebViewConfiguration {
    let processPool = WKProcessPool()

    let dataStore: WKWebsiteDataStore = WKWebsiteDataStore(
        forIdentifier: SDKDataStoreIdentifier.shared
    )

    /// Single long-lived offscreen runner. Reusing the same `WKWebView`
    /// across `auth.status` polls eliminates cold-start churn and avoids
    /// the per-call WebContent process spawn that filled the original
    /// investigation logs.
    private(set) lazy var offscreenRunner: OffscreenWebViewRunner = {
        OffscreenWebViewRunner(config: self.platformConfiguration())
    }()

    /// Coinbase modal + offscreen. No message handlers and no injected user
    /// scripts: deposit-address extraction reads the rendered DOM directly.
    func platformConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.processPool      = processPool
        config.websiteDataStore = dataStore
        return config
    }
}

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
    ///
    /// Media playback is configured for Coinbase's identity check, which the user
    /// completes inside this WebView. A camera preview has to render inline —
    /// `allowsInlineMediaPlayback` is false by default on iOS, which would throw the
    /// stream into the fullscreen player and break the surrounding UI — and it has to
    /// start without a second tap, which the capture requirement would otherwise
    /// demand. Granting the capture permission itself is the WKUIDelegate's job; see
    /// `AutomationSessionViewController`.
    func platformConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.processPool      = processPool
        config.websiteDataStore = dataStore
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        return config
    }
}

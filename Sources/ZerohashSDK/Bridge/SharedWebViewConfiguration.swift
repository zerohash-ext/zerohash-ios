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

    /// Loaded once. A missing resource means the tray is not suppressed, which is a
    /// degraded run rather than a broken one, so it must not be fatal.
    private static let setupExecutionContextJS: String? = {
        guard let url = Bundle.module.url(forResource: "setup-execution-context", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else {
            Log.automation.error("missing setup-execution-context.js; execution context not set up")
            return nil
        }
        return source
    }()

    /// Coinbase modal + offscreen.
    ///
    /// Installs `setup-execution-context.js` at document start, so it runs before
    /// Coinbase's own bundle. Anything the automation needs in place before the page
    /// renders belongs in that script. Document start is the requirement, not a
    /// preference: Coinbase reads the app-upsell flag while rendering, so a write
    /// after the page settles lands after the tray has painted.
    ///
    /// Installed here rather than per WebView so a new automation host cannot forget
    /// it — every one of them takes this configuration.
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
        // Telemetry sink: breadcrumbs from telemetry.js post here. Always registered,
        // but only receives messages when telemetry is on for the dispatch.
        config.userContentController.add(TelemetryScriptMessageHandler.shared, name: "zhTelemetry")
        if let setup = Self.setupExecutionContextJS {
            config.userContentController.addUserScript(
                WKUserScript(source: setup, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            )
        }
        return config
    }
}

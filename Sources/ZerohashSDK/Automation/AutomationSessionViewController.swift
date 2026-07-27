import Foundation
import UIKit
import WebKit

/// A long-lived, automation-driven WebView session presented full-screen with NO
/// chrome (the user can't act on it). Unlike `ModalViewController` (the user-driven
/// `auth.login` modal) and `AutomatedWebViewController` (single-shot), this one
/// stays alive across multiple bridge calls so a multi-step flow (withdraw) can
/// drive the same page, hide it behind a branded overlay, and step aside / resume
/// to let the host app collect an OTP mid-flow.
///
/// Conforms to `AutomationSessionHandle`; the coordinator retains it across
/// `start` → `continue…` → terminal and dismisses it when the session ends.
@MainActor
final class AutomationSessionViewController:
    UIViewController,
    AutomationSessionHandle,
    WKNavigationDelegate
{
    private let initialURL: URL
    private let webViewConfig: WKWebViewConfiguration
    private let timeoutMs: Int
    private let overlayOptions: OverlayOptions
    private let showOverlay: Bool
    /// Host-selected theme, forwarded to the branded overlay.
    private let theme: Theme
    /// Only created/added when `showOverlay` is true.
    private var overlay: LoadingOverlayView?
    private var webView: WKWebView!
    private var didDismiss = false
    private var timeoutTask: Task<Void, Never>?
    private var readinessTask: Task<Void, Never>?

    /// True once the first `didFinish` has fired (initial page load complete).
    private var didLoad = false
    /// Continuations awaiting `awaitInitialLoad()` while the page is still loading.
    private var loadWaiters: [CheckedContinuation<Void, Never>] = []

    /// The presenter (host VC) — set at presentation. Needed so the session can
    /// re-present itself in `resume()` after `stepAside()` (the per-request
    /// ExecutionContext is gone by the time `continue` resumes).
    weak var presenter: UIViewController?

    var currentURL: URL? { webView?.url }

    init(url: URL,
         sharedConfig: WKWebViewConfiguration,
         timeoutMs: Int = 300_000,
         overlay: OverlayOptions = .default,
         showOverlay: Bool = false,
         theme: Theme = .system) {
        self.initialURL = url
        self.webViewConfig = sharedConfig
        self.timeoutMs = timeoutMs
        self.overlayOptions = overlay
        self.showOverlay = showOverlay
        self.theme = theme
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        webView = WKWebView(frame: view.bounds, configuration: webViewConfig)
        #if DEBUG
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        #endif
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        // Full-bleed (no chrome — the user must not be able to act on this page).
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        // Opaque branded overlay ON TOP of the WebView (added last so it covers the
        // page) while the automation drives Coinbase. Lifted via revealOverlay.
        if showOverlay {
            let overlay = LoadingOverlayView(options: overlayOptions, theme: theme)
            view.addSubview(overlay)
            overlay.pinToSuperview()
            overlay.start()
            self.overlay = overlay
        }

        webView.load(URLRequest(url: initialURL))
        scheduleTimeout()
    }

    /// Force-closes the session with teardown if it neither completes nor is
    /// dismissed within the configured ceiling. Paused while parked on user input.
    private func scheduleTimeout() {
        let ms = timeoutMs
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
            guard let self, !Task.isCancelled else { return }
            self.dismissSession()
        }
    }

    /// Awaits Promise-returning automation via `callAsyncJavaScript`. `js` is (or
    /// ends with) an expression; we wrap it as `return (expr);` (parens defeat
    /// ASI). A thrown JS error's `WKJavaScriptExceptionMessage` is rethrown as a
    /// `JSException` so messages survive to the platform layer.
    func evaluateAsync(_ js: String, arguments: [String: Any]) async throws -> Any? {
        loadViewIfNeeded()
        // this session drives money-movement automation (types the destination address,
        // relays the OTP, clicks "Send now"). Refuse to evaluate if the page has somehow
        // landed on a non-Coinbase origin, even if a navigation slipped past the delegate.
        guard CoinbaseHostPolicy.isTrusted(webView.url) else {
            Log.automation.error("refusing to evaluate automation on untrusted host=\(self.webView.url?.host ?? "?", privacy: .private)")
            throw JSException(message: "withdraw/untrusted-host")
        }
        var expr = js
        while let last = expr.unicodeScalars.last,
              last == ";" || CharacterSet.whitespacesAndNewlines.contains(last) {
            expr.removeLast()
        }
        let wrapped = "return (\n\(expr)\n);"
        do {
            // `arguments` are bound as JS variables by WebKit (marshaled from native
            // values), so request data reaches the script without being interpolated
            // into its source.
            return try await webView.callAsyncJavaScript(
                wrapped, arguments: arguments, in: nil, contentWorld: .page)
        } catch {
            let nsErr = error as NSError
            if let jsMessage = nsErr.userInfo["WKJavaScriptExceptionMessage"] as? String,
               !jsMessage.isEmpty {
                throw JSException(message: jsMessage)
            }
            throw error
        }
    }

    func awaitInitialLoad() async {
        // Ensure the view is loaded so the URL load has started, then wait for the
        // first didFinish (or for teardown, which resumes waiters too).
        loadViewIfNeeded()
        if didLoad { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            loadWaiters.append(cont)
        }
    }

    /// Lift (true) or restore (false) the branded overlay. No-op when none exists.
    func revealOverlay(_ revealed: Bool) {
        overlay?.isHidden = revealed
    }

    /// Dismiss the presentation so the host shows, WITHOUT teardown — the VC (and
    /// its webview) stay alive (the coordinator retains this handle). Distinct from
    /// `dismiss()`: no teardown, the session resumes via `resume()`.
    func stepAside() async {
        guard let presenter, presentingViewController != nil else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            presenter.dismiss(animated: true) { cont.resume() }
        }
    }

    /// Re-present after `stepAside()` — the same webview/page rides along.
    func resume() async {
        guard let presenter, presentingViewController == nil else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            presenter.present(self, animated: true) { cont.resume() }
        }
    }

    /// Suspend the wall-clock timeout while parked on a user-input step (OTP /
    /// passkey). The user may take arbitrarily long; cancelling the pending
    /// force-close keeps the session alive. No-op if none is scheduled.
    func pauseTimeout() {
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    /// Restart the wall-clock timeout from zero — each automation leg gets a fresh
    /// budget instead of racing a clock that started at `start`.
    func restartTimeout() {
        timeoutTask?.cancel()
        scheduleTimeout()
    }

    func dismiss() async {
        dismissSession()
    }

    // Navigation host allowlist. This long-lived session drives the Coinbase
    // withdrawal automation and carries the live Coinbase session, so it must only
    // load Coinbase-owned origins in the main frame. Sub-frames (e.g. the
    // Cloudflare Turnstile widget) are third-party by design and left alone.
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.targetFrame?.isMainFrame == false {
            decisionHandler(.allow)
            return
        }
        guard CoinbaseHostPolicy.isTrusted(navigationAction.request.url) else {
            Log.automation.error("blocked off-Coinbase navigation host=\(navigationAction.request.url?.host ?? "?", privacy: .private)")
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        beginReadinessGate()
    }

    /// Truthy while a Cloudflare interstitial/Turnstile is on the page. Markers
    /// mirror the browser extension's canonical detector (coinbase/challenge.ts)
    /// and `AutomatedWebViewController.challengeProbe` — keep them in sync.
    private static let challengeProbe =
        "(!!(window._cf_chl_opt || document.querySelector('#challenge-running, #cf-challenge-running, #challenge-stage, #cf-chl-widget, iframe[src*=\"challenges.cloudflare.com\"], div[class=\"ch-title-zone\"]')))"

    /// After the first `didFinish`, defer marking the session ready until any
    /// Cloudflare challenge has cleared. The withdraw page frequently loads behind
    /// Cloudflare's non-interactive "managed challenge" (a spinner that runs JS
    /// then reloads to the real page). Evaluating `startWithdrawJS` on that
    /// challenge page runs the script in a context Cloudflare destroys on the
    /// reload — so the automation dies and the overlay hangs to timeout. Polling
    /// the live document (which survives the reload) until the challenge is gone
    /// keeps us from evaluating too early. No-op once ready or dismissed; the
    /// non-challenged path resolves on the first poll.
    private func beginReadinessGate() {
        guard !didLoad, readinessTask == nil else { return }
        readinessTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !self.didLoad && !self.didDismiss {
                var challenged = true
                do {
                    let result = try await self.webView.evaluateJavaScript(Self.challengeProbe)
                    challenged = (result as? Bool) ?? false
                } catch {
                    // Page is mid-navigation/reload (typical while Cloudflare
                    // resolves) — treat as still challenged and keep polling.
                    challenged = true
                }
                if self.didLoad || self.didDismiss { return }
                if !challenged {
                    Log.automation.debug("session ready: no Cloudflare challenge; resolving initial load")
                    self.markInitialLoadComplete()
                    return
                }
                Log.automation.debug("session waiting on Cloudflare challenge to clear…")
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            }
        }
    }

    /// Flips `didLoad` and resumes any `awaitInitialLoad()` waiters on the first
    /// `didFinish`. Idempotent — later navigations are ignored here.
    private func markInitialLoadComplete() {
        guard !didLoad else { return }
        didLoad = true
        let waiters = loadWaiters
        loadWaiters.removeAll()
        for w in waiters { w.resume() }
    }

    /// Tear down the session: cancel the timeout, stop the overlay, unblock any
    /// load waiters, and dismiss the presentation. Idempotent.
    private func dismissSession() {
        guard !didDismiss else { return }
        didDismiss = true
        timeoutTask?.cancel()
        timeoutTask = nil
        readinessTask?.cancel()
        readinessTask = nil
        overlay?.stop()
        // Unblock any awaitInitialLoad() callers so a dismiss/timeout before the
        // first load can't strand them.
        let waiters = loadWaiters
        loadWaiters.removeAll()
        for w in waiters { w.resume() }
        // Don't actually dismiss in test mode; presenting view controller may be nil.
        if presentingViewController != nil {
            dismiss(animated: true)
        }
    }
}

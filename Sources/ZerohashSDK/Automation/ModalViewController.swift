import Foundation
import UIKit
import WebKit

/// Why the login modal closed. Drives the `auth.login` `outcome` discriminant.
public enum ModalCloseReason: Equatable, Sendable {
    /// Reached a configured success host (e.g. a signed-in surface) — a
    /// plausible successful sign-in. The folded auth.status check is authoritative.
    case success
    /// User dismissed the modal (Cancel button).
    case userClosed
    /// The modal exceeded its time ceiling and was force-closed.
    case timeout
    /// A supplied `ModalAutoClose` probe reported a condition, carrying the
    /// condition *code* the probe returned. The caller interprets the code
    /// (e.g. Coinbase maps "passkey-only"/"account-not-found" to login outcomes).
    case conditionMet(String)
}

/// The interactive `auth.login` modal: a user-driven WebView with chrome (title +
/// Cancel), wrapped in a navigation controller, that resolves via `waitForClose()`
/// when the user finishes (redirect off the login host), cancels, times out, or an
/// `autoClose` probe fires. Long-lived automation flows (withdraw) use
/// `AutomationSessionViewController` instead.
@MainActor
final class ModalViewController:
    UIViewController,
    ModalWebViewHandle,
    WKNavigationDelegate,
    WKUIDelegate
{
    private let initialURL: URL
    let hostPolicy: ModalHostPolicy
    private let titleText: String?
    private let webViewConfig: WKWebViewConfiguration
    private let timeoutMs: Int
    /// Optional generic auto-close rule: a JS probe polled while the modal is
    /// open, closing with `.conditionMet` once it matches. nil disables it.
    private let autoClose: ModalAutoClose?
    private var webView: WKWebView!
    private var didDismiss = false
    private var timeoutTask: Task<Void, Never>?
    private var autoCloseProbeTask: Task<Void, Never>?

    /// The currently-presented social-login popup, if any. Held so its lifetime
    /// matches the modal and it can be torn down on modal close.
    private var popup: PopupWebViewController?

    #if DEBUG
    /// Test-only: whether a social-login popup is currently tracked.
    var debugHasLivePopup: Bool { popup != nil }
    #endif

    /// The reason recorded when the modal closed (nil until it closes).
    private var closeReason: ModalCloseReason?
    /// Continuations awaiting `waitForClose()` while the modal is still open.
    private var closeWaiters: [CheckedContinuation<ModalCloseReason, Never>] = []

    /// Fires exactly once when the modal closes, carrying the reason.
    var onClose: ((ModalCloseReason) -> Void)?

    var currentURL: URL? { webView?.url }

    init(url: URL,
         hostPolicy: ModalHostPolicy,
         title: String?,
         sharedConfig: WKWebViewConfiguration,
         timeoutMs: Int = 300_000,
         autoClose: ModalAutoClose? = nil,
         documentStartJS: String? = nil) {
        self.initialURL = url
        self.hostPolicy = hostPolicy
        self.titleText = title
        // Social login opens the IdP flow via window.open; the modal WebView
        // must be allowed to create new windows or the buttons do nothing.
        // `sharedConfig` is caller-owned and handed back fresh per call by
        // SharedWebViewConfiguration.platformConfiguration(), so mutating it here
        // does not leak this setting to other WebViews.
        sharedConfig.preferences.javaScriptCanOpenWindowsAutomatically = true
        // Optional caller-supplied script (e.g. Coinbase hiding the Google/passkey
        // options). Installed at documentStart so it runs before the page's own
        // scripts and persists across the login SPA's re-renders. Added to the
        // config BEFORE the WKWebView is built in viewDidLoad.
        if let documentStartJS {
            sharedConfig.userContentController.addUserScript(
                WKUserScript(source: documentStartJS,
                             injectionTime: .atDocumentStart,
                             forMainFrameOnly: true)
            )
        }
        self.webViewConfig = sharedConfig
        self.timeoutMs = timeoutMs
        self.autoClose = autoClose
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = titleText
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(onCancelTapped))

        webView = WKWebView(frame: view.bounds, configuration: webViewConfig)
        #if DEBUG
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        #endif
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        webView.load(URLRequest(url: initialURL))
        scheduleTimeout()
        startAutoCloseProbe()
    }

    /// Polls the optional `autoClose` JS probe while the modal is open and
    /// force-closes with `.conditionMet(code)` once the SAME non-empty condition
    /// code is returned `requiredHits` times in a row. No-op when no probe was
    /// supplied. Cancelled in `dismissModal` so it can't fire post-close.
    /// Evaluates first, then sleeps, so the first read is immediate and the
    /// interval is the gap between confirming reads.
    private func startAutoCloseProbe() {
        guard let autoClose else { return }
        let intervalNs = UInt64(autoClose.intervalMs) * 1_000_000
        autoCloseProbeTask = Task { @MainActor [weak self] in
            var lastCode: String?
            var hits = 0
            while !Task.isCancelled {
                guard let self, !Task.isCancelled else { return }
                // Tolerate eval failures (page mid-navigation): a thrown error
                // or a falsy/empty return is "no match" and resets the counter,
                // never closes. A non-empty string is the condition code.
                let code = (try? await self.evaluate(autoClose.probeJS)) as? String
                if let code, !code.isEmpty {
                    // Require the same code across consecutive reads — a transient
                    // flip between screens can't accumulate toward a close.
                    hits = (code == lastCode) ? hits + 1 : 1
                    lastCode = code
                    if hits >= autoClose.requiredHits {
                        self.dismissModal(reason: .conditionMet(code))
                        return
                    }
                } else {
                    lastCode = nil
                    hits = 0
                }
                try? await Task.sleep(nanoseconds: intervalNs)
            }
        }
    }

    /// Force-closes the modal with `.timeout` if the user neither completes
    /// nor dismisses the flow within the configured ceiling.
    private func scheduleTimeout() {
        let ms = timeoutMs
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
            guard let self, !Task.isCancelled else { return }
            self.dismissModal(reason: .timeout)
        }
    }

    func evaluate(_ js: String) async throws -> Any? {
        // A caller may drive the handle immediately after presentation, before
        // UIKit has lazily run viewDidLoad — which would leave `webView` nil.
        // Force the view to load so the WebView exists. Idempotent.
        loadViewIfNeeded()
        return try await webView.evaluateJavaScript(js)
    }

    func waitForClose() async -> ModalCloseReason {
        if let closeReason { return closeReason }
        return await withCheckedContinuation { continuation in
            closeWaiters.append(continuation)
        }
    }

    func dismiss() async {
        dismissModal(reason: .success)
    }

    @objc private func onCancelTapped() {
        dismissModal(reason: .userClosed)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Log.coinbase.debug("modal didFinish host=\(webView.url?.host ?? "nil", privacy: .public) url=\(webView.url?.absoluteString ?? "nil", privacy: .public)")
        evaluateDismiss(forHost: webView.url?.host)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Log.coinbase.error("modal didFailProvisional host=\(webView.url?.host ?? "nil", privacy: .public) err=\(String(describing: error), privacy: .public)")
    }

    /// Single production decision point for closing on navigation. The test hook
    /// `testTriggerNavigationOff(host:)` calls this so test and production share
    /// one code path.
    func evaluateDismiss(forHost host: String?) {
        if hostPolicy.decision(forHost: host) == .close {
            dismissModal(reason: .success)
        }
    }

    func dismissModal(reason: ModalCloseReason) {
        guard !didDismiss else { return }
        didDismiss = true
        timeoutTask?.cancel()
        timeoutTask = nil
        autoCloseProbeTask?.cancel()
        autoCloseProbeTask = nil
        // Shut the WebView down before resuming waiters (and before any
        // post-close cleanup like website-data clearing). The modal stays alive
        // for the ~0.3s dismiss animation; left running, the live page can keep
        // landing Set-Cookie responses and re-writing storage, racing a caller's
        // clear. Stop the load, detach delegates, and navigate to about:blank so
        // the page's JS context is torn down and can't re-set cookies/storage.
        // We're closing regardless, so this is safe for every close reason.
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView?.load(URLRequest(url: URL(string: "about:blank")!))
        closeReason = reason
        onClose?(reason)
        let waiters = closeWaiters
        closeWaiters.removeAll()
        for waiter in waiters { waiter.resume(returning: reason) }
        // Drop any live popup and dismiss via the PRESENTER. Calling
        // `self.dismiss()` would dismiss the modal's presented popup (if one is
        // up) instead of the modal itself, stranding the modal on screen.
        // Dismissing the presenter tears down the modal and any popup it owns.
        // In test mode there is no presenter, so nothing is dismissed.
        popup = nil
        if let presenter = presentingViewController {
            presenter.dismiss(animated: true)
        }
    }

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        let reqURL = navigationAction.request.url?.absoluteString ?? "nil"
        let isNewWindow = navigationAction.targetFrame == nil
        Log.coinbase.debug("modal createWebViewWith requested url=\(reqURL, privacy: .public) isNewWindow=\(isNewWindow)")
        // Only a genuine new window (target=_blank / window.open) has a nil
        // targetFrame. For in-frame navigations, return nil so WebKit loads them
        // normally in the existing WebView instead of spawning a popup.
        guard isNewWindow else { return nil }
        // Build the popup from the WebKit-provided `configuration` so it shares
        // the opener's cookies and window.opener relationship; WebKit loads
        // navigationAction.request into the returned WebView itself.
        let popupWebView = WKWebView(frame: .zero, configuration: configuration)
        presentPopup(webView: popupWebView, title: titleText)
        return popupWebView
    }

    /// Presents a popup controller over the modal and tracks it. Extracted so a
    /// test hook can exercise popup presentation without a real window.open.
    @discardableResult
    func presentPopup(webView popupWebView: WKWebView, title: String?) -> PopupWebViewController {
        let popupVC = PopupWebViewController(webView: popupWebView, title: title)
        popupVC.onClose = { [weak self] in self?.popup = nil }
        popupVC.onIdPRejection = { url in
            Log.coinbase.error("Coinbase social login blocked (embedded WebView) at \(url.absoluteString, privacy: .public); user should use email/password or Apple.")
        }
        self.popup = popupVC
        let nav = UINavigationController(rootViewController: popupVC)
        nav.modalPresentationStyle = .fullScreen
        let willPresent = presentingViewController != nil || view.window != nil
        Log.coinbase.debug("modal presentPopup willPresent=\(willPresent)")
        if willPresent {
            present(nav, animated: true)
        }
        return popupVC
    }
}

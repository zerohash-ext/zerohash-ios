import Foundation
import UIKit
import WebKit

/// Failure modes of a single `AutomatedWebViewController` run. Kept small and
/// dedicated (rather than reusing `OffscreenWebViewRunner`'s `RunnerError`)
/// because this VC is single-shot and has no navigation-race/generation
/// machinery — the offscreen runner's stages don't apply here. Each case
/// produces a useful `localizedDescription` so the message survives to the
/// wire when the caller maps the thrown error.
enum AutomatedRunError: LocalizedError, Equatable {
    /// The outer wall-clock ceiling (`timeoutMs`) elapsed before the run
    /// completed. The JS automation has its own ~15s internal deadline; this
    /// is the broader Swift-side guard (the caller passes 30_000).
    case timeout
    /// A WebKit navigation failed (`didFail` / `didFailProvisionalNavigation`).
    case loadFailed(String)
    /// The run was torn down before producing an outcome (e.g. the VC was
    /// deallocated). Surfaces as a deterministic error instead of hanging.
    case abandoned

    var errorDescription: String? {
        switch self {
        case .timeout: return "timeout"
        case .loadFailed(let detail): return "loadFailed: \(detail)"
        case .abandoned: return "run abandoned"
        }
    }
}

/// A full-screen, single-shot UIViewController that hosts a VISIBLE, real-sized
/// `WKWebView` covered by an opaque native loading overlay. It loads a URL,
/// runs one automation script once the page settles, resolves with the
/// script's result (or throws), and ALWAYS self-dismisses exactly once.
///
/// WHY this exists separately from `OffscreenWebViewRunner` and
/// `ModalViewController`:
/// Coinbase's SPA does not render in an offscreen/unfocused WebView (frame
/// `.zero`, not in the view hierarchy), so the offscreen runner can't drive
/// the multi-step Receive automation behind `getDepositAddress`. The fix is a
/// VISIBLE, full-screen, real-sized WebView so the SPA renders, with a native
/// opaque overlay on top so the user never sees the Coinbase page. We do NOT
/// extend the offscreen runner (its navigation-race/generation/serial-queue
/// machinery exists for the long-lived, concurrent, reused `auth.status` path)
/// nor the login `ModalViewController` (interactive, dismiss-on-navigate
/// lifecycle). This VC is SINGLE-SHOT and SINGLE-USE:
/// present → load → settle → run script once → resolve → always dismiss.
@MainActor
final class AutomatedWebViewController: UIViewController, WKNavigationDelegate {

    // MARK: - Inputs

    private let initialURL: URL
    private let settle: @MainActor (URL) -> OffscreenSettleDecision
    private let script: String
    /// Bound arguments marshaled into JS variables by WebKit (`callAsyncJavaScript`),
    /// so request data reaches the script without being interpolated into its source.
    private let arguments: [String: Any]
    private let overlayOptions: OverlayOptions
    /// Contract-intended (contract.ts:38-41): when false, the branded loading
    /// overlay is suppressed so the user watches the automation play out on the
    /// underlying page. The automation runs identically either way.
    private let showOverlay: Bool
    /// When true, defer script evaluation until a Cloudflare challenge clears
    /// (see `runVisibleWebView` docs). Drives the polling path in `didFinish`.
    private let waitForChallengeClearance: Bool
    private let webViewConfig: WKWebViewConfiguration
    private let timeoutMs: Int
    /// Host-selected theme, forwarded to the branded overlay.
    private let theme: Theme

    // MARK: - State

    private var webView: WKWebView!
    /// Optional: only created/added when `showOverlay` is true. All references
    /// are guarded so the no-overlay path leaves the WebView fully visible.
    private var overlay: LoadingOverlayView?
    private var timeoutTask: Task<Void, Never>?

    /// Idempotency guard for the single completion. Mirrors
    /// `ModalViewController.didDismiss`: once true, every further completion
    /// path (settle, script result, JS throw, timeout, load failure) is a
    /// no-op, guaranteeing the run resolves and dismisses exactly once.
    private(set) var didComplete = false

    /// Set once a `.evaluate`/`.answer` decision has been taken, so further
    /// `didFinish` callbacks can't kick off a second evaluation.
    var didStartEvaluation = false

    /// True once the present transition has finished animating. If `complete()`
    /// fires while presentation is still in flight (e.g. a fast not-logged-in
    /// redirect or an early provisional navigation failure), UIKit can silently
    /// drop a `dismiss(animated:)` issued mid-transition, stranding this VC on
    /// screen. We track presentation so the dismiss is either issued now (safe)
    /// or deferred until presentation completes.
    private var didFinishPresenting = false
    /// Set when `complete()` wanted to dismiss but presentation hadn't finished.
    private var dismissPending = false

    /// The stored outcome, populated when the run completes. Lets a
    /// `runToResult()` call awaited AFTER completion return/throw immediately,
    /// mirroring `ModalViewController.waitForClose`'s already-resolved handling.
    enum Outcome {
        case success(Any?)
        case failure(Error)
    }
    private var outcome: Outcome?

    /// Box that carries an `Any?` script result across a `CheckedContinuation`.
    /// `Any?` is not `Sendable`; we mark the box `@unchecked Sendable` because
    /// every store and resume happens on the MainActor (mirrors the offscreen
    /// runner's `EvaluateRaceOutcome` rationale).
    private struct ResultBox: @unchecked Sendable { let value: Any? }

    /// Continuations awaiting `runToResult()` while the run is still in flight.
    private var resultWaiters: [CheckedContinuation<ResultBox, Error>] = []

    // MARK: - Init

    init(url: URL,
         settle: @escaping @MainActor (URL) -> OffscreenSettleDecision,
         script: String,
         arguments: [String: Any] = [:],
         overlay: OverlayOptions,
         showOverlay: Bool,
         waitForChallengeClearance: Bool = false,
         sharedConfig: WKWebViewConfiguration,
         timeoutMs: Int,
         theme: Theme = .system) {
        self.initialURL = url
        self.settle = settle
        self.script = script
        self.arguments = arguments
        self.overlayOptions = overlay
        self.showOverlay = showOverlay
        self.waitForChallengeClearance = waitForChallengeClearance
        self.webViewConfig = sharedConfig
        self.timeoutMs = timeoutMs
        self.theme = theme
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - View lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        // The WebView must have a REAL, non-zero, device-sized frame so the
        // Coinbase SPA actually renders — full-bleed (edge-to-edge, including
        // behind the status bar) is best for rendering.
        webView = WKWebView(frame: view.bounds, configuration: webViewConfig)
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        // DEBUG: allow attaching Safari Web Inspector (Develop ▸ Simulator ▸
        // this page) so the live Coinbase page, its console, and the replay
        // fetch in the Network tab can be inspected while diagnosing hangs.
        #if DEBUG
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        #endif
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        // Opaque native overlay ON TOP of the WebView, covering the full view
        // bounds so the user never sees the underlying page while automation
        // runs. It auto-starts on `didMoveToWindow`, but we start() defensively.
        //
        // Contract-intended (contract.ts:38-41): when `showOverlay` is false
        // we SKIP the overlay entirely so the user can watch the automation
        // play out on the underlying page. The automation itself (settle /
        // evaluate / timeout / dismiss) is unchanged — only the overlay's
        // presence differs.
        if showOverlay {
            presentOverlay()
        }

        webView.load(URLRequest(url: initialURL))
        scheduleTimeout()
        Log.coinbase.debug("AutomatedWebViewController loading url=\(self.initialURL.absoluteString, privacy: .private) timeoutMs=\(self.timeoutMs)")
    }

    /// Creates, pins, and starts the branded overlay over the web view, unless
    /// one already exists. Idempotent so the challenge-clearance path can call
    /// it safely even if `showOverlay` already created one. The overlay is added
    /// last, so it sits above the web view and covers the page.
    private func presentOverlay() {
        guard overlay == nil else { return }
        let overlay = LoadingOverlayView(options: overlayOptions, theme: theme)
        view.addSubview(overlay)
        overlay.pinToSuperview()
        overlay.start()
        self.overlay = overlay
    }

    private func revealOverlay(_ revealed: Bool) {
        overlay?.isHidden = revealed
    }

    // MARK: - Challenge-clearance polling

    /// JS expression that is truthy while a Cloudflare interstitial/Turnstile
    /// is on the page. Evaluated against the LIVE document each poll, so it
    /// keeps working across the reload Cloudflare performs after a solve.
    private static let challengeProbe =
        "(!!(window._cf_chl_opt || document.querySelector('#challenge-running, #cf-challenge-running, #challenge-stage, #cf-chl-widget, iframe[src*=\"challenges.cloudflare.com\"], div[class=\"ch-title-zone\"]')))"

    /// Polls the live page until no Cloudflare challenge is present, then
    /// restores the overlay and evaluates the automation script ONCE. Because
    /// each poll is an independent `evaluateJavaScript`, this survives the
    /// post-solve page reload that would destroy an in-page wait. Bounded by the
    /// outer `scheduleTimeout` ceiling, which completes the run on expiry.
    private func pollUntilChallengeClears() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            var didReveal = false
            while !self.didComplete {
                var challenged = true
                do {
                    let result = try await self.webView.evaluateJavaScript(Self.challengeProbe)
                    challenged = (result as? Bool) ?? false
                } catch {
                    // Page is mid-navigation/reload (typical right after a solve)
                    // — treat as still challenged and keep polling.
                    challenged = true
                }
                if self.didComplete { return }
                if !challenged {
                    Log.coinbase.debug("challenge cleared; restoring overlay and replaying")
                    self.revealOverlay(false)
                    self.presentOverlay()
                    self.evaluateScript(on: self.webView)
                    return
                }
                if !didReveal {
                    Log.coinbase.debug("Cloudflare challenge up; lifting overlay so the user can solve it")
                    self.revealOverlay(true)
                    didReveal = true
                }
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            }
        }
    }

    /// Outer wall-clock ceiling. On expiry the run completes by THROWING
    /// `.timeout`. Mirrors `ModalViewController.scheduleTimeout`.
    private func scheduleTimeout() {
        let ms = timeoutMs
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
            guard let self, !Task.isCancelled else { return }
            self.complete(.failure(AutomatedRunError.timeout))
        }
    }

    // MARK: - Public API

    /// Suspends until the run completes; returns the script result (`Any?`) or
    /// throws. If the run already completed before this is awaited, returns or
    /// throws the stored outcome immediately.
    func runToResult() async throws -> Any? {
        if let outcome {
            switch outcome {
            case .success(let value): return value
            case .failure(let error): throw error
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            resultWaiters.append(continuation)
        }.value
    }

    // MARK: - Navigation delegate

    // Navigation host allowlist. This WebView carries the live Coinbase session
    // and injects the balance / deposit-address automation, so it must only load
    // Coinbase-owned origins in the main frame. Sub-frames (e.g. the Cloudflare
    // Turnstile widget) are third-party by design and left alone.
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        #if DEBUG
        Log.coinbase.debug("navAction -> \(navigationAction.request.url?.absoluteString ?? "?", privacy: .public)")
        #endif
        if navigationAction.targetFrame?.isMainFrame == false {
            decisionHandler(.allow)
            return
        }
        guard CoinbaseHostPolicy.isTrusted(navigationAction.request.url) else {
            Log.coinbase.error("blocked off-Coinbase navigation host=\(navigationAction.request.url?.host ?? "?", privacy: .private)")
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        #if DEBUG
        Log.coinbase.debug("didStartProvisional url=\(webView.url?.absoluteString ?? "?", privacy: .public)")
        #endif
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Once evaluation/answer is underway, ignore further navigations —
        // the run is single-shot.
        guard !didComplete, !didStartEvaluation else { return }
        let url = webView.url ?? initialURL
        let decision = settle(url)
        #if DEBUG
        Log.coinbase.debug("didFinish url=\(url.absoluteString, privacy: .public) decision=\(String(describing: decision), privacy: .public)")
        #else
        Log.coinbase.debug("didFinish host=\(url.host ?? "?", privacy: .private) decision=\(String(describing: decision), privacy: .public)")
        #endif
        switch decision {
        case .waitMore:
            // Do nothing; wait for the next didFinish.
            return
        case .answer(let value):
            didStartEvaluation = true
            complete(.success(value))
        case .evaluate:
            // Lock now so the post-solve reload's didFinish can't kick off a
            // second path; the poll (or single eval) owns evaluation from here.
            didStartEvaluation = true
            if waitForChallengeClearance {
                pollUntilChallengeClears()
            } else {
                evaluateScript(on: webView)
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Log.coinbase.error("didFail url=\(webView.url?.absoluteString ?? "?", privacy: .public) err=\(error.localizedDescription, privacy: .public)")
        complete(.failure(AutomatedRunError.loadFailed(error.localizedDescription)))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Log.coinbase.error("didFailProvisional url=\(webView.url?.absoluteString ?? "?", privacy: .public) err=\(error.localizedDescription, privacy: .public)")
        complete(.failure(AutomatedRunError.loadFailed(error.localizedDescription)))
    }

    // MARK: - Script evaluation

    /// Runs the one-shot automation script a SINGLE time. The automation is a
    /// long async IIFE that performs all DOM steps internally and resolves
    /// once; we evaluate it exactly once and complete (no loop/re-evaluate).
    private func evaluateScript(on webView: WKWebView) {
        let script = self.script
        let arguments = self.arguments
        Log.coinbase.debug("evaluateScript: starting injected automation (len=\(script.count))")
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await Self.evaluateAsync(on: webView, script: script, arguments: arguments)
                Log.coinbase.debug("evaluateScript: returned resultType=\(String(describing: type(of: result as Any)), privacy: .public)")
                self.complete(.success(result))
            } catch {
                Log.coinbase.error("evaluateScript: threw \(error.localizedDescription, privacy: .public)")
                self.complete(.failure(error))
            }
        }
    }

    /// Mirrors `OffscreenWebViewRunner.evaluateAsync` precisely so error
    /// semantics match the offscreen path: the script is wrapped as
    /// `return (expr);` (trailing `;`/whitespace stripped, parens defeat ASI),
    /// evaluated via `callAsyncJavaScript(... contentWorld: .page)`, and on
    /// error the `WKJavaScriptExceptionMessage` is extracted and rethrown as a
    /// `JSException` (the same type used by the offscreen runner) so messages
    /// like "requires an amount" survive to the web side's regex matching.
    private static func evaluateAsync(on webView: WKWebView, script: String, arguments: [String: Any] = [:]) async throws -> Any? {
        var expr = script
        while let last = expr.unicodeScalars.last,
              last == ";" || CharacterSet.whitespacesAndNewlines.contains(last) {
            expr.removeLast()
        }
        let wrapped = "\(TelemetryInstall.prelude())return (\n\(expr)\n);"
        do {
            return try await webView.callAsyncJavaScript(
                wrapped,
                arguments: arguments,
                in: nil,
                contentWorld: .page
            )
        } catch {
            let nsErr = error as NSError
            let jsMessage = nsErr.userInfo["WKJavaScriptExceptionMessage"] as? String
            Log.coinbase.error("evaluateAsync threw domain=\(nsErr.domain, privacy: .public) code=\(nsErr.code) msg=\(jsMessage ?? "", privacy: .public)")
            if let jsMessage, !jsMessage.isEmpty {
                throw JSException(message: jsMessage)
            }
            throw error
        }
    }

    // MARK: - Completion (idempotent, guaranteed dismissal)

    /// THE critical invariant: completion is idempotent and dismissal is
    /// guaranteed on EVERY path (script success, settle answer, JS throw,
    /// timeout, load failure). The first call wins; subsequent calls are
    /// no-ops. On completion we cancel the timeout, stop the overlay, resolve
    /// every waiter with the outcome, tear down the WebView, and dismiss if
    /// presented.
    func complete(_ result: Outcome) {
        guard !didComplete else { return }
        didComplete = true

        timeoutTask?.cancel()
        timeoutTask = nil

        overlay?.stop()

        // Stop loading and clear the delegate so late WebKit callbacks can't
        // fire against a torn-down VC (avoids leaks / use-after-complete).
        webView?.stopLoading()
        webView?.navigationDelegate = nil

        outcome = result
        let waiters = resultWaiters
        resultWaiters.removeAll()
        for waiter in waiters {
            switch result {
            case .success(let value): waiter.resume(returning: ResultBox(value: value))
            case .failure(let error): waiter.resume(throwing: error)
            }
        }

        // In test mode the presenting VC is nil, so guard to avoid crashing
        // (mirrors ModalViewController). This VC is presented directly
        // .fullScreen by the caller — dismiss self exactly once.
        if presentingViewController != nil {
            dismissWhenPresented()
        }
    }

    /// Dismisses self, but never mid-present: a `dismiss(animated:)` issued
    /// while the present transition is still animating can be dropped by UIKit.
    /// If presentation hasn't finished yet, we mark `dismissPending` and let
    /// `presentationDidFinish()` issue the dismiss once the transition lands.
    private func dismissWhenPresented() {
        guard didFinishPresenting else {
            dismissPending = true
            return
        }
        dismiss(animated: true)
    }

    /// Called by the presenter from `present(_:animated:completion:)` once the
    /// present transition has finished animating. Flushes any dismiss that
    /// `complete()` requested while the transition was still in flight.
    func presentationDidFinish() {
        didFinishPresenting = true
        if dismissPending {
            dismissPending = false
            dismiss(animated: true)
        }
    }
}

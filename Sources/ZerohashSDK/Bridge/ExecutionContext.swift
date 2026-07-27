import Foundation
import WebKit

/// Handle for the interactive login modal (`auth.login`): a user-driven WebView
/// with chrome (title + Cancel) that resolves when the user finishes or dismisses.
/// Long-lived automation sessions (withdraw) use `AutomationSessionHandle` instead.
@MainActor
public protocol ModalWebViewHandle: AnyObject {
    var currentURL: URL? { get }
    func dismiss() async
    /// Synchronous JS evaluation (`evaluateJavaScript`). Does NOT await Promises —
    /// use for quick sync probes (e.g. auth.login's autoClose check).
    func evaluate(_ js: String) async throws -> Any?
    /// Suspends until the modal closes, returning why it closed. If the modal
    /// has already closed, returns the recorded reason immediately.
    func waitForClose() async -> ModalCloseReason
}

/// Handle for a long-lived, automation-driven WebView session (withdraw): the page
/// is driven by injected Promise-based scripts across multiple bridge calls, can be
/// hidden behind a branded overlay, and can step aside / resume so the host app can
/// collect an OTP mid-flow. Distinct from `ModalWebViewHandle` (the user-driven
/// login modal) — this one is never user-actionable and carries no Cancel/close chrome.
@MainActor
public protocol AutomationSessionHandle: AnyObject {
    var currentURL: URL? { get }
    func dismiss() async
    /// Async JS evaluation (`callAsyncJavaScript`). Awaits a Promise-returning
    /// script and surfaces a thrown JS error's message. `js` is (or ends with) an
    /// expression. `arguments` are passed to WebKit as bound JS variables (marshaled
    /// from native values, never interpolated into the source) — use them to feed
    /// request data into the script without building code from it.
    func evaluateAsync(_ js: String, arguments: [String: Any]) async throws -> Any?
    /// Suspends until the session's initial page load finishes (first `didFinish`).
    /// Returns immediately if it has already loaded. Awaited before the first
    /// `evaluateAsync` so the script runs in the live page context, not a
    /// blank/about:blank context about to be replaced by the navigation.
    func awaitInitialLoad() async
    /// Lifts (true) or restores (false) the branded loading overlay covering the
    /// page, when one is present (no-op otherwise). Lets the session reveal the
    /// live page mid-flow — e.g. for passkey / ID-verification the user completes
    /// in Coinbase's own UI — then re-cover it.
    func revealOverlay(_ revealed: Bool)
    /// Temporarily dismiss the presentation so the host app is shown (e.g. to
    /// collect an OTP), WITHOUT ending the session — the caller keeps this handle
    /// alive and calls `resume()` to bring it back. The webview/page state is
    /// preserved across the step-aside.
    func stepAside() async
    /// Re-present the session after `stepAside()`, with its webview/page intact.
    func resume() async
    /// Suspend the session's wall-clock timeout (cancels the pending force-close)
    /// while parked on a user-input step — the user may take arbitrarily long to
    /// enter an OTP or complete a passkey, and that wait must not kill the session.
    /// No-op if no timeout is pending.
    func pauseTimeout()
    /// Restart the wall-clock timeout from zero — called before each automation leg
    /// (e.g. on `continue`) so the leg gets a fresh budget rather than racing a
    /// clock that started at `start`. Treats user-input steps as indefinite while
    /// still bounding the automation itself.
    func restartTimeout()
}

public extension AutomationSessionHandle {
    /// Convenience: evaluate with no bound arguments.
    func evaluateAsync(_ js: String) async throws -> Any? {
        try await evaluateAsync(js, arguments: [:])
    }
}

public enum ContextError: Error, Equatable {
    case hostUnavailable
}

@MainActor
public protocol ExecutionContext {
    /// Modal WebView for interactive flows (auth.login). User-driven, with chrome
    /// (title + Cancel button), wrapped in a navigation controller. Keyed by a host
    /// policy (stay-open + success hosts) so social-login redirects to IdP hosts do
    /// not prematurely dismiss it.
    /// `autoClose`: optional generic JS probe the modal polls while open; when
    /// it matches, the modal force-closes with `.conditionMet(code)` carrying the
    /// probe's condition code. The caller interprets that code (e.g. Coinbase →
    /// passkey-only / account-not-found outcomes).
    /// `documentStartJS`: optional caller script injected at documentStart on
    /// every main-frame load (e.g. Coinbase hiding the Google/passkey options
    /// that can't complete in an embedded WebView).
    func presentModalWebView(
        url: URL,
        hostPolicy: ModalHostPolicy,
        title: String?,
        autoClose: ModalAutoClose?,
        documentStartJS: String?
    ) async throws -> ModalWebViewHandle

    /// Long-lived, automation-driven WebView session for multi-call flows that
    /// need the page rendered and driven across several bridge requests (withdraw).
    /// Presented full-screen with NO chrome (the user can't act on it). When
    /// `showOverlay` is true a branded loading overlay covers the page (toggle via
    /// `AutomationSessionHandle.revealOverlay`) so the automation can drive Coinbase
    /// unseen, revealing it only for steps the user completes in Coinbase's own UI.
    func presentAutomationSession(
        url: URL,
        overlay: OverlayOptions,
        showOverlay: Bool
    ) async throws -> AutomationSessionHandle

    /// Offscreen WebView for stateless probes (auth.status).
    /// Returns the JSON-decoded value of `injectedScript` when the page
    /// settles (or the platform's `.answer` payload if the predicate
    /// short-circuits on a recognised URL).
    /// `arguments` are passed to WebKit as bound JS variables (marshaled from
    /// native values, never interpolated into the source) — use them to feed
    /// request data into `injectedScript` without building code from it.
    func runOffscreenWebView(
        url: URL,
        settle: @MainActor @escaping (URL) -> OffscreenSettleDecision,
        injectedScript: String,
        arguments: [String: Any],
        timeoutMs: Int
    ) async throws -> Any?

    /// Visible-but-overlaid WebView for interactive-page automation that needs
    /// the page to actually render (e.g. Coinbase getDepositAddress — the SPA
    /// will not render offscreen). Presents a full-screen AutomatedWebViewController
    /// with a native loading overlay covering the page, runs `injectedScript`
    /// once the page settles, and returns its JSON-decoded result (or the
    /// platform's `.answer` payload if the settle predicate short-circuits).
    ///
    /// `showOverlay` is part of the wire contract: pass false to
    /// suppress the branded loading overlay so the user watches the automation
    /// play out on the underlying page. The automation runs identically either
    /// way; only the overlay's presence changes.
    /// `waitForChallengeClearance`: when true, the runner does NOT evaluate the
    /// script as soon as the page settles. Instead it polls the live document
    /// for a Cloudflare challenge and only runs the script once the challenge is
    /// gone — surviving the page reload Cloudflare performs after the user
    /// solves the Turnstile (which would otherwise destroy an in-page wait).
    /// When the challenge clears, the branded overlay is restored before the
    /// script runs. Used by the Coinbase balance challenge retry.
    /// `arguments` are passed to WebKit as bound JS variables (marshaled from
    /// native values, never interpolated into the source) — use them to feed
    /// request data into `injectedScript` without building code from it.
    func runVisibleWebView(
        url: URL,
        settle: @MainActor @escaping (URL) -> OffscreenSettleDecision,
        injectedScript: String,
        arguments: [String: Any],
        overlay: OverlayOptions,
        showOverlay: Bool,
        waitForChallengeClearance: Bool,
        timeoutMs: Int
    ) async throws -> Any?

    /// Shared cookie/data store. Default: WKWebsiteDataStore.default().
    var dataStore: WKWebsiteDataStore { get }
}

public extension ExecutionContext {
    /// Convenience: host policy without an auto-close probe or injected script.
    func presentModalWebView(
        url: URL,
        hostPolicy: ModalHostPolicy,
        title: String?
    ) async throws -> ModalWebViewHandle {
        try await presentModalWebView(url: url, hostPolicy: hostPolicy, title: title,
                                      autoClose: nil, documentStartJS: nil)
    }

    /// Convenience: host policy + auto-close probe, no injected script.
    func presentModalWebView(
        url: URL,
        hostPolicy: ModalHostPolicy,
        title: String?,
        autoClose: ModalAutoClose?
    ) async throws -> ModalWebViewHandle {
        try await presentModalWebView(url: url, hostPolicy: hostPolicy, title: title,
                                      autoClose: autoClose, documentStartJS: nil)
    }

    /// Legacy single-host convenience: stay open on `host`, success on any other
    /// host. Forwards to the policy overload. `autoClose` defaults to nil so both
    /// `(…:title:)` and `(…:title:autoClose:)` legacy call sites resolve here.
    func presentModalWebView(
        url: URL,
        dismissOnNavigateAwayFromHost host: String?,
        title: String?,
        autoClose: ModalAutoClose? = nil
    ) async throws -> ModalWebViewHandle {
        let policy = host.map { ModalHostPolicy(legacyDismissAwayFromHost: $0) }
            ?? ModalHostPolicy(stayOpenHosts: [], successHosts: [], closeOnUnknownHost: false)
        return try await presentModalWebView(url: url, hostPolicy: policy, title: title,
                                              autoClose: autoClose, documentStartJS: nil)
    }

    /// Convenience overload that always evaluates the script
    /// (preserves pre-Group-A call sites).
    func runOffscreenWebView(
        url: URL,
        injectedScript: String,
        timeoutMs: Int
    ) async throws -> Any? {
        try await runOffscreenWebView(
            url: url,
            settle: { _ in .evaluate },
            injectedScript: injectedScript,
            arguments: [:],
            timeoutMs: timeoutMs
        )
    }

    /// Convenience: settle predicate, no bound arguments (preserves call sites
    /// that inject a self-contained script carrying no request data, e.g.
    /// `auth.status`).
    func runOffscreenWebView(
        url: URL,
        settle: @MainActor @escaping (URL) -> OffscreenSettleDecision,
        injectedScript: String,
        timeoutMs: Int
    ) async throws -> Any? {
        try await runOffscreenWebView(
            url: url,
            settle: settle,
            injectedScript: injectedScript,
            arguments: [:],
            timeoutMs: timeoutMs
        )
    }

    /// Convenience: visible WebView with no bound arguments.
    func runVisibleWebView(
        url: URL,
        settle: @MainActor @escaping (URL) -> OffscreenSettleDecision,
        injectedScript: String,
        overlay: OverlayOptions,
        showOverlay: Bool,
        waitForChallengeClearance: Bool,
        timeoutMs: Int
    ) async throws -> Any? {
        try await runVisibleWebView(
            url: url,
            settle: settle,
            injectedScript: injectedScript,
            arguments: [:],
            overlay: overlay,
            showOverlay: showOverlay,
            waitForChallengeClearance: waitForChallengeClearance,
            timeoutMs: timeoutMs
        )
    }
}

/// Internal capability interface for emitting BridgeEvents back to the web side.
/// Implemented by the AutomationWebView router. ExecutionContextImpl depends on this protocol
/// (not the concrete handler) so it can be unit-tested.
protocol BridgeEventEmitting: AnyObject {
    func emitEvent(correlationId: String, type: String)
}

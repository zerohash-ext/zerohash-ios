import Foundation
import WebKit

/// Wraps a WebKit JavaScript exception so the underlying
/// `WKJavaScriptExceptionMessage` (e.g. a `throw new Error("requires an amount")`
/// from an injected script) survives as `localizedDescription`. WebKit otherwise
/// reports only a generic "A JavaScript exception occurred." for these errors.
struct JSException: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Stage at which a runner timeout fired. Surfaced through
/// `AutomationWebViewError.platformThrew` so the JS side can distinguish
/// "page didn't load" from "navigation race exhausted the deadline".
public enum RunnerTimeoutStage: String, Equatable, Sendable {
    /// `webView.load(...)` did not produce a `didFinish` in time.
    case initialLoad
    /// `callAsyncJavaScript` did not return in time.
    case scriptEvaluation
    /// Settle predicate kept returning `.waitMore` until the deadline.
    case navigationSettle
}

enum RunnerError: Error, Equatable {
    case timeout(stage: RunnerTimeoutStage)
    case loadFailed(String)
    /// A mid-script navigation killed the JS context and no further
    /// `didFinish` arrived before the deadline.
    case navigationLost
}

extension RunnerError: LocalizedError {
    /// Wire-facing text; without it Foundation emits the useless
    /// "(<Module>.RunnerError error <N>.)" — the case index, stage discarded. These
    /// leading tokens are a contract with the web classifier
    /// (translate-scraping-error.ts); rewording them downgrades users to the generic
    /// "Something went wrong" bucket.
    var errorDescription: String? {
        switch self {
        case .timeout(let stage):     return "timeout: \(stage.rawValue)"
        case .loadFailed(let detail): return "loadFailed: \(detail)"
        case .navigationLost:         return "navigationLost"
        }
    }
}

/// One-shot async signal used by `OffscreenWebViewRunner.runSerialised`.
/// The gate task awaits `wait()`; the caller invokes `fire()` after the
/// body completes, releasing the next caller in the queue.
private actor SerialGateSignal {
    private var fired = false
    private var waiter: CheckedContinuation<Void, Never>?

    func wait() async {
        if fired { return }
        await withCheckedContinuation { c in
            waiter = c
        }
    }

    func fire() {
        guard !fired else { return }
        fired = true
        waiter?.resume()
        waiter = nil
    }
}

/// Outcome of racing a script-evaluation against a next-`didFinish` observer.
/// `Any?` cannot be made `Sendable`; we mark the enum `@unchecked Sendable`
/// because every fulfilment and consumption happens on the MainActor.
private enum EvaluateRaceOutcome: @unchecked Sendable {
    case scriptResult(Any?)
    case scriptError(Error)
    case navigated(URL)
}

/// One-shot signal used to race `evaluateAsync` against a next-`didFinish`.
/// Idempotent: subsequent `fulfill` calls are dropped. Implemented as a
/// MainActor-isolated class so we don't need `Sendable` on the payload type.
@MainActor
private final class OneShotSignalMA<T: Sendable> {
    private var resolved: T?
    private var waiter: CheckedContinuation<T, Never>?

    func fulfill(_ value: T) {
        if resolved != nil { return }
        if let w = waiter {
            waiter = nil
            w.resume(returning: value)
        } else {
            resolved = value
        }
    }

    func wait() async -> T {
        if let v = resolved { return v }
        return await withCheckedContinuation { cont in
            waiter = cont
        }
    }
}

@MainActor
final class OffscreenWebViewRunner: NSObject, WKNavigationDelegate {
    private let config: WKWebViewConfiguration
    private var webView: WKWebView?

    /// Web view of the CURRENT run. The runner is reused and never clears the old
    /// view's `navigationDelegate`, so a stale callback can still land here.
    private var activeWebViewId: Int?

    /// Monotonic counter incremented on every `didFinish`. Lets a waiter
    /// suspended after generation `N` resume on any later generation,
    /// regardless of whether `didFinish` arrived before or after the
    /// waiter was registered.
    private var navigationGeneration: Int = 0

    /// URL of the most recent successful `didFinish`. `nil` until the first
    /// load completes; updated on every subsequent `didFinish`.
    private var lastFinishedURL: URL?

    /// Each waiter resumes once `navigationGeneration > minGeneration`.
    private struct Waiter {
        let minGeneration: Int
        let cont: CheckedContinuation<URL, Error>
    }
    private var waiters: [Waiter] = []

    /// Monotonic id incremented on every `run`/`runHTML`/`abortCurrentRun`
    /// call. The current run's tasks check that this hasn't changed before
    /// resuming a continuation; if it has, the run was abandoned and the
    /// continuation throws `.navigationLost`.
    private var runGeneration: Int = 0

    /// Whether the navigation host allowlist is enforced for the current run.
    /// True for remote-URL runs (`_run`) — the money-movement surface, which must
    /// stay on Coinbase. False for local-HTML runs (`_runHTML`), where we author
    /// the content ourselves so its nominal baseURL host is not a trust boundary.
    /// Safe as shared state: runs are serialised (`runSerialised`), never concurrent.
    private var enforceHostAllowlist = true

    /// Serialises concurrent `run`/`runHTML` calls on the same runner.
    /// Implemented as a single-slot async queue so callers wait their turn
    /// without blocking the MainActor.
    private var serialQueue: Task<Void, Never>?

    init(config: WKWebViewConfiguration) {
        self.config = config
        super.init()
        Log.runner.debug("init pid=\(ProcessInfo.processInfo.processIdentifier) thread=\(Thread.isMainThread ? "main" : "bg")")
    }

    /// Network path: load `url`, then evaluate `script` and await its result.
    /// `script` is treated as the body of an async function — it may use
    /// `await` and may end with an expression statement (an IIFE returning a
    /// Promise is fine; we wrap it in `return ...;` so the Promise is awaited).
    func run(url: URL, script: String, arguments: [String: Any] = [:], timeoutMs: Int) async throws -> Any? {
        try await runSerialised { [self] in
            try await self._run(url: url, settle: { _ in .evaluate }, script: script, arguments: arguments, timeoutMs: timeoutMs)
        }
    }

    /// Test/local-html path: same shape but uses loadHTMLString so we don't hit
    /// the network. baseURL gives evaluateJavaScript a sensible origin.
    func runHTML(html: String, baseURL: URL, script: String, arguments: [String: Any] = [:], timeoutMs: Int) async throws -> Any? {
        try await runSerialised { [self] in
            try await self._runHTML(html: html, baseURL: baseURL, settle: { _ in .evaluate }, script: script, arguments: arguments, timeoutMs: timeoutMs)
        }
    }

    /// Settle-predicate variant of `run(url:script:timeoutMs:)`. The predicate
    /// is called on each `didFinish` (including the first one); the runner
    /// dispatches according to the returned `OffscreenSettleDecision`.
    func run(
        url: URL,
        settle: @MainActor @escaping (URL) -> OffscreenSettleDecision,
        script: String,
        arguments: [String: Any] = [:],
        timeoutMs: Int
    ) async throws -> Any? {
        try await runSerialised { [self] in
            try await self._run(url: url, settle: settle, script: script, arguments: arguments, timeoutMs: timeoutMs)
        }
    }

    /// HTML-string equivalent of `run(url:settle:script:timeoutMs:)`.
    func runHTML(
        html: String,
        baseURL: URL,
        settle: @MainActor @escaping (URL) -> OffscreenSettleDecision,
        script: String,
        arguments: [String: Any] = [:],
        timeoutMs: Int
    ) async throws -> Any? {
        try await runSerialised { [self] in
            try await self._runHTML(html: html, baseURL: baseURL, settle: settle, script: script, arguments: arguments, timeoutMs: timeoutMs)
        }
    }

    private func _run(
        url: URL,
        settle: @MainActor @escaping (URL) -> OffscreenSettleDecision,
        script: String,
        arguments: [String: Any],
        timeoutMs: Int
    ) async throws -> Any? {
        runGeneration += 1
        let myGeneration = runGeneration
        Log.runner.debug("[runGen=\(myGeneration)] _run url=\(url.absoluteString, privacy: .private) timeoutMs=\(timeoutMs)")
        enforceHostAllowlist = true
        let webView = createWebView()
        return try await runWithSettle(
            on: webView,
            kickoff: { webView.load(URLRequest(url: url)) },
            settle: settle,
            script: script,
            arguments: arguments,
            timeoutMs: timeoutMs,
            myGeneration: myGeneration
        )
    }

    private func _runHTML(
        html: String,
        baseURL: URL,
        settle: @MainActor @escaping (URL) -> OffscreenSettleDecision,
        script: String,
        arguments: [String: Any],
        timeoutMs: Int
    ) async throws -> Any? {
        runGeneration += 1
        let myGeneration = runGeneration
        Log.runner.debug("[runGen=\(myGeneration)] _runHTML baseURL=\(baseURL.absoluteString, privacy: .private) timeoutMs=\(timeoutMs)")
        enforceHostAllowlist = false
        let webView = createWebView()
        return try await runWithSettle(
            on: webView,
            kickoff: { webView.loadHTMLString(html, baseURL: baseURL) },
            settle: settle,
            script: script,
            arguments: arguments,
            timeoutMs: timeoutMs,
            myGeneration: myGeneration
        )
    }

    private func runSerialised<T>(
        _ body: @escaping @MainActor () async throws -> T
    ) async throws -> T {
        // Single-slot async queue. The runner is @MainActor, so the
        // read/store of `serialQueue` cannot interleave between concurrent
        // callers. Each caller publishes a `Task<Void, Never>` gate that
        // completes only when this caller's body has finished, so a
        // successor (which awaits its predecessor's `.value`) cannot
        // proceed until its predecessor's body has completed.
        let predecessor = serialQueue
        let hasPredecessor = predecessor != nil
        let queueStart = Date()
        Log.runner.debug("runSerialised entering hasPredecessor=\(hasPredecessor)")
        // A signal that the gate task awaits — we resume it after running
        // the body, which is what unblocks the next caller in line.
        let signal = SerialGateSignal()
        let gate = Task<Void, Never> {
            await predecessor?.value
            await signal.wait()
        }
        serialQueue = gate
        // Wait for our turn.
        await predecessor?.value
        if hasPredecessor {
            let queuedMs = Int(Date().timeIntervalSince(queueStart) * 1000)
            Log.runner.notice("runSerialised predecessor finished after \(queuedMs)ms; running body")
        }
        defer {
            Task { await signal.fire() }
            if self.serialQueue == gate {
                self.serialQueue = nil
            }
            Log.runner.debug("runSerialised body finished; gate fired")
        }
        return try await body()
    }

    private func runWithSettle(
        on webView: WKWebView,
        kickoff: @Sendable @escaping () -> Void,
        settle: @MainActor (URL) -> OffscreenSettleDecision,
        script: String,
        arguments: [String: Any],
        timeoutMs: Int,
        myGeneration: Int
    ) async throws -> Any? {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutMs) / 1000.0)
        let snapshot = navigationGeneration
        Log.runner.debug("[runGen=\(myGeneration)] runWithSettle starting navGen-snapshot=\(snapshot) timeoutMs=\(timeoutMs)")
        var settledURL = try await withTimeout(ms: timeoutMs, stage: .initialLoad) {
            try await self.waitForLoad(after: snapshot, kickoff: kickoff)
        }
        Log.runner.debug("[runGen=\(myGeneration)] initial load settled url=\(settledURL.absoluteString, privacy: .private) navGen=\(self.navigationGeneration)")
        try Self.checkGeneration(current: self.runGeneration, expected: myGeneration)

        var iter = 0
        while true {
            iter += 1
            // Deadline guard so a misbehaving page that keeps navigating
            // and never settles can't loop forever between .evaluate and
            // a re-consult of the predicate.
            let remainingSec = deadline.timeIntervalSinceNow
            guard remainingSec > 0 else {
                Log.runner.error("[runGen=\(myGeneration)] iter=\(iter) deadline exhausted; throwing .timeout(.navigationSettle)")
                throw RunnerError.timeout(stage: .navigationSettle)
            }
            let decision = settle(settledURL)
            switch decision {
            case .answer(let value):
                Log.runner.debug("[runGen=\(myGeneration)] iter=\(iter) settle(host=\(settledURL.host ?? "?", privacy: .private)) => .answer; returning without script")
                return value
            case .evaluate:
                let remainingMs = Int(remainingSec * 1000)
                Log.runner.debug("[runGen=\(myGeneration)] iter=\(iter) settle(host=\(settledURL.host ?? "?", privacy: .private)) => .evaluate; running script (remaining=\(remainingMs)ms)")
                let evalSnapshot = navigationGeneration
                let evalStart = Date()
                let signal = OneShotSignalMA<EvaluateRaceOutcome>()

                // Fire-and-forget script evaluation. iOS 17 simulator's
                // `callAsyncJavaScript` can take 20-30s to fire the
                // "no longer reachable" error after a navigation; we don't
                // want to block on it. The Task continues running in the
                // background and eventually fulfils the signal (which is
                // a no-op if already resolved by the navigation watcher).
                let evalTask = Task { @MainActor in
                    do {
                        let r = try await Self.evaluateAsync(on: webView, script: script, arguments: arguments)
                        signal.fulfill(.scriptResult(r))
                    } catch {
                        signal.fulfill(.scriptError(error))
                    }
                }

                // Concurrent navigation watcher.
                let navTask = Task { @MainActor in
                    do {
                        let u = try await self.waitForLoad(after: evalSnapshot)
                        signal.fulfill(.navigated(u))
                    } catch {
                        // Loser of the race; eval branch will resolve. No-op.
                    }
                }

                let raceOutcome = await signal.wait()
                let raceMs = Int(Date().timeIntervalSince(evalStart) * 1000)
                // Best-effort cancel of the loser. callAsyncJavaScript
                // doesn't honour Task cancellation but the resulting
                // fulfil is a no-op since the signal is already resolved.
                evalTask.cancel()
                navTask.cancel()

                switch raceOutcome {
                case .scriptResult(let value):
                    Log.runner.debug("[runGen=\(myGeneration)] iter=\(iter) script returned in \(raceMs)ms")
                    try Self.checkGeneration(current: self.runGeneration, expected: myGeneration)
                    return value

                case .scriptError(let error):
                    let nsErr = error as NSError
                    if Self.isPageNavigatedError(nsErr) {
                        // Rare on iOS 17 simulator: the script error came in
                        // before navTask observed the new didFinish. Same
                        // recovery path as the .navigated case.
                        let newURL = lastFinishedURL ?? settledURL
                        let prevHost = settledURL.host ?? "?"
                        let newHost = newURL.host ?? "?"
                        Log.runner.debug("[runGen=\(myGeneration)] iter=\(iter) script killed by navigation in \(raceMs)ms; prevHost=\(prevHost, privacy: .private) newHost=\(newHost, privacy: .private)")
                        if newHost == prevHost {
                            settledURL = try await settleAfterSameHostNavigation(
                                fallback: newURL,
                                deadline: deadline,
                                myGeneration: myGeneration,
                                iter: iter
                            )
                        } else {
                            settledURL = newURL
                        }
                        try await Task.sleep(nanoseconds: 200_000_000)
                        try Self.checkGeneration(current: self.runGeneration, expected: myGeneration)
                    } else {
                        Log.runner.error("[runGen=\(myGeneration)] iter=\(iter) script threw non-navigation error in \(raceMs)ms; rethrowing")
                        throw error
                    }

                case .navigated(let newURL):
                    let prevHost = settledURL.host ?? "?"
                    let newHost = newURL.host ?? "?"
                    Log.runner.debug("[runGen=\(myGeneration)] iter=\(iter) navigation won the race in \(raceMs)ms; prevHost=\(prevHost, privacy: .private) newHost=\(newHost, privacy: .private)")
                    if newHost == prevHost {
                        // Same-host nav — the predicate would just return
                        // `.evaluate` again and we'd race the same script
                        // against another nav, potentially in a tight loop.
                        settledURL = try await settleAfterSameHostNavigation(
                            fallback: newURL,
                            deadline: deadline,
                            myGeneration: myGeneration,
                            iter: iter
                        )
                    } else {
                        settledURL = newURL
                    }
                    try await Task.sleep(nanoseconds: 200_000_000)
                    try Self.checkGeneration(current: self.runGeneration, expected: myGeneration)
                }
            case .waitMore:
                let remainingMs = Int(max(0, deadline.timeIntervalSinceNow * 1000))
                let nextSnapshot = navigationGeneration
                Log.runner.debug("[runGen=\(myGeneration)] iter=\(iter) settle(host=\(settledURL.host ?? "?", privacy: .private)) => .waitMore; waiting up to \(remainingMs)ms")
                settledURL = try await withTimeout(ms: remainingMs, stage: .navigationSettle) {
                    try await self.waitForLoad(after: nextSnapshot)
                }
                Log.runner.debug("[runGen=\(myGeneration)] iter=\(iter) next didFinish url=\(settledURL.absoluteString, privacy: .private)")
                try Self.checkGeneration(current: self.runGeneration, expected: myGeneration)
            }
        }
    }

    /// How long a same-host navigation gets to be followed by another before we call
    /// the page settled.
    private static let sameHostQuietMs = 1_500

    /// Waits briefly for a FURTHER navigation: one arriving means the page is still
    /// churning, so return its URL; a quiet window means it settled, so return
    /// `fallback` and let the caller re-run the script. This used to wait out the
    /// whole deadline, which hung forever on a page that navigates once and stops.
    private func settleAfterSameHostNavigation(
        fallback: URL,
        deadline: Date,
        myGeneration: Int,
        iter: Int
    ) async throws -> URL {
        let remainingMs = Int(max(0, deadline.timeIntervalSinceNow * 1000))
        guard remainingMs > 0 else {
            throw RunnerError.navigationLost
        }
        let waitMs = min(Self.sameHostQuietMs, remainingMs)
        let waitSnapshot = navigationGeneration
        Log.runner.debug("[runGen=\(myGeneration)] iter=\(iter) same-host nav after race; waiting up to \(waitMs)ms for a further didFinish")
        do {
            let url = try await withTimeout(ms: waitMs, stage: .navigationSettle) {
                try await self.waitForLoad(after: waitSnapshot)
            }
            Log.runner.debug("[runGen=\(myGeneration)] iter=\(iter) page navigated again; re-consulting settle")
            return url
        } catch let e as RunnerError {
            guard case .timeout = e else { throw e }
            Log.runner.notice("[runGen=\(myGeneration)] iter=\(iter) page quiet for \(waitMs)ms; re-evaluating script")
            return fallback
        }
    }

    /// Returns true iff `error` is the WebKit "completion handler no longer
    /// reachable" error fired when the JS context is destroyed by a
    /// navigation while a `callAsyncJavaScript` call is in flight.
    private static func isPageNavigatedError(_ error: NSError) -> Bool {
        let msg = error.userInfo["WKJavaScriptExceptionMessage"] as? String ?? ""
        return error.domain == "WKErrorDomain"
            && error.code == 4
            && msg.contains("no longer reachable")
    }

    /// Awaits Promises returned by `script` via `callAsyncJavaScript`
    /// (requires iOS 15+; the SDK's deployment target is iOS 17 so this is
    /// always available).
    ///
    /// `script` must be (or end with) a JavaScript expression. We strip any
    /// trailing whitespace + semicolons and wrap it as `return (\(expr));`.
    /// The parens defeat JavaScript's automatic semicolon insertion, which
    /// would otherwise turn `return` + newline into `return;` and silently
    /// return `undefined`.
    private static func evaluateAsync(on webView: WKWebView, script: String, arguments: [String: Any] = [:]) async throws -> Any? {
        var expr = script
        while let last = expr.unicodeScalars.last,
              last == ";" || CharacterSet.whitespacesAndNewlines.contains(last) {
            expr.removeLast()
        }
        let wrapped = "\(TelemetryInstall.prelude())return (\n\(expr)\n);"
        let host = webView.url?.host ?? "?"
        Log.runner.debug("evaluateAsync starting host=\(host, privacy: .private) wrapperLen=\(wrapped.count)")
        let start = Date()
        do {
            let result = try await webView.callAsyncJavaScript(
                wrapped,
                arguments: arguments,
                in: nil,
                contentWorld: .page
            )
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            Log.runner.debug("evaluateAsync OK in \(ms)ms resultType=\(String(describing: type(of: result as Any)), privacy: .public)")
            return result
        } catch {
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            let nsErr = error as NSError
            // The "no longer reachable" error is the expected outcome when a
            // navigation kills the JS context mid-evaluation (this Task is the
            // loser of the race in `runWithSettle`). Log it at debug so it
            // doesn't masquerade as a genuine failure; everything else stays
            // at error level.
            if Self.isPageNavigatedError(nsErr) {
                Log.runner.debug("evaluateAsync killed by navigation after \(ms)ms (expected; loser of settle race)")
                throw error
            }
            let jsMessage = nsErr.userInfo["WKJavaScriptExceptionMessage"] as? String
            Log.runner.error("evaluateAsync threw after \(ms)ms domain=\(nsErr.domain, privacy: .public) code=\(nsErr.code) msg=\(jsMessage ?? "", privacy: .public)")
            if let jsMessage, !jsMessage.isEmpty {
                throw JSException(message: jsMessage)
            }
            throw error
        }
    }

    /// Cancels the in-flight run, if any. Resumes all pending waiters with
    /// `RunnerError.navigationLost`. Safe to call from MainActor (the runner
    /// is already MainActor-isolated). The runner remains usable for further
    /// runs after this returns.
    func abortCurrentRun() {
        runGeneration += 1
        let n = waiters.count
        Log.runner.error("abortCurrentRun bumped runGen->\(self.runGeneration); resuming \(n) waiter(s) with .navigationLost")
        let toResume = waiters
        waiters.removeAll()
        for w in toResume { w.cont.resume(throwing: RunnerError.navigationLost) }
        webView?.stopLoading()
    }

    func tearDown() {
        Log.runner.debug("tearDown navGen=\(self.navigationGeneration) runGen=\(self.runGeneration) waiters=\(self.waiters.count)")
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
    }

    // MARK: - Private

    private func createWebView() -> WKWebView {
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        self.webView = wv
        self.activeWebViewId = ObjectIdentifier(wv).hashValue
        Log.runner.notice("createWebView pid=\(ProcessInfo.processInfo.processIdentifier) wvId=\(ObjectIdentifier(wv).hashValue)")
        return wv
    }

    /// `wvId`, plus whether the callback came from an earlier run's web view.
    private func wvTag(_ webView: WKWebView) -> String {
        let id = ObjectIdentifier(webView).hashValue
        let stale = activeWebViewId != nil && id != activeWebViewId
        return "wvId=\(id) stale=\(stale)"
    }

    /// Awaits at least one new `didFinish` after `minGeneration`. Resolves
    /// immediately if a navigation has already happened. The optional
    /// `kickoff` runs *before* suspending — useful for `webView.load(...)`
    /// where we want the kickoff and the wait to be part of the same
    /// suspension.
    ///
    /// Cancel-aware: if the enclosing Task is cancelled (e.g. by an outer
    /// `withTimeout` racing the body), all outstanding waiters resume with
    /// `CancellationError`. Without this, the timeout's structured-concurrency
    /// parent would wait forever for the body task to complete.
    @discardableResult
    private func waitForLoad(after minGeneration: Int, kickoff: () -> Void = {}) async throws -> URL {
        // Fast path: a didFinish has already fired since `minGeneration`.
        if navigationGeneration > minGeneration, let url = lastFinishedURL {
            Log.runner.debug("waitForLoad fast-path navGen=\(self.navigationGeneration) > min=\(minGeneration); returning url=\(url.absoluteString, privacy: .private)")
            kickoff()
            return url
        }
        Log.runner.debug("waitForLoad suspending after navGen=\(minGeneration); waiters before=\(self.waiters.count)")
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
                waiters.append(Waiter(minGeneration: minGeneration, cont: cont))
                kickoff()
            }
        } onCancel: { [weak self] in
            // The runner is @MainActor; hop back to mutate `waiters`.
            Task { @MainActor in
                Log.runner.debug("waitForLoad cancelled; resuming waiters with CancellationError")
                self?.resumeWaitersOnFailure(CancellationError())
            }
        }
    }

    private func resumeWaitersOnFinish(_ url: URL) {
        let toResume = waiters.filter { $0.minGeneration < navigationGeneration }
        waiters.removeAll { $0.minGeneration < navigationGeneration }
        if !toResume.isEmpty {
            Log.runner.debug("resuming \(toResume.count) waiter(s) on didFinish navGen=\(self.navigationGeneration)")
        }
        for w in toResume { w.cont.resume(returning: url) }
    }

    private func resumeWaitersOnFailure(_ error: Error) {
        let toResume = waiters
        if !toResume.isEmpty {
            Log.runner.debug("resuming \(toResume.count) waiter(s) on failure: \(String(describing: error), privacy: .public)")
        }
        waiters.removeAll()
        for w in toResume { w.cont.resume(throwing: error) }
    }

    private func withTimeout<T: Sendable>(ms: Int, stage: RunnerTimeoutStage, _ body: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await body() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
                Log.runner.error("withTimeout(\(ms)ms, stage=\(stage.rawValue, privacy: .public)) firing")
                throw RunnerError.timeout(stage: stage)
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private static func checkGeneration(current: Int, expected: Int) throws {
        if current != expected {
            Log.runner.error("checkGeneration FAILED current=\(current) expected=\(expected); throwing .navigationLost")
            throw RunnerError.navigationLost
        }
    }

    // Navigation host allowlist. This offscreen WebView carries the live Coinbase
    // session and runs the auth.status probe, so it must only load Coinbase-owned
    // origins in the main frame. Sub-frames (e.g. the Cloudflare Turnstile widget)
    // are third-party by design and left alone. A cancelled off-Coinbase nav
    // surfaces as didFailProvisionalNavigation, aborting the run — the safe outcome.
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Local-HTML runs author their own content; only remote-URL runs are gated.
        guard enforceHostAllowlist else {
            decisionHandler(.allow)
            return
        }
        if navigationAction.targetFrame?.isMainFrame == false {
            decisionHandler(.allow)
            return
        }
        guard CoinbaseHostPolicy.isTrusted(navigationAction.request.url) else {
            Log.runner.error("blocked off-Coinbase navigation host=\(navigationAction.request.url?.host ?? "?", privacy: .private)")
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    /// Proof the load actually started: a `.initialLoad` timeout with no
    /// `didStartProvisional` means WebKit never began it. `.notice` so it reaches
    /// disk in a release build.
    func webView(_ webView: WKWebView, didStartProvisionalNavigation nav: WKNavigation!) {
        Log.runner.notice("didStartProvisional navGen=\(self.navigationGeneration) \(self.wvTag(webView), privacy: .public) host=\(webView.url?.host ?? "?", privacy: .public) waitingFor=\(self.waiters.count)")
    }

    func webView(_ webView: WKWebView, didFinish nav: WKNavigation!) {
        navigationGeneration += 1
        let url = webView.url ?? URL(string: "about:blank")!
        lastFinishedURL = url
        Log.runner.notice("didFinish navGen=\(self.navigationGeneration) \(self.wvTag(webView), privacy: .public) host=\(url.host ?? "?", privacy: .public) url=\(url.absoluteString, privacy: .private) waitingFor=\(self.waiters.count)")
        resumeWaitersOnFinish(url)
    }

    func webView(_ webView: WKWebView, didFail nav: WKNavigation!, withError e: Error) {
        Log.runner.error("didFail navGen=\(self.navigationGeneration) \(self.wvTag(webView), privacy: .public) host=\(webView.url?.host ?? "?", privacy: .public) error=\(e.localizedDescription, privacy: .public)")
        resumeWaitersOnFailure(RunnerError.loadFailed(e.localizedDescription))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation nav: WKNavigation!, withError e: Error) {
        Log.runner.error("didFailProvisionalNavigation navGen=\(self.navigationGeneration) \(self.wvTag(webView), privacy: .public) host=\(webView.url?.host ?? "?", privacy: .public) error=\(e.localizedDescription, privacy: .public)")
        resumeWaitersOnFailure(RunnerError.loadFailed(e.localizedDescription))
    }
}

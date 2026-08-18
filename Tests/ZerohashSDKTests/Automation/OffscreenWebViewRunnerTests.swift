import Testing
import WebKit
@testable import ZerohashSDK

/// Only the AUTH-4127 same-host navigation test. connect-ios carries the full
/// runner suite; the rest is not yet backfilled here.
@MainActor
@Suite("OffscreenWebViewRunner same-host navigation")
struct OffscreenWebViewRunnerSameHostNavigationTests {

    @Test("One same-host navigation followed by a quiet page re-runs the script instead of timing out")
    func sameHostNavigationThenQuietPageReevaluates() async throws {
        let cfg = SharedWebViewConfiguration().platformConfiguration()
        let probe = ScriptStartProbe()
        cfg.userContentController.add(probe, name: "runnerTestProbe")
        let runner = OffscreenWebViewRunner(config: cfg)
        let base = URL(string: "https://same.test/")!

        let script = """
        (async () => {
          window.__attempts = (window.__attempts || 0) + 1;
          window.webkit.messageHandlers.runnerTestProbe.postMessage(window.__attempts);
          if (window.__attempts === 1) { await new Promise(r => setTimeout(r, 30000)); }
          return "attempt" + window.__attempts;
        })()
        """

        let navSource = WKWebView(frame: .zero, configuration: SharedWebViewConfiguration().platformConfiguration())
        navSource.loadHTMLString("<html><body>nav</body></html>", baseURL: base)

        let run = Task { () -> Result<String?, RunnerError> in
            do {
                let r = try await runner.runHTML(
                    html: "<html><body>start</body></html>",
                    baseURL: base,
                    settle: { _ in .evaluate },
                    script: script,
                    timeoutMs: 8_000
                )
                return .success(r as? String)
            } catch let e as RunnerError {
                return .failure(e)
            } catch {
                return .failure(.navigationLost)
            }
        }

        await probe.wait()
        #expect(navSource.url?.host == "same.test")
        runner.webView(navSource, didFinish: nil)

        switch await run.value {
        case .success(let value):
            #expect(value == "attempt2")
        case .failure(let e):
            #expect(Bool(false), "expected the script to be re-evaluated, got \(e)")
        }
    }
}

/// Signals when the injected script starts, so a synthesized navigation can be
/// timed against real progress instead of a sleep.
@MainActor
private final class ScriptStartProbe: NSObject, WKScriptMessageHandler {
    private var waiter: CheckedContinuation<Void, Never>?
    private var fired = false

    /// Resolves on the first message; later ones are no-ops.
    func wait() async {
        if fired { return }
        await withCheckedContinuation { waiter = $0 }
    }

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        Task { @MainActor in self.signal() }
    }

    private func signal() {
        guard !fired else { return }
        fired = true
        waiter?.resume()
        waiter = nil
    }
}

import Foundation
import UIKit
import WebKit

@MainActor
final class ExecutionContextImpl: ExecutionContext {
    private weak var host: UIViewController?
    private let shared: SharedWebViewConfiguration
    private let currentRequestId: String
    private weak var eventEmitter: BridgeEventEmitting?
    /// Host-selected theme, threaded down to the automation VCs so their branded
    /// overlay can resolve light/dark colors.
    private let theme: Theme

    var dataStore: WKWebsiteDataStore { shared.dataStore }

    init(host: UIViewController,
         shared: SharedWebViewConfiguration,
         currentRequestId: String,
         eventEmitter: BridgeEventEmitting,
         theme: Theme = .system) {
        self.host = host
        self.shared = shared
        self.currentRequestId = currentRequestId
        self.eventEmitter = eventEmitter
        self.theme = theme
    }

    func presentModalWebView(
        url: URL,
        hostPolicy: ModalHostPolicy,
        title: String?,
        autoClose: ModalAutoClose?,
        documentStartJS: String?
    ) async throws -> ModalWebViewHandle {
        Log.bridge.debug("presentModalWebView reqId=\(self.currentRequestId, privacy: .public) url=\(url.absoluteString, privacy: .private) stayOpen=\(hostPolicy.stayOpenHosts.count) success=\(hostPolicy.successHosts.count)")
        guard let presenter = self.host else {
            Log.bridge.error("presentModalWebView reqId=\(self.currentRequestId, privacy: .public) host UIViewController is nil; throwing hostUnavailable")
            throw ContextError.hostUnavailable
        }
        let vc = ModalViewController(
            url: url,
            hostPolicy: hostPolicy,
            title: title,
            sharedConfig: shared.platformConfiguration(),
            autoClose: autoClose,
            documentStartJS: documentStartJS
        )
        // The modal's close reason is delivered to callers via
        // `ModalWebViewHandle.waitForClose()` and folded into the auth.login
        // response. Wrapped in a nav controller for the Cancel bar.
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .fullScreen
        presenter.present(nav, animated: true)
        return vc
    }

    func presentAutomationSession(
        url: URL,
        overlay: OverlayOptions,
        showOverlay: Bool
    ) async throws -> AutomationSessionHandle {
        Log.bridge.debug("presentAutomationSession reqId=\(self.currentRequestId, privacy: .public) url=\(url.absoluteString, privacy: .private) showOverlay=\(showOverlay)")
        guard let presenter = self.host else {
            Log.bridge.error("presentAutomationSession reqId=\(self.currentRequestId, privacy: .public) host UIViewController is nil; throwing hostUnavailable")
            throw ContextError.hostUnavailable
        }
        let vc = AutomationSessionViewController(
            url: url,
            sharedConfig: shared.platformConfiguration(),
            overlay: overlay,
            showOverlay: showOverlay,
            theme: theme
        )
        // Give the session its presenter so it can re-present itself in resume()
        // after a stepAside() (the per-request ctx is gone by then). Presented
        // full-screen with no chrome (the user must not be able to act on it).
        vc.presenter = presenter
        presenter.present(vc, animated: true)
        return vc
    }

    func runOffscreenWebView(
        url: URL,
        settle: @MainActor @escaping (URL) -> OffscreenSettleDecision,
        injectedScript: String,
        arguments: [String: Any],
        timeoutMs: Int
    ) async throws -> Any? {
        Log.bridge.debug("runOffscreenWebView reqId=\(self.currentRequestId, privacy: .public) url=\(url.absoluteString, privacy: .private) timeoutMs=\(timeoutMs)")
        // Long-lived, shared. No `tearDown()` here — the runner outlives
        // the request and is reused for every `auth.status` poll.
        let start = Date()
        do {
            let result = try await shared.offscreenRunner.run(
                url: url,
                settle: settle,
                script: injectedScript,
                arguments: arguments,
                timeoutMs: timeoutMs
            )
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            Log.bridge.debug("runOffscreenWebView reqId=\(self.currentRequestId, privacy: .public) OK in \(ms)ms")
            return result
        } catch {
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            Log.bridge.error("runOffscreenWebView reqId=\(self.currentRequestId, privacy: .public) FAILED after \(ms)ms err=\(String(describing: error), privacy: .public)")
            throw error
        }
    }

    func runVisibleWebView(
        url: URL,
        settle: @MainActor @escaping (URL) -> OffscreenSettleDecision,
        injectedScript: String,
        arguments: [String: Any],
        overlay: OverlayOptions,
        showOverlay: Bool,
        waitForChallengeClearance: Bool,
        timeoutMs: Int
    ) async throws -> Any? {
        Log.bridge.debug("runVisibleWebView reqId=\(self.currentRequestId, privacy: .public) url=\(url.absoluteString, privacy: .private) showOverlay=\(showOverlay) waitForChallengeClearance=\(waitForChallengeClearance) timeoutMs=\(timeoutMs)")
        guard let presenter = self.host else {
            Log.bridge.error("runVisibleWebView reqId=\(self.currentRequestId, privacy: .public) host UIViewController is nil; throwing hostUnavailable")
            throw ContextError.hostUnavailable
        }
        let vc = AutomatedWebViewController(
            url: url,
            settle: settle,
            script: injectedScript,
            arguments: arguments,
            overlay: overlay,
            showOverlay: showOverlay,
            waitForChallengeClearance: waitForChallengeClearance,
            sharedConfig: shared.platformConfiguration(),
            timeoutMs: timeoutMs,
            theme: theme
        )
        // Presented DIRECTLY full-screen (no UINavigationController): the
        // overlaid page must occupy the whole screen so the SPA renders. The
        // VC self-dismisses exactly once on completion (Task 11 guarantees
        // idempotent dismissal), so we do NOT dismiss manually here.
        vc.modalPresentationStyle = .fullScreen
        // Signal the VC once the present transition has finished animating: if
        // the run completes mid-present (e.g. a fast not-logged-in redirect),
        // the VC defers its self-dismiss until here so UIKit can't drop it.
        presenter.present(vc, animated: true) { [weak vc] in
            vc?.presentationDidFinish()
        }
        let start = Date()
        do {
            let result = try await vc.runToResult()
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            Log.bridge.debug("runVisibleWebView reqId=\(self.currentRequestId, privacy: .public) OK in \(ms)ms")
            return result
        } catch {
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            Log.bridge.error("runVisibleWebView reqId=\(self.currentRequestId, privacy: .public) FAILED after \(ms)ms err=\(String(describing: error), privacy: .public)")
            throw error
        }
    }
}

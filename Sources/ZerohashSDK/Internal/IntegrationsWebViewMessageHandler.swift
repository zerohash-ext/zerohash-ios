import Foundation
import UIKit
import WebKit

@MainActor
protocol IntegrationsWebViewMessageHandlerDelegate: AnyObject {
    func messageHandlerDidReceiveContentReady(_ handler: IntegrationsWebViewMessageHandler)
    func messageHandler(
        _ handler: IntegrationsWebViewMessageHandler, didReceiveNavigate url: String, mobileTarget: String?)
    func messageHandlerDidReceiveClose(_ handler: IntegrationsWebViewMessageHandler)
    func messageHandlerDidReceiveDeposit(
        _ handler: IntegrationsWebViewMessageHandler, data: [String: Any], jsonString: String)
    func messageHandlerDidReceiveCryptoWithdrawal(
        _ handler: IntegrationsWebViewMessageHandler, data: [String: Any], jsonString: String)
    /// Status of a deposit funded from an external source, posted as
    /// `deposit-status`. Its own message type because `deposit` already means the
    /// deposit *completed* — a status there would report that the money arrived
    /// while the deposit is still verifying, or has failed. Non-terminal: it can
    /// arrive more than once per deposit.
    func messageHandlerDidReceiveDepositStatus(
        _ handler: IntegrationsWebViewMessageHandler, data: [String: Any], jsonString: String)
    /// A terminal *failed* transaction, posted by the mobile web app as
    /// `transaction-failed`. Distinct from `didReceiveError`: this is the flow's
    /// own outcome and carries the transaction's details, not an error payload.
    func messageHandlerDidReceiveTransactionFailed(
        _ handler: IntegrationsWebViewMessageHandler, data: [String: Any], jsonString: String)
    func messageHandlerDidReceiveFundWithdrawal(
        _ handler: IntegrationsWebViewMessageHandler, data: [String: Any], jsonString: String)
    func messageHandler(
        _ handler: IntegrationsWebViewMessageHandler, didReceiveEvent type: String, data: [String: Any],
        jsonString: String)
    func messageHandler(
        _ handler: IntegrationsWebViewMessageHandler, didReceiveError data: [String: Any],
        jsonString: String)
    /// A ZeroAuth scraping envelope (`role: "zeroauth-host"`) arrived on the same
    /// `NativeIOS` channel. Routed to the automation bridge rather than the Fund flow.
    func messageHandler(
        _ handler: IntegrationsWebViewMessageHandler, didReceiveAutomationRequest request: ZeroAuthRequest)
}

/// Bridge contract matches the zerohash mobile web app:
/// inbound (web→native) `page-ready`, `content-ready`, `navigate`, `close`,
/// `error`, `event`, `deposit`, `deposit-status`, `crypto-withdrawal`,
/// `fund-withdrawal`, `transaction-failed`;
/// outbound (native→web) `jwt`, `config`.
class IntegrationsWebViewMessageHandler: NSObject, WKScriptMessageHandler, WKNavigationDelegate,
    WKUIDelegate
{

    // MARK: - Properties

    weak var delegate: IntegrationsWebViewMessageHandlerDelegate?
    private weak var webView: WKWebView?
    private let jwt: String
    private let theme: Theme
    private let environment: Environment

    // MARK: - Initialization

    init(jwt: String, theme: Theme, environment: Environment) {
        self.jwt = jwt
        self.theme = theme
        self.environment = environment
        super.init()
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        let host = message.frameInfo.securityOrigin.host

        // The Fund UI runs inside a trusted CDN iframe (iframe-based SDK), so the
        // navigation bridge legitimately posts from a sub-frame. The origin
        // allow-list below is the real security boundary — `frameInfo.securityOrigin`
        // is set by WebKit and cannot be spoofed by page JS — so we authorize by
        // origin rather than requiring the main frame (which broke redirect/oauth links).

        guard environment.trustedHosts.contains(host) else {
            Log.error("[Bridge] Message rejected from unauthorized origin: \(host)")
            return
        }

        // Parse body — accept both stringified JSON (sandbox/prod) and raw JS objects (dev).
        let rawObject: [String: Any]
        let jsonString: String

        if let bodyString = message.body as? String,
            let parsed = try? JSONSerialization.jsonObject(with: Data(bodyString.utf8))
                as? [String: Any]
        {
            rawObject = parsed
            jsonString = bodyString
        } else if let bodyDict = message.body as? [String: Any] {
            rawObject = bodyDict
            jsonString =
                (try? String(
                    data: JSONSerialization.data(withJSONObject: bodyDict), encoding: .utf8))
                ?? "{}"
        } else {
            #if DEBUG
                print(
                    "[Bridge] Unrecognized message body type from '\(host)': \(type(of: message.body))"
                )
            #endif
            return
        }

        // ZeroAuth scraping envelopes ride the same channel, discriminated by
        // `role: "zeroauth-host"` (matches zerohash-android's dispatchMessage and
        // connect-ios's NativeIOSMessageHandler). They carry `operation`, not `type`.
        if MessageBodyDecoder.isAutomationWebViewRequest(rawObject) {
            let id = rawObject["id"] as? String ?? "-"
            let platform = rawObject["platform"] as? String ?? "-"
            let op = rawObject["operation"] as? String ?? "-"

            Log.bridge.notice("inbound automation envelope id=\(id, privacy: .public) platform=\(platform, privacy: .public) op=\(op, privacy: .public) origin=\(host, privacy: .public)")

            let request: ZeroAuthRequest
            if let decoded = try? JSONDecoder().decode(ZeroAuthRequest.self, from: Data(jsonString.utf8)) {
                request = decoded
            } else {
                Log.bridge.error("automation envelope failed to decode; routing to invalidEnvelopeProbe")
                request = .invalidEnvelopeProbe()
            }
            Task { @MainActor in
                self.delegate?.messageHandler(self, didReceiveAutomationRequest: request)
            }
            return
        }

        guard let rawType = rawObject["type"] as? String else { return }

        Log.bridge.notice("inbound common envelope op=\(rawType, privacy: .public) origin=\(host, privacy: .public)")

        if rawType.hasPrefix("console.") {
            Task { @MainActor in
                let msg = rawObject["message"] as? String ?? "(empty)"
                #if DEBUG
                    print("[Bridge] [JS:\(rawType)] \(msg)")
                #endif
            }
            return
        }

        Task { @MainActor in
            self.handleMessage(type: rawType, jsonObject: rawObject, jsonString: jsonString)
        }
    }

    // MARK: - Private (outbound)

    private func sendJWT() {
        sendMessageToWeb(type: "jwt", data: ["token": jwt, "env": environment.toWebValue])
    }

    private func sendConfig() {
        sendMessageToWeb(type: "config", data: ["theme": theme.toWebValue])
    }

    func sendOAuthCancelled() {
        sendMessageToWeb(type: "oauth-error", data: ["success": false, "error": "User cancelled"])
    }

    /// Relays a completed OAuth connection to the web SDK. `waitForConnectionId`
    /// resolves with `data.connectionId`. Matches the zerohash-android contract.
    func sendOAuthSuccess(connectionId: String) {
        sendMessageToWeb(type: "oauth-success", data: ["success": true, "connectionId": connectionId])
    }

    /// Relays an OAuth failure (provider error / session failure) to the web SDK.
    func sendOAuthError(_ error: String) {
        sendMessageToWeb(type: "oauth-error", data: ["success": false, "error": error])
    }

    private func sendMessageToWeb(type: String, data: [String: Any]) {
        guard let webView = webView else { return }

        do {
            let message: [String: Any] = ["type": type, "data": data]
            let jsonData = try JSONSerialization.data(withJSONObject: message)
            guard let jsonString = String(data: jsonData, encoding: .utf8) else { return }

            let script = "window.postMessage(\(jsonString));"
            webView.evaluateJavaScript(script) { _, error in
                if let error = error {
                    Log.error("[Bridge] Error sending \(type): \(error.localizedDescription)")
                }
            }
        } catch {
            Log.error("[Bridge] Error serializing \(type): \(error)")
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.webView = webView
        #if DEBUG
            print("[Bridge] Page finished loading: \(webView.url?.host ?? "nil")")
        #endif
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        #if DEBUG
            print("[Bridge] Started loading: \(webView.url?.host ?? "nil")")
        #endif
    }

    func webView(_ webView: WKWebView, didFailProvisionalLoadWithError error: Error) {
        #if DEBUG
            print(
                "[Bridge] Failed to load: \(error.localizedDescription) | code: \((error as NSError).code)"
            )
        #endif
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        #if DEBUG
            print(
                "[Bridge] Navigation failed: \(error.localizedDescription) | code: \((error as NSError).code)"
            )
        #endif
    }

    func webView(
        _ webView: WKWebView,
        didReceiveAuthenticationChallenge challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        #if DEBUG
            // Sandbox uses internally-signed certificates that iOS simulators don't trust.
            // Accept them for known sandbox hosts in debug builds only — never compiled into release.
            let sandboxHosts = Environment.sandbox.trustedHosts
            if sandboxHosts.contains(challenge.protectionSpace.host),
                challenge.protectionSpace.authenticationMethod
                    == NSURLAuthenticationMethodServerTrust,
                let serverTrust = challenge.protectionSpace.serverTrust
            {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return
            }
        #endif
        completionHandler(.performDefaultHandling, nil)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        let scheme = url.scheme?.lowercased() ?? ""
        if scheme != "http" && scheme != "https" {
            let safeSchemes: Set<String> = ["tel", "mailto", "sms"]
            if safeSchemes.contains(scheme) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            } else {
                Log.error("[Bridge] Blocked navigation to unknown scheme: \(scheme)")
            }
            decisionHandler(.cancel)
            return
        }

        // Only restrict the main frame — sub-frames (iframes) are controlled by the
        // trusted main page and may navigate to external hosts for OAuth or content.
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        if isMainFrame {
            let host = url.host ?? ""
            guard environment.trustedHosts.contains(host) else {
                Log.error("[Bridge] Blocked main-frame navigation to untrusted host: \(host)")
                decisionHandler(.cancel)
                return
            }
        }

        decisionHandler(.allow)
    }

    // MARK: - WKUIDelegate

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        let scheme = url.scheme?.lowercased() ?? ""
        let host = url.host ?? ""

        if scheme == "http" || scheme == "https" {
            guard environment.trustedHosts.contains(host) else {
                Log.error("[Bridge] Blocked popup to untrusted host: \(host)")
                return nil
            }
        } else {
            let safeSchemes: Set<String> = ["tel", "mailto", "sms"]
            guard safeSchemes.contains(scheme) else {
                Log.error("[Bridge] Blocked popup to unknown scheme: \(scheme)")
                return nil
            }
        }

        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        return nil
    }

    // MARK: - Private

    @MainActor
    private func handleMessage(type: String, jsonObject: [String: Any], jsonString: String) {
        switch type {
        case "page-ready":
            sendJWT()
            sendConfig()

        case "content-ready":
            delegate?.messageHandlerDidReceiveContentReady(self)

        case "deposit":
            let data = jsonObject["data"] as? [String: Any] ?? [:]
            delegate?.messageHandlerDidReceiveDeposit(self, data: data, jsonString: jsonString)

        case "deposit-status":
            let data = jsonObject["data"] as? [String: Any] ?? [:]
            delegate?.messageHandlerDidReceiveDepositStatus(self, data: data, jsonString: jsonString)

        case "crypto-withdrawal":
            let data = jsonObject["data"] as? [String: Any] ?? [:]
            delegate?.messageHandlerDidReceiveCryptoWithdrawal(self, data: data, jsonString: jsonString)

        case "fund-withdrawal":
            let data = jsonObject["data"] as? [String: Any] ?? [:]
            delegate?.messageHandlerDidReceiveFundWithdrawal(self, data: data, jsonString: jsonString)

        case "transaction-failed":
            let data = jsonObject["data"] as? [String: Any] ?? [:]
            delegate?.messageHandlerDidReceiveTransactionFailed(self, data: data, jsonString: jsonString)

        case "close":
            delegate?.messageHandlerDidReceiveClose(self)

        case "navigate":
            if let data = jsonObject["data"] as? [String: Any],
                let url = data["url"] as? String
            {
                let mobileTarget = data["mobileTarget"] as? String
                delegate?.messageHandler(self, didReceiveNavigate: url, mobileTarget: mobileTarget)
            }

        case "error":
            let data = jsonObject["data"] as? [String: Any] ?? [:]
            delegate?.messageHandler(self, didReceiveError: data, jsonString: jsonString)

        case "event":
            // The mobile bridge flattens events and carries the original type in
            // `eventType` (the `data` object spreads `...event.data`).
            let data = jsonObject["data"] as? [String: Any] ?? [:]
            let eventType = data["eventType"] as? String ?? data["type"] as? String ?? "unknown"
            delegate?.messageHandler(
                self, didReceiveEvent: eventType, data: data, jsonString: jsonString)

        default:
            let data = jsonObject["data"] as? [String: Any] ?? [:]
            delegate?.messageHandler(
                self, didReceiveEvent: type, data: data, jsonString: jsonString)
        }
    }
}

private extension ZeroAuthRequest {
    /// Synthetic request used to surface "invalid envelope" replies through the
    /// automation router when the body has `role=zeroauth-host` but doesn't decode.
    /// The router will reject with `.platformNotRegistered("?")` because the
    /// platform field is empty — but `?` as a sentinel id keeps any pending
    /// JS-side promise from leaking. Replaced with a dedicated path in a
    /// future revision.
    static func invalidEnvelopeProbe() -> ZeroAuthRequest {
        ZeroAuthRequest(id: "?", role: WireRole.host, platform: "?", operation: "?")
    }
}

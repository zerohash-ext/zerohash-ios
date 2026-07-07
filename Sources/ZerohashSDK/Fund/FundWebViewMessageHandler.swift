import UIKit
import WebKit
import Foundation

@MainActor
protocol FundWebViewMessageHandlerDelegate: AnyObject {
    func messageHandlerDidReceiveContentReady(_ handler: FundWebViewMessageHandler)
    func messageHandler(_ handler: FundWebViewMessageHandler, didReceiveNavigate url: String, mobileTarget: String?)
    func messageHandlerDidReceiveClose(_ handler: FundWebViewMessageHandler)
    func messageHandlerDidReceiveDeposit(_ handler: FundWebViewMessageHandler, data: [String: Any], jsonString: String)
    func messageHandler(_ handler: FundWebViewMessageHandler, didReceiveEvent type: String, data: [String: Any], jsonString: String)
    func messageHandler(_ handler: FundWebViewMessageHandler, didReceiveError data: [String: Any], jsonString: String)
}

/// Bridge contract matches the zerohash mobile web app (`apps/mobile`):
/// inbound (web→native) `page-ready`, `content-ready`, `navigate`, `close`,
/// `error`, `event`, `deposit`; outbound (native→web) `jwt`, `config`.
class FundWebViewMessageHandler: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {

    // MARK: - Properties

    weak var delegate: FundWebViewMessageHandlerDelegate?
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

        guard message.frameInfo.isMainFrame else {
            Log.error("[Fund] Message rejected from non-main frame: \(host)")
            return
        }

        guard environment.trustedHosts.contains(host) else {
            Log.error("[Fund] Message rejected from unauthorized origin: \(host)")
            return
        }

        // Parse body — accept both stringified JSON (sandbox/prod) and raw JS objects (dev).
        let rawObject: [String: Any]
        let jsonString: String

        if let bodyString = message.body as? String,
           let parsed = try? JSONSerialization.jsonObject(with: Data(bodyString.utf8)) as? [String: Any]
        {
            rawObject = parsed
            jsonString = bodyString
        } else if let bodyDict = message.body as? [String: Any] {
            rawObject = bodyDict
            jsonString = (try? String(data: JSONSerialization.data(withJSONObject: bodyDict), encoding: .utf8)) ?? "{}"
        } else {
            #if DEBUG
            print("[Fund] ⚠️ Unrecognized message body type from '\(host)': \(type(of: message.body))")
            #endif
            return
        }

        guard let rawType = rawObject["type"] as? String else { return }

        if rawType.hasPrefix("console.") {
            Task { @MainActor in
                let msg = rawObject["message"] as? String ?? "(empty)"
                #if DEBUG
                print("[Fund] [JS:\(rawType)] \(msg)")
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

    private func sendMessageToWeb(type: String, data: [String: Any]) {
        guard let webView = webView else { return }

        do {
            let message: [String: Any] = ["type": type, "data": data]
            let jsonData = try JSONSerialization.data(withJSONObject: message)
            guard let jsonString = String(data: jsonData, encoding: .utf8) else { return }

            let script = "window.postMessage(\(jsonString));"
            webView.evaluateJavaScript(script) { _, error in
                if let error = error {
                    Log.error("[Fund] Error sending \(type): \(error.localizedDescription)")
                }
            }
        } catch {
            Log.error("[Fund] Error serializing \(type): \(error)")
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.webView = webView
        #if DEBUG
        print("[Fund] ✅ Page finished loading: \(webView.url?.host ?? "nil")")
        #endif
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        #if DEBUG
        print("[Fund] 🔄 Started loading: \(webView.url?.host ?? "nil")")
        #endif
    }

    func webView(_ webView: WKWebView, didFailProvisionalLoadWithError error: Error) {
        #if DEBUG
        print("[Fund] ❌ Failed to load: \(error.localizedDescription) | code: \((error as NSError).code)")
        #endif
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        #if DEBUG
        print("[Fund] ❌ Navigation failed: \(error.localizedDescription) | code: \((error as NSError).code)")
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
           challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
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
                Log.error("[Fund] Blocked navigation to unknown scheme: \(scheme)")
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
                Log.error("[Fund] Blocked main-frame navigation to untrusted host: \(host)")
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
                Log.error("[Fund] Blocked popup to untrusted host: \(host)")
                return nil
            }
        } else {
            let safeSchemes: Set<String> = ["tel", "mailto", "sms"]
            guard safeSchemes.contains(scheme) else {
                Log.error("[Fund] Blocked popup to unknown scheme: \(scheme)")
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
            delegate?.messageHandler(self, didReceiveEvent: eventType, data: data, jsonString: jsonString)

        default:
            let data = jsonObject["data"] as? [String: Any] ?? [:]
            delegate?.messageHandler(self, didReceiveEvent: type, data: data, jsonString: jsonString)
        }
    }
}

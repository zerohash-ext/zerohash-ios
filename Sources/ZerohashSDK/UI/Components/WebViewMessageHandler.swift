import Foundation
import WebKit

class WebViewMessageHandler: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {

    // MARK: - Properties

    private weak var webView: WKWebView?
    private let jwt: String
    private let appIdentifier: String
    private let appIdentifierEventPrefix: String
    private let environment: Environment
    private let callbacks: ZerohashCallbacks
    private var onClose: (() -> Void)?

    // MARK: - Initialization

    init(
        jwt: String, appIdentifier: String, environment: Environment, callbacks: ZerohashCallbacks,
        onClose: @escaping () -> Void
    ) {
        self.jwt = jwt
        self.appIdentifier = appIdentifier
        self.appIdentifierEventPrefix = appIdentifier.replacingOccurrences(of: "-", with: "_")
            .uppercased()
        self.environment = environment
        self.callbacks = callbacks
        self.onClose = onClose
        super.init()
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        let host = message.frameInfo.securityOrigin.host

        guard message.frameInfo.isMainFrame else {
            Log.error("Message rejected from non-main frame: \(host)")
            return
        }

        guard environment.trustedHosts.contains(host) else {
            Log.error("Message rejected from unauthorized origin: \(host)")
            return
        }

        guard let jsonString = message.body as? String else {
            Log.debug("Unexpected message body type: \(type(of: message.body))")
            return
        }

        do {
            guard
                let jsonObject = try JSONSerialization.jsonObject(
                    with: Data(jsonString.utf8), options: []) as? [String: Any]
            else {
                Log.debug("Failed to convert JSON string to a JSON object")
                return
            }

            guard let messageType = jsonObject["type"] as? String else {
                Log.debug("Missing 'type' key in JSON object")
                return
            }

            handleMessage(type: messageType)
        } catch {
            Log.error("Error parsing JSON: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Methods

    private func handleMessage(type: String) {
        switch type {
        case "SDK_MOBILE_READY":
            Log.debug("SDK Mobile ready")
            sendMessageToWebView("OPEN_MODAL")

        case "\(appIdentifierEventPrefix)_APP_LOADED":
            Log.debug("App loaded: \(type)")
            let event = GenericEvent(type: type, data: [:])
            callbacks.onEvent?(event)

        case "\(appIdentifierEventPrefix)_COMPLETED":
            Log.debug("App completed: \(type)")
            let event = DepositEvent(from: ["success": true, "status": "success"])
            callbacks.onDeposit?(event)

        case "\(appIdentifierEventPrefix)_FAILED":
            Log.debug("App failed: \(type)")
            let event = DepositEvent(from: ["success": false, "status": "failed"])
            callbacks.onDeposit?(event)

        case "\(appIdentifierEventPrefix)_CLOSE_BUTTON_CLICKED":
            Log.debug("Close button clicked")
            callbacks.onClose?()
            onClose?()

        default:
            Log.debug("Unknown message type: \(type)")
            let event = GenericEvent(type: type, data: [:])
            callbacks.onEvent?(event)
        }
    }

    private func sendMessageToWebView(_ event: String) {
        do {
            let message: [String: Any] = [
                "type": event,
                "payload": ["appIdentifier": appIdentifier, "jwt": jwt],
            ]
            let jsonData = try JSONSerialization.data(withJSONObject: message)
            guard let jsonString = String(data: jsonData, encoding: .utf8) else { return }

            let script = "window.postMessage(\(jsonString));"
            Log.debug("Sending message to WebView: \(event)")

            webView?.evaluateJavaScript(script) { _, error in
                if let error = error {
                    Log.error("Error sending message to WebView: \(error.localizedDescription)")
                }
            }
        } catch {
            Log.error("Error serializing message: \(error)")
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.webView = webView
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        let scheme = url.scheme?.lowercased() ?? ""
        if scheme != "http" && scheme != "https" {
            let safeSchemes: Set<String> = ["tel", "mailto", "sms"]
            if safeSchemes.contains(scheme) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            } else {
                Log.error("Blocked navigation to unknown scheme: \(scheme)")
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
                Log.error("Blocked navigation to untrusted host: \(host)")
                decisionHandler(.cancel)
                return
            }
        }

        decisionHandler(.allow)
    }

    // MARK: - WKUIDelegate

    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        let scheme = url.scheme?.lowercased() ?? ""
        let host = url.host ?? ""

        if scheme == "http" || scheme == "https" {
            guard environment.trustedHosts.contains(host) else {
                Log.error("Blocked popup to untrusted host: \(host)")
                return nil
            }
        } else {
            let safeSchemes: Set<String> = ["tel", "mailto", "sms"]
            guard safeSchemes.contains(scheme) else {
                Log.error("Blocked popup to unknown scheme: \(scheme)")
                return nil
            }
        }

        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        return nil
    }
}

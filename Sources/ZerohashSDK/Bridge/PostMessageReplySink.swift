import Foundation
import WebKit

@MainActor
final class PostMessageReplySink: AutomationWebViewReplySink {
    private weak var webView: WKWebView?
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }()

    init(webView: WKWebView) { self.webView = webView }

    // MARK: UIWebView outbound

    func sendUIWebViewMessage(type: String, data: [String: Any]) {
        guard let json = Self.encodeUIWebViewMessage(type: type, data: data) else { return }
        evaluatePostMessage(json: json)
    }

    // MARK: AutomationWebView outbound (via AutomationWebViewReplySink)

    nonisolated func send(response: ZeroAuthResponse) {
        Task { @MainActor in self.evaluateAutomationWebView(type: "scraping-webview-response", encoded: response) }
    }

    nonisolated func send(event: BridgeEvent) {
        Task { @MainActor in self.evaluateAutomationWebView(type: "scraping-webview-event", encoded: event) }
    }

    // MARK: - Private

    private func evaluateAutomationWebView<T: Encodable>(type: String, encoded: T) {
        guard let json = try? Self.encode(type: type, encoded: encoded) else { return }
        evaluatePostMessage(json: json)
    }

    private func evaluatePostMessage(json: String) {
        guard let webView = webView else { return }
        // Trailing `null` makes the script's last expression a JSON-bridgeable
        // value. Without it, WKWebView's evaluateJavaScript surfaces
        // "Error: JavaScript execution returned a result of an unsupported type"
        // because window.postMessage(...) returns undefined.
        webView.evaluateJavaScript("window.postMessage(\(json)); null;", completionHandler: nil)
    }

    // MARK: - JSON encoding

    /// Produces the `{type, data}` JSON for an Encodable AutomationWebView payload.
    static func encode<T: Encodable>(type: String, encoded: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let inner = try encoder.encode(encoded)
        guard let innerStr = String(data: inner, encoding: .utf8) else {
            throw NSError(domain: "PostMessageReplySink", code: 0)
        }
        return "{\"type\":\"\(type)\",\"data\":\(innerStr)}"
    }

    /// Produces a UIWebView `{type, data}` JSON object for `[String: Any]`.
    /// Returns `nil` if the type contains disallowed characters or the data isn't valid JSON.
    static func encodeUIWebViewMessage(type: String, data: [String: Any]) -> String? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        guard type.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        let envelope: [String: Any] = ["type": type, "data": data]
        guard JSONSerialization.isValidJSONObject(envelope),
              let bytes = try? JSONSerialization.data(withJSONObject: envelope),
              let str = String(data: bytes, encoding: .utf8) else { return nil }
        return str
    }
}

extension PostMessageReplySink {
    func sendOAuthResult(success: Bool, connectionId: String? = nil, error: String? = nil) {
        if success, let connectionId = connectionId {
            sendUIWebViewMessage(type: "oauth-success", data: ["connectionId": connectionId])
        } else {
            sendUIWebViewMessage(type: "oauth-error",
                       data: ["error": error ?? "Error processing the data."])
        }
    }
}

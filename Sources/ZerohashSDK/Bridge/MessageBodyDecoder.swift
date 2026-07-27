import Foundation

/// JSON-decoding helpers for `WKScriptMessage.body` values.
///
/// Extracted out of `NativeIOSMessageHandler` so tests can call these
/// directly without needing `*ForTest` shim methods on the handler. The
/// type is intentionally `enum` (uninhabited) and exposes only static
/// functions — no instance state, no surface to misuse.
enum MessageBodyDecoder {
    /// Returns JSON `Data` for a `WKScriptMessage.body`, or `nil` if the
    /// body is neither a JSON string nor a JSON-serialisable Foundation
    /// value (e.g. NSDictionary, NSArray of primitives).
    static func data(from body: Any) -> Data? {
        if let s = body as? String { return s.data(using: .utf8) }
        if JSONSerialization.isValidJSONObject(body) {
            return try? JSONSerialization.data(withJSONObject: body)
        }
        return nil
    }

    /// True iff the parsed JSON object carries a `role` of `zeroauth-host`,
    /// the wire marker for a `ZeroAuthRequest` envelope.
    static func isAutomationWebViewRequest(_ obj: [String: Any]) -> Bool {
        (obj["role"] as? String) == WireRole.host
    }
}

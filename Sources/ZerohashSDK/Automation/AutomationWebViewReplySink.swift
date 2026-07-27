import Foundation

/// Outbound channel for the AutomationWebView bridge: lets a router push responses and
/// events back to the JavaScript side without owning a WebView.
///
/// Conformers automatically gain `BridgeEventEmitting` so they can be passed
/// to `ExecutionContextImpl.eventEmitter` (the cancel-path emitter).
protocol AutomationWebViewReplySink: AnyObject, BridgeEventEmitting {
    func send(response: ZeroAuthResponse)
    func send(event: BridgeEvent)
}

extension AutomationWebViewReplySink {
    func emitEvent(correlationId: String, type: String) {
        send(event: BridgeEvent(correlationId: correlationId, type: type, data: nil))
    }
}

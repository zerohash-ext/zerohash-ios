import Foundation

@MainActor
final class AutomationWebViewMessageRouter: BridgeEventEmitting {
    private let registry: PlatformRegistry
    private weak var sink: AutomationWebViewReplySink?
    private let executionContextFactory: (_ requestId: String) -> ExecutionContext
    /// Holds the single in-flight withdraw session across bridge requests. The
    /// router delegates `withdraw.*` here so it stays a generic dispatcher.
    private let withdraw: WithdrawCoordinator

    /// In-flight idempotent reads keyed by "platform/op". Multiple
    /// concurrent dispatches for the same key share the same Task and
    /// reply with the same payload (each tagged with its own request id).
    private var inFlight: [String: Task<Result<OperationSuccess, AutomationWebViewError>, Never>] = [:]

    /// Internal success payload for an operation. `data` is the encoded result;
    /// `sessionId` is non-nil only for session-opening/continuing ops (withdraw),
    /// which the reply echoes back to the web side. Everything else leaves it nil.
    private struct OperationSuccess {
        let data: JSONValue
        var sessionId: String? = nil
    }

    init(
        registry: PlatformRegistry,
        sink: AutomationWebViewReplySink,
        executionContextFactory: @escaping (_ requestId: String) -> ExecutionContext,
        withdraw: WithdrawCoordinator = WithdrawCoordinator()
    ) {
        self.registry = registry
        self.sink = sink
        self.executionContextFactory = executionContextFactory
        self.withdraw = withdraw
    }

    nonisolated func emitEvent(correlationId: String, type: String) {
        Task { @MainActor in
            self.sink?.send(event: BridgeEvent(correlationId: correlationId, type: type, data: nil))
        }
    }

    func dispatch(_ req: ZeroAuthRequest) async {
        Log.automation.debug("dispatch id=\(req.id, privacy: .public) platform=\(req.platform, privacy: .public) op=\(req.operation, privacy: .public) inFlight=\(self.inFlight.count)")
        let start = Date()

        // 1. core.ping short-circuit
        if req.operation == "core.ping" {
            let v = "ios-\(ZerohashSDK.version)"
            let data: JSONValue = .object(["ok": .bool(true), "version": .string(v)])
            Log.automation.debug("core.ping OK id=\(req.id, privacy: .public) version=\(v, privacy: .public)")
            sink?.send(response: ZeroAuthResponse(
                id: req.id, success: true, data: data, error: nil, sessionId: nil
            ))
            return
        }

        // 2. platform lookup
        guard let platform = registry[req.platform] else {
            Log.automation.error("platform not registered: \(req.platform, privacy: .public) id=\(req.id, privacy: .public)")
            sink?.send(response: errorResponse(id: req.id, error: .platformNotRegistered(req.platform), operation: req.operation))
            return
        }

        // 3. coalescing for idempotent reads
        if Self.isCoalescable(operation: req.operation) {
            await dispatchCoalesced(req: req, platform: platform)
        } else {
            await dispatchUnique(req: req, platform: platform)
        }
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        Log.automation.debug("dispatch finished id=\(req.id, privacy: .public) op=\(req.operation, privacy: .public) totalMs=\(ms)")
    }

    static func isCoalescable(operation: String) -> Bool {
        switch operation {
        case "auth.status", "getBalance": return true
        default: return false
        }
    }

    private func dispatchCoalesced(req: ZeroAuthRequest, platform: any PlatformIdentity) async {
        let key = "\(req.platform)/\(req.operation)"
        let task: Task<Result<OperationSuccess, AutomationWebViewError>, Never>
        if let existing = inFlight[key] {
            Log.automation.debug("coalescing id=\(req.id, privacy: .public) onto in-flight \(key, privacy: .public)")
            task = existing
        } else {
            Log.automation.debug("starting in-flight task id=\(req.id, privacy: .public) key=\(key, privacy: .public)")
            task = Task { [weak self] in
                guard let self else { return .failure(.cancelled) }
                let result = await self.runOperation(req: req, platform: platform)
                self.inFlight[key] = nil
                return result
            }
            inFlight[key] = task
        }

        switch await task.value {
        case .success(let success):
            Log.automation.debug("coalesced reply id=\(req.id, privacy: .public) success=true")
            sink?.send(response: ZeroAuthResponse(
                id: req.id, success: true, data: success.data, error: nil, sessionId: success.sessionId))
        case .failure(let err):
            Log.automation.error("coalesced reply id=\(req.id, privacy: .public) success=false err=\(err.wire, privacy: .public)")

            if case .cancelled = err {
                sink?.send(event: BridgeEvent(correlationId: req.id, type: "cancelled", data: nil))
            }
            sink?.send(response: errorResponse(id: req.id, error: err, operation: req.operation))
        }
    }

    private func dispatchUnique(req: ZeroAuthRequest, platform: any PlatformIdentity) async {
        let result = await runOperation(req: req, platform: platform)
        switch result {
        case .success(let success):
            Log.automation.debug("unique reply id=\(req.id, privacy: .public) success=true")
            sink?.send(response: ZeroAuthResponse(
                id: req.id, success: true, data: success.data, error: nil, sessionId: success.sessionId))
        case .failure(let err):
            Log.automation.error("unique reply id=\(req.id, privacy: .public) success=false err=\(err.wire, privacy: .public)")
            // CancellationError is mapped here, with the cancelled event.
            if case .cancelled = err {
                sink?.send(event: BridgeEvent(correlationId: req.id, type: "cancelled", data: nil))
            }
            sink?.send(response: errorResponse(id: req.id, error: err, operation: req.operation))
        }
    }

    private func runOperation(
        req: ZeroAuthRequest,
        platform: any PlatformIdentity
    ) async -> Result<OperationSuccess, AutomationWebViewError> {
        let ctx = executionContextFactory(req.id)
        do {
            switch req.operation {
            case "auth.login":
                guard let p = platform as? AuthFlow else {
                    return .failure(.unsupported(operation: req.operation, on: platform.id))
                }
                let result = try await p.login(ctx: ctx)
                Log.automation.debug("auth.login OK id=\(req.id, privacy: .public)")
                return .success(OperationSuccess(data: try Self.encode(result)))

            case "auth.status":
                guard let p = platform as? AuthFlow else {
                    return .failure(.unsupported(operation: req.operation, on: platform.id))
                }
                let result = try await p.status(ctx: ctx)
                Log.automation.debug("auth.status OK id=\(req.id, privacy: .public) loggedIn=\(result.loggedIn)")
                return .success(OperationSuccess(data: try Self.encode(result)))

            case "getDepositAddress":
                guard let p = platform as? DepositFlow else {
                    return .failure(.unsupported(operation: req.operation, on: platform.id))
                }
                let payload = try GetDepositAddressPayload.decode(from: req.payload)

                let overlay = OverlayOptions(resolving: req.options?.overlayOptions?.asPartial)
                let showOverlay = req.options?.initialOverlay ?? true
            
                let result = try await p.getDepositAddress(ctx: ctx, payload: payload, overlay: overlay, showOverlay: showOverlay)
                Log.automation.debug("getDepositAddress OK id=\(req.id, privacy: .public)")
                return .success(OperationSuccess(data: try Self.encode(result)))

            case "getBalance":
                guard let p = platform as? BalanceFlow else {
                    return .failure(.unsupported(operation: req.operation, on: platform.id))
                }
                let overlay = OverlayOptions(resolving: req.options?.overlayOptions?.asPartial)
                let showOverlay = req.options?.initialOverlay ?? true
                let result = try await p.getBalance(ctx: ctx, overlay: overlay, showOverlay: showOverlay)
                Log.automation.debug("getBalance OK id=\(req.id, privacy: .public) count=\(result.count)")
                return .success(OperationSuccess(data: try Self.encode(result)))

            case "withdraw.start":
                guard let p = platform as? WithdrawFlow else {
                    return .failure(.unsupported(operation: req.operation, on: platform.id))
                }
                let payload = try StartWithdrawPayload.decode(from: req.payload)
                let overlay = OverlayOptions(resolving: req.options?.overlayOptions?.asPartial)
                let showOverlay = req.options?.initialOverlay ?? true
                let (state, sessionId) = try await withdraw.start(
                    platform: p, ctx: ctx, payload: payload, overlay: overlay, showOverlay: showOverlay)
                Log.automation.debug("withdraw.start OK id=\(req.id, privacy: .public) sessionId=\(sessionId, privacy: .public)")
                return .success(OperationSuccess(data: try Self.encode(state), sessionId: sessionId))

            case "withdraw.continue":
                guard let p = platform as? WithdrawFlow else {
                    return .failure(.unsupported(operation: req.operation, on: platform.id))
                }
                let payload = try ContinueWithdrawPayload.decode(from: req.payload)
                let (state, sessionId) = try await withdraw.continue(
                    platform: p, sessionId: req.sessionId, payload: payload)
                Log.automation.debug("withdraw.continue OK id=\(req.id, privacy: .public) sessionId=\(sessionId, privacy: .public)")
                return .success(OperationSuccess(data: try Self.encode(state), sessionId: sessionId))

            case "withdraw.cancel":
                guard let p = platform as? WithdrawFlow else {
                    return .failure(.unsupported(operation: req.operation, on: platform.id))
                }
                let cancelled = try await withdraw.cancel(platform: p, sessionId: req.sessionId)
                Log.automation.debug("withdraw.cancel OK id=\(req.id, privacy: .public) cancelled=\(cancelled)")
                return .success(OperationSuccess(
                    data: .object(["cancelled": .bool(cancelled)]), sessionId: req.sessionId))

            default:
                return .failure(.unsupported(operation: req.operation, on: platform.id))
            }
        } catch is CancellationError {
            Log.automation.debug("cancelled id=\(req.id, privacy: .public)")
            return .failure(.cancelled)
        } catch let e as PlatformError {
            Log.automation.error("PlatformError id=\(req.id, privacy: .public): \(String(describing: e), privacy: .public)")
            return .failure(.platformThrew(e.message))
        } catch {
            Log.automation.error("error id=\(req.id, privacy: .public) type=\(String(describing: type(of: error)), privacy: .public)")
            return .failure(.platformThrew(Self.stripErrorPrefix(error.localizedDescription)))
        }
    }

    /// WebKit surfaces `throw new Error("code/slug")` as a `WKJavaScriptExceptionMessage`
    /// of `"Error: code/slug"`. The web-side classifier (`translateScrapingError`)
    /// extracts the code from the START of the string, so the `"Error: "` prefix makes
    /// every JS-thrown domain code (e.g. `withdraw/network-unavailable`) fall through to
    /// the generic "Something went wrong" bucket. Strip it so the code leads the wire string.
    private static func stripErrorPrefix(_ raw: String) -> String {
        let prefix = "Error: "
        return raw.hasPrefix(prefix) ? String(raw.dropFirst(prefix.count)) : raw
    }

    /// Whether the front-end may AUTOMATICALLY re-issue `operation`. Withdraw is out
    /// because a re-issue could move funds twice, `getDepositAddress` because a retry
    /// mints a fresh Lightning invoice. Unknown operations default to unsafe.
    static func isSafeToRetry(operation: String) -> Bool {
        switch operation {
        case "auth.login", "auth.status", "getBalance", "core.ping":
            return true
        default:
            return false
        }
    }

    private static func encode<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// `retryable` needs both a transient failure and a re-issuable operation.
    private func errorResponse(
        id: String,
        error: AutomationWebViewError,
        operation: String
    ) -> ZeroAuthResponse {
        ZeroAuthResponse(
            id: id, success: false, data: nil, error: error.wire, sessionId: nil,
            retryable: error.retryable && Self.isSafeToRetry(operation: operation))
    }
}

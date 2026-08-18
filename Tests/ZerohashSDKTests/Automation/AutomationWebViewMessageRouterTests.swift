import Testing
import Foundation
import UIKit
@testable import ZerohashSDK

@MainActor
/// Only the AUTH-4127 retry/error-contract tests. connect-ios carries the full
/// dispatch-routing suite; the rest is not yet backfilled here.
@Suite("AutomationWebViewMessageRouter error contract")
struct AutomationWebViewMessageRouterErrorContractTests {

    /// Records every reply / event the router emits.
    final class FakeReplySink: AutomationWebViewReplySink {
        var responses: [ZeroAuthResponse] = []
        var events: [BridgeEvent] = []
        func send(response: ZeroAuthResponse) { responses.append(response) }
        func send(event: BridgeEvent) { events.append(event) }
    }

    private struct StubAuthFlow: AuthFlow {
        let id: String
        let loginResult: AuthLoginResult
        let statusResult: AuthStatusResult
        let throwOnLogin: Error?
        let throwOnStatus: Error?

        init(id: String,
             login: AuthLoginResult = .init(loggedIn: true, outcome: "success"),
             status: AuthStatusResult = .init(loggedIn: false),
             throwOnLogin: Error? = nil,
             throwOnStatus: Error? = nil) {
            self.id = id
            self.loginResult = login
            self.statusResult = status
            self.throwOnLogin = throwOnLogin
            self.throwOnStatus = throwOnStatus
        }

        func login(ctx: ExecutionContext) async throws -> AuthLoginResult {
            if let e = throwOnLogin { throw e }
            return loginResult
        }
        func status(ctx: ExecutionContext) async throws -> AuthStatusResult {
            if let e = throwOnStatus { throw e }
            return statusResult
        }
    }

    private func makeRouter(seed: [any PlatformIdentity], sink: FakeReplySink) -> AutomationWebViewMessageRouter {
        let registry = PlatformRegistry(default: seed)
        let shared = SharedWebViewConfiguration()
        let host = UIViewController()
        return AutomationWebViewMessageRouter(
            registry: registry,
            sink: sink,
            executionContextFactory: { reqId in
                ExecutionContextImpl(
                    host: host, shared: shared,
                    currentRequestId: reqId, eventEmitter: sink
                )
            }
        )
    }

    @Test("a platform timeout reaches the wire naming its stage")
    func timeoutStageReachesTheWire() async {
        let sink = FakeReplySink()
        let router = makeRouter(
            seed: [StubAuthFlow(id: "cbase",
                                throwOnStatus: RunnerError.timeout(stage: .navigationSettle))],
            sink: sink)
        await router.dispatch(ZeroAuthRequest(id: "s1", platform: "cbase", operation: "auth.status"))
        #expect(sink.responses.count == 1)
        #expect(sink.responses[0].success == false)
        #expect(sink.responses[0].error == "timeout: navigationSettle")
    }

    @Test("a timeout on a read is advertised as retryable")
    func readTimeoutIsRetryable() async {
        let sink = FakeReplySink()
        let router = makeRouter(
            seed: [StubAuthFlow(id: "cbase",
                                throwOnStatus: RunnerError.timeout(stage: .initialLoad))],
            sink: sink)
        await router.dispatch(ZeroAuthRequest(id: "s2", platform: "cbase", operation: "auth.status"))
        #expect(sink.responses[0].retryable == true)
    }

    @Test("withdraw steps are never advertised as retryable")
    func withdrawStepsNeverRetryable() {
        let R = AutomationWebViewMessageRouter.self
        #expect(R.isSafeToRetry(operation: "withdraw.start") == false)
        #expect(R.isSafeToRetry(operation: "withdraw.continue") == false)
        #expect(R.isSafeToRetry(operation: "withdraw.cancel") == false)
        #expect(R.isSafeToRetry(operation: "something.unknown") == false)

        #expect(R.isSafeToRetry(operation: "auth.status") == true)
        #expect(R.isSafeToRetry(operation: "auth.login") == true)
        #expect(R.isSafeToRetry(operation: "getBalance") == true)

        #expect(R.isSafeToRetry(operation: "getDepositAddress") == false)
    }
}

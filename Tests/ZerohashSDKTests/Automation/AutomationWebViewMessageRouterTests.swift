import Testing
import Foundation
import UIKit
@testable import ZerohashSDK

@MainActor
/// Only the AUTH-4127 retry/error-contract tests. connect-ios carries the full
/// dispatch-routing suite; the rest is not yet backfilled here.
@Suite("AutomationWebViewMessageRouter error contract")
struct AutomationWebViewMessageRouterErrorContractTests {
    private let fictionalUserId = "8b0c2f4e-1a2b-4c3d-9e8f-0a1b2c3d4e5f"

    private var fictionalProfile: AuthProfile {
        AuthProfile(userId: fictionalUserId, firstName: "Jane Mary", lastName: "Doe")
    }

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

    private struct StubBalanceFlow: BalanceFlow {
        let id: String
        let throwOnGetBalance: Error?

        init(id: String, throwOnGetBalance: Error? = nil) {
            self.id = id
            self.throwOnGetBalance = throwOnGetBalance
        }

        func getBalance(
            ctx: ExecutionContext,
            overlay: OverlayOptions,
            showOverlay: Bool
        ) async throws -> [AssetBalance] {
            if let e = throwOnGetBalance { throw e }
            return []
        }
    }

    private func makeRouter(
        seed: [any PlatformIdentity],
        sink: FakeReplySink,
        isAutomationSupported: Bool = true
    ) -> AutomationWebViewMessageRouter {
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
            },
            isAutomationSupported: { isAutomationSupported }
        )
    }

    @Test("core.ping keeps automation integrations visible on a supported OS")
    func pingClearsHideFlagWhenSupported() async {
        let sink = FakeReplySink()
        let router = makeRouter(seed: [], sink: sink)
        await router.dispatch(ZeroAuthRequest(id: "p1", platform: "cbase", operation: "core.ping"))
        guard case .object(let fields)? = sink.responses.first?.data else {
            Issue.record("expected an object payload")
            return
        }
        #expect(fields["ok"] == .bool(true))
        #expect(fields["hideAutomationIntegrations"] == .bool(false))
    }

    @Test("core.ping asks the web side to hide automation integrations on an unsupported OS")
    func pingSetsHideFlagWhenUnsupported() async {
        let sink = FakeReplySink()
        let router = makeRouter(seed: [], sink: sink, isAutomationSupported: false)
        await router.dispatch(ZeroAuthRequest(id: "p2", platform: "cbase", operation: "core.ping"))
        guard case .object(let fields)? = sink.responses.first?.data else {
            Issue.record("expected an object payload")
            return
        }
        #expect(fields["hideAutomationIntegrations"] == .bool(true))
    }

    @Test("automation operations are refused on an unsupported OS")
    func operationsRefusedWhenUnsupported() async {
        let sink = FakeReplySink()
        let router = makeRouter(seed: [StubAuthFlow(id: "cbase")], sink: sink, isAutomationSupported: false)
        await router.dispatch(ZeroAuthRequest(id: "s3", platform: "cbase", operation: "auth.status"))
        #expect(sink.responses.count == 1)
        #expect(sink.responses[0].success == false)
        #expect(sink.responses[0].error == "operation 'auth.status' not supported on platform 'cbase'")
        #expect(sink.responses[0].retryable == false)
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

    @Test("a getBalance timeout is advertised as retryable")
    func balanceTimeoutIsRetryable() async {
        let sink = FakeReplySink()
        let router = makeRouter(
            seed: [StubBalanceFlow(id: "cbase", throwOnGetBalance: AutomatedRunError.timeout)],
            sink: sink)
        await router.dispatch(ZeroAuthRequest(id: "b1", platform: "cbase", operation: "getBalance"))
        #expect(sink.responses.count == 1)
        #expect(sink.responses[0].success == false)
        #expect(sink.responses[0].error == "timeout")
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
        #expect(R.isSafeToRetry(operation: "getDepositAddress") == true)
    }

    private func object(_ value: JSONValue?) -> [String: JSONValue]? {
        switch value {
        case .object(let fields)?:
            return fields
        default:
            return nil
        }
    }

    @Test("an auth.status profile failure is a success reply carrying the failure")
    func statusProfileFailure() async {
        let failure = AuthProfileFailure.forReason("graphql_error")
        let sink = FakeReplySink()
        let router = makeRouter(
            seed: [StubAuthFlow(id: "cbase", status: .init(loggedIn: true, profileFailure: failure))], sink: sink)

        await router.dispatch(ZeroAuthRequest(id: "pf1", platform: "cbase", operation: "auth.status"))

        let r = sink.responses[0]
        #expect(r.success == true)
        #expect(r.error == nil)
        #expect(r.retryable == false)
        #expect(r.data == .object([
            "loggedIn": .bool(true),
            "profileFailure": .object(["error": .string("PROFILE_INDETERMINATE"), "reason": .string("graphql_error")]),
        ]))
    }

    @Test("an auth.login profile failure is a success reply carrying the outcome and the failure")
    func loginProfileFailure() async {
        let failure = AuthProfileFailure.forReason("missing_field")
        let login = AuthLoginResult(loggedIn: true, outcome: "success", profileFailure: failure)
        let sink = FakeReplySink()
        let router = makeRouter(seed: [StubAuthFlow(id: "cbase", login: login)], sink: sink)

        await router.dispatch(ZeroAuthRequest(id: "pf2", platform: "cbase", operation: "auth.login"))

        let r = sink.responses[0]
        #expect(r.success == true)
        #expect(r.error == nil)
        #expect(r.retryable == false)
        #expect(r.data == .object([
            "loggedIn": .bool(true),
            "outcome": .string("success"),
            "profileFailure": .object(["error": .string("PROFILE_INCOMPLETE"), "reason": .string("missing_field")]),
        ]))
    }

    @Test("a signed-in status carries only the profile; a signed-out one has neither profile key")
    func statusProfileOnTheWire() async throws {
        let sink = FakeReplySink()
        let router = makeRouter(
            seed: [StubAuthFlow(id: "cbase", status: .init(loggedIn: true, profile: fictionalProfile))], sink: sink)
        await router.dispatch(ZeroAuthRequest(id: "pf4", platform: "cbase", operation: "auth.status"))
        let data = try #require(object(sink.responses[0].data))
        let p = try #require(object(data["profile"]))
        #expect(Set(data.keys) == ["loggedIn", "profile"])
        #expect(Set(p.keys) == ["userId", "firstName", "lastName"])
        #expect(p["firstName"] == .string("Jane Mary"))

        let outSink = FakeReplySink()
        let outRouter = makeRouter(seed: [StubAuthFlow(id: "cbase")], sink: outSink)
        await outRouter.dispatch(ZeroAuthRequest(id: "pf5", platform: "cbase", operation: "auth.status"))
        let out = try #require(object(outSink.responses[0].data))
        #expect(Set(out.keys) == ["loggedIn"])
    }
}

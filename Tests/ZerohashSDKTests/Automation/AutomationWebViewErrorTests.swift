import Testing
@testable import ZerohashSDK

@Suite("AutomationWebViewError retryable")
struct AutomationWebViewErrorTests {

    @Test("BALANCES_INDETERMINATE is retryable")
    func indeterminateRetryable() {
        let e = AutomationWebViewError.platformThrew(
            "BALANCES_INDETERMINATE: CryptoQuery — could not load a complete response")
        #expect(e.retryable == true)
    }

    @Test("CHALLENGE_UNSOLVED is retryable")
    func challengeRetryable() {
        #expect(AutomationWebViewError.platformThrew("CHALLENGE_UNSOLVED").retryable == true)
    }

    @Test("NOT_LOGGED_IN and other errors are not retryable")
    func othersNotRetryable() {
        #expect(AutomationWebViewError.platformThrew("not logged in").retryable == false)
        #expect(AutomationWebViewError.cancelled.retryable == false)
        #expect(AutomationWebViewError.invalidEnvelope.retryable == false)
    }

    @Test("transient runner failures are retryable")
    func transientRunnerFailuresRetryable() {
        #expect(AutomationWebViewError.platformThrew("timeout: navigationSettle").retryable == true)
        #expect(AutomationWebViewError.platformThrew("timeout: initialLoad").retryable == true)
        #expect(AutomationWebViewError.platformThrew("loadFailed: offline").retryable == true)
        #expect(AutomationWebViewError.platformThrew("navigationLost").retryable == true)
        #expect(AutomationWebViewError.platformThrew("hostUnavailable").retryable == true)
    }

    @Test("the stageless visible-runner timeout is retryable too")
    func statelessTimeoutRetryable() {
        #expect(AutomationWebViewError.platformThrew("timeout").retryable == true)
        #expect(
            AutomationWebViewError.platformThrew(
                AutomatedRunError.timeout.errorDescription ?? "").retryable == true)
    }

    @Test("platform-shape failures stay non-retryable")
    func shapeFailuresNotRetryable() {
        #expect(AutomationWebViewError.platformThrew("invalid JS return").retryable == false)
        #expect(AutomationWebViewError.platformThrew("asset_not_available:SOL visible=[BTC]").retryable == false)
    }
}

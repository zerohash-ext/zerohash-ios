import XCTest

/// Fund SDK e2e against the real gating backend (AUTH-3839, mirrors AUTH-3838).
/// Two configs toggled by the JWT's `auth_policy_enabled` claim: Auth-enabled
/// and non-Auth (ENG-6631 guard). See E2E/README.md for setup + triage.
final class FundGatingE2ETests: XCTestCase {

    private var harness: FundSessionHarness?

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        harness?.tearDown()
        harness = nil
        super.tearDown()
    }

    func testAuthEnabledJwtRendersIntegrationsSourcePicker() throws {
        let codes = try Gating.requireCodes(authEnabled: true)
        let jwt = try Gating.mintJwt(codes: codes, authPolicyEnabled: true)

        let h = FundSessionHarness(jwt: jwt).boot()
        harness = h

        h.acceptTermsIfPresent()

        // Auth on -> the source picker (or its manual-deposit escape hatch) must render.
        let picker = h.waitForText(FundSessionHarness.integrationsPickerTitle)
        let manual = picker
            ? true
            : h.waitForText(FundSessionHarness.depositManuallyText, timeout: 10)
        XCTAssertTrue(
            picker || manual,
            "Expected the integrations source picker "
                + "('\(FundSessionHarness.integrationsPickerTitle)' or "
                + "'\(FundSessionHarness.depositManuallyText)') to render for an "
                + "auth_policy_enabled JWT. Errors so far: \(h.recordedErrors)"
        )

        XCTAssertTrue(
            h.recordedErrors.isEmpty,
            "SDK reported errors during Auth-enabled boot: \(h.recordedErrors)"
        )
    }

    func testNonAuthJwtBootsStraightToNativeFundFlow_eng6631Guard() throws {
        // Non-auth platform (fwc only) — the exact ENG-6631 configuration.
        let codes = try Gating.requireCodes(authEnabled: false)
        let jwt = try Gating.mintJwt(codes: codes, authPolicyEnabled: false)

        let h = FundSessionHarness(jwt: jwt).boot()
        harness = h

        h.acceptTermsIfPresent()

        // Non-Auth -> gate stays off; the native Fund flow must render.
        let selectAsset = h.waitForText(FundSessionHarness.selectAssetTitle)
        XCTAssertTrue(
            selectAsset,
            "Expected '\(FundSessionHarness.selectAssetTitle)' to render for a "
                + "non-Auth JWT (ENG-6631 guard). Errors so far: \(h.recordedErrors)"
        )

        // ENG-6631 symptom was a terminal auth error on boot — assert none.
        XCTAssertTrue(
            h.recordedErrors.isEmpty,
            "SDK reported errors during non-Auth boot (ENG-6631 regression?): "
                + "\(h.recordedErrors)"
        )

        XCTAssertFalse(
            h.hasText(FundSessionHarness.integrationsPickerTitle),
            "Integrations source picker rendered for a non-Auth JWT — the "
                + "integrations gate should be off (ENG-6631)."
        )
    }
}
import XCTest

/// Boots a real Fund session against gating via HostApp (JWT injected through
/// `launchEnvironment["E2E_JWT"]`). Mirrors Android AUTH-3838; assertions use
/// the same semantic anchors as the AUTH-3630 web page objects.
final class FundSessionHarness {

    static let defaultTimeout: TimeInterval = 60
    static let termsTimeout: TimeInterval = 20

    // Semantic anchors — same strings the AUTH-3630 web page objects assert on.
    static let termsAcceptText = "Accept"
    static let integrationsPickerTitle = "Select source"
    static let depositManuallyText = "Deposit manually"
    static let selectAssetTitle = "Select asset"

    let app: XCUIApplication

    init(jwt: String) {
        app = XCUIApplication()
        app.launchEnvironment["E2E_JWT"] = jwt
    }

    @discardableResult
    func boot() -> FundSessionHarness {
        app.launch()
        return self
    }

    func tearDown() {
        app.terminate()
    }

    /// The Fund UI renders inside a WKWebView — match text anywhere in the app
    /// (static texts, links, buttons, and web-exposed accessibility elements).
    private func anyElement(containing text: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", text)
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    @discardableResult
    func waitForText(_ text: String, timeout: TimeInterval = FundSessionHarness.defaultTimeout) -> Bool {
        return anyElement(containing: text).waitForExistence(timeout: timeout)
    }

    func hasText(_ text: String) -> Bool {
        return anyElement(containing: text).exists
    }

    @discardableResult
    func tapText(_ text: String, timeout: TimeInterval = FundSessionHarness.defaultTimeout) -> Bool {
        let element = anyElement(containing: text)
        guard element.waitForExistence(timeout: timeout) else { return false }
        element.tap()
        return true
    }

    /// T&Cs may already be signed for a real gating participant — fall through if absent.
    func acceptTermsIfPresent(timeout: TimeInterval = FundSessionHarness.termsTimeout) {
        let accept = anyElement(containing: FundSessionHarness.termsAcceptText)
        guard accept.waitForExistence(timeout: timeout) else { return }
        accept.tap()
    }

    /// SDK errors recorded by the host app's `e2e-errors` label (empty = none).
    var recordedErrors: String {
        let label = app.staticTexts["e2e-errors"]
        return label.exists ? label.label : ""
    }
}
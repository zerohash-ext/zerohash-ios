import UIKit

@MainActor
public class ZerohashFundWithdrawalsSession {

    // MARK: - Properties

    private let jwt: String
    private let environment: Environment
    private let theme: Theme
    private let callbacks: FundWithdrawalsCallbacks
    private var webViewController: IntegrationsWebViewController?
    private var isPresented: Bool = false

    /// Hash route served by the mobile web app (`createHashRouter`, base `/mobile`).
    /// The route embeds the fund-withdrawals web component + iframe.
    private static let appIdentifier = "fund-withdrawals"

    // MARK: - Initialization

    public init(
        jwt: String,
        environment: Environment = .production,
        theme: Theme = .system,
        callbacks: FundWithdrawalsCallbacks = FundWithdrawalsCallbacks()
    ) {
        self.jwt = jwt
        self.environment = environment
        self.theme = theme
        self.callbacks = callbacks
    }

    // MARK: - Public API

    /// Presents the fund-withdrawals UI from the specified view controller
    public func present(from viewController: UIViewController) {
        guard !isPresented else { return }
        guard !jwt.isEmpty else { return }

        let callbacks = self.callbacks
        let webVC = IntegrationsWebViewController(
            appIdentifier: Self.appIdentifier,
            jwt: jwt,
            environment: environment,
            theme: theme,
            callbacks: IntegrationsWebViewCallbacks(
                onClose: callbacks.onClose,
                onCompleted: { data, jsonString in
                    callbacks.onWithdrawal?(
                        FundWithdrawalsEvent(
                            externalAccountId: data["externalAccountId"] as? String,
                            assetSymbol: data["assetSymbol"] as? String,
                            amount: data["amount"] as? String,
                            data: data,
                            jsonString: jsonString
                        )
                    )
                },
                onError: callbacks.onError,
                onEvent: callbacks.onEvent
            )
        )
        self.webViewController = webVC

        let nav = UINavigationController(rootViewController: webVC)
        nav.modalPresentationStyle = .fullScreen
        nav.modalPresentationCapturesStatusBarAppearance = true

        if theme.shouldUseDarkMode(in: nav.traitCollection) {
            nav.view.backgroundColor = Theme.darkBackgroundColor
        } else {
            nav.view.backgroundColor = .systemBackground
        }

        if let navigationBar = nav.navigationBar as UINavigationBar? {
            theme.configureNavigationBar(navigationBar, traitCollection: nav.traitCollection)
        }

        isPresented = true
        viewController.present(nav, animated: true)
    }

    /// Cancels the current session
    public func cancel() {
        webViewController?.dismiss(animated: true)
        webViewController = nil
        isPresented = false
    }

    /// Whether this session is currently active
    public var isActive: Bool {
        return isPresented
    }
}

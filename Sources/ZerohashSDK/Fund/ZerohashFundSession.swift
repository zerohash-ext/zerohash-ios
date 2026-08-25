import UIKit

@MainActor
public class ZerohashFundSession {

    // MARK: - Properties

    private let jwt: String
    private let environment: Environment
    private let theme: Theme
    private let callbacks: FundCallbacks
    private var webViewController: IntegrationsWebViewController?
    private var isPresented: Bool = false

    // MARK: - Initialization

    public init(
        jwt: String,
        environment: Environment = .production,
        theme: Theme = .system,
        callbacks: FundCallbacks = FundCallbacks()
    ) {
        self.jwt = jwt
        self.environment = environment
        self.theme = theme
        self.callbacks = callbacks
    }

    // MARK: - Public API

    /// Presents the Fund UI from the specified view controller
    public func present(from viewController: UIViewController) {
        guard !isPresented else { return }
        guard !jwt.isEmpty else { return }

        let webVC = IntegrationsWebViewController(
            appIdentifier: "fund",
            jwt: jwt,
            environment: environment,
            theme: theme,
            callbacks: IntegrationsWebViewCallbacks(
                onClose: callbacks.onClose,
                // Fund completes a deposit; the bridge hands back the raw payload
                // and this session types it as a `FundEvent`.
                onCompleted: { [callbacks] data, jsonString in
                    callbacks.onCompleted?(FundEvent(from: data, jsonString: jsonString))
                },
                onFailed: { [callbacks] data, jsonString in
                    callbacks.onFailed?(FundEvent(from: data, jsonString: jsonString))
                },
                // A status rather than an outcome, so it gets its own event type
                // and never touches onCompleted/onFailed.
                onDepositStatus: { [callbacks] data, jsonString in
                    callbacks.onDeposit?(FundDepositEvent(from: data, jsonString: jsonString))
                },
                onError: callbacks.onError,
                onLoaded: callbacks.onLoaded,
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

import UIKit

@MainActor
public class ZerohashFundSession {

    // MARK: - Properties

    private let jwt: String
    private let environment: Environment
    private let theme: Theme
    private let callbacks: FundCallbacks
    private var webViewController: FundWebViewController?
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

        let webVC = FundWebViewController(
            jwt: jwt,
            environment: environment,
            theme: theme,
            callbacks: callbacks
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

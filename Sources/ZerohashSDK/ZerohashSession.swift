import UIKit
import WebKit

@MainActor
public class ZerohashSession {

    // MARK: - Properties

    private let jwt: String
    private let environment: Environment
    private let callbacks: ZerohashCallbacks
    private var webViewController: WebViewController?

    // MARK: - Initialization

    public init(jwt: String, environment: Environment = .production, callbacks: ZerohashCallbacks = ZerohashCallbacks()) {
        self.jwt = jwt
        self.environment = environment
        self.callbacks = callbacks
    }

    // MARK: - Public API

    /// Presents the Zerohash WebView from the specified view controller
    /// - Parameters:
    ///   - viewController: The view controller to present from
    public func present(from viewController: UIViewController) {
        let webVC = WebViewController(jwt: jwt, environment: environment, callbacks: callbacks)
        self.webViewController = webVC

        webVC.modalPresentationStyle = .fullScreen
        viewController.present(webVC, animated: true)
    }

    /// Cancels the current session
    public func cancel() {
        webViewController?.dismiss(animated: true)
        webViewController = nil
    }
}

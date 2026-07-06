import UIKit
import WebKit

class WebViewController: UIViewController {

    // MARK: - Properties

    private var webView: WKWebView!
    private var messageHandler: WebViewMessageHandler?
    private let jwt: String
    private let environment: Environment
    private let callbacks: ZerohashCallbacks
    private let appIdentifier = "fund"

    // MARK: - Initialization

    init(jwt: String, environment: Environment, callbacks: ZerohashCallbacks) {
        self.jwt = jwt
        self.environment = environment
        self.callbacks = callbacks
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        setupUI()
        loadWebContent()
    }

    // MARK: - Private Methods

    private func setupUI() {
        view.backgroundColor = .systemBackground

        let userContentController = WKUserContentController()
        messageHandler = WebViewMessageHandler(jwt: jwt, appIdentifier: appIdentifier, environment: environment, callbacks: callbacks) { [weak self] in
            self?.dismiss(animated: true)
        }

        if let messageHandler = messageHandler {
            userContentController.add(messageHandler, name: "NativeIOS")
        }

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController
        configuration.allowsInlineMediaPlayback = true

        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences

        webView = WKWebView(frame: view.bounds, configuration: configuration)
        webView.backgroundColor = .systemBackground

        if let messageHandler = messageHandler {
            webView.navigationDelegate = messageHandler
            webView.uiDelegate = messageHandler
        }

        view.addSubview(webView)

        // Add constraints
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func loadWebContent() {
        let baseURL = environment.baseURL
        let urlString = "\(baseURL)?jwt=\(jwt)"

        guard let url = URL(string: urlString) else { return }
        let request = URLRequest(url: url)
        webView.load(request)
    }
}

import UIKit
import WebKit

class SubViewController: UIViewController, WKNavigationDelegate {

    private var webView: WKWebView!
    private let urlString: String
    private let theme: Theme
    private let environment: Environment
    private let activityIndicator = UIActivityIndicatorView(style: .large)

    init(urlString: String, theme: Theme = .system, environment: Environment) {
        self.urlString = urlString
        self.theme = theme
        self.environment = environment
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = "Loading..."

        if theme.shouldUseDarkMode(in: traitCollection) {
            view.backgroundColor = Theme.darkBackgroundColor
        } else {
            view.backgroundColor = .systemBackground
        }

        setupWebView()
        setupActivityIndicator()
        loadWebsite()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)

        if let navigationBar = navigationController?.navigationBar {
            theme.configureNavigationBar(navigationBar, traitCollection: traitCollection)
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if theme == .system && traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle {
            if theme.shouldUseDarkMode(in: traitCollection) {
                view.backgroundColor = Theme.darkBackgroundColor
            } else {
                view.backgroundColor = .systemBackground
            }

            if let navigationBar = navigationController?.navigationBar {
                theme.configureNavigationBar(navigationBar, traitCollection: traitCollection)
            }
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return theme.shouldUseDarkMode(in: traitCollection) ? .lightContent : .default
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        activityIndicator.stopAnimating()

        if let pageTitle = webView.title, !pageTitle.isEmpty {
            self.title = pageTitle
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        activityIndicator.startAnimating()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        activityIndicator.stopAnimating()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "http" || scheme == "https" else {
            decisionHandler(.cancel)
            return
        }

        let host = url.host ?? ""
        guard environment.trustedHosts.contains(host) else {
            Log.error("[SubViewController] Blocked navigation to untrusted host: \(host)")
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    // MARK: - Private

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func setupActivityIndicator() {
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)
        activityIndicator.center = view.center
    }

    private func loadWebsite() {
        guard let url = URL(string: urlString) else { return }
        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "https" || scheme == "http" else {
            Log.error("[SubViewController] Blocked initial load with non-http scheme: \(scheme)")
            return
        }
        let host = url.host ?? ""
        guard environment.trustedHosts.contains(host) else {
            Log.error("[SubViewController] Blocked initial load of untrusted host: \(host)")
            return
        }
        webView.load(URLRequest(url: url))
    }
}

import UIKit
import WebKit
import SafariServices

class FundWebViewController: UIViewController,
    WebViewLoadingManagerDelegate,
    FundWebViewMessageHandlerDelegate
{

    // MARK: - Properties

    private var webView: WKWebView!
    private let jwt: String
    private let environment: Environment
    private let theme: Theme
    private let callbacks: FundCallbacks
    private let appIdentifier = "fund"

    private var loadingManager: WebViewLoadingManager!
    private var messageHandler: FundWebViewMessageHandler!
    private var didFireClose = false

    // MARK: - Initialization

    init(jwt: String, environment: Environment, theme: Theme, callbacks: FundCallbacks) {
        self.jwt = jwt
        self.environment = environment
        self.theme = theme
        self.callbacks = callbacks
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        extendedLayoutIncludesOpaqueBars = true
        edgesForExtendedLayout = .all

        if theme.shouldUseDarkMode(in: traitCollection) {
            view.backgroundColor = Theme.darkBackgroundColor
            navigationController?.view.backgroundColor = Theme.darkBackgroundColor
        } else {
            view.backgroundColor = .systemBackground
            navigationController?.view.backgroundColor = .systemBackground
        }

        setupWebView()
        setupLoadingManager()
        loadWebContent()

        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)

        if let navigationBar = navigationController?.navigationBar {
            theme.configureNavigationBar(navigationBar, traitCollection: traitCollection)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || isMovingFromParent {
            fireClose()
        }
    }

    // MARK: - Theme

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if theme == .system && traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle {
            let isDark = theme.shouldUseDarkMode(in: traitCollection)

            if isDark {
                view.backgroundColor = Theme.darkBackgroundColor
                navigationController?.view.backgroundColor = Theme.darkBackgroundColor
                webView?.backgroundColor = Theme.darkBackgroundColor
                webView?.scrollView.backgroundColor = Theme.darkBackgroundColor
            } else {
                view.backgroundColor = .systemBackground
                navigationController?.view.backgroundColor = .systemBackground
                webView?.backgroundColor = .systemBackground
                webView?.scrollView.backgroundColor = .systemBackground
            }

            loadingManager?.updateTheme(for: traitCollection)

            if let navigationBar = navigationController?.navigationBar {
                theme.configureNavigationBar(navigationBar, traitCollection: traitCollection)
            }
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return theme.shouldUseDarkMode(in: traitCollection) ? .lightContent : .default
    }

    // MARK: - Setup

    private func setupWebView() {
        let userContentController = WKUserContentController()

        #if DEBUG
        let consoleBridge = WKUserScript(
            source: """
            (function() {
                function relay(level, args) {
                    var msg = Array.prototype.slice.call(args).map(function(a) {
                        return typeof a === 'object' ? JSON.stringify(a) : String(a);
                    }).join(' ');
                    if (window.webkit && window.webkit.messageHandlers.NativeIOS) {
                        window.webkit.messageHandlers.NativeIOS.postMessage(
                            JSON.stringify({ type: 'console.' + level, message: msg })
                        );
                    }
                }
                ['log','warn','error'].forEach(function(lvl) {
                    var orig = console[lvl];
                    console[lvl] = function() { orig.apply(console, arguments); relay(lvl, arguments); };
                });
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        userContentController.addUserScript(consoleBridge)

        let networkBridge = WKUserScript(
            source: """
            (function() {
                var _fetch = window.fetch;
                window.fetch = function(input, init) {
                    var url = typeof input === 'string' ? input : (input && input.url) || '';
                    var method = (init && init.method) || (input && input.method) || 'GET';
                    console.log('[Network] ' + method.toUpperCase() + ' ' + url);
                    return _fetch.apply(this, arguments).then(function(response) {
                        console.log('[Network] ' + response.status + ' ' + method.toUpperCase() + ' ' + url);
                        return response;
                    }).catch(function(err) {
                        console.error('[Network] FAILED ' + method.toUpperCase() + ' ' + url + ' — ' + err);
                        throw err;
                    });
                };

                var _open = XMLHttpRequest.prototype.open;
                var _send = XMLHttpRequest.prototype.send;
                XMLHttpRequest.prototype.open = function(method, url) {
                    this._zhMethod = method;
                    this._zhUrl = url;
                    return _open.apply(this, arguments);
                };
                XMLHttpRequest.prototype.send = function() {
                    var method = this._zhMethod || 'XHR';
                    var url = this._zhUrl || '';
                    console.log('[Network] ' + method.toUpperCase() + ' ' + url);
                    this.addEventListener('load', function() {
                        console.log('[Network] ' + this.status + ' ' + method.toUpperCase() + ' ' + url);
                    });
                    this.addEventListener('error', function() {
                        console.error('[Network] FAILED ' + method.toUpperCase() + ' ' + url);
                    });
                    return _send.apply(this, arguments);
                };
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        userContentController.addUserScript(networkBridge)
        #endif

        let config = WKWebViewConfiguration()
        config.userContentController = userContentController
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.allowsInlineMediaPlayback = true
        config.websiteDataStore = .nonPersistent()

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.isOpaque = false

        if theme.shouldUseDarkMode(in: traitCollection) {
            webView.backgroundColor = Theme.darkBackgroundColor
            webView.scrollView.backgroundColor = Theme.darkBackgroundColor
        } else {
            webView.backgroundColor = .systemBackground
            webView.scrollView.backgroundColor = .systemBackground
        }

        webView.alpha = 0.0
        webView.isUserInteractionEnabled = false

        messageHandler = FundWebViewMessageHandler(
            jwt: jwt,
            theme: theme,
            environment: environment
        )
        messageHandler.delegate = self
        userContentController.add(messageHandler, name: "NativeIOS")

        webView.navigationDelegate = messageHandler
        webView.uiDelegate = messageHandler

        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func setupLoadingManager() {
        loadingManager = WebViewLoadingManager(parentView: view, theme: theme)
        loadingManager.delegate = self
        loadingManager.setupLoadingView(in: traitCollection)
    }

    private func loadWebContent() {
        let urlString = "\(environment.fundBaseURL)/mobile/#\(appIdentifier)"
        guard let url = URL(string: urlString) else { return }
        webView.load(URLRequest(url: url))
    }

    // MARK: - FundWebViewMessageHandlerDelegate

    func messageHandlerDidReceiveContentReady(_ handler: FundWebViewMessageHandler) {
        loadingManager.transitionToWebView(webView: webView)
        let event = GenericEvent(type: "APP_LOADED", data: [:])
        callbacks.onEvent?(event)
    }

    func messageHandler(
        _ handler: FundWebViewMessageHandler,
        didReceiveNavigate url: String,
        mobileTarget: String?
    ) {
        guard let parsedURL = URL(string: url) else { return }

        switch mobileTarget {
        case "in_app":
            navigationController?.setNavigationBarHidden(false, animated: true)
            let subVC = SubViewController(urlString: url, theme: theme, environment: environment)
            navigationController?.pushViewController(subVC, animated: true)

        case "oauth":
            let safariVC = SFSafariViewController(url: parsedURL)
            safariVC.delegate = self
            safariVC.preferredControlTintColor = .systemBlue
            present(safariVC, animated: true)

        default:
            UIApplication.shared.open(parsedURL, options: [:], completionHandler: nil)
        }
    }

    func messageHandlerDidReceiveClose(_ handler: FundWebViewMessageHandler) {
        fireClose()
        dismiss(animated: true)
    }

    func messageHandlerDidReceiveDeposit(
        _ handler: FundWebViewMessageHandler,
        data: [String: Any],
        jsonString: String
    ) {
        let event = FundEvent(
            success: true,
            status: data["status"] as? String ?? "completed",
            data: data,
            jsonString: jsonString
        )
        callbacks.onFund?(event)
    }

    func messageHandler(
        _ handler: FundWebViewMessageHandler,
        didReceiveEvent type: String,
        data: [String: Any],
        jsonString: String
    ) {
        let event = GenericEvent(type: type, data: data, jsonString: jsonString)
        callbacks.onEvent?(event)
    }

    func messageHandler(
        _ handler: FundWebViewMessageHandler,
        didReceiveError data: [String: Any],
        jsonString: String
    ) {
        let event = ErrorEvent(from: data, jsonString: jsonString)
        callbacks.onError?(event)
    }

    // MARK: - WebViewLoadingManagerDelegate

    func loadingManagerDidRequestRetry(_ manager: WebViewLoadingManager) {
        manager.resetForRetry()
        loadWebContent()
    }

    func loadingManagerDidRequestClose(_ manager: WebViewLoadingManager) {
        fireClose()
        dismiss(animated: true)
    }

    private func fireClose() {
        guard !didFireClose else { return }
        didFireClose = true
        callbacks.onClose?()
    }
}

// MARK: - SFSafariViewControllerDelegate

extension FundWebViewController: @preconcurrency SFSafariViewControllerDelegate {
    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {}
}

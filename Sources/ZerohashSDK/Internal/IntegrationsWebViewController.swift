import AuthenticationServices
import UIKit
import WebKit

class IntegrationsWebViewController: UIViewController,
    WebViewLoadingManagerDelegate,
    IntegrationsWebViewMessageHandlerDelegate
{

    // MARK: - Properties

    private var webView: WKWebView!
    private let jwt: String
    private let environment: Environment
    private let theme: Theme
    private let callbacks: IntegrationsWebViewCallbacks
    /// Hash route segment served by the mobile web app (`/mobile/#<appIdentifier>`),
    /// and the prefix the web app's completion message maps to. `fund` for the
    /// Fund flow, `crypto-withdrawals` for the crypto-withdrawal flow,
    /// `fund-withdrawals` for the fund-withdrawal flow.
    private let appIdentifier: String

    private var loadingManager: WebViewLoadingManager!
    private var messageHandler: IntegrationsWebViewMessageHandler!
    private var didFireClose = false

    /// Shared process pool + persistent data store so a Coinbase login session
    /// carries across the Fund WebView, the offscreen `auth.status` runner, and
    /// the modal login flow. Mirrors connect-ios `SharedWebViewConfiguration`.
    private let sharedConfig = SharedWebViewConfiguration()
    private var replySink: PostMessageReplySink!
    private var automationRouter: AutomationWebViewMessageRouter!

    /// Fixed redirect scheme connection-service uses for mobile OAuth callbacks
    /// (`connectsdk-oauth://callback?connectionId=<uuid>`) — matches zerohash-android.
    private static let oauthCallbackScheme = "connectsdk-oauth"
    /// Held so the session isn't deallocated mid-flow.
    private var authSession: ASWebAuthenticationSession?

    // MARK: - Initialization

    init(
        appIdentifier: String,
        jwt: String,
        environment: Environment,
        theme: Theme,
        callbacks: IntegrationsWebViewCallbacks
    ) {
        self.appIdentifier = appIdentifier
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

        if theme == .system
            && traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle
        {
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
                forMainFrameOnly: true
            )
            userContentController.addUserScript(consoleBridge)

            let networkBridge = WKUserScript(
                source: """
                    (function() {
                        function stripQuery(url) {
                            var q = url.indexOf('?');
                            return q === -1 ? url : url.substring(0, q);
                        }
                        var _fetch = window.fetch;
                        window.fetch = function(input, init) {
                            var url = typeof input === 'string' ? input : (input && input.url) || '';
                            var method = (init && init.method) || (input && input.method) || 'GET';
                            var safe = stripQuery(url);
                            console.log('[Network] ' + method.toUpperCase() + ' ' + safe);
                            return _fetch.apply(this, arguments).then(function(response) {
                                console.log('[Network] ' + response.status + ' ' + method.toUpperCase() + ' ' + safe);
                                return response;
                            }).catch(function(err) {
                                console.error('[Network] FAILED ' + method.toUpperCase() + ' ' + safe + ' — ' + err);
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
                            var safe = stripQuery(this._zhUrl || '');
                            console.log('[Network] ' + method.toUpperCase() + ' ' + safe);
                            this.addEventListener('load', function() {
                                console.log('[Network] ' + this.status + ' ' + method.toUpperCase() + ' ' + safe);
                            });
                            this.addEventListener('error', function() {
                                console.error('[Network] FAILED ' + method.toUpperCase() + ' ' + safe);
                            });
                            return _send.apply(this, arguments);
                        };
                    })();
                    """,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
            userContentController.addUserScript(networkBridge)
        #endif

        let config = WKWebViewConfiguration()
        config.userContentController = userContentController
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.allowsInlineMediaPlayback = true
        // Shared persistent store (not `.nonPersistent()`) so the Coinbase login
        // session is reused by the automation runners.
        config.processPool = sharedConfig.processPool
        config.websiteDataStore = sharedConfig.dataStore

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

        messageHandler = IntegrationsWebViewMessageHandler(
            jwt: jwt,
            theme: theme,
            environment: environment
        )
        messageHandler.delegate = self
        userContentController.add(messageHandler, name: "NativeIOS")

        webView.navigationDelegate = messageHandler
        webView.uiDelegate = messageHandler

        // ZeroAuth scraping bridge: replies post back through the Fund WebView;
        // operations run in offscreen/modal WebViews sharing `sharedConfig`.
        replySink = PostMessageReplySink(webView: webView)
        automationRouter = AutomationWebViewMessageRouter(
            registry: PlatformRegistry.shared,
            sink: replySink,
            executionContextFactory: { [weak self] requestId in
                guard let self = self else {
                    fatalError("ExecutionContext factory invoked without owning controller")
                }
                return ExecutionContextImpl(
                    host: self,
                    shared: self.sharedConfig,
                    currentRequestId: requestId,
                    eventEmitter: self.automationRouter,
                    theme: self.theme
                )
            }
        )

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
        let urlString = "\(environment.cdnBaseURL)/mobile/#\(appIdentifier)"
        guard let url = URL(string: urlString) else { return }
        webView.load(URLRequest(url: url))
    }

    // MARK: - IntegrationsWebViewMessageHandlerDelegate

    func messageHandlerDidReceiveContentReady(_ handler: IntegrationsWebViewMessageHandler) {
        loadingManager.transitionToWebView(webView: webView)
        let event = GenericEvent(type: "APP_LOADED", data: [:])
        callbacks.onEvent?(event)
    }

    func messageHandler(
        _ handler: IntegrationsWebViewMessageHandler,
        didReceiveNavigate url: String,
        mobileTarget: String?
    ) {
        guard let parsedURL = URL(string: url) else { return }
        let scheme = parsedURL.scheme?.lowercased() ?? ""

        switch mobileTarget {
        case "in_app":
            guard scheme == "https" || scheme == "http" else { return }
            navigationController?.setNavigationBarHidden(false, animated: true)
            let subVC = SubViewController(urlString: url, theme: theme, environment: environment)
            navigationController?.pushViewController(subVC, animated: true)

        case "oauth":
            guard scheme == "https" else {
                Log.error("[Integrations] Blocked oauth navigation to non-https URL")
                return
            }
            startOAuthSession(url: parsedURL)

        default:
            // `external` hands the URL to the system browser (out-of-process, no
            // bridge/JWT access), so the destination is intentionally a third-party
            // host (Robinhood, Gemini, etc.). Gate on scheme only — a trusted-host
            // allow-list here would defeat the purpose of external navigation and
            // block every redirect integration.
            let safeSchemes: Set<String> = ["https", "http", "tel", "mailto", "sms"]
            guard safeSchemes.contains(scheme) else {
                Log.error("[Integrations] Blocked external navigation to unknown scheme: \(scheme)")
                return
            }
            UIApplication.shared.open(parsedURL, options: [:], completionHandler: nil)
        }
    }

    func messageHandlerDidReceiveClose(_ handler: IntegrationsWebViewMessageHandler) {
        fireClose()
        dismiss(animated: true)
    }

    func messageHandlerDidReceiveDeposit(
        _ handler: IntegrationsWebViewMessageHandler,
        data: [String: Any],
        jsonString: String
    ) {
        callbacks.onCompleted?(data, jsonString)
    }

    /// Withdrawal counterpart to `deposit`. The mobile web app posts
    /// `crypto-withdrawal` for the crypto-withdrawals route; both land on the
    /// same completion sink.
    func messageHandlerDidReceiveCryptoWithdrawal(
        _ handler: IntegrationsWebViewMessageHandler,
        data: [String: Any],
        jsonString: String
    ) {
        callbacks.onCompleted?(data, jsonString)
    }

    /// Completion for the fund-withdrawals route. The mobile web app posts
    /// `fund-withdrawal`; like `deposit`/`crypto-withdrawal` it lands on the
    /// same completion sink and the session types the payload.
    func messageHandlerDidReceiveFundWithdrawal(
        _ handler: IntegrationsWebViewMessageHandler,
        data: [String: Any],
        jsonString: String
    ) {
        callbacks.onCompleted?(data, jsonString)
    }

    func messageHandler(
        _ handler: IntegrationsWebViewMessageHandler,
        didReceiveEvent type: String,
        data: [String: Any],
        jsonString: String
    ) {
        let event = GenericEvent(type: type, data: data, jsonString: jsonString)
        callbacks.onEvent?(event)
    }

    func messageHandler(
        _ handler: IntegrationsWebViewMessageHandler,
        didReceiveError data: [String: Any],
        jsonString: String
    ) {
        let event = ErrorEvent(from: data, jsonString: jsonString)
        callbacks.onError?(event)
    }

    func messageHandler(
        _ handler: IntegrationsWebViewMessageHandler,
        didReceiveAutomationRequest request: ZeroAuthRequest
    ) {
        Task { @MainActor in await automationRouter.dispatch(request) }
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

// MARK: - OAuth (ASWebAuthenticationSession)

extension IntegrationsWebViewController: @preconcurrency ASWebAuthenticationPresentationContextProviding {

    /// Runs the OAuth flow. connection-service redirects to
    /// `connectsdk-oauth://callback?connectionId=<uuid>` on success; the session
    /// intercepts that scheme (no Info.plist registration needed), auto-dismisses,
    /// and we relay the outcome to the web SDK as `oauth-success` / `oauth-error`.
    /// `SFSafariViewController` could never capture this redirect — hence the flow
    /// used to hang and a manual close read as a cancel.
    fileprivate func startOAuthSession(url: URL) {
        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: IntegrationsWebViewController.oauthCallbackScheme
        ) { [weak self] callbackURL, error in
            Task { @MainActor in self?.finishOAuth(callbackURL: callbackURL, error: error) }
        }
        session.presentationContextProvider = self
        // Share the Safari cookie jar so an existing provider login is reused
        // (matches the previous SFSafariViewController behaviour).
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        if !session.start() {
            Log.error("[Integrations] Failed to start OAuth session")
            messageHandler.sendOAuthCancelled()
        }
    }

    private func finishOAuth(callbackURL: URL?, error: Error?) {
        authSession = nil
        if let error = error {
            // .canceledLogin == user dismissed the auth sheet.
            if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                messageHandler.sendOAuthCancelled()
            } else {
                Log.error("[Integrations] OAuth session failed: \(error.localizedDescription)")
                messageHandler.sendOAuthError("oauth_error")
            }
            return
        }
        guard let callbackURL = callbackURL,
            let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        else {
            messageHandler.sendOAuthCancelled()
            return
        }
        let items = components.queryItems ?? []
        if let providerError = items.first(where: { $0.name == "error" })?.value,
            !providerError.isEmpty
        {
            messageHandler.sendOAuthError(providerError)
            return
        }
        // Only a well-formed UUID connectionId is accepted (mirrors zerohash-android).
        if let connectionId = items.first(where: { $0.name == "connectionId" })?.value,
            UUID(uuidString: connectionId) != nil
        {
            messageHandler.sendOAuthSuccess(connectionId: connectionId)
        } else {
            messageHandler.sendOAuthCancelled()
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        view.window ?? ASPresentationAnchor()
    }
}

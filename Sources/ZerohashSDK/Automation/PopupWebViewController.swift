import Foundation
import UIKit
import WebKit

/// Hosts a social-login popup WebView created by `window.open` on any exchange.
@MainActor
final class PopupWebViewController:
    UIViewController,
    WKUIDelegate,
    WKNavigationDelegate
{
    private let webView: WKWebView
    private let titleText: String?
    private var didClose = false

    /// Invoked exactly once when the popup closes (window.close, Cancel, or
    /// dismissal). The owner uses this to drop its reference.
    var onClose: (() -> Void)?

    /// Invoked when the popup page looks like an embedded-WebView rejection
    /// (e.g. Google `disallowed_useragent`). Carries the offending URL.
    var onIdPRejection: ((URL) -> Void)?

    /// Heuristics for an embedded-WebView rejection page.
    static func isIdPRejection(_ url: URL?) -> Bool {
        guard let s = url?.absoluteString.lowercased() else { return false }
        return s.contains("disallowed_useragent")
            || s.contains("error=disallowed")
    }

    /// Internal (not private) so the production `didCommit` path can be exercised
    /// directly from a test hook rather than re-implementing the heuristic.
    /// Logging lives at the owner's `onIdPRejection` site to avoid duplicate logs.
    func checkRejection(_ url: URL?) {
        if Self.isIdPRejection(url), let url {
            onIdPRejection?(url)
        }
    }

    init(webView: WKWebView, title: String?) {
        self.webView = webView
        self.titleText = title
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = titleText
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(onCancelTapped))

        webView.uiDelegate = self
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

    @objc private func onCancelTapped() { close() }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Log.coinbase.debug("popup didStartProvisional url=\(webView.url?.absoluteString ?? "nil", privacy: .public)")
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        Log.coinbase.debug("popup didCommit host=\(webView.url?.host ?? "nil", privacy: .public) url=\(webView.url?.absoluteString ?? "nil", privacy: .public)")
        checkRejection(webView.url)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Log.coinbase.error("popup didFailProvisional url=\(webView.url?.absoluteString ?? "nil", privacy: .public) err=\(String(describing: error), privacy: .public)")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Log.coinbase.error("popup didFail url=\(webView.url?.absoluteString ?? "nil", privacy: .public) err=\(String(describing: error), privacy: .public)")
    }

    // `window.close()` from the popup (the final step of the OAuth handshake).
    func webViewDidClose(_ webView: WKWebView) { close() }

    private func close() {
        guard !didClose else { return }
        didClose = true
        onClose?()
        if presentingViewController != nil { dismiss(animated: true) }
    }
}

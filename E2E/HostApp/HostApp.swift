import UIKit
import ZerohashSDK

/// Minimal host for the Fund gating e2e suite (AUTH-3839). Reads `E2E_JWT`
/// from the launch environment, boots `configureFund(.gating)`, and mirrors
/// SDK callbacks into accessibility labels that XCUITest asserts on.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = HostViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

final class HostViewController: UIViewController {

    /// Accessibility identifiers the UI tests assert on.
    enum A11y {
        static let status = "e2e-status"
        static let errors = "e2e-errors"
        static let closed = "e2e-closed"
    }

    private let statusLabel = UILabel()
    private let errorsLabel = UILabel()
    private let closedLabel = UILabel()

    private var session: ZerohashFundSession?
    private var recordedErrors: [String] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        for (label, identifier, initial) in [
            (statusLabel, A11y.status, "idle"),
            (errorsLabel, A11y.errors, ""),
            (closedLabel, A11y.closed, "open"),
        ] {
            label.accessibilityIdentifier = identifier
            label.text = initial
            label.numberOfLines = 0
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
        }

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            errorsLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            errorsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            errorsLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            closedLabel.topAnchor.constraint(equalTo: errorsLabel.bottomAnchor, constant: 8),
            closedLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            closedLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard session == nil else { return }

        let jwt = ProcessInfo.processInfo.environment["E2E_JWT"] ?? ""
        guard !jwt.isEmpty else {
            statusLabel.text = "missing-jwt"
            return
        }

        let callbacks = FundCallbacks(
            onClose: { [weak self] in
                self?.closedLabel.text = "closed"
            },
            onCompleted: { [weak self] event in
                self?.statusLabel.text = "funded:\(event.transactionId ?? "nil"):\(event.assetSymbol ?? "nil")"
            },
            onFailed: { [weak self] event in
                self?.statusLabel.text = "fund-failed:\(event.transactionId ?? "nil")"
            },
            onError: { [weak self] error in
                guard let self else { return }
                self.recordedErrors.append("\(error.code): \(error.message)")
                self.errorsLabel.text = self.recordedErrors.joined(separator: " | ")
            },
            onEvent: { _ in }
        )

        let session = ZerohashSDK.configureFund(
            jwt: jwt,
            environment: .gating,
            theme: .light,
            callbacks: callbacks
        )
        self.session = session
        statusLabel.text = "presented"
        session.present(from: self)
    }
}
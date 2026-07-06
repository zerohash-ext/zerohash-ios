import UIKit
import WebKit

@MainActor
protocol WebViewLoadingManagerDelegate: AnyObject {
    func loadingManagerDidRequestRetry(_ manager: WebViewLoadingManager)
    func loadingManagerDidRequestClose(_ manager: WebViewLoadingManager)
}

@MainActor
class WebViewLoadingManager {

    weak var delegate: WebViewLoadingManagerDelegate?

    private weak var parentView: UIView?
    private var loadingContainerView: UIView!
    private var loadingLabel: UILabel!
    private var dotsContainer: UIView!
    private var dots: [UIView] = []
    private var closeButton: UIButton!
    private let theme: Theme

    init(parentView: UIView, theme: Theme) {
        self.parentView = parentView
        self.theme = theme
    }

    func setupLoadingView(in traitCollection: UITraitCollection) {
        guard let parentView = parentView else { return }

        loadingContainerView = UIView()
        loadingContainerView.translatesAutoresizingMaskIntoConstraints = false

        if theme.shouldUseDarkMode(in: traitCollection) {
            loadingContainerView.backgroundColor = Theme.darkBackgroundColor
        } else {
            loadingContainerView.backgroundColor = .systemBackground
        }

        dotsContainer = UIView()
        dotsContainer.translatesAutoresizingMaskIntoConstraints = false

        let dotSize = Constants.LoadingAnimation.dotSize
        let dotColors = [
            UIColor(red: 204.0/255.0, green: 255.0/255.0, blue: 208.0/255.0, alpha: 1.0), // #CCFFD0
            UIColor(red: 171.0/255.0, green: 249.0/255.0, blue: 177.0/255.0, alpha: 1.0), // #ABF9B1
            UIColor(red: 143.0/255.0, green: 235.0/255.0, blue: 150.0/255.0, alpha: 1.0), // #8FEB96
        ]

        for i in 0..<3 {
            let dot = UIView()
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.backgroundColor = dotColors[i]
            dot.layer.cornerRadius = dotSize / 2
            dot.alpha = i == 0 ? 1.0 : 0.0
            dots.append(dot)
            dotsContainer.addSubview(dot)

            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: dotSize),
                dot.heightAnchor.constraint(equalToConstant: dotSize),
                dot.centerYAnchor.constraint(equalTo: dotsContainer.centerYAnchor),
                dot.centerXAnchor.constraint(equalTo: dotsContainer.centerXAnchor),
            ])
        }

        loadingLabel = UILabel()
        loadingLabel.translatesAutoresizingMaskIntoConstraints = false
        loadingLabel.text = ""
        loadingLabel.textColor = theme.shouldUseDarkMode(in: traitCollection) ? .white : .label
        loadingLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        loadingLabel.textAlignment = .center

        closeButton = UIButton(type: .system)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = theme.shouldUseDarkMode(in: traitCollection) ? .white : .label
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        parentView.addSubview(loadingContainerView)
        loadingContainerView.addSubview(dotsContainer)
        loadingContainerView.addSubview(loadingLabel)
        loadingContainerView.addSubview(closeButton)

        NSLayoutConstraint.activate([
            loadingContainerView.topAnchor.constraint(equalTo: parentView.topAnchor),
            loadingContainerView.bottomAnchor.constraint(equalTo: parentView.bottomAnchor),
            loadingContainerView.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
            loadingContainerView.trailingAnchor.constraint(equalTo: parentView.trailingAnchor),

            dotsContainer.centerXAnchor.constraint(equalTo: loadingContainerView.centerXAnchor),
            dotsContainer.centerYAnchor.constraint(
                equalTo: loadingContainerView.centerYAnchor, constant: -20),
            dotsContainer.widthAnchor.constraint(
                equalToConstant: dotSize * 3 + Constants.LoadingAnimation.dotSpacing * 2),
            dotsContainer.heightAnchor.constraint(equalToConstant: dotSize + 20),

            loadingLabel.topAnchor.constraint(
                equalTo: dotsContainer.bottomAnchor,
                constant: Constants.Layout.loadingLabelTopSpacing),
            loadingLabel.centerXAnchor.constraint(equalTo: loadingContainerView.centerXAnchor),
            loadingLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: loadingContainerView.leadingAnchor,
                constant: Constants.Layout.labelHorizontalPadding),
            loadingLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: loadingContainerView.trailingAnchor,
                constant: -Constants.Layout.labelHorizontalPadding),

            closeButton.topAnchor.constraint(
                equalTo: loadingContainerView.safeAreaLayoutGuide.topAnchor, constant: 20),
            closeButton.trailingAnchor.constraint(
                equalTo: loadingContainerView.trailingAnchor, constant: -20),
            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30),
        ])

        startThreeStepAnimation()
    }

    func transitionToWebView(webView: WKWebView, completion: (() -> Void)? = nil) {
        guard loadingContainerView?.superview != nil else { return }

        UIView.animate(
            withDuration: Constants.Layout.webViewTransitionDuration,
            delay: Constants.Layout.webViewTransitionDelay,
            options: [.curveEaseInOut],
            animations: {
                self.loadingContainerView.alpha = 0.0
                webView.alpha = 1.0
            },
            completion: { _ in
                self.stopThreeStepAnimation()
                self.loadingContainerView.removeFromSuperview()
                webView.isUserInteractionEnabled = true
                completion?()
            }
        )
    }

    func showError(in traitCollection: UITraitCollection) {
        guard loadingContainerView?.superview != nil else { return }

        stopThreeStepAnimation()
        loadingLabel.text = "Failed to load"

        let retryButton = UIButton(type: .system)
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.setTitle("Retry", for: .normal)
        retryButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        retryButton.tintColor = theme.shouldUseDarkMode(in: traitCollection) ? .white : .systemBlue

        loadingContainerView.addSubview(retryButton)

        NSLayoutConstraint.activate([
            retryButton.topAnchor.constraint(
                equalTo: loadingLabel.bottomAnchor,
                constant: Constants.Layout.retryButtonTopSpacing),
            retryButton.centerXAnchor.constraint(equalTo: loadingContainerView.centerXAnchor),
        ])
    }

    func resetForRetry() {
        loadingLabel.text = ""

        for (index, dot) in dots.enumerated() {
            dot.alpha = index == 0 ? 1.0 : 0.0
            dot.transform = .identity
        }

        startThreeStepAnimation()

        loadingContainerView.subviews.forEach { view in
            if view is UIButton {
                view.removeFromSuperview()
            }
        }
    }

    func updateTheme(for traitCollection: UITraitCollection) {
        guard loadingContainerView?.superview != nil else { return }

        let isDark = theme.shouldUseDarkMode(in: traitCollection)
        loadingContainerView?.backgroundColor = isDark ? Theme.darkBackgroundColor : .systemBackground
        loadingLabel?.textColor = isDark ? .white : .label
        closeButton?.tintColor = isDark ? .white : .label

        for subview in loadingContainerView?.subviews ?? [] {
            if let button = subview as? UIButton, button != closeButton {
                button.tintColor = isDark ? .white : .systemBlue
            }
        }
    }

    // MARK: - Private animation methods

    private func startThreeStepAnimation() {
        animateStep1()
    }

    private func animateStep1() {
        guard dots.count >= 1 else { return }

        let firstDot = dots[0]
        let dotSpacing = Constants.LoadingAnimation.dotSpacing

        UIView.animate(withDuration: 0.4, delay: 0.3, options: [.curveEaseInOut], animations: {
            firstDot.transform = CGAffineTransform(translationX: -(dotSpacing * 1.5), y: 0)
        }) { _ in
            self.animateStep2()
        }
    }

    private func animateStep2() {
        guard dots.count >= 3 else { return }

        let dotSpacing = Constants.LoadingAnimation.dotSpacing
        dots[1].transform = CGAffineTransform(translationX: 0, y: 0)
        dots[2].transform = CGAffineTransform(translationX: dotSpacing * 1.5, y: 0)

        UIView.animate(withDuration: 0.4, delay: 0, options: [.curveEaseInOut], animations: {
            self.dots[1].alpha = 1.0
        }) { _ in
            UIView.animate(withDuration: 0.4, delay: 0, options: [.curveEaseInOut], animations: {
                self.dots[2].alpha = 1.0
            }) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.animateStep3()
                }
            }
        }
    }

    private func animateStep3() {
        guard dots.count >= 3 else { return }

        dotsContainer.bringSubviewToFront(dots[0])

        UIView.animate(withDuration: 0.4, delay: 0, options: [.curveEaseInOut], animations: {
            for dot in self.dots {
                dot.transform = .identity
            }
        }) { _ in
            UIView.animate(withDuration: 0.3, animations: {
                self.dots[1].alpha = 0.0
                self.dots[2].alpha = 0.0
            }) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now()) {
                    if self.loadingContainerView?.superview != nil {
                        self.animateStep1()
                    }
                }
            }
        }
    }

    private func stopThreeStepAnimation() {
        if dots.count >= 1 {
            dotsContainer.bringSubviewToFront(dots[0])
        }

        UIView.animate(withDuration: 0.3, animations: {
            for dot in self.dots {
                dot.transform = .identity
            }
            self.dots[1].alpha = 0.0
            self.dots[2].alpha = 0.0
        }) { _ in
            for dot in self.dots {
                dot.layer.removeAllAnimations()
            }
        }
    }

    @objc private func retryTapped() {
        delegate?.loadingManagerDidRequestRetry(self)
    }

    @objc private func closeTapped() {
        delegate?.loadingManagerDidRequestClose(self)
    }
}

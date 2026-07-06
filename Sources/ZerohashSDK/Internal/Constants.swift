import UIKit

internal enum Constants {

    enum LoadingAnimation {
        static let dotSize: CGFloat = 16
        static let dotSpacing: CGFloat = 20
        static let animationDuration: TimeInterval = 0.5
        static let animationDelay: TimeInterval = 0.15
        static let animationTranslation: CGFloat = -15
    }

    enum Layout {
        static let labelHorizontalPadding: CGFloat = 40
        static let loadingLabelTopSpacing: CGFloat = 20
        static let retryButtonTopSpacing: CGFloat = 20
        static let webViewTransitionDuration: TimeInterval = 0.3
        static let webViewTransitionDelay: TimeInterval = 0.1
    }
}

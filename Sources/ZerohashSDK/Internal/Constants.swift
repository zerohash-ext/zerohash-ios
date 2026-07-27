import UIKit

internal enum Constants {

    enum LoadingAnimation {
        static let dotColor = UIColor(red: 204.0/255.0, green: 255.0/255.0, blue: 208.0/255.0, alpha: 1.0) // ZH Green #CCFFD0
        static let dotSize: CGFloat = 16
        static let dotSpacing: CGFloat = 20
        // Center-to-center distance between adjacent dots at full spread.
        // With dotSize 16 this yields a 14pt visible gap, so dots stay equally
        // spaced and never overlap.
        static let dotTranslation: CGFloat = 30
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

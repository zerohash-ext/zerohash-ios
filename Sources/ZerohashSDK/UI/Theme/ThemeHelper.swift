import UIKit

extension Theme {
    /// Dark background color (#111113)
    static let darkBackgroundColor = UIColor(red: 17.0/255.0, green: 17.0/255.0, blue: 19.0/255.0, alpha: 1.0)

    func shouldUseDarkMode(in traitCollection: UITraitCollection) -> Bool {
        switch self {
        case .dark: return true
        case .light: return false
        case .system: return traitCollection.userInterfaceStyle == .dark
        }
    }

    func navigationBarTintColor(in traitCollection: UITraitCollection) -> UIColor {
        return shouldUseDarkMode(in: traitCollection) ? .white : .label
    }

    func configureNavigationBar(_ navigationBar: UINavigationBar, traitCollection: UITraitCollection) {
        let appearance = UINavigationBarAppearance()

        if shouldUseDarkMode(in: traitCollection) {
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = Theme.darkBackgroundColor
            appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
            appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
            navigationBar.tintColor = .white
            navigationBar.barStyle = .black
        } else {
            appearance.configureWithDefaultBackground()
            appearance.titleTextAttributes = [.foregroundColor: UIColor.label]
            appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.label]
            navigationBar.tintColor = .systemBlue
            navigationBar.barStyle = .default
        }

        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
    }
}

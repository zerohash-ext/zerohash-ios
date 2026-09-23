#if DEBUG
import SwiftUI
import UIKit

// Xcode Canvas previews for the branded loading overlay. The overlay is a
// UIKit view, so we wrap it in a SwiftUI `UIViewRepresentable`; Canvas renders
// SwiftUI views more reliably than a bare `UIView`, and the wrapper lets us
// pin `.ignoresSafeArea()` so the footer sits above the home indicator like
// it does in the real automation flow.
//
// Not shipped: `#if DEBUG` keeps this out of release builds.

private struct LoadingOverlayPreview: UIViewRepresentable {
    let brand: Brand
    let theme: Theme

    // Production callers do `parent.addSubview(overlay); overlay.pinToSuperview()`
    // (see AutomatedWebViewController / AutomationSessionViewController). The
    // overlay's stage/footer constraints rely on that host chain — without a
    // superview it pins to, its layout collapses. So we return a container and
    // pin the overlay to it, mirroring the production embedding.
    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        let options = OverlayOptions(
            titles: ["Almost there", "One moment"],
            subtitles: [
                "We\u{2019}re securely accessing your account.",
                "Finalizing your session.",
            ],
            cycleMs: 5000,
            brand: brand
        )
        let overlay = LoadingOverlayView(options: options, theme: theme)
        container.addSubview(overlay)
        overlay.pinToSuperview()
        return container
    }

    func updateUIView(_ view: UIView, context: Context) {}
}

#Preview("connect · light") {
    LoadingOverlayPreview(brand: .connect, theme: .light).ignoresSafeArea()
}

#Preview("connect · dark") {
    LoadingOverlayPreview(brand: .connect, theme: .dark).ignoresSafeArea()
}

#Preview("zerohash · light") {
    LoadingOverlayPreview(brand: .zerohash, theme: .light).ignoresSafeArea()
}

#Preview("zerohash · dark") {
    LoadingOverlayPreview(brand: .zerohash, theme: .dark).ignoresSafeArea()
}

#Preview("secured-connect · light") {
    LoadingOverlayPreview(brand: .securedConnect, theme: .light).ignoresSafeArea()
}

#Preview("secured-connect · dark") {
    LoadingOverlayPreview(brand: .securedConnect, theme: .dark).ignoresSafeArea()
}
#endif

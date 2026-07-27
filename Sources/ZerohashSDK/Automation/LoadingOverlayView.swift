import UIKit

/// Full-screen, opaque, Connect-branded loading view that overlays the
/// automation WebView so the user never sees the underlying Coinbase page.
///
/// This is the native UIKit counterpart of the extension's injected overlay
/// (scraper-browser-extensions/src/platforms/coinbase/overlay.ts): a white
/// full-bleed background, a centered three-dot loader (using the three
/// `colors`), a title + subtitle, and a "Powered by <brand>" footer whose
/// mark is chosen by `options.brand`.
///
/// Titles/subtitles cycle in parallel every `cycleMs` when more than one
/// message is supplied; only the line whose text actually changed fades.
@MainActor
final class LoadingOverlayView: UIView {

    /// The resolved options driving copy, colors, and cycle timing.
    let options: OverlayOptions

    /// Host-selected theme used to resolve light/dark colors.
    let theme: Theme

    // MARK: - Subviews

    private let stage = UIView()
    private let dotsContainer = UIView()
    private var dots: [UIView] = []
    let titleLabel = UILabel()
    let subtitleLabel = UILabel()

    // Footer pieces kept so `applyTheme` can recolor them.
    private let footerBorder = UIView()
    private let footerLabel = UILabel()
    /// Trimmed brand mark, retained so `applyTheme` can re-render it (original in
    /// light, white template in dark). Nil if the asset failed to load.
    private var markBaseImage: UIImage?
    private var markImageView: UIImageView?

    // MARK: - Cycling state

    /// Number of cycle slots — the longer of the two arrays. <= 1 means static.
    private let slotCount: Int
    private var cycleIndex = 0
    private var cycleTimer: Timer?
    private var dotAnimationRunning = false

    // MARK: - Visual constants (mirrors overlay.ts CSS)

    private enum Metrics {
        // Sourced from Constants.LoadingAnimation so both overlays share one
        // source of truth and the dots stay equally spaced (no overlap).
        static let dotSize: CGFloat = Constants.LoadingAnimation.dotSize        // --dot-size
        static let dotSpacing: CGFloat = Constants.LoadingAnimation.dotSpacing  // --dot-spacing
        static let stageGap: CGFloat = 56       // gap between loader and text
        static let textGap: CGFloat = 6         // gap between title and subtitle
        // Gap between "Powered by" and the mark. The reference uses 8px, but it
        // never trims its SVGs, so its 8px sits against the asset's padded edge;
        // we trim to the first opaque pixel, making this a *true* gap — so a
        // slightly smaller value matches the reference's visual spacing.
        static let footerGap: CGFloat = 6
        // Height of the *trimmed* glyph (transparent margins removed), so this is
        // the true visible mark height. Set to the size the mark previously
        // rendered at: the connect glyph fills ~40% of its 28pt viewBox, i.e.
        // ~11.3pt visible, so trimming + this constant preserves that size while
        // fixing the vertical centering.
        static let footerMarkHeight: CGFloat = 11.3
        static let footerMarkOpticalRise: CGFloat = 0 // residual up-nudge if the centered glyph still reads low vs the text caps
        static let fadeDuration: TimeInterval = 0.25
    }

    // MARK: - Init

    init(options: OverlayOptions, theme: Theme = .system) {
        self.options = options
        self.theme = theme
        self.slotCount = max(options.titles.count, options.subtitles.count)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setupViews()
        setMessage(title: options.titles[0], subtitle: options.subtitles[0])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Layout helpers

    /// Pin all four edges to the immediate superview. Call after `addSubview`.
    func pinToSuperview() {
        guard let superview else { return }
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: superview.topAnchor),
            bottomAnchor.constraint(equalTo: superview.bottomAnchor),
            leadingAnchor.constraint(equalTo: superview.leadingAnchor),
            trailingAnchor.constraint(equalTo: superview.trailingAnchor),
        ])
    }

    private func setupViews() {
        // Opaque + swallow touches so the user can't interact with the page
        // underneath while automation runs. (Background set by `applyTheme`.)
        isOpaque = true
        isUserInteractionEnabled = true

        stage.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stage)

        dotsContainer.translatesAutoresizingMaskIntoConstraints = false
        stage.addSubview(dotsContainer)

        let dotColors = [
            UIColor(hexString: options.colors.left) ?? .yellow,
            UIColor(hexString: options.colors.middle) ?? .yellow,
            UIColor(hexString: options.colors.right) ?? .yellow,
        ]
        for i in 0..<3 {
            let dot = UIView()
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.backgroundColor = dotColors[i]
            dot.layer.cornerRadius = Metrics.dotSize / 2
            dot.alpha = i == 0 ? 1.0 : 0.0   // only the first dot visible initially
            dots.append(dot)
            dotsContainer.addSubview(dot)
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: Metrics.dotSize),
                dot.heightAnchor.constraint(equalToConstant: Metrics.dotSize),
                dot.centerYAnchor.constraint(equalTo: dotsContainer.centerYAnchor),
                dot.centerXAnchor.constraint(equalTo: dotsContainer.centerXAnchor),
            ])
        }

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 15, weight: .regular)
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        stage.addSubview(titleLabel)
        stage.addSubview(subtitleLabel)

        // Footer: "Powered by" + the brand mark for options.brand.
        let footer = makeFooter()
        addSubview(footer)

        NSLayoutConstraint.activate([
            // Stage fills the area above the footer and centers its content.
            stage.topAnchor.constraint(equalTo: topAnchor),
            stage.leadingAnchor.constraint(equalTo: leadingAnchor),
            stage.trailingAnchor.constraint(equalTo: trailingAnchor),
            stage.bottomAnchor.constraint(equalTo: footer.topAnchor),

            dotsContainer.centerXAnchor.constraint(equalTo: stage.centerXAnchor),
            dotsContainer.centerYAnchor.constraint(equalTo: stage.centerYAnchor),
            dotsContainer.widthAnchor.constraint(
                equalToConstant: Metrics.dotSize * 3 + Metrics.dotSpacing * 2),
            dotsContainer.heightAnchor.constraint(equalToConstant: Metrics.dotSize),

            titleLabel.topAnchor.constraint(
                equalTo: dotsContainer.bottomAnchor, constant: Metrics.stageGap),
            titleLabel.centerXAnchor.constraint(equalTo: stage.centerXAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: stage.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: stage.trailingAnchor, constant: -24),

            subtitleLabel.topAnchor.constraint(
                equalTo: titleLabel.bottomAnchor, constant: Metrics.textGap),
            subtitleLabel.centerXAnchor.constraint(equalTo: stage.centerXAnchor),
            subtitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: stage.leadingAnchor, constant: 24),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: stage.trailingAnchor, constant: -24),

            footer.leadingAnchor.constraint(equalTo: leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
        ])

        applyTheme(for: traitCollection)
    }

    /// Footer mirroring overlay.ts's `.zeroauth-footer`: a hairline top border,
    /// then a centered row of "Powered by" + the brand mark (28pt tall, aspect
    /// preserved, 8pt gap). If the mark asset can't be loaded we fall back to
    /// the text alone, matching overlay.ts's `onerror="this.remove()"`.
    private func makeFooter() -> UIView {
        let footer = UIView()
        footer.translatesAutoresizingMaskIntoConstraints = false

        // Hairline top border (color set by `applyTheme`).
        let border = footerBorder
        border.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(border)

        // Centered "Powered by" + mark row (CSS `display:flex; gap:8px`).
        let row = UIStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = Metrics.footerGap
        footer.addSubview(row)

        let label = footerLabel
        label.text = "Powered by"
        label.font = .systemFont(ofSize: 14, weight: .regular)
        // Text color set by `applyTheme`.
        row.addArrangedSubview(label)

        // Brand mark from the asset catalog (vector, rendered with its own
        // colors). The source SVGs center a small glyph inside a much larger
        // viewBox (the connect glyph is only ~40% of its box height; the zerohash
        // mark sits in a wide, tall box), so rendering the padded box would leave
        // the visible glyph floating high and offset from the text. We trim the
        // transparent margins on all four sides so the image box *is* the glyph:
        // `footerGap` becomes the true horizontal gap and the glyph's geometric
        // center is its visual center, so `.center` alignment lands it level with
        // the "Powered by" text. `footerMarkHeight` then sizes the bare glyph.
        if let raw = UIImage(named: options.brand.theme.markAssetName,
                             in: .module, compatibleWith: nil) {
            let mark = raw.trimmedToOpaqueBounds() ?? raw
            markBaseImage = mark
            // Rendering mode + tint set by `applyTheme`.
            let imageView = UIImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .scaleAspectFit
            // Optical centering nudge, mirroring the reference overlay's
            // `.zeroauth-mark { position: relative; bottom: 2px }`: the glyph
            // sits a touch low against the text, so lift it without disturbing
            // Auto Layout (the stack still centers the box).
            imageView.transform = CGAffineTransform(
                translationX: 0, y: -Metrics.footerMarkOpticalRise)
            row.addArrangedSubview(imageView)
            markImageView = imageView
            let aspect = mark.size.width / mark.size.height
            NSLayoutConstraint.activate([
                imageView.heightAnchor.constraint(equalToConstant: Metrics.footerMarkHeight),
                imageView.widthAnchor.constraint(
                    equalTo: imageView.heightAnchor, multiplier: aspect),
            ])
        }

        NSLayoutConstraint.activate([
            border.topAnchor.constraint(equalTo: footer.topAnchor),
            border.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            border.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            border.heightAnchor.constraint(equalToConstant: 1),

            row.topAnchor.constraint(equalTo: footer.topAnchor, constant: 22),
            row.bottomAnchor.constraint(equalTo: footer.bottomAnchor, constant: -22),
            row.centerXAnchor.constraint(equalTo: footer.centerXAnchor),
            row.leadingAnchor.constraint(greaterThanOrEqualTo: footer.leadingAnchor, constant: 24),
            row.trailingAnchor.constraint(lessThanOrEqualTo: footer.trailingAnchor, constant: -24),
        ])
        return footer
    }

    // MARK: - Theming

    /// Resolve theme-dependent colors. Dark values are fixed (not dynamic system
    /// colors) so an explicit `.light`/`.dark` renders correctly even on a device
    /// set to the opposite appearance. Dots keep their brand colors in both modes.
    private func applyTheme(for traitCollection: UITraitCollection) {
        let isDark = theme.shouldUseDarkMode(in: traitCollection)

        backgroundColor = isDark
            ? Theme.darkBackgroundColor
            : (UIColor(hexString: "#ffffff") ?? .white)

        let primaryText: UIColor = isDark ? .white : (UIColor(hexString: "#111827") ?? .label)
        titleLabel.textColor = primaryText
        footerLabel.textColor = primaryText

        subtitleLabel.textColor = isDark
            ? (UIColor(hexString: "#9ca3af") ?? .secondaryLabel)   // gray-400, legible on dark
            : (UIColor(hexString: "#4b5563") ?? .secondaryLabel)   // gray-600

        footerBorder.backgroundColor = isDark
            ? (UIColor(hexString: "#374151") ?? .separator)        // gray-700 hairline on dark
            : (UIColor(hexString: "#e5e7eb") ?? .separator)        // gray-200

        // Dark-on-transparent marks would vanish on the dark background, so use a
        // white template there; keep their own colors in light.
        if let base = markBaseImage {
            if isDark {
                markImageView?.image = base.withRenderingMode(.alwaysTemplate)
                markImageView?.tintColor = .white
            } else {
                markImageView?.image = base.withRenderingMode(.alwaysOriginal)
            }
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // Only `.system` tracks the device; re-apply when the appearance flips.
        guard theme == .system,
              traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle
        else { return }
        applyTheme(for: traitCollection)
    }

    // MARK: - Lifecycle

    /// Begin the dot animation and (if multiple messages) the copy cycle.
    /// Safe to call repeatedly. Automatically invoked when the view enters a
    /// window; call manually for explicit control.
    func start() {
        startDotAnimationIfNeeded()
        startCycleIfNeeded()
    }

    /// Stop animations and tear down the cycle timer. Safe to call repeatedly.
    func stop() {
        dotAnimationRunning = false
        cycleTimer?.invalidate()
        cycleTimer = nil
        for dot in dots { dot.layer.removeAllAnimations() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            start()
        } else {
            stop()
        }
    }

    // MARK: - Message cycling (mirrors overlay.ts startCycle/fadeSwap)

    private func startCycleIfNeeded() {
        guard slotCount > 1, cycleTimer == nil else { return }
        let interval = TimeInterval(options.cycleMs) / 1000.0
        // weak self in the closure to avoid a retain cycle through the timer.
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.advanceCycle()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        cycleTimer = timer
    }

    private func advanceCycle() {
        cycleIndex = (cycleIndex + 1) % slotCount
        // Index into each array independently with modulo, so a single-element
        // array stays static while the other cycles.
        let nextTitle = options.titles[cycleIndex % options.titles.count]
        let nextSubtitle = options.subtitles[cycleIndex % options.subtitles.count]
        fadeSwap(title: nextTitle, subtitle: nextSubtitle)
    }

    /// Fade only the line(s) whose text actually changed (matching overlay.ts).
    private func fadeSwap(title: String, subtitle: String) {
        let titleChanged = titleLabel.text != title
        let subtitleChanged = subtitleLabel.text != subtitle
        guard titleChanged || subtitleChanged else { return }

        UIView.animate(withDuration: Metrics.fadeDuration, animations: {
            if titleChanged { self.titleLabel.alpha = 0 }
            if subtitleChanged { self.subtitleLabel.alpha = 0 }
        }, completion: { _ in
            if titleChanged { self.titleLabel.text = title }
            if subtitleChanged { self.subtitleLabel.text = subtitle }
            UIView.animate(withDuration: Metrics.fadeDuration) {
                if titleChanged { self.titleLabel.alpha = 1 }
                if subtitleChanged { self.subtitleLabel.alpha = 1 }
            }
        })
    }

    private func setMessage(title: String, subtitle: String) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
    }

    // MARK: - Three-dot animation (reuses WebViewLoadingManager's keyframes)

    private func startDotAnimationIfNeeded() {
        guard !dotAnimationRunning else { return }
        dotAnimationRunning = true
        animateStep1()
    }

    private func animateStep1() {
        guard dotAnimationRunning, dots.count >= 1 else { return }
        let firstDot = dots[0]
        UIView.animate(withDuration: 0.4, delay: 0.3, options: [.curveEaseInOut], animations: {
            firstDot.transform = CGAffineTransform(translationX: -Constants.LoadingAnimation.dotTranslation, y: 0)
        }) { [weak self] _ in
            self?.animateStep2()
        }
    }

    private func animateStep2() {
        guard dotAnimationRunning, dots.count >= 3 else { return }
        dots[1].transform = .identity
        dots[2].transform = CGAffineTransform(translationX: Constants.LoadingAnimation.dotTranslation, y: 0)

        UIView.animate(withDuration: 0.4, delay: 0, options: [.curveEaseInOut], animations: {
            self.dots[1].alpha = 1.0
        }) { [weak self] _ in
            UIView.animate(withDuration: 0.4, delay: 0, options: [.curveEaseInOut], animations: {
                self?.dots[2].alpha = 1.0
            }) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.animateStep3()
                }
            }
        }
    }

    private func animateStep3() {
        guard dotAnimationRunning, dots.count >= 3 else { return }
        dotsContainer.bringSubviewToFront(dots[0])
        UIView.animate(withDuration: 0.4, delay: 0, options: [.curveEaseInOut], animations: {
            for dot in self.dots { dot.transform = .identity }
        }) { [weak self] _ in
            UIView.animate(withDuration: 0.3, animations: {
                self?.dots[1].alpha = 0.0
                self?.dots[2].alpha = 0.0
            }) { _ in
                guard let self, self.dotAnimationRunning else { return }
                self.animateStep1()
            }
        }
    }
}

extension UIColor {
    /// Parse a CSS hex string ("#rrggbb", "#rgb", or with optional alpha
    /// "#rrggbbaa" / "#rgba") into a `UIColor`. Returns `nil` for malformed
    /// input so callers can fall back to a sensible default. The leading `#`
    /// is optional. No existing hex helper shipped in the SDK, so this is the
    /// single source of truth for wire hex → UIColor conversion.
    convenience init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }

        // Expand shorthand (#rgb / #rgba) to full form.
        if hex.count == 3 || hex.count == 4 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        guard hex.count == 6 || hex.count == 8 else { return nil }

        var value: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&value) else { return nil }

        let r, g, b, a: CGFloat
        if hex.count == 8 {
            r = CGFloat((value & 0xFF00_0000) >> 24) / 255
            g = CGFloat((value & 0x00FF_0000) >> 16) / 255
            b = CGFloat((value & 0x0000_FF00) >> 8) / 255
            a = CGFloat(value & 0x0000_00FF) / 255
        } else {
            r = CGFloat((value & 0xFF0000) >> 16) / 255
            g = CGFloat((value & 0x00FF00) >> 8) / 255
            b = CGFloat(value & 0x0000FF) / 255
            a = 1.0
        }
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}

extension UIImage {
    /// Returns a copy cropped to the tight bounding box of its non-transparent
    /// pixels — transparent margins removed on all four sides. The vector brand
    /// marks center a small glyph inside a much larger viewBox; cropping to the
    /// glyph makes the footer's `footerGap` the true horizontal gap and makes the
    /// image box's center the glyph's visual center, so `.center` alignment sits
    /// the mark level with the "Powered by" text. The caller sizes the result via
    /// a height constraint, so this is the *visible* mark height. Returns `nil` if
    /// the image can't be rasterized or is fully transparent, so callers can fall
    /// back to the untrimmed image.
    func trimmedToOpaqueBounds(alphaThreshold: UInt8 = 1) -> UIImage? {
        // Rasterize the (vector) mark at >1x so edge detection is crisp; the
        // returned image carries this scale so its point size stays correct.
        let renderScale: CGFloat = 3
        let pxW = Int((size.width * renderScale).rounded(.up))
        let pxH = Int((size.height * renderScale).rounded(.up))
        guard pxW > 0, pxH > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * pxW
        var data = [UInt8](repeating: 0, count: bytesPerRow * pxH)
        guard let ctx = CGContext(
            data: &data, width: pxW, height: pxH,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Flip to UIKit's top-left origin so the drawn (and later cropped) image
        // is upright and the crop rect is expressed in the same coordinates.
        ctx.translateBy(x: 0, y: CGFloat(pxH))
        ctx.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(ctx)
        draw(in: CGRect(x: 0, y: 0, width: CGFloat(pxW), height: CGFloat(pxH)))
        UIGraphicsPopContext()

        // Tightest box containing any pixel at/above the alpha threshold.
        var minX = pxW, maxX = -1, minY = pxH, maxY = -1
        for y in 0..<pxH {
            let rowStart = y * bytesPerRow
            for x in 0..<pxW where data[rowStart + x * bytesPerPixel + 3] >= alphaThreshold {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY, let full = ctx.makeImage() else { return nil }

        let cropRect = CGRect(x: minX, y: minY,
                              width: maxX - minX + 1, height: maxY - minY + 1)
        guard let cropped = full.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: cropped, scale: renderScale, orientation: .up)
    }
}

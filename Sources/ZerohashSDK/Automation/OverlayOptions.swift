import Foundation

/// The three dot-fill colors of the loading overlay, as CSS hex strings
/// (e.g. `"#FCFC99"`). Mirrors the wire contract `OverlayColors`.
public struct OverlayColors: Equatable, Sendable {
    public let left: String
    public let middle: String
    public let right: String

    public init(left: String, middle: String, right: String) {
        self.left = left
        self.middle = middle
        self.right = right
    }
}

/// The brand whose palette + "Powered by" mark the overlay renders.
/// Mirrored from the Browser extension implementation. 
/// The brand is the *single source of truth* for the dot
/// palette and the footer logo: callers do not supply colors directly anymore
/// (matching `resolveOverlayOptions`, which derives `colors` purely from the
/// brand). `zerohash` is the default.
public enum Brand: String, Equatable, Sendable, CaseIterable {
    case connect
    case zerohash

    /// The default brand applied when the host omits or sends an unknown value.
    /// zerohash SDK: default to the zerohash mark/palette (connect-ios defaults
    /// to `.connect`; this is the zerohash-branded counterpart).
    public static let `default`: Brand = .zerohash

    /// Coerce an arbitrary wire string to a known brand, falling back to
    /// `.default` for anything not an exact match. Mirrors `normalizeBranding`
    /// (types.ts:167): an unknown, empty, or absent value resolves to the
    /// default brand so palette/asset lookup always has a valid brand.
    public static func normalize(_ raw: String?) -> Brand {
        guard let raw, let brand = Brand(rawValue: raw) else { return .default }
        return brand
    }

    /// The resolved theme — dot palette + footer mark asset — for this brand.
    /// Mirrors `BRANDING_THEMES` (types.ts:150). The asset names refer to
    /// imagesets in `Resources/Media.xcassets`, loaded from `Bundle.module`;
    /// they are the native counterpart of the extension's web-accessible
    /// `connect-mark.svg` / `zerohash-mark.svg`.
    public var theme: (colors: OverlayColors, markAssetName: String) {
        switch self {
        case .connect:
            return (OverlayColors(left: "#FCFC99", middle: "#F2F07D", right: "#F0D53E"),
                    "connect-mark")
        case .zerohash:
            return (OverlayColors(left: "#CCFFD0", middle: "#ABF9B1", right: "#8FEB96"),
                    "zerohash-mark")
        }
    }
}

/// Resolved per-call customization for the branded loading overlay.
///
/// This holds the *effective* (non-optional) values: every field has been
/// filled in from the caller's partial input or the defaults. Mirrors the
/// wire contract `OverlayOptions` (titles/subtitles cycle in parallel every
/// `cycleMs`; `branding` selects the dot palette and footer mark).
///
/// Note: `colors` is derived from `brand` (never supplied directly) and
/// `assetUrl` is intentionally absent — the "Powered by" mark is a local SDK
/// concern resolved from `brand.theme.markAssetName`, not part of the wire
/// payload.
public struct OverlayOptions: Equatable, Sendable {
    public let titles: [String]
    public let subtitles: [String]
    public let cycleMs: Int
    public let brand: Brand
    /// Derived from `brand` — see `Brand.theme`. Kept as a stored property so
    /// `LoadingOverlayView` and tests read the resolved palette directly.
    public let colors: OverlayColors

    public init(titles: [String], subtitles: [String], cycleMs: Int, brand: Brand) {
        self.titles = titles
        self.subtitles = subtitles
        self.cycleMs = cycleMs
        self.brand = brand
        self.colors = brand.theme.colors
    }

    /// The effective defaults applied when a field is omitted. Mirrors
    /// `DEFAULT_OVERLAY_OPTIONS`
    /// byte-for-byte — including the curly apostrophe (U+2019) in the subtitle.
    /// The default palette comes from `Brand.default` (connect).
    public static let `default` = OverlayOptions(
        titles: ["Almost there"],
        subtitles: ["We\u{2019}re securely accessing your account."],
        cycleMs: 5000,
        brand: .default
    )

    /// Caller-supplied, fully optional overlay customization — the inbound
    /// (wire) shape before resolution. Each field is merged individually
    /// against `OverlayOptions.default`. Mirrors the contract's
    /// `OverlayOptions` (all fields optional; `branding` an optional string).
    public struct Partial: Equatable, Sendable {
        public var titles: [String]?
        public var subtitles: [String]?
        public var cycleMs: Int?
        /// Wire brand string; normalized to a `Brand` during resolution
        /// (unknown/absent → default).
        public var branding: String?

        public init(
            titles: [String]? = nil,
            subtitles: [String]? = nil,
            cycleMs: Int? = nil,
            branding: String? = nil
        ) {
            self.titles = titles
            self.subtitles = subtitles
            self.cycleMs = cycleMs
            self.branding = branding
        }
    }

    /// Resolve a (possibly nil/partial) caller input against the defaults,
    /// mirroring `resolveOverlayOptions`:
    ///
    /// - `titles` / `subtitles`: a non-empty array wins; an empty array or
    ///   `nil` falls back to the default (matching the TS `?.length` check).
    /// - `cycleMs`: `nil` falls back to the default.
    /// - `branding`: normalized to a known `Brand` (unknown/absent → default),
    ///   which then determines `colors` — the host no longer supplies colors
    ///   directly.
    public init(resolving partial: Partial?) {
        let d = OverlayOptions.default
        let titles = partial?.titles
        let subtitles = partial?.subtitles
        let resolvedTitles = (titles?.isEmpty == false) ? titles! : d.titles
        let resolvedSubtitles = (subtitles?.isEmpty == false) ? subtitles! : d.subtitles
        self.init(
            titles: resolvedTitles,
            subtitles: resolvedSubtitles,
            cycleMs: partial?.cycleMs ?? d.cycleMs,
            brand: Brand.normalize(partial?.branding)
        )
    }
}

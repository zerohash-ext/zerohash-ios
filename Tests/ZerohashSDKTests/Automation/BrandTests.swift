import Testing
@testable import ZerohashSDK

/// Cover `Brand.normalize`, `Brand.theme`, and the wire-string resolution the
/// host relies on — the same host-facing strings ("connect", "zerohash",
/// "secured-connect") plus unknown/absent fall-through to the default.
@Suite("Brand")
struct BrandTests {

    // MARK: - normalize / rawValue

    @Test("`connect` wire string resolves to `.connect`")
    func normalizeConnect() {
        #expect(Brand.normalize("connect") == .connect)
        #expect(Brand.connect.rawValue == "connect")
    }

    @Test("`zerohash` wire string resolves to `.zerohash`")
    func normalizeZerohash() {
        #expect(Brand.normalize("zerohash") == .zerohash)
        #expect(Brand.zerohash.rawValue == "zerohash")
    }

    @Test("`secured-connect` wire string resolves to `.securedConnect`")
    func normalizeSecuredConnect() {
        #expect(Brand.normalize("secured-connect") == .securedConnect)
        #expect(Brand.securedConnect.rawValue == "secured-connect")
    }

    @Test("unknown / empty / absent wire strings fall back to the default")
    func normalizeFallback() {
        #expect(Brand.normalize(nil) == .default)
        #expect(Brand.normalize("") == .default)
        #expect(Brand.normalize("zerohsh") == .default)
        // The camelCased Swift-case name is not a valid wire value — hosts
        // send the hyphenated form.
        #expect(Brand.normalize("securedConnect") == .default)
        // `.default` today is `.zerohash`; assert explicitly so a future flip
        // shows up here.
        #expect(Brand.default == .zerohash)
    }

    // MARK: - themes

    @Test("`.connect` theme: Connect palette, `Powered by`, 14pt centered")
    func connectTheme() {
        let t = Brand.connect.theme
        #expect(t.colors == OverlayColors(left: "#FCFC99", middle: "#F2F07D", right: "#F0D53E"))
        #expect(t.markAssetName == "connect-mark")
        #expect(t.footerLabel == "Powered by")
        #expect(t.markHeightPt == 14)
        #expect(t.footerAlignment == .center)
    }

    @Test("`.zerohash` theme: zerohash palette, `Powered by`, 14pt centered")
    func zerohashTheme() {
        let t = Brand.zerohash.theme
        #expect(t.colors == OverlayColors(left: "#CCFFD0", middle: "#ABF9B1", right: "#8FEB96"))
        #expect(t.markAssetName == "zerohash-mark")
        #expect(t.footerLabel == "Powered by")
        #expect(t.markHeightPt == 14)
        #expect(t.footerAlignment == .center)
    }

    @Test("`.securedConnect` theme: Connect palette, `Secured by`, 28pt top-aligned")
    func securedConnectTheme() {
        let t = Brand.securedConnect.theme
        // Same palette as `.connect` — the two lockups differ in the mark +
        // prefix + height + alignment, not in the dot colors.
        #expect(t.colors == Brand.connect.theme.colors)
        #expect(t.markAssetName == "connect-by-zerohash-mark")
        #expect(t.footerLabel == "Secured by")
        #expect(t.markHeightPt == 28)
        #expect(t.footerAlignment == .top)
    }

    // MARK: - OverlayOptions resolution

    @Test("OverlayOptions resolves `secured-connect` end-to-end")
    func overlayOptionsResolvesSecuredConnect() {
        let opts = OverlayOptions(resolving: .init(branding: "secured-connect"))
        #expect(opts.brand == .securedConnect)
        #expect(opts.colors == Brand.securedConnect.theme.colors)
    }

    @Test("OverlayOptions resolves unknown branding to the default (backwards compatible)")
    func overlayOptionsFallsBackToDefault() {
        let opts = OverlayOptions(resolving: .init(branding: "not-a-real-brand"))
        #expect(opts.brand == .default)
    }
}

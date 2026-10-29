import XCTest

@testable import ZerohashSDK

final class WalletSchemeStoreTests: XCTestCase {
    private let walletBook = """
    {"wallets": {
      "okx": {"mobile": {"native": "okxwallet://", "universal": "https://www.okx.com/download"}},
      "binance": {"mobile": {"native": "bnc://app.binance.com/cedefi/wc"}},
      "spaced": {"mobile": {"native": " payperless://"}},
      "upper": {"mobile": {"native": "MyWallet://wc"}},
      "dotted": {"mobile": {"native": "app.dosivault://"}},
      "evil": {"mobile": {"native": "javascript:alert(1)"}},
      "phone": {"mobile": {"native": "tel:+1"}},
      "https": {"mobile": {"native": "https://example.com"}},
      "nocolon": {"mobile": {"native": "broken"}},
      "nomobile": {"desktop": {"universal": "https://example.com"}}
    }}
    """.data(using: .utf8)!

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "WalletSchemeStoreTests")
        defaults.removePersistentDomain(forName: "WalletSchemeStoreTests")
    }

    func testParserExtractsNormalizedNativeSchemes() {
        XCTAssertEqual(WalletBookParser.schemes(from: walletBook), ["okxwallet", "bnc", "payperless", "mywallet", "app.dosivault"])
    }

    func testParserIgnoresMalformedPayloads() {
        XCTAssertEqual(WalletBookParser.schemes(from: Data("not json".utf8)), [])
        XCTAssertEqual(WalletBookParser.schemes(from: Data("{\"groups\":{}}".utf8)), [])
    }

    func testStartsFromSnapshotAndCache() {
        defaults.set(["cachedwallet"], forKey: WalletSchemeStore.schemesKey)
        let store = WalletSchemeStore(defaults: defaults) { _, _ in XCTFail("no fetch expected") }

        XCTAssertTrue(store.schemes.contains("cachedwallet"))
        XCTAssertTrue(store.schemes.contains("okxwallet"))
    }

    func testRefreshFetchesWhenStaleAndPersists() {
        let fetched = expectation(description: "fetched")
        let book = walletBook
        let store = WalletSchemeStore(defaults: defaults) { url, completion in
            XCTAssertEqual(url, WalletSchemeStore.walletBookURL)
            completion(book)
            fetched.fulfill()
        }

        store.refreshIfStale()
        wait(for: [fetched], timeout: 1)

        XCTAssertTrue(store.schemes.contains("bnc"))
        XCTAssertEqual(Set(defaults.stringArray(forKey: WalletSchemeStore.schemesKey) ?? []), ["okxwallet", "bnc", "payperless", "mywallet", "app.dosivault"])
        XCTAssertNotNil(defaults.object(forKey: WalletSchemeStore.fetchedAtKey) as? Date)
    }

    func testRefreshSkipsWhenFresh() {
        defaults.set(Date(), forKey: WalletSchemeStore.fetchedAtKey)
        let store = WalletSchemeStore(defaults: defaults) { _, _ in XCTFail("no fetch expected") }

        store.refreshIfStale()
    }

    func testRefreshRunsAgainAfterMaxAge() {
        defaults.set(Date(timeIntervalSinceNow: -WalletSchemeStore.maxAge - 1), forKey: WalletSchemeStore.fetchedAtKey)
        let fetched = expectation(description: "fetched")
        let store = WalletSchemeStore(defaults: defaults) { _, completion in
            completion(nil)
            fetched.fulfill()
        }

        store.refreshIfStale()
        wait(for: [fetched], timeout: 1)
    }

    func testFailedOrEmptyFetchKeepsTheCurrentList() {
        defaults.set(["cachedwallet"], forKey: WalletSchemeStore.schemesKey)
        let store = WalletSchemeStore(defaults: defaults) { _, completion in completion(Data("{\"wallets\":{}}".utf8)) }

        store.refreshIfStale()

        XCTAssertTrue(store.schemes.contains("cachedwallet"))
        XCTAssertEqual(defaults.stringArray(forKey: WalletSchemeStore.schemesKey), ["cachedwallet"])
        XCTAssertNil(defaults.object(forKey: WalletSchemeStore.fetchedAtKey))
    }
}

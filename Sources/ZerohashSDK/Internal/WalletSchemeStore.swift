import Foundation

/// Custom URL schemes from Dynamic's wallet book, so a new wallet reaches the
/// allow-list without an SDK release. Starts from the build-time snapshot, then
/// merges the cached copy and a daily refresh fetched by the native side.
final class WalletSchemeStore: @unchecked Sendable {
    typealias Fetcher = @Sendable (URL, @escaping @Sendable (Data?) -> Void) -> Void

    static let walletBookURL = URL(string: "https://dynamic-static-assets.com/wallet-book/v1/stable/wallet-book.json")!
    static let schemesKey = "com.zerohash.sdk.walletSchemes"
    static let fetchedAtKey = "com.zerohash.sdk.walletSchemesFetchedAt"
    static let maxAge: TimeInterval = 24 * 60 * 60

    static let shared = WalletSchemeStore(defaults: .standard)

    private let defaults: UserDefaults
    private let fetcher: Fetcher
    private let lock = NSLock()
    private var remote: Set<String>
    private var refreshing = false

    init(defaults: UserDefaults, fetcher: @escaping Fetcher = WalletSchemeStore.urlSessionFetcher) {
        self.defaults = defaults
        self.fetcher = fetcher
        self.remote = Set(defaults.stringArray(forKey: Self.schemesKey) ?? [])
    }

    var schemes: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return WalletSchemeSnapshot.schemes.union(remote)
    }

    func refreshIfStale(now: Date = Date()) {
        lock.lock()
        let fetchedAt = defaults.object(forKey: Self.fetchedAtKey) as? Date
        let fresh = fetchedAt.map { now.timeIntervalSince($0) < Self.maxAge } ?? false
        if fresh || refreshing {
            lock.unlock()
            return
        }
        refreshing = true
        lock.unlock()

        fetcher(Self.walletBookURL) { [weak self] data in
            guard let self else { return }
            defer {
                self.lock.lock()
                self.refreshing = false
                self.lock.unlock()
            }
            guard let data else {
                Log.debug("[WalletSchemes] Wallet book fetch failed; keeping the current list")
                return
            }
            self.apply(data, fetchedAt: Date())
        }
    }

    /// Replaces the remote set when the payload parses to a non-empty list.
    func apply(_ data: Data, fetchedAt: Date) {
        let parsed = WalletBookParser.schemes(from: data)
        guard !parsed.isEmpty else {
            Log.error("[WalletSchemes] Wallet book had no usable schemes; keeping the current list")
            return
        }
        lock.lock()
        remote = parsed
        defaults.set(parsed.sorted(), forKey: Self.schemesKey)
        defaults.set(fetchedAt, forKey: Self.fetchedAtKey)
        lock.unlock()
    }

    private static let urlSessionFetcher: Fetcher = { url, completion in
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let ok = (response as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false
            completion(ok ? data : nil)
        }.resume()
    }
}

/// Extracts the scheme of every `mobile.native` deep link in a wallet book.
/// Same rules as scripts/generate-wallet-schemes.mjs.
enum WalletBookParser {
    private static let schemeShape = try! NSRegularExpression(pattern: "^[a-z][a-z0-9+.-]*$")

    static func schemes(from data: Data) -> Set<String> {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let wallets = root["wallets"] as? [String: Any]
        else { return [] }

        var result = Set<String>()
        for case let wallet as [String: Any] in wallets.values {
            guard
                let mobile = wallet["mobile"] as? [String: Any],
                let native = mobile["native"] as? String,
                let scheme = scheme(of: native)
            else { continue }
            result.insert(scheme)
        }
        return result
    }

    static func scheme(of deeplink: String) -> String? {
        let trimmed = deeplink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = trimmed.firstIndex(of: ":") else { return nil }
        let scheme = trimmed[..<colon].lowercased()
        let range = NSRange(scheme.startIndex..., in: scheme)
        guard schemeShape.firstMatch(in: scheme, range: range) != nil else { return nil }
        guard !ExternalSchemePolicy.reservedSchemes.contains(scheme) else { return nil }
        return scheme
    }
}

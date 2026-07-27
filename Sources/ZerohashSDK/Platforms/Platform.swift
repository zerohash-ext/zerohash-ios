import Foundation

// MARK: - Identity

public protocol PlatformIdentity {
    /// Stable wire string ("coinbase", "kraken", ...). Used as the lookup
    /// key in PlatformRegistry and as the value of ZeroAuthRequest.platform.
    var id: String { get }
}

// MARK: - Errors thrown by platform implementations

public enum PlatformError: Error, Equatable {
    case invalidJSReturn
    case underlying(String)
}

public extension PlatformError {
    /// Human/wire-facing message (no Swift enum decoration). Used by the
    /// bridge router so `.underlying("not logged in")` serializes as
    /// `not logged in`, not `underlying("not logged in")`.
    var message: String {
        switch self {
        case .invalidJSReturn: return "invalid JS return"
        case .underlying(let s): return s
        }
    }
}

// MARK: - Registry

public final class PlatformRegistry: @unchecked Sendable {
    private var platforms: [String: any PlatformIdentity] = [:]
    private let lock = NSLock()

    public init(default seeds: [any PlatformIdentity] = []) {
        for p in seeds { platforms[p.id] = p }
    }

    public func register(_ platform: any PlatformIdentity) {
        lock.lock(); defer { lock.unlock() }
        platforms[platform.id] = platform
    }

    public subscript(_ id: String) -> (any PlatformIdentity)? {
        lock.lock(); defer { lock.unlock() }
        return platforms[id]
    }
}

extension PlatformRegistry {
    /// Process-wide default registry. Pre-seeded with `Coinbase()` so
    /// host apps that don't register custom platforms get it for free.
    public static let shared: PlatformRegistry = PlatformRegistry(default: [Coinbase()])
}

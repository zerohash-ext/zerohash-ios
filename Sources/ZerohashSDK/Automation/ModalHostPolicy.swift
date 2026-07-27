import Foundation

public struct ModalHostPolicy: Equatable, Sendable {
    public enum Decision: Equatable, Sendable {
        case stayOpen
        case close
    }

    /// Hosts on which the modal must remain open: the login host plus the
    /// identity-provider hosts a social sign-in redirects through.
    public let stayOpenHosts: Set<String>
    /// Hosts that indicate a completed sign-in; reaching one closes `.success`.
    public let successHosts: Set<String>
    /// When true, a host in neither set is treated as `.close` (the legacy
    /// "navigate away from the login host == success" behavior). When false,
    /// unknown hosts keep the modal open. Default false — safer for OAuth hops.
    public let closeOnUnknownHost: Bool

    public init(stayOpenHosts: Set<String>,
                successHosts: Set<String>,
                closeOnUnknownHost: Bool = false) {
        self.stayOpenHosts = stayOpenHosts
        self.successHosts = successHosts
        self.closeOnUnknownHost = closeOnUnknownHost
    }

    /// Back-compat with the old single-host API: stay open on `host`, treat any
    /// other host as success. Preserves pre-existing email/password behavior.
    public init(legacyDismissAwayFromHost host: String) {
        self.stayOpenHosts = [host]
        self.successHosts = []
        self.closeOnUnknownHost = true
    }

    public func decision(forHost host: String?) -> Decision {
        guard let host else { return .stayOpen }
        if successHosts.contains(host) { return .close }
        if stayOpenHosts.contains(host) { return .stayOpen }
        return closeOnUnknownHost ? .close : .stayOpen
    }
}

import Foundation

enum AutomationWebViewError: Error, Equatable {
    case platformNotRegistered(String)
    case unsupported(operation: String, on: String)
    case cancelled
    case platformThrew(String)
    case invalidEnvelope

    /// Wire-format error string sent in ZeroAuthResponse.error.
    var wire: String {
        switch self {
        case .platformNotRegistered(let id):
            return "platform '\(id)' is not registered"
        case .unsupported(let op, let pid):
            return "operation '\(op)' not supported on platform '\(pid)'"
        case .cancelled:
            return "cancelled"
        case .platformThrew(let s):
            return s
        case .invalidEnvelope:
            return "invalid envelope"
        }
    }

    /// Prefixes of the `RunnerError` / `ContextError` descriptions that mean the
    /// page was fine and the attempt merely didn't land.
    private static let transientPrefixes = [
        "timeout", "loadFailed:", "navigationLost", "hostUnavailable",
    ]

    /// Whether the failure was transient. Says nothing about whether the caller may
    /// act on it — see `AutomationWebViewMessageRouter.isSafeToRetry`.
    var retryable: Bool {
        switch self {
        case .platformThrew(let s):
            if s.hasPrefix("BALANCES_INDETERMINATE") || s == "CHALLENGE_UNSOLVED" { return true }
            return Self.transientPrefixes.contains { s.hasPrefix($0) }
        case .platformNotRegistered, .unsupported, .cancelled, .invalidEnvelope:
            return false
        }
    }
}

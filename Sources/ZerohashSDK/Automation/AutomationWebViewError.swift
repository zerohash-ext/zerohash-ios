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

    /// Whether the front-end may retry. Only specific domain errors raised by
    /// the balance flow are retryable; everything else is terminal.
    var retryable: Bool {
        switch self {
        case .platformThrew(let s):
            return s.hasPrefix("BALANCES_INDETERMINATE") || s == "CHALLENGE_UNSOLVED"
        case .platformNotRegistered, .unsupported, .cancelled, .invalidEnvelope:
            return false
        }
    }
}

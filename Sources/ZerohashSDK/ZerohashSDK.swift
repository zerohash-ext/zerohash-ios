import UIKit

public class ZerohashSDK {

    // MARK: - Public API

    /// Configures a Fund session that can be presented later
    /// - Parameters:
    ///   - jwt: JWT token for authentication
    ///   - environment: Environment to use (defaults to production)
    ///   - theme: UI theme (defaults to system)
    ///   - callbacks: Optional callbacks for fund events
    /// - Returns: A ZerohashFundSession ready to be presented
    @MainActor
    public static func configureFund(
        jwt: String,
        environment: Environment = .production,
        theme: Theme = .system,
        callbacks: FundCallbacks = FundCallbacks()
    ) -> ZerohashFundSession {
        return ZerohashFundSession(
            jwt: jwt,
            environment: environment,
            theme: theme,
            callbacks: callbacks
        )
    }

    /// Configures a crypto-deposits session that can be presented later
    ///
    /// Destination mode is decided by the JWT, not by this call: a
    /// `deposit_details.to_address` claim routes the deposit to that
    /// platform-owned address (external mode), and its absence routes to a
    /// Zero Hash internal wallet (internal mode).
    /// - Parameters:
    ///   - jwt: JWT token for authentication
    ///   - environment: Environment to use (defaults to production)
    ///   - theme: UI theme (defaults to system)
    ///   - callbacks: Optional callbacks for deposit events
    /// - Returns: A ZerohashCryptoDepositsSession ready to be presented
    @MainActor
    public static func configureCryptoDeposits(
        jwt: String,
        environment: Environment = .production,
        theme: Theme = .system,
        callbacks: CryptoDepositsCallbacks = CryptoDepositsCallbacks()
    ) -> ZerohashCryptoDepositsSession {
        return ZerohashCryptoDepositsSession(
            jwt: jwt,
            environment: environment,
            theme: theme,
            callbacks: callbacks
        )
    }

    /// Configures a crypto-withdrawals session that can be presented later
    /// - Parameters:
    ///   - jwt: JWT token for authentication
    ///   - environment: Environment to use (defaults to production)
    ///   - theme: UI theme (defaults to system)
    ///   - callbacks: Optional callbacks for withdrawal events
    /// - Returns: A ZerohashCryptoWithdrawalsSession ready to be presented
    @MainActor
    public static func configureCryptoWithdrawals(
        jwt: String,
        environment: Environment = .production,
        theme: Theme = .system,
        callbacks: CryptoWithdrawalsCallbacks = CryptoWithdrawalsCallbacks()
    ) -> ZerohashCryptoWithdrawalsSession {
        return ZerohashCryptoWithdrawalsSession(
            jwt: jwt,
            environment: environment,
            theme: theme,
            callbacks: callbacks
        )
    }

    /// Configures a fund-withdrawals session that can be presented later
    /// - Parameters:
    ///   - jwt: JWT token for authentication
    ///   - environment: Environment to use (defaults to production)
    ///   - theme: UI theme (defaults to system)
    ///   - callbacks: Optional callbacks for withdrawal events
    /// - Returns: A ZerohashFundWithdrawalsSession ready to be presented
    @MainActor
    public static func configureFundWithdrawals(
        jwt: String,
        environment: Environment = .production,
        theme: Theme = .system,
        callbacks: FundWithdrawalsCallbacks = FundWithdrawalsCallbacks()
    ) -> ZerohashFundWithdrawalsSession {
        return ZerohashFundWithdrawalsSession(
            jwt: jwt,
            environment: environment,
            theme: theme,
            callbacks: callbacks
        )
    }
}

// MARK: - SDK Version

extension ZerohashSDK {
    /// Must track the released git tag — the automation bridge reports it to the
    /// backend as `ios-<version>`, so a stale value misattributes telemetry.
    /// Bump this in the same commit that tags a release.
    public static let version: String = "1.2.0"
}

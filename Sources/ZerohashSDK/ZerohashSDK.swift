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
}

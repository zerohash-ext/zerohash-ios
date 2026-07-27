import Foundation
import WebKit

public struct Coinbase: AuthFlow, DepositFlow, BalanceFlow, WithdrawFlow {
    public let id = "cbase"

    public init() {}

    @MainActor
    public func login(ctx: ExecutionContext) async throws -> AuthLoginResult {
        Log.coinbase.debug("login starting")
        let handle = try await ctx.presentModalWebView(
            url: URL(string: "https://login.coinbase.com/signin")!,
            hostPolicy: ModalHostPolicy(
                stayOpenHosts: [
                    "login.coinbase.com",
                    "appleid.apple.com",
                ],
                successHosts: ["www.coinbase.com"]
            ),
            title: "Sign in to Coinbase",
            autoClose: ModalAutoClose(probeJS: Self.loginProbeJS, intervalMs: 100, requiredHits: 2),
            documentStartJS: Self.loginModalJS
        )

        let reason = await handle.waitForClose()
        Log.coinbase.debug("login modal closed reason=\(String(describing: reason), privacy: .public)")

        switch reason {
        case .success:
            let status = try await status(ctx: ctx)
            return AuthLoginResult(loggedIn: status.loggedIn, outcome: "success")
        case .userClosed:
            return AuthLoginResult(loggedIn: false, outcome: "user-closed")
        case .timeout:
            return AuthLoginResult(loggedIn: false, outcome: "timeout")
        case .conditionMet(let code):
            // The probe names its own condition ("passkey-only" / "account-not-found"),
            // so the code is the outcome directly. Only Apple is exposed today
            // (Google is hidden in the WebView), so an account-not-found necessarily
            // came from Apple — hardcode the provider for now. Eventually if more providers
            // are supported we'll have to extend this logic.
            let provider = (code == "account-not-found") ? "apple" : nil
            if code == "account-not-found" {
                await Self.clearCoinbaseWebsiteData(ctx: ctx)
            }
            return AuthLoginResult(loggedIn: false, outcome: code, provider: provider)
        }
    }

    /// Remove ALL website data (cookies, localStorage, IndexedDB, caches, …)
    /// scoped to `coinbase.com` and its subdomains from the SDK's shared
    /// persistent data store. Only the web layer's native side can do this — the
    /// embedded page cannot reach `WKWebsiteDataStore`. Scoped to coinbase.com,
    /// so other domains (e.g. appleid.apple.com) are untouched.
    @MainActor
    private static func clearCoinbaseWebsiteData(ctx: ExecutionContext) async {
        let store = ctx.dataStore
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types)
        let coinbase = records.filter { record in
            let name = record.displayName
            return name == "coinbase.com" || name.hasSuffix(".coinbase.com")
        }
        guard !coinbase.isEmpty else {
            Log.coinbase.debug("no coinbase.com website-data records to clear after account-not-found")
            return
        }
        await store.removeData(ofTypes: types, for: coinbase)
        let names = coinbase.map(\.displayName).joined(separator: ",")
        Log.coinbase.debug("cleared website data for \(coinbase.count) coinbase.com record(s) [\(names, privacy: .public)] after account-not-found")
    }

    @MainActor
    public func status(ctx: ExecutionContext) async throws -> AuthStatusResult {
        Log.coinbase.debug("status starting URL=https://www.coinbase.com/home timeout=20000ms")
        let start = Date()

        let raw: Any?
        do {
            raw = try await ctx.runOffscreenWebView(
                url: URL(string: "https://www.coinbase.com/home")!,
                settle: { url in
                    let host = url.host ?? "?"
                    switch url.host {
                    case "login.coinbase.com":
                        Log.coinbase.debug("settle host=\(host, privacy: .private) => .answer({loggedIn:false})")
                        return .answer(["loggedIn": false])
                    case "www.coinbase.com":
                        Log.coinbase.debug("settle host=\(host, privacy: .private) => .evaluate")
                        return .evaluate
                    default:
                        Log.coinbase.debug("settle host=\(host, privacy: .private) => .waitMore")
                        return .waitMore
                    }
                },
                injectedScript: Self.statusJS,
                timeoutMs: 20_000
            )
        } catch {
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            Log.coinbase.error("status FAILED in \(ms)ms err=\(String(describing: error), privacy: .public)")
            throw error
        }

        guard let dict = raw as? [String: Any] else {
            Log.coinbase.error("invalid JS return: not [String: Any]")
            throw PlatformError.invalidJSReturn
        }
        guard let loggedIn = dict["loggedIn"] as? Bool else {
            Log.coinbase.error("invalid JS return: dict[loggedIn] not Bool")
            throw PlatformError.invalidJSReturn
        }
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        Log.coinbase.debug("status OK in \(ms)ms loggedIn=\(loggedIn)")
        return AuthStatusResult(loggedIn: loggedIn)
    }

    // MARK: - DepositFlow

    @MainActor
    public func getDepositAddress(
        ctx: ExecutionContext,
        payload: GetDepositAddressPayload,
        overlay: OverlayOptions,
        showOverlay: Bool
    ) async throws -> DepositAddressResult {
        Log.coinbase.debug("getDepositAddress starting asset=\(payload.asset, privacy: .public) network=\(payload.network ?? "-", privacy: .public)")

        var automation = Self.depositAddressJS
        while let last = automation.last, last == ";" || last == "\n" || last == " " {
            automation.removeLast()
        }

        // The request payload is handed to WebKit as the bound
        // argument `params` (see `jsonObject`), which marshals it into an in-scope
        // JS variable. It is NEVER interpolated into the script source, so payload
        // values can't break out of a literal and execute as code.
        let script = "(function(){ \(Self.domHelpersJS); return (\(automation)); })()"

        let raw = try await ctx.runVisibleWebView(
            url: URL(string: "https://www.coinbase.com/trade")!,
            settle: { url in
                switch url.host {
                case "www.coinbase.com": return .evaluate
                case "login.coinbase.com": return .answer(nil) // not logged in
                default: return .waitMore
                }
            },
            injectedScript: script,
            arguments: ["params": Self.jsonObject(payload)],
            overlay: overlay,
            showOverlay: showOverlay,
            waitForChallengeClearance: false,
            timeoutMs: 30_000
        )

        if raw == nil {
            throw PlatformError.underlying("not logged in")
        }
        guard let dict = raw as? [String: Any] else {
            throw PlatformError.invalidJSReturn
        }
        return try Self.mapResult(dict, requestedAsset: payload.asset, requestedNetwork: payload.network)
    }

    // MARK: - BalanceFlow

    @MainActor
    public func getBalance(
        ctx: ExecutionContext,
        overlay: OverlayOptions,
        showOverlay: Bool
    ) async throws -> [AssetBalance] {
        Log.coinbase.debug("getBalance starting")
        let ops = ["CryptoQuery", "CashQuery"]
        let url = URL(string: "https://www.coinbase.com/home")!

        let normalTimeoutMs = 10_000
        let challengeSolveTimeoutMs = 90_000

        func attempt(showOverlay: Bool, forChallengeRetry: Bool) async throws -> Any? {
            // The challenge is gated natively (waitForChallengeClearance) before
            // the script runs, so the script itself just replays both ops.
            var automation = Self.balanceJS
            while let last = automation.last, last == ";" || last == "\n" || last == " " {
                automation.removeLast()
            }
            // The ops list is passed as the bound argument
            // `params` (marshaled into a JS variable by WebKit), never
            // interpolated into the script source.
            let script = "(function(){ \(Self.balanceQueriesJS); return (\(automation)); })()"
            return try await ctx.runVisibleWebView(
                url: url,
                settle: { u in
                    switch u.host {
                    case "www.coinbase.com": return .evaluate
                    case "login.coinbase.com": return .answer(nil)
                    default: return .waitMore
                    }
                },
                injectedScript: script,
                arguments: ["params": ["ops": ops]],
                overlay: overlay,
                showOverlay: showOverlay,
                waitForChallengeClearance: forChallengeRetry,
                timeoutMs: forChallengeRetry ? challengeSolveTimeoutMs : normalTimeoutMs
            )
        }

        func map(_ raw: Any?) throws -> [AssetBalance] {
            if raw == nil { throw PlatformError.underlying("not logged in") }
            guard let dict = raw as? [String: Any] else { throw PlatformError.invalidJSReturn }
            return try Self.mapBalances(dict)
        }

        do {
            return try map(try await attempt(showOverlay: showOverlay, forChallengeRetry: false))
        } catch let e as JSException where e.message.contains("CHALLENGE_PRESENT") {
            Log.coinbase.debug("getBalance challenge; revealing live page for one retry")
            do {
                return try map(try await attempt(showOverlay: false, forChallengeRetry: true))
            } catch let e2 as JSException where e2.message.contains("CHALLENGE_PRESENT") {
                throw PlatformError.underlying("CHALLENGE_UNSOLVED")
            }
        }
    }

    /// Maps the JS result dictionary to a typed DepositAddressResult.
    static func mapResult(
        _ dict: [String: Any],
        requestedAsset: String,
        requestedNetwork: String?
    ) throws -> DepositAddressResult {
        guard let address = dict["address"] as? String, !address.isEmpty else {
            throw PlatformError.invalidJSReturn
        }
        let warnings = (dict["warnings"] as? [String]) ?? []
        var amountSubmitted: AmountSubmitted? = nil
        if let a = dict["amountSubmitted"] as? [String: Any],
           let value = a["value"] as? String,
           let currencyRaw = a["requestedCurrency"] as? String,
           let currency = AmountCurrency(rawValue: currencyRaw),
           let symbol = a["resolvedSymbol"] as? String {
            amountSubmitted = AmountSubmitted(value: value, requestedCurrency: currency, resolvedSymbol: symbol)
        }
        return DepositAddressResult(
            address: address,
            destinationTag: (dict["destinationTag"] as? String) ?? "",
            network: (dict["network"] as? String) ?? (requestedNetwork ?? ""),
            asset: (dict["asset"] as? String) ?? requestedAsset,
            warnings: warnings,
            depositUri: (dict["depositUri"] as? String) ?? "",
            amountSubmitted: amountSubmitted
        )
    }


    static func mapBalances(_ dict: [String: Any]) throws -> [AssetBalance] {
        guard let rows = dict["balances"] as? [[String: Any]] else {
            throw PlatformError.invalidJSReturn
        }
        func str(_ row: [String: Any], _ k: String) throws -> String {
            guard let v = row[k] as? String else { throw PlatformError.invalidJSReturn }
            return v
        }
        func optStr(_ row: [String: Any], _ k: String) -> String? {
            row[k] as? String
        }
        return try rows.map { row in
            AssetBalance(
                key: try str(row, "key"),
                label: try str(row, "label"),
                amount: try str(row, "amount"),
                notional: try str(row, "notional"),
                currency: optStr(row, "currency"),
                totalStakedPercent: optStr(row, "totalStakedPercent"),
                precision: row["precision"] as? Int,
                extractedAt: try str(row, "extractedAt")
            )
        }
    }

    // MARK: - WithdrawFlow
    //
    // Presents a long-lived automation session, drives the bundled `withdraw.js`
    // via `evaluateAsync`, and maps the returned object into a typed `WithdrawState`.

    /// Surface the withdraw/send flow runs on (coinbase.com/home) — also the
    /// surface the SDK's working `auth.status` loads. (The deposit flow uses /trade
    /// as its own tweak, but /trade was observed not to settle in the modal; /home
    /// is proven here.)
    static let withdrawURL = URL(string: "https://www.coinbase.com/home")!

    @MainActor
    public func startWithdraw(
        ctx: ExecutionContext,
        payload: StartWithdrawPayload,
        // overlay / showOverlay are reserved for Phase 6 (Option A). Until then the
        // modal's page is visible so we can watch the automation during dev.
        overlay: OverlayOptions,
        showOverlay: Bool
    ) async throws -> WithdrawStartResult {
        Log.coinbase.debug("startWithdraw asset=\(payload.asset, privacy: .public) network=\(payload.network ?? "-", privacy: .public)")
        // Long-lived automation session: stays alive across continue calls,
        // full-screen with no chrome (the user can't act on it). The send flow
        // navigates within coinbase.com, so there's no dismiss-on-navigate.
        let session = try await ctx.presentAutomationSession(
            url: Self.withdrawURL,
            overlay: overlay,
            showOverlay: showOverlay
        )
        // Wait for the Coinbase page to finish its initial load before driving it,
        // so the automation runs in the live page context (not a blank/about:blank
        // context about to be replaced by the navigation).
        await session.awaitInitialLoad()
        do {
            let raw = try await session.evaluateAsync(
                Self.startWithdrawJS, arguments: ["params": Self.jsonObject(payload)])
            let state = try Self.mapWithdrawState(raw)
            return WithdrawStartResult(session: session, state: state)
        } catch {
            // start failed before a session could be handed back — tear the modal
            // down so a failed start doesn't strand it on screen (the coordinator
            // never receives the handle to dismiss when start throws).
            await session.dismiss()
            throw error
        }
    }

    @MainActor
    public func continueWithdraw(
        session: AutomationSessionHandle,
        payload: ContinueWithdrawPayload
    ) async throws -> WithdrawState {
        Log.coinbase.debug("continueWithdraw kind=\(Self.continueKind(payload), privacy: .public)")
        let raw = try await session.evaluateAsync(
            Self.continueWithdrawJS, arguments: ["payload": Self.jsonObject(payload)])
        return try Self.mapWithdrawState(raw)
    }

    @MainActor
    public func cancelWithdraw(session: AutomationSessionHandle) async throws -> Bool {
        Log.coinbase.debug("cancelWithdraw")
        let raw = try await session.evaluateAsync(Self.cancelWithdrawJS)
        guard let dict = raw as? [String: Any], let cancelled = dict["cancelled"] as? Bool else {
            throw PlatformError.invalidJSReturn
        }
        return cancelled
    }

    /// Maps the JS-returned object into a typed `WithdrawState`. The JS returns the
    /// exact wire shape (`{ state, kind, details, result, reason, ... }`), so we
    /// round-trip the dictionary through `Data` and reuse `WithdrawState`'s
    /// `Codable`. Internal (not private) so it's unit-testable via @testable import.
    static func mapWithdrawState(_ raw: Any?) throws -> WithdrawState {
        guard let dict = raw as? [String: Any], JSONSerialization.isValidJSONObject(dict) else {
            throw PlatformError.invalidJSReturn
        }
        let data = try JSONSerialization.data(withJSONObject: dict)
        do {
            return try JSONDecoder().decode(WithdrawState.self, from: data)
        } catch {
            throw PlatformError.invalidJSReturn
        }
    }

    private static func continueKind(_ payload: ContinueWithdrawPayload) -> String {
        switch payload {
        case .otp:  return "otp"
        case .poll: return "poll"
        }
    }

    // MARK: Injected withdraw automation
    //
    // `withdraw.js` installs `window.__zhWithdraw = { start, continue, cancel }`
    // (idempotent). Each builder injects it and invokes the entry point, returning
    // its Promise — awaited by the modal's `evaluateAsync` (callAsyncJavaScript).

    /// Encode a payload to a plain `[String: Any]` (via JSON) for passing as a
    /// `callAsyncJavaScript` bound argument — WebKit marshals it into a JS value,
    /// so request data never gets interpolated into the script source.
    static func jsonObject<T: Encodable>(_ value: T) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(value),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    /// The payload is supplied at call time as the bound argument `params`
    /// (see `jsonObject`), not interpolated into this source.
    static let startWithdrawJS =
        "(function(){ \(domHelpersJS); \(withdrawJS) return window.__zhWithdraw.start(params); })()"

    /// The payload is supplied at call time as the bound argument `payload`.
    static let continueWithdrawJS =
        "(function(){ \(domHelpersJS); \(withdrawJS) return window.__zhWithdraw.continue(payload); })()"

    static let cancelWithdrawJS = "(function(){ \(domHelpersJS); \(withdrawJS) return window.__zhWithdraw.cancel(); })()"

    // MARK: - Bundled JS resource

    /// The SDK's SwiftPM resource bundle (`Bundle.module`), resolved from inside
    /// the ConnectSDK target where `.module` is valid. The JS resource loaders
    /// below resolve their files through this bundle; tests assert on bundled
    /// resources via the same bundle, instead of hardcoding the generated bundle
    /// name from the test target.
    static var resourceBundle: Bundle { Bundle.module }

    private static let withdrawJS: String = {
        guard let url = resourceBundle.url(forResource: "withdraw", withExtension: "js"),
              let body = try? String(contentsOf: url, encoding: .utf8)
        else {
            preconditionFailure(
                "Coinbase withdraw.js missing from SDK bundle. " +
                "Check Package.swift declares .process(\"Platforms/Coinbase/withdraw.js\").")
        }
        return body
    }()

    private static let statusJS: String = {
        guard let url = resourceBundle.url(
                forResource: "auth-status",
                withExtension: "js"
              ),
              let body = try? String(contentsOf: url, encoding: .utf8)
        else {
            preconditionFailure(
                "Coinbase auth-status.js missing from SDK bundle. " +
                "Check Package.swift declares resources: [.process(\"Platforms/Coinbase/auth-status.js\")]."
            )
        }
        return body
    }()

    private static let detectUnsupportedTwoFactorJS: String = {
        guard let url = resourceBundle.url(
                forResource: "auth-detect-unsupported-2fa",
                withExtension: "js"
              ),
              let body = try? String(contentsOf: url, encoding: .utf8)
        else {
            preconditionFailure(
                "Coinbase auth-detect-unsupported-2fa.js missing from SDK bundle. " +
                "Check Package.swift declares resources: [.process(\"Platforms/Coinbase/auth-detect-unsupported-2fa.js\")]."
            )
        }
        return body
    }()

    private static let signupJS: String = {
        guard let url = resourceBundle.url(
                forResource: "auth-signup",
                withExtension: "js"
              ),
              let body = try? String(contentsOf: url, encoding: .utf8)
        else {
            preconditionFailure(
                "Coinbase auth-signup.js missing from SDK bundle. " +
                "Check Package.swift declares resources: [.process(\"Platforms/Coinbase/auth-signup.js\")]."
            )
        }
        return body
    }()

    /// Auto-close probe for the login modal. Returns the matching condition
    /// *code* (consumed as the `auth.login` outcome) or null. Composed from the
    /// two bundled IIFEs with their trailing `;`/whitespace stripped so each can
    /// be embedded as an expression inside the wrapping `if (...)`.
    static let loginProbeJS: String = {
        func expr(_ js: String) -> String {
            var s = js
            while let last = s.last, last == ";" || last == "\n" || last == " " || last == "\r" {
                s.removeLast()
            }
            return s
        }
        return "(function(){"
            + " if ((\(expr(signupJS)))) return \"account-not-found\";"
            + " if ((\(expr(detectUnsupportedTwoFactorJS)))) return \"passkey-only\";"
            + " return null;"
            + " })()"
    }()

    private static let hideSocialJS: String = {
        guard let url = resourceBundle.url(
                forResource: "auth-hide-social",
                withExtension: "js"
              ),
              let body = try? String(contentsOf: url, encoding: .utf8)
        else {
            preconditionFailure(
                "Coinbase auth-hide-social.js missing from SDK bundle. " +
                "Check Package.swift declares resources: [.process(\"Platforms/Coinbase/auth-hide-social.js\")]."
            )
        }
        return body
    }()

    private static let chooseTwoFactorMethodJS: String = {
        guard let url = resourceBundle.url(
                forResource: "auth-choose-2fa-method",
                withExtension: "js"
              ),
              let body = try? String(contentsOf: url, encoding: .utf8)
        else {
            preconditionFailure(
                "Coinbase auth-choose-2fa-method.js missing from SDK bundle. " +
                "Check Package.swift declares resources: [.process(\"Platforms/Coinbase/auth-choose-2fa-method.js\")]."
            )
        }
        return body
    }()

    /// Combined documentStart script for the login modal:
    ///  • hide unsupported buttons everywhere — Google + all passkey buttons
    ///    (neither can complete in an embedded WebView),
    ///  • auto-advance to a supported 2FA method — Password when offered, else
    ///    an OTP factor (SMS/TOTP) reached via the "try another way" tray.
    private static let loginModalJS: String = {
        hideSocialJS + "\n" + chooseTwoFactorMethodJS
    }()

    private static let depositAddressJS: String = {
        guard let url = resourceBundle.url(
                forResource: "get-deposit-address",
                withExtension: "js"
              ),
              let body = try? String(contentsOf: url, encoding: .utf8)
        else {
            preconditionFailure(
                "Coinbase get-deposit-address.js missing from SDK bundle. " +
                "Check Package.swift declares .process(\"Platforms/Coinbase/get-deposit-address.js\")."
            )
        }
        return body
    }()

    private static let domHelpersJS: String = {
        guard let url = resourceBundle.url(
                forResource: "dom-helpers",
                withExtension: "js"
              ),
              let body = try? String(contentsOf: url, encoding: .utf8)
        else {
            preconditionFailure(
                "Shared dom-helpers.js missing from SDK bundle. " +
                "Check Package.swift declares .process(\"Automation/dom-helpers.js\")."
            )
        }
        return body
    }()

    private static let balanceJS: String = {
        guard let url = resourceBundle.url(forResource: "get-balance", withExtension: "js"),
              let body = try? String(contentsOf: url, encoding: .utf8)
        else {
            preconditionFailure(
                "Coinbase get-balance.js missing from SDK bundle. " +
                "Check Package.swift declares .process(\"Platforms/Coinbase/get-balance.js\").")
        }
        return body
    }()

    private static let balanceQueriesJS: String = {
        guard let url = resourceBundle.url(forResource: "coinbase-balance-queries", withExtension: "js"),
              let body = try? String(contentsOf: url, encoding: .utf8)
        else {
            preconditionFailure(
                "Coinbase coinbase-balance-queries.js missing from SDK bundle. " +
                "Check Package.swift declares .process(\"Platforms/Coinbase/coinbase-balance-queries.js\").")
        }
        return body
    }()
}

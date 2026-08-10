import Foundation

/// Owns the single in-flight withdraw session for one Connect session, so the
/// generic `AutomationWebViewMessageRouter` stays free of session state. Works
/// against any `WithdrawFlow` platform; the router delegates `withdraw.*` here.
///
/// Withdraw is a multi-step conversation (start → continue… → terminal): the
/// same live modal must be driven across several bridge requests, so its handle
/// has to outlive a single request. This coordinator is that long-lived holder,
/// scoped (via the router) to one presented Connect session.
@MainActor
final class WithdrawCoordinator {
    /// The one open withdraw session, if any. `id` is the sessionId echoed to the
    /// web app and matched on follow-ups; `handle` is the live modal we keep
    /// driving across `continue`/`cancel`.
    private var active: (id: String, handle: AutomationSessionHandle)?
    /// Whether the modal is currently stepped aside (host visible). Drives whether
    /// the next `continue` must `resume()` the modal or merely re-cover the overlay.
    private var steppedAside = false
    /// True while a `start` is in flight (between the guard and storing `active`).
    /// `active` is only set AFTER the `await startWithdraw` suspension, so without
    /// this an overlapping `start` (e.g. a fast double-tap) would pass the
    /// `active == nil` guard during that window and open a second modal. Claimed
    /// synchronously right after the guard so the check-and-claim is atomic on the
    /// actor; cleared via `defer`.
    private var starting = false

    /// `withdraw.start`: open the session and return its first state plus a freshly
    /// minted sessionId. The live modal is stored unless the first state already
    /// ends the session (rare — e.g. an immediate rejection), in which case it's
    /// dismissed and nothing is kept. Throws if a withdrawal is already open.
    func start(
        platform: any WithdrawFlow,
        ctx: ExecutionContext,
        payload: StartWithdrawPayload,
        overlay: OverlayOptions,
        showOverlay: Bool
    ) async throws -> (state: WithdrawState, sessionId: String) {
        guard active == nil, !starting else {
            throw PlatformError.underlying("withdraw already in progress")
        }
        starting = true
        defer { starting = false }
        let result = try await platform.startWithdraw(
            ctx: ctx, payload: payload, overlay: overlay, showOverlay: showOverlay)
        let sessionId = UUID().uuidString
        if result.state.endsSession {
            await result.session.dismiss()
        } else {
            active = (id: sessionId, handle: result.session)
            steppedAside = false
            await handOff(after: result.state, result.session)
        }
        return (result.state, sessionId)
    }

    /// `withdraw.continue`: drive the open session one more step (OTP or poll).
    /// Requires an active session whose id matches `sessionId` — otherwise a
    /// stale/unknown follow-up is rejected rather than poking a dead modal. If
    /// the resulting state ends the session, the modal is dismissed and the slot
    /// cleared.
    func `continue`(
        platform: any WithdrawFlow,
        sessionId: String?,
        payload: ContinueWithdrawPayload
    ) async throws -> (state: WithdrawState, sessionId: String) {
        guard let active, active.id == sessionId else {
            throw PlatformError.underlying("no active withdraw session")
        }
        do {
            // Only present the page when this step has to ACT on it. A poll is a
            // read, and the host polls a parked id-verification every few seconds —
            // presenting for each one made Coinbase's risk page flash open and shut
            // on that cadence. See `ContinueWithdrawPayload.needsPagePresented`.
            if payload.needsPagePresented {
                await resumeScraping(active.handle)
            } else {
                // Still give this leg a fresh wall-clock budget, which resumeScraping
                // would otherwise have done.
                active.handle.restartTimeout()
            }
            let state = try await platform.continueWithdraw(session: active.handle, payload: payload)
            if state.endsSession {
                await active.handle.dismiss()
                self.active = nil
            } else {
                await handOff(after: state, active.handle)
            }
            return (state, active.id)
        } catch {
            // A throw mid-drive is unexpected (recoverable outcomes like
            // otp_rejected come back as states, not throws). Tear the session down
            // so we don't strand the modal or block the next start, then rethrow.
            await active.handle.dismiss()
            self.active = nil
            throw error
        }
    }

    // MARK: - Visibility choreography (who's on screen at each pause)

    /// After a non-terminal step: hand the screen to whoever completes the pause.
    ///
    /// Every reachable pause currently steps the modal aside so the host shows its
    /// own UI — `surfacesCoinbase` is `false` for all of them. The reveal branch is
    /// retained because it is the switch point for letting the user complete
    /// Coinbase's identity check inside the WebView, which needs camera and
    /// microphone support the SDK does not yet grant. See
    /// `WithdrawState.surfacesCoinbase`.
    private func handOff(after state: WithdrawState, _ handle: AutomationSessionHandle) async {
        // The session is now parked waiting on the user — entering an OTP, or
        // finishing an identity check in the Coinbase app. That wait is unbounded, so
        // suspend the modal's wall-clock timeout; resumeScraping restarts it before
        // the next leg.
        handle.pauseTimeout()
        if state.surfacesCoinbase {
            Log.automation.debug("withdraw handOff → reveal page (user acts in modal)")
            handle.revealOverlay(true)
            steppedAside = false
        } else {
            Log.automation.debug("withdraw handOff → stepAside (host web app shows)")
            await handle.stepAside()
            steppedAside = true
        }
    }

    /// Before driving on `continue`: get the page back, covered by the overlay.
    /// If it was stepped aside, re-present it (the overlay was up, so it stays up);
    /// otherwise — only reachable if `surfacesCoinbase` ever returns true again —
    /// re-cover it.
    private func resumeScraping(_ handle: AutomationSessionHandle) async {
        // Give this automation leg a fresh wall-clock budget (it was paused while
        // the user acted).
        handle.restartTimeout()
        if steppedAside {
            Log.automation.debug("withdraw resumeScraping → resume (re-present page)")
            await handle.resume()
        } else {
            Log.automation.debug("withdraw resumeScraping → re-cover overlay")
            handle.revealOverlay(false)
        }
    }

    /// `withdraw.cancel`: cancel the open session. Always dismisses the modal and
    /// clears the slot (cancel ends the session regardless); returns whatever the
    /// platform reports for aborting the transfer itself. Requires an active session
    /// whose id matches `sessionId`.
    ///
    /// On Coinbase that return value is always `false` — the SDK deliberately does
    /// not abort the transfer, because the one screen offering that button is the
    /// risk screen, which is exactly when the user has been sent to the Coinbase app
    /// to finish an identity check. See `withdraw.js`'s `cancel` entry point.
    func cancel(platform: any WithdrawFlow, sessionId: String?) async throws -> Bool {
        guard let active, active.id == sessionId else {
            throw PlatformError.underlying("no active withdraw session")
        }
        // Cancel ends the session regardless of outcome — clear the slot up front
        // and guarantee the modal is dismissed on both success and failure.
        self.active = nil
        do {
            // Deliberately NOT resumeScraping first. That used to re-present the page
            // so a "Cancel transfer" button would be queryable; nothing clicks it now,
            // and re-presenting Coinbase's risk screen one line before dismissing it
            // just flashes it at the user.
            let cancelled = try await platform.cancelWithdraw(session: active.handle)
            await active.handle.dismiss()
            return cancelled
        } catch {
            await active.handle.dismiss() // tear down even if cancel failed
            throw error
        }
    }
}

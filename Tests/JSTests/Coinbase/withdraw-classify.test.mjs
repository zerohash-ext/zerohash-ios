import assert from "node:assert";
import { test } from "node:test";
import { classify, loadWithdraw, rehome, SEL } from "./withdraw-shim.mjs";

test("the risk screen with its start button settles on id-verification", () => {
  assert.deepStrictEqual(
    classify({ riskStep: true, startChallenge: true }),
    { kind: "id-verification", settled: true }
  );
});

// The container mounts ~2s before its buttons render. Deciding on the container
// alone is the over-eager detection this work replaces, so pin it down now rather
// than leaving the AND unconstrained.
test("the risk container alone is not decisive", () => {
  assert.deepStrictEqual(classify({ riskStep: true }), { kind: null, settled: false });
});

test("a start button outside the risk container is not decisive", () => {
  assert.deepStrictEqual(classify({ startChallenge: true }), { kind: null, settled: false });
});

test("a cancellation outranks the risk screen", () => {
  assert.deepStrictEqual(
    classify({ userCancellation: true, riskStep: true, startChallenge: true }),
    { kind: "canceled", settled: true }
  );
});

test("the risk screen mid-capture settles on id-verification", () => {
  assert.deepStrictEqual(
    classify({ riskStep: true, stepIdVerification: true }),
    { kind: "id-verification", settled: true }
  );
});

test("a failed capture still settles on id-verification", () => {
  assert.deepStrictEqual(
    classify({ riskStep: true, idvFailed: true }),
    { kind: "id-verification", settled: true }
  );
});

test("an OTP field settles on otp", () => {
  assert.deepStrictEqual(classify({ otpInput: true }), { kind: "otp", settled: true });
});

test("an SMS method button settles on otp", () => {
  assert.deepStrictEqual(classify({ twoFactorSms: true }), { kind: "otp", settled: true });
});

test("a TOTP method button settles on otp", () => {
  assert.deepStrictEqual(classify({ twoFactorTotp: true }), { kind: "otp", settled: true });
});

test("a passkey prompt settles on passkey", () => {
  assert.deepStrictEqual(classify({ passkeyPrompt: true }), { kind: "passkey", settled: true });
});

test("the success screen settles on none", () => {
  assert.deepStrictEqual(classify({ success: true }), { kind: "none", settled: true });
});

// Both containers can be mounted during a fade. A wrong id-verification is
// recoverable on the next poll; a wrong submitted loses the send.
test("the risk screen outranks the success screen", () => {
  assert.deepStrictEqual(
    classify({ riskStep: true, startChallenge: true, success: true }),
    { kind: "id-verification", settled: true }
  );
});

test("the risk container with only the scam intro is not decisive", () => {
  assert.deepStrictEqual(
    classify({ riskStep: true, scamIntro: true }),
    { kind: null, settled: false }
  );
});

// Coinbase offers a passkey and a typed-code method on the same screen. That is
// demonstrated, not assumed: chooseOtpMethod exists to "prefer a typed-code method
// (SMS first, then TOTP) the host can relay over a passkey", and commit eb0bde7
// was a shipped fix for "passkey only detection on passkey + sms US accounts".
//
// The typed code MUST win, because passkey maps to passkey_unsupported, which is
// TERMINAL (toState). Ranking it above otp strands a user whose SMS fallback was
// sitting right there on the screen.
test("a method chooser outranks a passkey offered alongside it", () => {
  assert.deepStrictEqual(
    classify({ twoFactorSms: true, passkeyPrompt: true }),
    { kind: "otp", settled: true }
  );
});

// This case is a DELIBERATE BEHAVIOUR CHANGE, not a pin. The two legacy paths
// disagreed when only the code field was up beside a passkey prompt:
//   activeGate          — isOtpScreen() before PASSKEY_PROMPT  => otp
//   detectAndHandle2fa  — chooseOtpMethod() matches only the SMS/TOTP *buttons*,
//                         so a bare code field fell through to PASSKEY_PROMPT => passkey
// The classifier sides with activeGate. A visible, relayable code field beside a
// terminal passkey rejection is the strictly better outcome.
test("a bare code field outranks a passkey prompt (overrides detectAndHandle2fa)", () => {
  assert.deepStrictEqual(
    classify({ otpInput: true, passkeyPrompt: true }),
    { kind: "otp", settled: true }
  );
});

// past2fa returns false whenever activeGate() is truthy, BEFORE it ever looks at
// SEND_SUCCESS — legacy code encoding "a live gate outranks a success screen". Same
// asymmetry as risk-over-success: reporting submitted while a gate is up is the bug
// this work exists to remove, whereas a stale gate self-corrects on the next poll.
test("a live gate outranks a success screen", () => {
  assert.deepStrictEqual(
    classify({ otpInput: true, success: true }),
    { kind: "otp", settled: true }
  );
  assert.deepStrictEqual(
    classify({ passkeyPrompt: true, success: true }),
    { kind: "passkey", settled: true }
  );
});

// The empty identity-access wrapper mounts ~1.4s before Coinbase's commit
// returns. Deciding on it is the original bug.
test("the empty identity-access wrapper alone is not decisive", () => {
  assert.deepStrictEqual(
    classify({ identityAccessWrapper: true }),
    { kind: null, settled: false }
  );
});

test("the verify-access spinner alone is not decisive", () => {
  assert.deepStrictEqual(
    classify({ verifyAccessLoader: true }),
    { kind: null, settled: false }
  );
});

test("a missing overlay is not decisive while the budget remains", () => {
  assert.deepStrictEqual(classify({ overlay: false }), { kind: null, settled: false });
});

// Last resort: the modal is gone, the clock ran out, and no success screen ever
// appeared. Held sends cannot reach this — see the sawIdVerification tests.
test("a missing overlay after the budget expires settles on none", () => {
  assert.deepStrictEqual(
    classify({ overlay: false, budgetExpired: true }),
    { kind: "none", settled: true }
  );
});

test("an overlay still up after the budget expires settles on processing", () => {
  assert.deepStrictEqual(
    classify({ overlay: true, budgetExpired: true }),
    { kind: "processing", settled: true }
  );
});

// settlePostConfirm needs an ANSWER when the clock runs out, not merely a
// terminated loop — so assert kind is usable, not just settled. Without the kind
// check, a regression returning { kind: null, settled: true } would pass.
test("budget expiry always produces a settled outcome with a usable kind", () => {
  for (const overlay of [true, false]) {
    for (const extra of [{}, { verifyAccessLoader: true }, { statusLoading: true },
                         { stepLoaded: true }, { scamIntro: true },
                         { identityAccessWrapper: true }]) {
      const where = JSON.stringify({ overlay, extra });
      const r = classify({ overlay, budgetExpired: true, ...extra });
      assert.strictEqual(r.settled, true, where);
      assert.notStrictEqual(r.kind, null, where);
    }
  }
});

// Capture d9d96c27: the risk screen sat unchanged for ~130 polls while the
// transfer completed underneath it. If the screen unmounts, the overlay fallback
// would report a completed send for a transfer still on hold.
test("a session that saw a hold never falls back to none", () => {
  assert.deepStrictEqual(
    classify({ overlay: false, budgetExpired: true, sawIdVerification: true }),
    { kind: "id-verification", settled: true }
  );
});

test("a session that saw a hold reports the hold, not processing", () => {
  assert.deepStrictEqual(
    classify({ overlay: true, budgetExpired: true, sawIdVerification: true }),
    { kind: "id-verification", settled: true }
  );
});

// A repeated poll that lands mid-fade: the risk container is up but its buttons
// have not rendered, so nothing is decisive. Only the sticky guard can answer, and
// it must still say "hold" rather than falling through to processing.
//
// Do NOT add startChallenge here. With it, the decisive branch fires first and the
// sticky guard is never reached — the test then passes even if the guard is deleted
// outright, which is exactly how it was originally written.
test("a repeated poll mid-fade still reports the hold", () => {
  assert.deepStrictEqual(
    classify({ riskStep: true, scamIntro: true, sawIdVerification: true, budgetExpired: true }),
    { kind: "id-verification", settled: true }
  );
});

test("a hold does not mask a genuine cancellation", () => {
  assert.deepStrictEqual(
    classify({ userCancellation: true, sawIdVerification: true, budgetExpired: true }),
    { kind: "canceled", settled: true }
  );
});

test("a hold does not mask a genuine OTP prompt", () => {
  assert.deepStrictEqual(
    classify({ otpInput: true, sawIdVerification: true }),
    { kind: "otp", settled: true }
  );
});

test("the sticky flag does nothing while the budget remains", () => {
  assert.deepStrictEqual(
    classify({ sawIdVerification: true }),
    { kind: null, settled: false }
  );
});

// settlePostConfirm must record the hold so later polls inherit it (Task 4).
test("settling on a hold sets the sticky flag on module state", async () => {
  const { internals, window } = loadWithdraw({
    present: [SEL.STEP_RISK_VERIFICATION, SEL.RISK_START_CHALLENGE, SEL.MODAL_OVERLAY]
  });
  const outcome = rehome(await internals.settlePostConfirm(1000));
  assert.deepStrictEqual(outcome, { kind: "id-verification", settled: true });
  assert.strictEqual(window.__zhWithdrawState.sawIdVerification, true);
});

test("settling on success does not set the sticky flag", async () => {
  const { internals, window } = loadWithdraw({ present: [SEL.SEND_SUCCESS] });
  const outcome = rehome(await internals.settlePostConfirm(1000));
  assert.deepStrictEqual(outcome, { kind: "none", settled: true });
  assert.ok(!window.__zhWithdrawState.sawIdVerification);
});

// Nothing decisive on screen: the loop must run out the budget and then settle,
// never hand an unsettled outcome back to its caller.
test("an undecidable page settles once the budget expires", async () => {
  const { internals } = loadWithdraw({ present: [SEL.MODAL_OVERLAY] });
  const outcome = rehome(await internals.settlePostConfirm(0));
  assert.deepStrictEqual(outcome, { kind: "processing", settled: true });
});

// THE test for this task. Coinbase mounts the 2FA loader ~1.4s before its commit
// resolves and the risk screen appears ~0.7s after that. The old code slept a
// fixed 1500ms and decided in the gap. The loop must poll through the gap.
//
// The injected `sleep` is the hook: it counts polls and mutates the document, so
// the page changes under the loop without any wall-clock dependency.
test("the loop polls through a transitional screen and settles when the risk screen mounts", async () => {
  let polls = 0;
  let doc;
  const { internals, document } = loadWithdraw(
    { present: [SEL.VERIFY_ACCESS_LOADER, SEL.IDENTITY_ACCESS_WRAPPER, SEL.MODAL_OVERLAY] },
    {
      sleep: () => {
        polls += 1;
        if (polls === 3) {
          doc.present.add(SEL.STEP_RISK_VERIFICATION);
          doc.present.add(SEL.RISK_START_CHALLENGE);
        }
        return Promise.resolve();
      }
    }
  );
  doc = document;

  const outcome = rehome(await internals.settlePostConfirm(60000));

  assert.deepStrictEqual(outcome, { kind: "id-verification", settled: true });
  // Three sleeps: it did NOT decide on the first, transitional, look.
  assert.strictEqual(polls, 3);
});

// The mirror case: the transitional screen never resolves, so the budget decides.
test("a page stuck on the transitional loader settles as processing, not success", async () => {
  let polls = 0;
  const { internals } = loadWithdraw(
    { present: [SEL.VERIFY_ACCESS_LOADER, SEL.IDENTITY_ACCESS_WRAPPER, SEL.MODAL_OVERLAY] },
    { sleep: () => { polls += 1; return Promise.resolve(); } }
  );
  const outcome = rehome(await internals.settlePostConfirm(0));
  assert.deepStrictEqual(outcome, { kind: "processing", settled: true });
  assert.strictEqual(polls, 0); // budget already spent, no sleep needed
});

// Tier-1 success sits ABOVE the sticky latch, so without a guard a latched session
// that sees any success marker reports submitted — which is what the spec's
// criterion 2 forbids absolutely, while its D3/D7 precedence permits. Resolved in
// favour of criterion 2, but narrowly.
//
// Believe an unambiguous statement. send-success-content and its headline say, in
// words, that the send went through; refusing that would strand a completed
// transfer.
test("unambiguous success overrules a hold", () => {
  assert.deepStrictEqual(
    classify({ success: true, successConfirmed: true, sawIdVerification: true }),
    { kind: "none", settled: true }
  );
});

// Do not believe a weak one. status-step-complete-button is a generic status-step
// "Done" control and status-animation-success appears in none of the 318 captured
// snapshots, so neither may overrule a known hold. Falls through to the latch.
test("a weak success marker does not overrule a hold", () => {
  assert.deepStrictEqual(
    classify({ success: true, sawIdVerification: true, budgetExpired: true }),
    { kind: "id-verification", settled: true }
  );
  // Still not decisive before the clock runs out.
  assert.deepStrictEqual(
    classify({ success: true, sawIdVerification: true }),
    { kind: null, settled: false }
  );
});

// The guard must not touch the ordinary path: an unlatched session treats every
// marker as success, exactly as before.
test("without a prior hold, any success marker still settles on none", () => {
  assert.deepStrictEqual(classify({ success: true }), { kind: "none", settled: true });
  assert.deepStrictEqual(
    classify({ success: true, successConfirmed: true }),
    { kind: "none", settled: true }
  );
});

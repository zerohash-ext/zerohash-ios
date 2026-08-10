import assert from "node:assert";
import { test } from "node:test";
import { loadWithdraw, baseProbe, SEL } from "./withdraw-shim.mjs";

// These selector strings are HARDCODED ON PURPOSE, not read from SEL. They are
// transcribed from the exploration captures under
// scrapping/bots/logs/coinbase_webkit/001/{98957de7,d9d96c27}.
//
// How this catches drift: the fake document's `present` set holds THESE literals,
// while probePostConfirm queries SEL.*. If a constant in withdraw.js changes, the
// two stop matching, the probe returns false, and the test fails — forcing someone
// to check the new value against a real capture.
//
// What it does NOT catch: Coinbase changing its own markup. Nothing here can. That
// needs a fixture of real captured HTML, which is out of scope.
const RISK_STEP     = '[data-testid="step-riskSelfServeStep-active"]';
const START_CHAL    = '[data-testid="start-challenge-button"]';
const STEP_IDV      = '[data-testid="step-idVerification-active"]';
const IDV_FAILED    = '[data-testid="id-capture-reskinned-failure-view"]';
const SCAM_INTRO    = '[data-testid="scam-warning-intro"]';
const VERIFY_LOADER = '[data-testid="verify_access_loader"]';
const ID_ACCESS     = '[data-testid="identity-access-view-wrapper"]';
const SUCCESS_ANIM  = '[data-testid="status-animation-success"]';
const OVERLAY       = '[data-testid="modal-overlay"]';

function probe(documentOptions, state) {
  const { internals, window } = loadWithdraw(documentOptions);
  if (state) window.__zhWithdrawState = state;
  return internals.probePostConfirm();
}

test("the risk overview screen is read correctly (capture 98957de7, snapshot 6604)", () => {
  const p = probe({ present: [RISK_STEP, START_CHAL, OVERLAY],
                    activeSteps: ["step-riskSelfServeStep-active", "step-overview-active"] });
  assert.equal(p.riskStep, true);
  assert.equal(p.startChallenge, true);
  assert.equal(p.overlay, true);
  assert.equal(p.stepIdVerification, false);
  assert.equal(p.success, false);
  assert.equal(p.budgetExpired, false);
  assert.equal(p.sawIdVerification, false);
});

test("the transient scam-warning intro is read as not-yet-settled markup", () => {
  const p = probe({ present: [RISK_STEP, SCAM_INTRO, OVERLAY] });
  assert.equal(p.riskStep, true);
  assert.equal(p.scamIntro, true);
  assert.equal(p.startChallenge, false);
});

test("the mid-capture and failed-capture screens are read correctly", () => {
  const mid = probe({ present: [RISK_STEP, STEP_IDV, OVERLAY] });
  assert.equal(mid.stepIdVerification, true);
  const failed = probe({ present: [RISK_STEP, STEP_IDV, IDV_FAILED, OVERLAY] });
  assert.equal(failed.idvFailed, true);
});

// The wrapper mounts EMPTY before the commit resolves. Empty means "still
// transitioning"; populated means a real 2FA view rendered inside it.
test("an empty identity-access wrapper is flagged; a populated one is not", () => {
  const empty = probe({ present: [ID_ACCESS, VERIFY_LOADER, OVERLAY],
                        childCounts: { [ID_ACCESS]: 0 } });
  assert.equal(empty.identityAccessWrapper, true);
  assert.equal(empty.verifyAccessLoader, true);

  const populated = probe({ present: [ID_ACCESS, OVERLAY],
                            childCounts: { [ID_ACCESS]: 3 } });
  assert.equal(populated.identityAccessWrapper, false);
});

test("the success animation counts as success", () => {
  const p = probe({ present: [SUCCESS_ANIM] });
  assert.equal(p.success, true);
  assert.equal(p.overlay, false);
});

test("stepLoaded is true only when every active step is a loaded wrapper", () => {
  assert.equal(probe({ activeSteps: ["step-loaded-active"] }).stepLoaded, true);
  assert.equal(
    probe({ activeSteps: ["step-loaded-active", "step-overview-active"] }).stepLoaded,
    false
  );
  assert.equal(probe({ activeSteps: [] }).stepLoaded, false);
});

test("the sticky flag is read from persisted module state", () => {
  const p = probe({ present: [OVERLAY] }, { details: null, sawIdVerification: true });
  assert.equal(p.sawIdVerification, true);
});

// baseProbe() hardcodes the probe shape so classify tests can spread over it. If
// probePostConfirm gains, loses or renames a field, every classify test silently
// starts asserting against a key nobody reads — and PASSES, because the classifier
// sees undefined, which is falsy. This is the only thing standing between that
// drift and a green suite.
test("baseProbe mirrors probePostConfirm's field set exactly", () => {
  assert.deepStrictEqual(
    Object.keys(baseProbe()).sort(),
    Object.keys(probe({})).sort()
  );
});

// STEP_ACTIVE is the one selector the shim cannot pin the way the others are
// pinned: makeDocument special-cases it using the HARVESTED value, so the fake DOM
// would follow a change in lockstep and every test would still pass. Assert the
// literal directly to close that gap.
test("STEP_ACTIVE still matches the value transcribed from the captures", () => {
  assert.strictEqual(SEL.STEP_ACTIVE, '[data-testid^="step-"][data-testid$="-active"]');
});

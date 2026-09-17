// waitForStepPrimary. The destination-tag confirm has no testid, so it
// was found by the English "Continue". Coinbase disables it until validation
// settles, so the wait polls — but NOT via pollUntil, which eats the error.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { loadWithdraw } from "./withdraw-shim.mjs";

const SOURCE = readFileSync(
  fileURLToPath(
    new URL("../../../Sources/ZerohashSDK/Platforms/Coinbase/withdraw.js", import.meta.url)
  ),
  "utf8"
);

const PRIMARY = 'button[data-variant="primary"]';

/** Line comments stripped, so a guard never matches its own rationale. Mirrors
 *  the `code()` helper the Android asset tests use for the same reason. */
const code = (src) =>
  src.split("\n").map((l) => l.replace(/\/\/.*$/, "")).join("\n");

/** The body of `name`, comments removed, up to the next top-level function. */
function fnBody(name, until) {
  const src = code(SOURCE);
  const from = src.indexOf(`async function ${name}`);
  const to = src.indexOf(`async function ${until}`);
  assert.ok(from !== -1, `${name} must exist`);
  assert.ok(to > from, `${until} must follow ${name}`);
  return src.slice(from, to);
}

/** A step holding `count` primary buttons, optionally reporting as disabled. */
function makeStep(count, disabled = false) {
  const buttons = Array.from({ length: count }, (_, i) => ({
    id: `primary-${i}`,
    disabled,
    getAttribute: () => null
  }));
  return {
    buttons,
    querySelectorAll: (sel) => (sel === PRIMARY ? buttons : [])
  };
}

/** withdraw.js's own D.stepPrimaryButton comes from dom-helpers in production;
 *  the shim's __zhDom stub does not carry it, so supply the real contract. */
function withDom(step, hooks = {}) {
  const { internals, window } = loadWithdraw({}, hooks);
  window.__zhDom.stepPrimaryButton = (s) => {
    if (!s) return null;
    const primaries = s.querySelectorAll(PRIMARY);
    if (primaries.length > 1) {
      throw new Error("step-primary-ambiguous: expected 1 primary button in the step, found " + primaries.length);
    }
    return primaries.length === 1 ? primaries[0] : null;
  };
  return internals.waitForStepPrimary;
}

test("returns the step's enabled primary button", async () => {
  const step = makeStep(1);
  const waitForStepPrimary = withDom(step);

  const btn = await waitForStepPrimary(step, 1000, "withdraw/nope");

  assert.equal(btn.id, "primary-0");
});

test("keeps waiting while the confirm is still disabled, then takes it", async () => {
  // Coinbase disables Continue until its async tag-format validation settles.
  // Returning the disabled button would click a no-op and stall the flow.
  const step = makeStep(1, true);
  let polls = 0;
  const waitForStepPrimary = withDom(step, {
    sleep: () => {
      polls += 1;
      if (polls === 2) step.buttons[0].disabled = false;
      return Promise.resolve();
    }
  });

  const btn = await waitForStepPrimary(step, 1000, "withdraw/nope");

  assert.equal(btn.id, "primary-0");
  assert.equal(polls, 2, "must have waited rather than grabbed the disabled button");
});

test("throws the caller's error code when the confirm never enables", async () => {
  const step = makeStep(1, true);
  const waitForStepPrimary = withDom(step);

  await assert.rejects(
    () => waitForStepPrimary(step, 1, "withdraw/destination-tag-continue-not-found"),
    /destination-tag-continue-not-found/
  );
});

test("an ambiguous step surfaces as ambiguity, not as a timeout", async () => {
  // The property that would silently disappear if this were built on pollUntil.
  const step = makeStep(2);
  const waitForStepPrimary = withDom(step);

  await assert.rejects(
    () => waitForStepPrimary(step, 1000, "withdraw/destination-tag-continue-not-found"),
    (e) => {
      assert.match(e.message, /step-primary-ambiguous/);
      assert.doesNotMatch(e.message, /destination-tag-continue-not-found/);
      return true;
    }
  );
});

test("a step that never renders times out with the caller's code", async () => {
  const waitForStepPrimary = withDom(null);

  await assert.rejects(
    () => waitForStepPrimary(null, 1, "withdraw/destination-tag-continue-not-found"),
    /destination-tag-continue-not-found/
  );
});

test("the destination-tag step no longer advances on an English label", () => {
  const fn = fnBody("fillDestinationTag", "skipDestinationTag");

  assert.doesNotMatch(fn, /"Continue"/);
  assert.match(fn, /waitForStepPrimary/);
});

test("waitForStepPrimary is not built on pollUntil's exception-swallowing path", () => {
  // Documents WHY the loop is hand-rolled, so a future tidy-up that folds it back
  // into pollUntil fails here rather than quietly losing the ambiguity signal.
  const fn = fnBody("waitForStepPrimary", "fillDestinationTag");

  assert.doesNotMatch(fn, /pollUntil/);
});

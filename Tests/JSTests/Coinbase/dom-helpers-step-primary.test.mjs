// __zhDom.stepPrimaryButton. Some step confirms carry no testid and no
// icon, leaving data-variant as the only handle. Not unique document-wide, so it
// is only safe scoped to the active step and only honest when ambiguity throws.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const SRC = fileURLToPath(
  new URL("../../../Sources/ZerohashSDK/Automation/dom-helpers.js", import.meta.url)
);
const SOURCE = readFileSync(SRC, "utf8");

const PRIMARY = 'button[data-variant="primary"]';

function loadDom() {
  const window = {};
  // dom-helpers.js touches `document` only inside its functions, so an inert one
  // is enough to load it. Each test supplies its own scoped step instead.
  const document = { querySelector: () => null, querySelectorAll: () => [] };
  vm.runInNewContext(SOURCE, { window, document, setTimeout, clearTimeout, Promise, Object, Event });
  return window.__zhDom;
}

/** A step whose `querySelectorAll` answers only for the primary-button selector. */
function makeStep(primaryCount) {
  const buttons = Array.from({ length: primaryCount }, (_, i) => ({ id: `primary-${i}` }));
  return {
    querySelectorAll(sel) {
      return sel === PRIMARY ? buttons : [];
    }
  };
}

test("returns the step's single primary button", () => {
  const D = loadDom();
  const step = makeStep(1);

  const btn = D.stepPrimaryButton(step);

  assert.equal(btn.id, "primary-0");
});

test("returns null when the step has no primary button", () => {
  // The destination-tag step disables Continue until Coinbase's async tag-format
  // validation settles, so "not there yet" has to be pollable, not fatal.
  const D = loadDom();

  assert.equal(D.stepPrimaryButton(makeStep(0)), null);
});

test("throws rather than guess when the step holds two primary buttons", () => {
  const D = loadDom();

  assert.throws(() => D.stepPrimaryButton(makeStep(2)), /step-primary-ambiguous/);
});

test("the ambiguity error reports how many it found", () => {
  // So a Coinbase layout change is diagnosable from the error alone, without
  // needing a repro.
  const D = loadDom();

  assert.throws(() => D.stepPrimaryButton(makeStep(3)), /found 3/);
});

test("it is scoped to the step, never the document", () => {
  // Every step has a primary button. A document-wide query would click whichever
  // one happened to come first — the whole reason scoping is mandatory.
  const D = loadDom();
  const queried = [];
  const step = {
    querySelectorAll(sel) {
      queried.push(sel);
      return sel === PRIMARY ? [{ id: "scoped" }] : [];
    }
  };

  const btn = D.stepPrimaryButton(step);

  assert.equal(btn.id, "scoped");
  assert.deepEqual(queried, [PRIMARY]);
});

test("a missing step is null, not a crash", () => {
  // Callers poll for the step and the control together; a null step during a
  // transition must not throw.
  const D = loadDom();

  assert.equal(D.stepPrimaryButton(null), null);
  assert.equal(D.stepPrimaryButton(undefined), null);
});

test("dom-helpers.js does not use :has()", () => {
  // :has() needs Safari 15.4+ and WKWebView tracks the OS version, so it would fail silently.
  assert.doesNotMatch(SOURCE, /:has\(/);
});

import assert from "node:assert";
import { test } from "node:test";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const SOURCE = readFileSync(
  new URL("../../../Sources/ZerohashSDK/Automation/setup-execution-context.js", import.meta.url),
  "utf8"
);

const RISK_GATE_RULE =
  '[data-testid="step-riskSelfServeStep-active"] button.cds-IconButton{display:none !important;}';

/** Runs the real asset against a fake window, so these assert on behaviour. */
function runSetup({
  origin = "https://www.coinbase.com",
  throwOnSet = false,
  throwOnAppend = false,
  hasHead = false,
  runs = 1,
} = {}) {
  const writes = [];
  const appended = [];

  const localStorage = {
    setItem(key, value) {
      if (throwOnSet) throw new Error("storage disabled");
      writes.push([key, value]);
    },
  };

  const makeParent = (name) => ({
    name,
    appendChild(node) {
      if (throwOnAppend) throw new Error("append blocked");
      appended.push({ parent: this, node });
      return node;
    },
  });

  const documentElement = makeParent("documentElement");
  const head = hasHead ? makeParent("head") : null;

  const document = {
    head,
    documentElement,
    createElement(tagName) {
      return { tagName, id: "", textContent: "" };
    },
    getElementById(id) {
      const found = appended.find((entry) => entry.node.id === id);
      return found ? found.node : null;
    },
  };

  const sandbox = { location: { origin }, window: { localStorage }, localStorage, document };
  for (let run = 0; run < runs; run++) vm.runInNewContext(SOURCE, sandbox);

  return { writes, appended, head, documentElement };
}

test("seeds the flag Coinbase gates the app-upsell tray on", () => {
  assert.deepStrictEqual(runSetup().writes, [["appUpsellDismissed", "true"]]);
});

test("writes the four characters true, not JSON", () => {
  const [[, value]] = runSetup().writes;
  assert.strictEqual(value, "true");
  assert.notStrictEqual(value, '"true"');
});

test("writes nothing on another origin", () => {
  assert.deepStrictEqual(runSetup({ origin: "https://login.coinbase.com" }).writes, []);
  assert.deepStrictEqual(runSetup({ origin: "https://evil.example" }).writes, []);
});

test("an exact origin match is required, not a suffix", () => {
  assert.deepStrictEqual(runSetup({ origin: "https://www.coinbase.com.evil.example" }).writes, []);
});

test("a throwing step does not propagate", () => {
  assert.doesNotThrow(() => runSetup({ throwOnSet: true }));
});

test("hides the risk gate's X and nothing outside that step", () => {
  const { appended } = runSetup();

  assert.strictEqual(appended.length, 1);
  assert.strictEqual(appended[0].node.textContent, RISK_GATE_RULE);
});

test("the fix survives document start, when <head> does not exist yet", () => {
  const { appended, documentElement } = runSetup({ hasHead: false });

  assert.strictEqual(appended.length, 1);
  assert.strictEqual(appended[0].parent, documentElement);
});

test("the fix lands in <head> when the page already has one", () => {
  const { appended, head } = runSetup({ hasHead: true });

  assert.strictEqual(appended.length, 1);
  assert.strictEqual(appended[0].parent, head);
});

test("a second run leaves one stylesheet, not two", () => {
  const { appended } = runSetup({ runs: 2 });

  assert.strictEqual(appended.length, 1);
});

test("a page that merely looks like Coinbase gets no stylesheet", () => {
  assert.deepStrictEqual(runSetup({ origin: "https://login.coinbase.com" }).appended, []);
  assert.deepStrictEqual(
    runSetup({ origin: "https://www.coinbase.com.evil.example" }).appended,
    []
  );
});

test("a DOM that refuses the stylesheet still leaves the upsell dismissed", () => {
  let result;
  assert.doesNotThrow(() => {
    result = runSetup({ throwOnAppend: true });
  });

  assert.deepStrictEqual(result.appended, []);
  assert.deepStrictEqual(result.writes, [["appUpsellDismissed", "true"]]);
});

test("a failing storage step does not cost us the stylesheet", () => {
  const { writes, appended } = runSetup({ throwOnSet: true });

  assert.deepStrictEqual(writes, []);
  assert.strictEqual(appended.length, 1);
  assert.strictEqual(appended[0].node.textContent, RISK_GATE_RULE);
});

test("the rule is applied as a stylesheet, not rendered as text", () => {
  const { appended } = runSetup();

  assert.strictEqual(appended.length, 1);
  assert.strictEqual(appended[0].node.tagName, "style");
});

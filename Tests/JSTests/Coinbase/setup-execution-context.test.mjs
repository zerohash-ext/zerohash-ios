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

// Coinbase's resolution-hub banner: one testid, three severities, all hidden.
const BANNER_RULE = '[data-testid="system-alert-banner"]{display:none !important;}';

/** The CSS text of every stylesheet the asset injected, order-independent. */
const sheets = (appended) => appended.map((entry) => entry.node.textContent).sort();
const bothRules = [BANNER_RULE, RISK_GATE_RULE].sort();

/** Source with line comments stripped, so a guard never matches its own rationale. */
const CODE = SOURCE.split("\n")
  .map((l) => l.replace(/\/\/.*$/, ""))
  .join("\n");

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
  assert.ok(sheets(runSetup().appended).includes(RISK_GATE_RULE));
});

test("hides the Central Resolution Hub banner, every severity", () => {
  assert.ok(sheets(runSetup().appended).includes(BANNER_RULE));
});

test("each concern gets its own stylesheet, and there are exactly two", () => {
  // A third one appearing means a step was added without a test.
  assert.deepStrictEqual(sheets(runSetup().appended), bothRules);
});

test("the banner rule targets the banner itself, not the portal that hosts it", () => {
  // The portal hosts other content too; hiding it would take that with it.
  const css = sheets(runSetup().appended).join("\n");
  assert.doesNotMatch(css, /portal-alert-container/);
  assert.doesNotMatch(css, /portal-modal-container/);
});

test("the banner rule leaves Coinbase's other banners alone", () => {
  // The cookie notice (banner-container) and the BR onboarding modal are not ours
  // to suppress.
  const css = sheets(runSetup().appended).join("\n");
  assert.doesNotMatch(css, /banner-container/);
  assert.doesNotMatch(css, /brazil-onboarding-modal/);
  assert.doesNotMatch(css, /mobile-cookie-banner/);
});

test("the banner is hidden, never clicked", () => {
  // Deliberate: its dismiss button is a real control on the user's account.
  assert.doesNotMatch(CODE, /undefined-dismiss-btn/);
  assert.doesNotMatch(CODE, /\.click\(\)/);
});

test("the fix survives document start, when <head> does not exist yet", () => {
  const { appended, documentElement } = runSetup({ hasHead: false });

  assert.deepStrictEqual(sheets(appended), bothRules);
  for (const entry of appended) assert.strictEqual(entry.parent, documentElement);
});

test("the fix lands in <head> when the page already has one", () => {
  const { appended, head } = runSetup({ hasHead: true });

  assert.deepStrictEqual(sheets(appended), bothRules);
  for (const entry of appended) assert.strictEqual(entry.parent, head);
});

test("a second run re-injects nothing", () => {
  // Each step guards on its own STYLE_ID, so re-injection on a soft navigation is
  // a no-op rather than a pile of duplicate stylesheets.
  assert.deepStrictEqual(sheets(runSetup({ runs: 2 }).appended), bothRules);
  assert.deepStrictEqual(sheets(runSetup({ runs: 5 }).appended), bothRules);
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

test("a failing storage step does not cost us either stylesheet", () => {
  const { writes, appended } = runSetup({ throwOnSet: true });

  assert.deepStrictEqual(writes, []);
  assert.deepStrictEqual(sheets(appended), bothRules);
});

test("the rules are applied as stylesheets, not rendered as text", () => {
  const { appended } = runSetup();

  assert.strictEqual(appended.length, 2);
  for (const entry of appended) assert.strictEqual(entry.node.tagName, "style");
});

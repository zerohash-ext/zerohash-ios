import assert from "node:assert";
import { test } from "node:test";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const SOURCE = readFileSync(
  new URL("../../../Sources/ZerohashSDK/Automation/setup-execution-context.js", import.meta.url),
  "utf8"
);

/** Runs the real asset against a fake window, so these assert on behaviour. */
function runSetup({ origin = "https://www.coinbase.com", throwOnSet = false } = {}) {
  const writes = [];
  const localStorage = {
    setItem(key, value) {
      if (throwOnSet) throw new Error("storage disabled");
      writes.push([key, value]);
    },
  };
  const sandbox = { location: { origin }, window: { localStorage }, localStorage };
  vm.runInNewContext(SOURCE, sandbox);
  return writes;
}

test("seeds the flag Coinbase gates the app-upsell tray on", () => {
  assert.deepStrictEqual(runSetup(), [["appUpsellDismissed", "true"]]);
});

test("writes the four characters true, not JSON", () => {
  const [[, value]] = runSetup();
  assert.strictEqual(value, "true");
  assert.notStrictEqual(value, '"true"');
});

test("writes nothing on another origin", () => {
  assert.deepStrictEqual(runSetup({ origin: "https://login.coinbase.com" }), []);
  assert.deepStrictEqual(runSetup({ origin: "https://evil.example" }), []);
});

test("an exact origin match is required, not a suffix", () => {
  assert.deepStrictEqual(runSetup({ origin: "https://www.coinbase.com.evil.example" }), []);
});

test("a throwing step does not propagate", () => {
  assert.doesNotThrow(() => runSetup({ throwOnSet: true }));
});

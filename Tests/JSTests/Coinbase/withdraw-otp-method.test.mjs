import assert from "node:assert";
import { test } from "node:test";
import { readFileSync } from "node:fs";

const SOURCE = readFileSync(
  new URL("../../../Sources/ZerohashSDK/Platforms/Coinbase/withdraw.js", import.meta.url),
  "utf8"
);

const enterOtp = SOURCE.slice(SOURCE.indexOf("async function enterOtp("));

test("enterOtp re-chooses the method only when the field is absent", () => {
  assert.ok(enterOtp.includes("!queryVisible(SEL.OTP_INPUT) && chooseOtpMethod()"));
});

test("a chosen method with no field gets its own error", () => {
  assert.ok(SOURCE.includes("withdraw/otp-field-missing-after-method-choice"));
  const body = enterOtp.slice(0, enterOtp.indexOf("fillOtpCode"));
  assert.ok(body.includes("choseMethod"), "the rename must be gated on having chosen");
});

test("the error is not raised when no method was chosen", () => {
  const body = enterOtp.slice(0, enterOtp.indexOf("fillOtpCode"));
  assert.ok(body.includes("if (choseMethod)"));
  assert.ok(body.includes("throw e;"), "the original error must still propagate");
});

test("SMS is preferred over TOTP as in login", () => {
  const chooser = SOURCE.slice(SOURCE.indexOf("function chooseOtpMethod("));
  const body = chooser.slice(0, chooser.indexOf("\n  }"));
  assert.ok(body.indexOf("TWO_FACTOR_SMS") < body.indexOf("TWO_FACTOR_TOTP"));
});

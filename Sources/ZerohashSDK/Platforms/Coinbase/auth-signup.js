// ─── Coinbase: signup-page detection ─────────────────────────────────
//
// A social sign-in (Apple) for an account that does NOT exist on Coinbase
// doesn't sign the user in — Coinbase redirects to a sign-up / create-account
// page on login.coinbase.com (a stay-open host, so host policy can't catch it).
// This probe, polled by the modal's auto-close, returns `true` once we're on
// that signup page so the login flow can resolve `account-not-found`.
(function () {
  function has(sel) {
    return document.querySelector(sel) !== null;
  }

  // URL signal: the signup route. Robust to DOM churn.
  var url = "";
  try { url = location.href || ""; } catch (e) { url = ""; }
  if (url.indexOf("/signup") !== -1) return true;

  // DOM signals: the signup screen's header, or its phone-number input.
  return (
    has('[data-testid="signup-header"]') ||
    has('[data-testid*="phone-input"]')
  );
})();

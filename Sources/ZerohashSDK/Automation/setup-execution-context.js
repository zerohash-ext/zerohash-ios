// Runs at document start on every page the automation drives, before the page's
// own bundle executes. Add setup steps as functions and call them below.
//
// WKUserScript has no origin parameter, unlike Android's
// addDocumentStartJavaScript, so the origin check has to happen here. The hosting
// WebViews are already Coinbase-allowlisted, but this script grants a write into
// whatever document is loaded, so it does not rely on that alone.
(function () {
  if (location.origin !== "https://www.coinbase.com") return;

  // Coinbase gates its "See more on the Coinbase app" tray on this key. The tray
  // sits behind a full-screen backdrop that intercepts taps, so a click that looks
  // fine silently does nothing (AUTH-4270). Seeding the key means it never mounts.
  //
  // The value is the string "true", not JSON: JSON.stringify(true) writes quotes
  // and breaks both `v === "true"` and `JSON.parse(v) === true`.
  function dismissAppUpsell() {
    window.localStorage.setItem("appUpsellDismissed", "true");
  }

  function hideRiskGateCloseButton() {
    var STYLE_ID = "zh-hide-risk-gate-close";
    var CSS =
      '[data-testid="step-riskSelfServeStep-active"] button.cds-IconButton' +
      "{display:none !important;}";

    function inject() {
      if (document.getElementById(STYLE_ID)) return;
      var style = document.createElement("style");
      style.id = STYLE_ID;
      style.textContent = CSS;
      (document.head || document.documentElement).appendChild(style);
    }

    inject();
  }

  var steps = [dismissAppUpsell, hideRiskGateCloseButton];
  for (var i = 0; i < steps.length; i++) {
    // One failing step must not stop the others, and none of them is worth
    // aborting the run for.
    try {
      steps[i]();
    } catch (e) {}
  }
})();

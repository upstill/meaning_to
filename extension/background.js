// Send to ROUZME — MV3 service worker.
// On toolbar click, hand the active tab's URL + title to the ROUZME web app,
// which prompts for a Pursuit and creates a task (no page fetch needed — the
// title comes from here).

// DEV: set true to target a local dev server (flip back to false before
// committing/shipping — the production build must use meaning-to.me).
const DEV = false;
const ROUZME_ORIGIN = DEV ? "http://localhost:8080" : "https://meaning-to.me";

chrome.action.onClicked.addListener((tab) => {
  if (!tab || !tab.url || !/^https?:/i.test(tab.url)) {
    return; // nothing sensible to send (e.g. chrome:// pages)
  }
  const url =
    ROUZME_ORIGIN +
    "/?addlink=" +
    encodeURIComponent(tab.url) +
    "&title=" +
    encodeURIComponent(tab.title || "");
  chrome.tabs.create({ url });
});

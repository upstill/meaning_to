// Send to ROUZME — MV3 service worker.
// On toolbar click, hand the active tab's URL + title to the ROUZME web app,
// which prompts for a Pursuit and creates a task (no page fetch needed — the
// title comes from here).

// DEV: set true to target a local dev server (flip back to false before
// committing/shipping — the production build must use meaning-to.me).
const DEV = false;
const ROUZME_ORIGIN = DEV ? "http://localhost:8080" : "https://meaning-to.me";

chrome.action.onClicked.addListener(async (tab) => {
  if (!tab || !tab.url || !/^https?:/i.test(tab.url)) {
    return; // nothing sensible to send (e.g. chrome:// pages)
  }
  const url =
    ROUZME_ORIGIN +
    "/?addlink=" +
    encodeURIComponent(tab.url) +
    "&title=" +
    encodeURIComponent(tab.title || "");

  // Reuse an already-open ROUZME tab instead of piling up new ones. Updating
  // its URL reloads the app, which processes the new link. Prefer a tab in the
  // current window; fall back to any ROUZME tab, then to opening a new one.
  try {
    const rouzTabs = await chrome.tabs.query({ url: ROUZME_ORIGIN + "/*" });
    if (rouzTabs && rouzTabs.length) {
      const target =
        rouzTabs.find((t) => t.windowId === tab.windowId) || rouzTabs[0];
      await chrome.tabs.update(target.id, { url, active: true });
      if (target.windowId != null) {
        await chrome.windows.update(target.windowId, { focused: true });
      }
      return;
    }
  } catch (e) {
    // Any failure (e.g. missing permission) → just open a new tab below.
  }
  chrome.tabs.create({ url });
});

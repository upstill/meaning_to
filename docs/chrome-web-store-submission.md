# Chrome Web Store submission — "Send to RouzMe" extension

Copy/paste material for the Chrome Web Store listing + the reviewer-facing
permission justifications. (Edge Add-ons reuses all of this verbatim; Firefox
AMO reuses most of it; Safari is a separate Xcode-conversion job.)

The store-ready package (localhost stripped) lives in `dist/extension-store/`.

## Item name
**Send to RouzMe — Save any page as a task**
(or simply **Send to RouzMe** — the tagline helps discoverability)

## Category
**Productivity**

## Short summary (≤132 chars)
Send any web page to your RouzMe account as a task — one click captures the
link and title, no copy-paste.

## Detailed description
Send to RouzMe turns any web page into a task in your RouzMe account at
rouzme.com — the app that tracks the things you've been meaning to do,
organized into Pursuits.

**How it works**
- Found something you've been meaning to get to? Click the RouzMe button.
- It grabs the page's link and title and hands them to RouzMe — no copy-paste,
  no page scraping.
- RouzMe opens, lets you pick (or create) the Pursuit it belongs to, tweak the
  title, and save.
- The task lands in your RouzMe account, synced across your devices.

**Why Send to RouzMe**
- One-click capture from anywhere on the web.
- The page's real title comes straight from your browser, so bot-hostile sites
  still get a clean task name.
- Reuses your open RouzMe tab instead of piling up new ones.

Sign in once at rouzme.com and the extension keeps sending pages to your
account.

## Permission justifications (reviewer-facing)
For each item Chrome asks you to justify, use:

- **activeTab** — Reads the URL and title of the page the user is currently
  viewing, *only* when the user clicks the RouzMe toolbar button, to create a
  task from it. No background or automatic page access.
- **Host `https://rouzme.com/*`** — The extension opens (or reuses) a RouzMe
  tab at rouzme.com and hands it the captured link + title via the URL, so
  the RouzMe web app can create the task in the signed-in user's account. It
  also queries for an existing RouzMe tab (matched by this host) to reuse it
  rather than opening a new one.
- **Remote code** — None. The extension contains no remote or eval'd code; all
  executable code is bundled in the package. It only passes the current page's
  link and title to the RouzMe web app (rouzme.com) via a URL parameter; no
  external scripts are downloaded or executed.

## ⚠️ Pre-submission checklist
- [ ] **Use the store build in `dist/extension-store/`** — its manifest drops
  the dev-only `http://localhost:8080/*` host permission and its background.js
  has no localhost/DEV code. (Reviewers question localhost access in a published
  extension.) The committed `extension/` copy keeps the DEV toggle for local
  testing — do NOT zip that one.
- [ ] **Privacy policy URL** — REQUIRED (the extension transmits the page URL +
  title, i.e. user data). `https://rouzme.com/privacy` is currently a 404 —
  host a policy there before submitting. A minimal policy: state that the
  extension sends only the current page's link and title to the user's RouzMe
  account when the button is clicked, stores nothing locally, and shares nothing
  with third parties.
- [ ] **Single purpose** (Chrome asks): "Send the current web page's link and
  title to the user's RouzMe account as a task."
- [ ] **Data usage disclosures**: check "Web history / user activity" is
  collected (the page URL/title), used only for the app's core function, not
  sold, not used for unrelated purposes.
- [ ] Bump **`version`** in `dist/extension-store/manifest.json` if resubmitting
  (currently `1.0.1`).
- [ ] **Screenshots** (1280×800 or 640×400, 1–5): (1) the RouzMe button on a web
  page, (2) the RouzMe "New Task" screen with the captured title + Pursuit
  selector, (3) the task in the RouzMe list.
- [ ] **Store icon:** `dist/extension-store/icons/icon128.png` (the head + "!"
  mark, 128×128).
- [ ] Load `dist/extension-store/` **unpacked** and test the full send flow
  against live rouzme.com before zipping.

## Packaging
From the repo root:
```
cd dist/extension-store && zip -r ../send-to-rouzme-<version>.zip . -x '*.DS_Store' && cd -
```
Upload the resulting zip in the Chrome Web Store Developer Dashboard
(one-time $5 developer registration fee if this is your first item).

## Multi-browser notes
- **Edge Add-ons:** same zip; submit via Microsoft Partner Center.
- **Firefox (AMO):** MV3 works; verify `background.service_worker` +
  `chrome.tabs`/`chrome.windows` behave under Firefox. Separate submission.
- **Safari:** convert with `xcrun safari-web-extension-converter extension/`,
  wrap as a macOS/iOS app in Xcode, needs an Apple Developer account, ship via
  the App Store. Separate, heavier effort — do last.

# Send to RouzMe — Chrome extension

A one-click toolbar button that sends the current page (URL + title) to the
RouzMe web app (https://meaning-to.me), which prompts you to pick a Pursuit and
creates a Task from it. Because the extension already knows the page title,
RouzMe skips fetching the page.

## How it works
`background.js` listens for the toolbar click and opens
`https://meaning-to.me/?addlink=<url>&title=<title>` in a new tab. The web app
reads those params and (once you're signed in) shows its normal "add this link"
dialog with the title pre-filled.

## Install (unpacked, for development)
1. Open `chrome://extensions`.
2. Turn on **Developer mode** (top-right).
3. Click **Load unpacked** and select this `extension/` folder.
4. Pin "Send to RouzMe" to the toolbar. Click it on any page to send it.

Works in Chromium browsers (Chrome, Edge, Brave). To publish, zip this folder
and upload to the Chrome Web Store.

## Notes
- Requires only the `activeTab` permission (granted per-click); no browsing
  history or host access.
- On `chrome://` / extension pages there's nothing to send, so the click is a
  no-op.

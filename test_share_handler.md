# Share Handler Test Guide

## Testing Text Sharing Functionality

### Prerequisites
- App installed on Android device (Pixel 8a)
- App running and logged in

### Test Steps

1. **Open a text-sharing app** (e.g., Chrome browser, WhatsApp, Notes app)

2. **Select some text** that you want to share

3. **Use the share button** (usually three dots or share icon)

4. **Select "Meaning To"** from the share options

5. **Expected Results:**
   - App should receive the shared text
   - Snackbar notification should appear: "Received Text Share intent"
   - Console logs should show detailed intent information
   - Tapping "Details" should open a new screen with intent details

### Console Logs to Look For

```
=== Intent Received ===
Timestamp: 2024-01-XX...
Type: Text Share
Data: [shared text content]
=====================
```

### Troubleshooting

**If sharing doesn't work:**
1. Check that "Meaning To" appears in the share menu
2. Verify the app is running and not in background
3. Check console logs for any error messages

**If MaterialLocalizations error occurs:**
- The error should now be fixed with the Navigator.push approach
- If it still occurs, restart the app

### Network Issues

Note: The app may show network errors when trying to load categories from Supabase. This is a separate issue and doesn't affect the share handler functionality.

## Intent Types Currently Logged

1. **Text Share** - When users share text to your app
2. **Deep Link** - When users open your app via custom URLs
3. **Auth Errors** - When authentication fails via deep links
4. **Share Handler Errors** - Any errors in the share handler itself 
# Deep Linking Test Guide

## Overview
This app now supports deep linking to categories using multiple URL formats:

### URL Formats Supported

1. **Web URLs:**
   - `https://your-domain.com/category/123`
   - `https://your-domain.com/?category=123`

2. **Custom Scheme URLs:**
   - `meaningto://category/123`

3. **Path-based URLs:**
   - `/category/123`

## Testing Deep Links

### 1. Web Testing
- Navigate to `https://your-domain.com/category/123` in a browser
- The app should open and navigate to category with ID 123
- Test with query parameter: `https://your-domain.com/?category=123`

### 2. Mobile Testing

#### Android
```bash
# Test custom scheme
adb shell am start -W -a android.intent.action.VIEW -d "meaningto://category/123" com.example.meaning_to

# Test web URL (if universal links are configured)
adb shell am start -W -a android.intent.action.VIEW -d "https://your-domain.com/category/123" com.example.meaning_to
```

#### iOS
```bash
# Test custom scheme
xcrun simctl openurl booted "meaningto://category/123"

# Test web URL (if universal links are configured)
xcrun simctl openurl booted "https://your-domain.com/category/123"
```

### 3. Manual Testing
1. Open the app
2. Select a category
3. Tap the share button (green share icon)
4. Choose "Copy Link" to copy the deep link
5. Paste the link in a browser or messaging app
6. Tap the link to test deep linking

## Expected Behavior

1. **Valid Category ID:** App opens and navigates to the specified category
2. **Invalid Category ID:** App opens and shows default/home screen
3. **No Category ID:** App opens normally

## Debug Information

The app logs deep link processing to the console. Look for:
- "Processing category deep link"
- "Category ID from deep link: [ID]"
- "Creating HomeScreen with category ID: [ID]"

## Configuration Files

### Android
- `android/app/src/main/AndroidManifest.xml` - Intent filters for deep linking

### iOS  
- `ios/Runner/Info.plist` - URL schemes and universal link support

### Web
- `web/index.html` - Base configuration for web deep linking

## Troubleshooting

1. **Deep link not working:**
   - Check console logs for errors
   - Verify intent filters are properly configured
   - Ensure category ID exists in the database

2. **Web deep links not working:**
   - Verify the domain in `DeepLinkGenerator` matches your actual domain
   - Check if the web app is properly deployed

3. **Mobile deep links not working:**
   - Verify URL schemes are properly configured
   - Check if the app is installed and can handle the scheme

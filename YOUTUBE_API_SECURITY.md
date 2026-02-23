# Secure Credentials Management

## 🔒 Complete Application Security

This document outlines how **all credentials** (YouTube API, Supabase) are securely managed in this application.

## Implementation Details

### **Production (Vercel Deployment):**
- **All credentials** stored as Vercel environment variables:
  - `YOUTUBE_API_KEY` - YouTube Data API v3 key
  - `SUPABASE_URL` - Supabase project URL
  - `SUPABASE_ANON_KEY` - Supabase anonymous key
- Injected at build time using `--dart-define` flags
- **Never stored in code or committed to repository**

### **Local Development:**
- Falls back to `.env` file for local testing (if needed)
- API key removed from `.env` file in production
- Graceful fallback when no API key is available

### **Code Implementation:**
```dart
static String? get apiKey {
  // Priority 1: Build-time environment variable (Production)
  const apiKeyFromBuild = String.fromEnvironment('YOUTUBE_API_KEY');
  if (apiKeyFromBuild.isNotEmpty) {
    return apiKeyFromBuild;
  }

  // Priority 2: Local .env fallback (Development)
  try {
    final apiKeyFromDotenv = dotenv.env['YOUTUBE_API_KEY'];
    if (apiKeyFromDotenv != null && apiKeyFromDotenv.isNotEmpty) {
      return apiKeyFromDotenv;
    }
  } catch (e) {
    // Graceful fallback
  }

  return null; // No API key available
}
```

## Vercel Configuration

### **vercel.json:**
```json
{
  "buildCommand": "flutter build web --dart-define=YOUTUBE_API_KEY=$YOUTUBE_API_KEY --dart-define=SUPABASE_URL=$SUPABASE_URL --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY",
  "framework": null
}
```

### **Environment Variables Setup:**
1. Go to Vercel Project Settings
2. Add Environment Variables:
   - `YOUTUBE_API_KEY` - Your YouTube Data API v3 key
   - `SUPABASE_URL` - Your Supabase project URL
   - `SUPABASE_ANON_KEY` - Your Supabase anonymous key
3. Deploy - all credentials will be injected at build time

## Security Benefits

✅ **API key never exposed in client code**
✅ **Not stored in repository or version control**
✅ **Injected only at build time on secure platform**
✅ **Graceful fallback when key unavailable**
✅ **Local development flexibility**

## Fallback Behavior

When YouTube API is unavailable:
1. **Video ID extraction** still works
2. **Falls back to web scraping** with CORS proxy
3. **No application crashes**
4. **User experience maintained**

## Testing

Run tests to verify security implementation:

```bash
# Test without API key
flutter test test/test_secure_api_key.dart

# Test with API key (for local development)
flutter test test/test_secure_api_key.dart --dart-define=YOUTUBE_API_KEY=your_key
```

## Deployment

### **For Vercel:**
1. Set `YOUTUBE_API_KEY` environment variable in Vercel dashboard
2. Push to repository - Vercel will automatically build with secure key injection

### **For other platforms:**
Update build command to include:
```bash
flutter build web --dart-define=YOUTUBE_API_KEY=$YOUTUBE_API_KEY
```

## Important Notes

⚠️ **Never commit API keys to repository**
⚠️ **Remove API key from `.env` file before committing**
⚠️ **Use environment variables on hosting platform**
⚠️ **Test graceful fallback behavior**

## Security Verification

The implementation includes tests that verify:
- API key precedence (build-time over dotenv)
- Graceful handling of missing keys
- No accidental logging/exposure
- Continued functionality without API key

This ensures the YouTube API integration is both secure and resilient.
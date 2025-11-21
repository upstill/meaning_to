# Spotify Integration Guide

## Overview

The app now supports processing Spotify album links to automatically extract artist and album information using the Spotify Web API.

## Setup

### 1. Get Spotify API Credentials

1. Go to the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard)
2. Log in with your Spotify account (or create one if needed)
3. Click "Create app"
4. Fill in the app details:
   - **App name**: Meaning To (or whatever you prefer)
   - **App description**: Personal task management app
   - **Redirect URI**: http://localhost (not used, but required)
   - **API/SDKs**: Check "Web API"
5. After creating the app, you'll see your **Client ID** and **Client Secret**

### 2. Configure Your Environment

Add your Spotify credentials to the `.env` file:

```bash
# Spotify API Configuration
SPOTIFY_CLIENT_ID=your_client_id_here
SPOTIFY_CLIENT_SECRET=your_client_secret_here
```

Replace `your_client_id_here` and `your_client_secret_here` with the values from the Spotify Developer Dashboard.

## How It Works

### When Processing Spotify Album Links

When you add a Spotify album link (e.g., `https://open.spotify.com/album/4aawyAB9vmqN3uQ7FjRGTy`):

1. **API Fetch (Primary)**: The app will first try to fetch album information from the Spotify API
   - Extracts: Artist name and Album title
   - Fast and reliable

2. **Title Extraction (Fallback)**: If the API is not configured or fails, it will attempt to extract information from the webpage title
   - Pattern: `"<album> - album by <artist> | Spotify"`

3. **Task Creation**: The extracted information is used to create a task with:
   - **Headline**: Artist name
   - **Notes**: Album title
   - **Links**: The Spotify album link
   - **Suggested Categories**: "Play a Favorite Record" (54) or "Try out some New Music" (41)

### Supported URL Formats

- Full album URLs: `https://open.spotify.com/album/{album_id}`
- Short URLs will be expanded automatically

### Example

**Input Link**: `https://open.spotify.com/album/4aawyAB9vmqN3uQ7FjRGTy`

**Extracted Data**:
- Artist: "Pink Floyd"
- Album: "The Dark Side of the Moon"

**Created Task**:
- Headline: "Pink Floyd"
- Notes: "The Dark Side of the Moon"
- Link: HTML link to the Spotify album

## Optional Configuration

The Spotify API is **optional**. The app will work without it, but:
- ✅ **With API**: Reliable extraction of artist and album names
- ⚠️ **Without API**: Relies on webpage title parsing, which may be less reliable

## Authentication

The app uses Spotify's **Client Credentials flow**, which:
- Does not require user login
- Only accesses public album information
- Access tokens are cached and automatically refreshed
- Suitable for server-side or personal apps

## Rate Limits

Spotify's rate limits are generous for the Client Credentials flow:
- Typically allows several thousand requests per hour
- Tokens are cached to minimize API calls
- Each album link only requires 1 API call (plus occasional token refresh)

## Troubleshooting

### API Not Working

1. **Check credentials**: Ensure `SPOTIFY_CLIENT_ID` and `SPOTIFY_CLIENT_SECRET` are correctly set in `.env`
2. **Check logs**: Look for messages starting with `SpotifyApi:` in the console
3. **Verify app status**: Make sure your Spotify app is active in the Developer Dashboard

### Common Issues

**"API credentials not configured"**
- The `.env` file doesn't have the Spotify credentials
- Solution: Add your credentials to `.env`

**"Failed to get access token"**
- Invalid credentials
- Solution: Double-check your Client ID and Secret

**"Could not extract album ID from URL"**
- The URL format is not recognized
- Solution: Ensure you're using a Spotify album URL (not playlist, track, or artist)

## Files Modified

- `lib/utils/spotify_api.dart` - New Spotify API service
- `lib/utils/streaming_media_constants.dart` - Added Spotify patterns and functions
- `lib/utils/link_to_task_converter.dart` - Integrated Spotify processing
- `.env` - Added configuration placeholders

## Future Enhancements

Potential additions:
- Support for Spotify playlist links
- Support for Spotify track links (singles)
- Support for Spotify artist pages
- Apple Music integration (similar pattern)

# Spotify Link Processing - Implementation Summary

## Overview

The app now supports processing Spotify links (albums and playlists) with proper URL normalization and API-based data extraction.

## Features Implemented

### 1. URL Normalization

**Spotify URLs are cleaned to canonical format:**
- Removes all query parameters (tracking, sharing, etc.)
- Standardizes to: `https://open.spotify.com/{type}/{id}`

**Examples:**
```
Input:  https://open.spotify.com/album/4aawyAB9vmqN3uQ7FjRGTy?si=abc123
Output: https://open.spotify.com/album/4aawyAB9vmqN3uQ7FjRGTy

Input:  https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?utm_source=copy-link
Output: https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M
```

### 2. Album Link Processing

**When you add a Spotify album link:**

**API Extraction (Primary):**
- Fetches artist name and album title from Spotify API
- Creates task with:
  - **Headline**: Artist name (e.g., "Pink Floyd")
  - **Notes**: Album title (e.g., "The Dark Side of the Moon")
  - **Link Text**: Album title + " on Spotify" (e.g., `<a href="...">The Dark Side of the Moon on Spotify</a>`)
  - **Categories**: Suggests "Play a Favorite Record" (54) or "Try out some New Music" (41)

**Fallback (if API unavailable):**
- Attempts to extract from page title using regex pattern
- Falls back to full page title if extraction fails

**Example:**

Input: `https://open.spotify.com/album/4aawyAB9vmqN3uQ7FjRGTy`

Result:
- Headline: "Pink Floyd"
- Notes: "The Dark Side of the Moon"
- Link: `<a href="https://open.spotify.com/album/4aawyAB9vmqN3uQ7FjRGTy">The Dark Side of the Moon on Spotify</a>`

### 3. Playlist Link Processing

**When you add a Spotify playlist link:**

**API Extraction (Primary):**
- Fetches playlist name (and owner if available) from Spotify API
- Creates task with:
  - **Headline**: Playlist name (e.g., "Today's Top Hits")
  - **Notes**: null
  - **Link Text**: Playlist name + " on Spotify" (e.g., `<a href="...">Today's Top Hits on Spotify</a>`)
  - **Categories**: Suggests "Play a Favorite Record" (54) or "Try out some New Music" (41)

**Example:**

Input: `https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M`

Result:
- Headline: "Today's Top Hits"
- Notes: null
- Link: `<a href="https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M">Today's Top Hits on Spotify</a>`

## Technical Implementation

### Files Modified

1. **`lib/utils/spotify_api.dart`** (NEW)
   - `extractSpotifyResource()` - Extracts type and ID from URL
   - `getAlbumInfo()` - Fetches album data from API
   - `getPlaylistInfo()` - Fetches playlist data from API
   - `getInfoFromUrl()` - Unified method for all Spotify resources
   - OAuth Client Credentials flow with automatic token caching

2. **`lib/utils/link_to_task_converter.dart`**
   - Added Spotify URL normalization (lines 271-296)
   - Updated streaming media processing to use `SpotifyApiService.getInfoFromUrl()`
   - Differentiates between albums and playlists
   - Sets custom link text for both albums and playlists
   - Early return when custom link text is set to avoid duplicate processing

3. **`lib/utils/streaming_media_constants.dart`**
   - Added `SPOTIFY_TITLE_PATTERN` regex
   - Added `extractArtistAndWorkFromSpotify()` function
   - Updated `isStreamingMediaUrl()` to include Spotify
   - Updated `getStreamingServiceName()` to include Spotify

4. **`.env`**
   - Added configuration placeholders:
     - `SPOTIFY_CLIENT_ID`
     - `SPOTIFY_CLIENT_SECRET`

### API Authentication

**OAuth Client Credentials Flow:**
- Does not require user login
- Only accesses public data
- Tokens are cached and automatically refreshed
- Token expiry: ~1 hour (cached for 59 minutes)

**Configuration:**
```env
SPOTIFY_CLIENT_ID=your_client_id_here
SPOTIFY_CLIENT_SECRET=your_client_secret_here
```

Get credentials at: https://developer.spotify.com/dashboard

**Redirect URI:** Use `https://meaning-to.me` (required by Spotify but not used)

### API Endpoints Used

1. **Get Album:**
   - `GET https://api.spotify.com/v1/albums/{id}`
   - Returns: artist name, album name, release date, etc.

2. **Get Playlist:**
   - `GET https://api.spotify.com/v1/playlists/{id}`
   - Returns: playlist name, owner, description, etc.

3. **Get Access Token:**
   - `POST https://accounts.spotify.com/api/token`
   - Body: `grant_type=client_credentials`

## Data Flow

### Album Processing Flow:

```
User pastes Spotify album URL
    ↓
Normalize URL (remove query params)
    ↓
Extract album ID from URL
    ↓
Call Spotify API: GET /albums/{id}
    ↓
Extract artist name and album title
    ↓
Create task:
  - Headline = artist name
  - Notes = album title
  - Link text = album title
```

### Playlist Processing Flow:

```
User pastes Spotify playlist URL
    ↓
Normalize URL (remove query params)
    ↓
Extract playlist ID from URL
    ↓
Call Spotify API: GET /playlists/{id}
    ↓
Extract playlist name
    ↓
Create task:
  - Headline = playlist name
  - Notes = null
  - Link text = playlist name
```

## Error Handling

The implementation includes graceful fallbacks:

1. **API credentials not configured** → Falls back to title extraction
2. **API request fails** → Falls back to title extraction
3. **Invalid URL format** → Uses page title as fallback
4. **Network timeout** → Falls back to title extraction

## Testing

To test the implementation:

1. **Album Link:**
   ```
   https://open.spotify.com/album/4aawyAB9vmqN3uQ7FjRGTy
   ```
   Expected: Headline = "Pink Floyd", Notes = "The Dark Side of the Moon"

2. **Playlist Link:**
   ```
   https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M
   ```
   Expected: Headline = "Today's Top Hits", Notes = null

3. **With Query Parameters:**
   ```
   https://open.spotify.com/album/4aawyAB9vmqN3uQ7FjRGTy?si=abc123&utm_source=copy
   ```
   Expected: URL normalized, same result as above

## Future Enhancements

Potential additions:
- Track/single link support
- Artist page support
- Podcast episode support
- Enhanced metadata (release date, genres, etc.)
- Apple Music integration (similar pattern)
- YouTube Music integration

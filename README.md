# meaning_to

A new Flutter project for managing tasks and categories with intelligent link processing.

## Getting Started

This project is a starting point for a Flutter application.**

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

** After build, authorization was added using instructions at
https://www.freecodecamp.org/news/add-auth-to-flutter-apps-with-supabase-auth-ui/

## Environment Setup

This project uses environment variables for API keys and configuration. To set up:

1. Copy `.env.example` to `.env`:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env` and fill in your credentials:

### Required Configuration

- **SUPABASE_URL**: Your Supabase project URL
- **SUPABASE_ANON_KEY**: Your Supabase anonymous key

### Optional Configuration

#### OMDb API (Recommended for IMDb link processing)

The app can extract rich metadata from IMDb links using the OMDb API. This is **optional** - if not configured, the app will fall back to HTML scraping (which still works but is less reliable).

**To enable OMDb API:**

1. Get a free API key:
   - Visit: http://www.omdbapi.com/apikey.aspx
   - Select "FREE! (1,000 daily limit)"
   - Enter your email and activate via the confirmation email
   - Copy your API key

2. Add to `.env`:
   ```
   OMDB_API_KEY=your_actual_api_key_here
   ```

3. Build/run with the environment variable:
   ```bash
   flutter run --dart-define=OMDB_API_KEY=your_actual_api_key_here
   ```

**What OMDb API provides:**
- Clean movie/TV show titles
- Full plot summaries
- Ratings (IMDb, Rotten Tomatoes, Metascore)
- Runtime, release date, genre
- Distinguishes between movies, TV series, and episodes

**Free tier limits:** 1,000 API calls per day (plenty for personal use)

#### YouTube API (Optional)

For YouTube-specific features, configure:
```
YOUTUBE_API_KEY=your_youtube_api_key_here
```

## Running with Environment Variables

When running or building the app, pass environment variables using `--dart-define`:

```bash
# Run with OMDb API
flutter run --dart-define=OMDB_API_KEY=your_key_here

# Build with all variables
flutter build web \
  --dart-define=SUPABASE_URL=your_url \
  --dart-define=SUPABASE_ANON_KEY=your_key \
  --dart-define=OMDB_API_KEY=your_omdb_key
```

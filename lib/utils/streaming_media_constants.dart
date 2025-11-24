/// Constants and utilities for handling streaming media categories and links.
///
/// This file defines categories that are used for cataloging music from
/// streaming services like Tidal, Spotify, Apple Music, etc.

/// List of category original_ids that are classified as "streaming media" categories.
/// These categories are used for cataloging music from streaming services.
///
/// Currently includes:
/// - 54: "Play a Favorite Record"
/// - 41: "Try out some New Music"
/// - 74: Playlist category (primary suggestion for Spotify playlists)
const List<int> STREAMING_MEDIA_CATEGORY_IDS = [54, 41, 74];

/// Regex pattern to extract artist and work from Tidal link titles.
/// Format: "<work> by <artist> on TIDAL"
/// Example: "Dark Side of the Moon by Pink Floyd on TIDAL"
final RegExp TIDAL_TITLE_PATTERN = RegExp(r'^(.+?) by (.+?) on TIDAL$');

/// Regex pattern to extract artist and work from Spotify link titles.
/// Format: "<work> - album by <artist> | Spotify" or "<work> | Spotify"
/// Examples:
///   "Dark Side of the Moon - album by Pink Floyd | Spotify"
///   "The Wall | Spotify"
///   "Global Warming (feat. Sensato) - song and lyrics by Pitbull, Sensato | Spotify"
final RegExp SPOTIFY_TITLE_PATTERN =
    RegExp(r'^(.+?)(?: - (?:album|single|EP|song and lyrics|playlist) by (.+?))? \| Spotify$', caseSensitive: false);

/// Data class to hold extracted artist and work information from streaming links.
class ArtistWorkInfo {
  final String artist;
  final String work;

  const ArtistWorkInfo({
    required this.artist,
    required this.work,
  });
}

/// Extracts artist and work information from a Tidal link title.
///
/// Expected format: "<work> by <artist> on TIDAL"
/// Returns null if the title doesn't match the expected format.
///
/// Example:
/// ```dart
/// final info = extractArtistAndWorkFromTidal("Dark Side of the Moon by Pink Floyd on TIDAL");
/// // info.artist == "Pink Floyd"
/// // info.work == "Dark Side of the Moon"
/// ```
ArtistWorkInfo? extractArtistAndWorkFromTidal(String title) {
  final match = TIDAL_TITLE_PATTERN.firstMatch(title);
  if (match == null) return null;

  final work = match.group(1)?.trim();
  final artist = match.group(2)?.trim();

  if (work == null || artist == null || work.isEmpty || artist.isEmpty) {
    return null;
  }

  return ArtistWorkInfo(
    artist: artist,
    work: work,
  );
}

/// Extracts artist and work information from a Spotify link title.
///
/// Expected formats:
/// - "<work> - album by <artist> | Spotify"
/// - "<work> | Spotify" (when artist is not in title)
/// Returns null if the title doesn't match the expected format.
///
/// Example:
/// ```dart
/// final info = extractArtistAndWorkFromSpotify("Dark Side of the Moon - album by Pink Floyd | Spotify");
/// // info.artist == "Pink Floyd"
/// // info.work == "Dark Side of the Moon"
/// ```
ArtistWorkInfo? extractArtistAndWorkFromSpotify(String title) {
  final match = SPOTIFY_TITLE_PATTERN.firstMatch(title);
  if (match == null) return null;

  final work = match.group(1)?.trim();
  final artist = match.group(2)?.trim(); // May be null if not in title

  if (work == null || work.isEmpty) {
    return null;
  }

  // If artist is not in title, return null so we can use API fallback
  if (artist == null || artist.isEmpty) {
    return null;
  }

  return ArtistWorkInfo(
    artist: artist,
    work: work,
  );
}

/// Extracts track and artist information from a YouTube video title.
///
/// Handles various formats:
/// - "Track Name (feat. Artist2) - Artist1"
/// - "Artist1 - Track Name (feat. Artist2)"
/// - "Track Name - Artist1"
///
/// Returns an ArtistWorkInfo where:
/// - work: The track name (including featured artists in parentheses)
/// - artist: Comma-separated list of all artists (main artist and featured artists)
///
/// Example:
/// ```dart
/// final info = extractArtistAndWorkFromYouTube("Global Warming (feat. Sensato) - Pitbull");
/// // info.work == "Global Warming (feat. Sensato)"
/// // info.artist == "Pitbull, Sensato"
/// ```
ArtistWorkInfo? extractArtistAndWorkFromYouTube(String title) {
  // Remove common YouTube suffixes
  String cleanTitle = title.trim();
  cleanTitle = cleanTitle.replaceAll(RegExp(r'\s*-\s*YouTube$'), '').trim();
  cleanTitle = cleanTitle.replaceAll(RegExp(r'\s*\[.*?\]$'), '').trim();
  cleanTitle = cleanTitle
      .replaceAll(RegExp(r'\s*\(Official.*?\)$', caseSensitive: false), '')
      .trim();

  // Pattern 1: "Track Name (feat. Featured) - Main Artist"
  var match =
      RegExp(r'^(.+?)\s*\(feat\.\s*(.+?)\)\s*-\s*(.+?)$', caseSensitive: false)
          .firstMatch(cleanTitle);
  if (match != null) {
    final trackName =
        '${match.group(1)!.trim()} (feat. ${match.group(2)!.trim()})';
    final mainArtist = match.group(3)!.trim();
    final featuredArtist = match.group(2)!.trim();
    final allArtists = '$mainArtist, $featuredArtist';
    return ArtistWorkInfo(artist: allArtists, work: trackName);
  }

  // Pattern 2: "Main Artist - Track Name (feat. Featured)"
  match =
      RegExp(r'^(.+?)\s*-\s*(.+?)\s*\(feat\.\s*(.+?)\)$', caseSensitive: false)
          .firstMatch(cleanTitle);
  if (match != null) {
    final mainArtist = match.group(1)!.trim();
    final trackBase = match.group(2)!.trim();
    final featuredArtist = match.group(3)!.trim();
    final trackName = '$trackBase (feat. $featuredArtist)';
    final allArtists = '$mainArtist, $featuredArtist';
    return ArtistWorkInfo(artist: allArtists, work: trackName);
  }

  // Pattern 3: "Track Name - Main Artist"
  match = RegExp(r'^(.+?)\s*-\s*(.+?)$').firstMatch(cleanTitle);
  if (match != null) {
    final firstPart = match.group(1)!.trim();
    final secondPart = match.group(2)!.trim();

    // Check if first part looks like an artist name (shorter, might be capitalized differently)
    // and second part looks like a track name (longer, or has parentheses)
    // For now, assume: if second part doesn't contain " - ", then "Artist - Track"
    if (!firstPart.contains(' - ') && !secondPart.contains(' - ')) {
      // Likely "Artist - Track"
      final trackName = secondPart;
      final artist = firstPart;
      return ArtistWorkInfo(artist: artist, work: trackName);
    }
  }

  // Pattern 4: Just the track name (no artist in title)
  // Return null so we can use the channel name or full title as fallback
  return null;
}

/// Checks if a URL is from a streaming media service.
/// Currently supports Tidal, Spotify, and YouTube. Can be extended for Apple Music, etc.
bool isStreamingMediaUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;

  final host = uri.host.toLowerCase();

  return host.contains('tidal.com') ||
      host.contains('spotify.com') ||
      host.contains('youtube.com') ||
      host.contains('youtu.be');
  // Future additions:
  // || host.contains('music.apple.com')
}

/// Gets the streaming service name from a URL.
/// Returns null if the URL is not from a recognized streaming service.
String? getStreamingServiceName(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;

  final host = uri.host.toLowerCase();

  if (host.contains('tidal.com')) return 'Tidal';
  if (host.contains('spotify.com')) return 'Spotify';
  if (host.contains('youtube.com') || host.contains('youtu.be'))
    return 'YouTube';
  // Future additions:
  // if (host.contains('music.apple.com')) return 'Apple Music';

  return null;
}

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
const List<int> STREAMING_MEDIA_CATEGORY_IDS = [54, 41];

/// Regex pattern to extract artist and work from Tidal link titles.
/// Format: "<work> by <artist> on TIDAL"
/// Example: "Dark Side of the Moon by Pink Floyd on TIDAL"
final RegExp TIDAL_TITLE_PATTERN = RegExp(r'^(.+?) by (.+?) on TIDAL$');

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

/// Checks if a URL is from a streaming media service.
/// Currently only supports Tidal, but can be extended for Spotify, Apple Music, etc.
bool isStreamingMediaUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;

  final host = uri.host.toLowerCase();

  // Add more streaming services as needed
  return host.contains('tidal.com');
  // Future additions:
  // || host.contains('spotify.com')
  // || host.contains('music.apple.com')
  // || host.contains('youtube.com/music')
}

/// Gets the streaming service name from a URL.
/// Returns null if the URL is not from a recognized streaming service.
String? getStreamingServiceName(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;

  final host = uri.host.toLowerCase();

  if (host.contains('tidal.com')) return 'Tidal';
  // Future additions:
  // if (host.contains('spotify.com')) return 'Spotify';
  // if (host.contains('music.apple.com')) return 'Apple Music';

  return null;
}

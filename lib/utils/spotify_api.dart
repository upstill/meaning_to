import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Spotify Web API integration for fetching album and artist information.
///
/// Requires SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET in .env file.
/// Get your credentials at: https://developer.spotify.com/dashboard
class SpotifyApiService {
  static String? _accessToken;
  static DateTime? _tokenExpiry;

  /// Check if Spotify API credentials are available
  static bool get isAvailable {
    final clientId = dotenv.env['SPOTIFY_CLIENT_ID'];
    final clientSecret = dotenv.env['SPOTIFY_CLIENT_SECRET'];
    return clientId != null &&
        clientId.isNotEmpty &&
        clientSecret != null &&
        clientSecret.isNotEmpty;
  }

  /// Get or refresh access token using Client Credentials flow
  static Future<String?> _getAccessToken() async {
    // Return cached token if still valid
    if (_accessToken != null &&
        _tokenExpiry != null &&
        DateTime.now().isBefore(_tokenExpiry!)) {
      return _accessToken;
    }

    try {
      final clientId = dotenv.env['SPOTIFY_CLIENT_ID'];
      final clientSecret = dotenv.env['SPOTIFY_CLIENT_SECRET'];

      if (clientId == null || clientSecret == null) {
        print('SpotifyApi: Missing credentials in .env file');
        return null;
      }

      // Encode credentials for Basic Auth
      final credentials = base64Encode(utf8.encode('$clientId:$clientSecret'));

      final response = await http.post(
        Uri.parse('https://accounts.spotify.com/api/token'),
        headers: {
          'Authorization': 'Basic $credentials',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'grant_type': 'client_credentials'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _accessToken = data['access_token'];
        final expiresIn = data['expires_in'] as int; // seconds
        _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn - 60));
        print('SpotifyApi: Successfully obtained access token');
        return _accessToken;
      } else {
        print(
            'SpotifyApi: Failed to get access token: ${response.statusCode} ${response.body}');
        return null;
      }
    } catch (e) {
      print('SpotifyApi: Error getting access token: $e');
      return null;
    }
  }

  /// Extract Spotify resource type and ID from URL
  /// Returns a map with 'type' and 'id' keys
  /// Example: https://open.spotify.com/album/4aawyAB9vmqN3uQ7FjRGTy
  ///   -> {type: 'album', id: '4aawyAB9vmqN3uQ7FjRGTy'}
  static Map<String, String>? extractSpotifyResource(String url) {
    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;

      // Look for /{type}/{id} in path
      for (int i = 0; i < pathSegments.length - 1; i++) {
        if (pathSegments[i] == 'album' ||
            pathSegments[i] == 'playlist' ||
            pathSegments[i] == 'track') {
          return {
            'type': pathSegments[i],
            'id': pathSegments[i + 1],
          };
        }
      }
      return null;
    } catch (e) {
      print('SpotifyApi: Error extracting resource: $e');
      return null;
    }
  }

  /// Extract album ID from Spotify URL (backward compatibility)
  /// Example: https://open.spotify.com/album/4aawyAB9vmqN3uQ7FjRGTy -> 4aawyAB9vmqN3uQ7FjRGTy
  static String? extractAlbumId(String url) {
    final resource = extractSpotifyResource(url);
    if (resource != null && resource['type'] == 'album') {
      return resource['id'];
    }
    return null;
  }

  /// Fetch album information from Spotify API
  /// Returns a map with 'artist' and 'album' keys
  static Future<Map<String, String>?> getAlbumInfo(String albumId) async {
    try {
      if (!isAvailable) {
        print('SpotifyApi: API credentials not configured');
        return null;
      }

      final token = await _getAccessToken();
      if (token == null) {
        print('SpotifyApi: Failed to get access token');
        return null;
      }

      final response = await http.get(
        Uri.parse('https://api.spotify.com/v1/albums/$albumId'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Extract artist name (use first artist if multiple)
        final artists = data['artists'] as List<dynamic>?;
        final artistName = artists != null && artists.isNotEmpty
            ? artists[0]['name'] as String
            : null;

        // Extract album name
        final albumName = data['name'] as String?;

        if (artistName != null && albumName != null) {
          print(
              'SpotifyApi: Successfully fetched album: "$albumName" by $artistName');
          return {
            'artist': artistName,
            'album': albumName,
          };
        }

        print('SpotifyApi: Missing artist or album name in response');
        return null;
      } else {
        print(
            'SpotifyApi: API request failed: ${response.statusCode} ${response.body}');
        return null;
      }
    } catch (e) {
      print('SpotifyApi: Error fetching album info: $e');
      return null;
    }
  }

  /// Fetch track information from Spotify API
  /// Returns a map with 'artist' and 'track' keys
  static Future<Map<String, String>?> getTrackInfo(String trackId) async {
    try {
      if (!isAvailable) {
        print('SpotifyApi: API credentials not configured');
        return null;
      }

      final token = await _getAccessToken();
      if (token == null) {
        print('SpotifyApi: Failed to get access token');
        return null;
      }

      final response = await http.get(
        Uri.parse('https://api.spotify.com/v1/tracks/$trackId'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Extract artist name (use first artist if multiple)
        final artists = data['artists'] as List<dynamic>?;
        final artistName = artists != null && artists.isNotEmpty
            ? artists[0]['name'] as String
            : null;

        // Extract track name
        final trackName = data['name'] as String?;

        if (artistName != null && trackName != null) {
          print(
              'SpotifyApi: Successfully fetched track: "$trackName" by $artistName');
          return {
            'artist': artistName,
            'track': trackName,
          };
        }

        print('SpotifyApi: Missing artist or track name in response');
        return null;
      } else {
        print(
            'SpotifyApi: API request failed: ${response.statusCode} ${response.body}');
        return null;
      }
    } catch (e) {
      print('SpotifyApi: Error fetching track info: $e');
      return null;
    }
  }

  /// Fetch playlist information from Spotify API
  /// Returns a map with 'name' and 'owner' keys
  static Future<Map<String, String>?> getPlaylistInfo(String playlistId) async {
    try {
      if (!isAvailable) {
        print('SpotifyApi: API credentials not configured');
        return null;
      }

      final token = await _getAccessToken();
      if (token == null) {
        print('SpotifyApi: Failed to get access token');
        return null;
      }

      final response = await http.get(
        Uri.parse('https://api.spotify.com/v1/playlists/$playlistId'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Extract playlist name
        final playlistName = data['name'] as String?;

        // Extract owner name
        final owner = data['owner'] as Map<String, dynamic>?;
        final ownerName = owner?['display_name'] as String?;

        if (playlistName != null) {
          print(
              'SpotifyApi: Successfully fetched playlist: "$playlistName"${ownerName != null ? ' by $ownerName' : ''}');
          return {
            'name': playlistName,
            if (ownerName != null) 'owner': ownerName,
          };
        }

        print('SpotifyApi: Missing playlist name in response');
        return null;
      } else {
        print(
            'SpotifyApi: API request failed: ${response.statusCode} ${response.body}');
        return null;
      }
    } catch (e) {
      print('SpotifyApi: Error fetching playlist info: $e');
      return null;
    }
  }

  /// Get album information from a Spotify URL
  /// Returns a map with 'artist' and 'album' keys, or null if failed
  static Future<Map<String, String>?> getAlbumInfoFromUrl(String url) async {
    final albumId = extractAlbumId(url);
    if (albumId == null) {
      print('SpotifyApi: Could not extract album ID from URL: $url');
      return null;
    }

    print('SpotifyApi: Extracted album ID: $albumId from URL');
    return await getAlbumInfo(albumId);
  }

  /// Get information from any Spotify URL (album, playlist, or track)
  /// Returns a map with appropriate keys based on the resource type:
  /// - Album: {type: 'album', artist: '...', album: '...'}
  /// - Playlist: {type: 'playlist', name: '...', owner: '...' (optional)}
  /// - Track: {type: 'track', artist: '...', track: '...'}
  static Future<Map<String, String>?> getInfoFromUrl(String url) async {
    final resource = extractSpotifyResource(url);
    if (resource == null) {
      print('SpotifyApi: Could not extract resource from URL: $url');
      return null;
    }

    final type = resource['type']!;
    final id = resource['id']!;

    print('SpotifyApi: Extracted $type ID: $id from URL');

    if (type == 'album') {
      final albumInfo = await getAlbumInfo(id);
      if (albumInfo != null) {
        return {
          'type': 'album',
          ...albumInfo,
        };
      }
    } else if (type == 'playlist') {
      final playlistInfo = await getPlaylistInfo(id);
      if (playlistInfo != null) {
        return {
          'type': 'playlist',
          ...playlistInfo,
        };
      }
    } else if (type == 'track') {
      final trackInfo = await getTrackInfo(id);
      if (trackInfo != null) {
        return {
          'type': 'track',
          ...trackInfo,
        };
      }
    }

    return null;
  }
}

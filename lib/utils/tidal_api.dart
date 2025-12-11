import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Tidal Web API integration for fetching album, track, and playlist information.
///
/// Requires TIDAL_CLIENT_ID and TIDAL_CLIENT_SECRET in .env file.
/// Get your credentials at: https://developer.tidal.com/
class TidalApiService {
  static String? _accessToken;
  static DateTime? _tokenExpiry;
  static const String _defaultCountryCode = 'US';

  /// Get TIDAL client ID from build-time env or dotenv
  static String? get _clientId {
    // Priority 1: Build-time environment variable (Production)
    const clientIdFromBuild = String.fromEnvironment('TIDAL_CLIENT_ID');
    if (clientIdFromBuild.isNotEmpty) {
      print('TidalApi: Found clientId from build-time environment');
      return clientIdFromBuild;
    }

    // Priority 2: Local .env fallback (Development)
    try {
      // Debug: Check if dotenv is loaded
      final allKeys = dotenv.env.keys.toList();
      print('TidalApi: dotenv loaded with ${allKeys.length} keys');
      print('TidalApi: Available keys in dotenv: $allKeys');

      // Try to access the key directly to see what happens
      final directAccess = dotenv.env['TIDAL_CLIENT_ID'];
      print(
          'TidalApi: Direct access to dotenv.env[\'TIDAL_CLIENT_ID\']: ${directAccess != null ? "found (${directAccess.length} chars)" : "null"}');

      print('TidalApi: Looking for TIDAL_CLIENT_ID in dotenv...');

      // Check for variations of the key name
      final clientIdFromDotenv = dotenv.env['TIDAL_CLIENT_ID'] ??
          dotenv.env['tidal_client_id'] ??
          dotenv.env['Tidal_Client_Id'];

      if (clientIdFromDotenv != null && clientIdFromDotenv.isNotEmpty) {
        print('TidalApi: Found clientId from dotenv');
        return clientIdFromDotenv;
      } else {
        print(
            'TidalApi: clientId not found in dotenv (value: ${clientIdFromDotenv != null ? "empty string" : "null"})');
        // Debug: Show available keys that contain "tidal" or "client"
        final relevantKeys = allKeys
            .where((key) =>
                key.toLowerCase().contains('tidal') ||
                key.toLowerCase().contains('client'))
            .toList();
        if (relevantKeys.isNotEmpty) {
          print(
              'TidalApi: Available keys containing "tidal" or "client": $relevantKeys');
        }
      }
    } catch (e) {
      print('TidalApi: Error accessing dotenv for clientId: $e');
      return null;
    }
    return null;
  }

  /// Get TIDAL client secret from build-time env or dotenv
  static String? get _clientSecret {
    // Priority 1: Build-time environment variable (Production)
    const clientSecretFromBuild = String.fromEnvironment('TIDAL_CLIENT_SECRET');
    if (clientSecretFromBuild.isNotEmpty) {
      print('TidalApi: Found clientSecret from build-time environment');
      return clientSecretFromBuild;
    }

    // Priority 2: Local .env fallback (Development)
    try {
      print('TidalApi: Looking for TIDAL_CLIENT_SECRET in dotenv...');

      // Check for variations of the key name
      final clientSecretFromDotenv = dotenv.env['TIDAL_CLIENT_SECRET'] ??
          dotenv.env['tidal_client_secret'] ??
          dotenv.env['Tidal_Client_Secret'];

      if (clientSecretFromDotenv != null && clientSecretFromDotenv.isNotEmpty) {
        print('TidalApi: Found clientSecret from dotenv');
        return clientSecretFromDotenv;
      } else {
        print(
            'TidalApi: clientSecret not found in dotenv (value: ${clientSecretFromDotenv != null ? "empty string" : "null"})');
      }
    } catch (e) {
      print('TidalApi: Error accessing dotenv for clientSecret: $e');
      return null;
    }
    return null;
  }

  /// Check if Tidal API credentials are available
  static bool get isAvailable {
    final clientId = _clientId;
    final clientSecret = _clientSecret;
    final available = clientId != null &&
        clientId.isNotEmpty &&
        clientSecret != null &&
        clientSecret.isNotEmpty;
    if (!available) {
      print(
          'TidalApi: Credentials check - clientId: ${clientId != null ? "present" : "null"}, clientSecret: ${clientSecret != null ? "present" : "null"}');
    }
    return available;
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
      final clientId = _clientId;
      final clientSecret = _clientSecret;

      if (clientId == null || clientSecret == null) {
        print(
            'TidalApi: Missing credentials (checked build-time env and dotenv)');
        return null;
      }

      // Encode credentials for Basic Auth
      final credentials = base64Encode(utf8.encode('$clientId:$clientSecret'));

      final response = await http.post(
        Uri.parse('https://auth.tidal.com/v1/oauth2/token'),
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
        print('TidalApi: Successfully obtained access token');
        return _accessToken;
      } else {
        print(
            'TidalApi: Failed to get access token: ${response.statusCode} ${response.body}');
        return null;
      }
    } catch (e) {
      print('TidalApi: Error getting access token: $e');
      return null;
    }
  }

  /// Extract Tidal resource type and ID from URL
  /// Returns a map with 'type' and 'id' keys
  /// Example: https://tidal.com/album/31826314/u
  ///   -> {type: 'album', id: '31826314'}
  static Map<String, String>? extractTidalResource(String url) {
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
      print('TidalApi: Error extracting resource: $e');
      return null;
    }
  }

  /// Fetch album information from Tidal API
  /// Returns a map with 'artist' and 'album' keys
  static Future<Map<String, String>?> getAlbumInfo(String albumId) async {
    try {
      if (!isAvailable) {
        print('TidalApi: API credentials not configured');
        return null;
      }

      final token = await _getAccessToken();
      if (token == null) {
        print('TidalApi: Failed to get access token');
        return null;
      }

      final response = await http.get(
        Uri.parse(
            'https://openapi.tidal.com/v2/albums/$albumId?countryCode=$_defaultCountryCode'),
        headers: {
          'Authorization': 'Bearer $token',
          'accept': 'application/vnd.tidal.v1+json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final resource = data['resource'];

        if (resource == null) {
          print('TidalApi: No resource data in response');
          return null;
        }

        // Extract artist name (use first artist if multiple)
        final artists = resource['artists'] as List<dynamic>?;
        final artistName = artists != null && artists.isNotEmpty
            ? artists[0]['name'] as String?
            : null;

        // Extract album name
        final albumName = resource['title'] as String?;

        if (artistName != null && albumName != null) {
          print(
              'TidalApi: Successfully fetched album: "$albumName" by $artistName');
          return {
            'artist': artistName,
            'album': albumName,
          };
        }

        print('TidalApi: Missing artist or album name in response');
        return null;
      } else {
        print(
            'TidalApi: API request failed: ${response.statusCode} ${response.body}');
        return null;
      }
    } catch (e) {
      print('TidalApi: Error fetching album info: $e');
      return null;
    }
  }

  /// Fetch track information from Tidal API
  /// Returns a map with 'artist' and 'track' keys
  static Future<Map<String, String>?> getTrackInfo(String trackId) async {
    try {
      if (!isAvailable) {
        print('TidalApi: API credentials not configured');
        return null;
      }

      final token = await _getAccessToken();
      if (token == null) {
        print('TidalApi: Failed to get access token');
        return null;
      }

      final response = await http.get(
        Uri.parse(
            'https://openapi.tidal.com/v2/tracks/$trackId?countryCode=$_defaultCountryCode'),
        headers: {
          'Authorization': 'Bearer $token',
          'accept': 'application/vnd.tidal.v1+json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final resource = data['resource'];

        if (resource == null) {
          print('TidalApi: No resource data in response');
          return null;
        }

        // Extract artist name (use first artist if multiple)
        final artists = resource['artists'] as List<dynamic>?;
        final artistName = artists != null && artists.isNotEmpty
            ? artists[0]['name'] as String?
            : null;

        // Extract track name
        final trackName = resource['title'] as String?;

        if (artistName != null && trackName != null) {
          print(
              'TidalApi: Successfully fetched track: "$trackName" by $artistName');
          return {
            'artist': artistName,
            'track': trackName,
          };
        }

        print('TidalApi: Missing artist or track name in response');
        return null;
      } else {
        print(
            'TidalApi: API request failed: ${response.statusCode} ${response.body}');
        return null;
      }
    } catch (e) {
      print('TidalApi: Error fetching track info: $e');
      return null;
    }
  }

  /// Fetch playlist information from Tidal API
  /// Returns a map with 'name' and optionally 'owner' keys
  static Future<Map<String, String>?> getPlaylistInfo(String playlistId) async {
    try {
      if (!isAvailable) {
        print('TidalApi: API credentials not configured');
        return null;
      }

      final token = await _getAccessToken();
      if (token == null) {
        print('TidalApi: Failed to get access token');
        return null;
      }

      final response = await http.get(
        Uri.parse(
            'https://openapi.tidal.com/v2/playlists/$playlistId?countryCode=$_defaultCountryCode'),
        headers: {
          'Authorization': 'Bearer $token',
          'accept': 'application/vnd.tidal.v1+json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final resource = data['resource'];

        if (resource == null) {
          print('TidalApi: No resource data in response');
          return null;
        }

        // Extract playlist name
        final playlistName = resource['title'] as String?;

        // Extract creator/owner name if available
        final creator = resource['creator'] as Map<String, dynamic>?;
        final creatorName = creator?['name'] as String?;

        if (playlistName != null) {
          print(
              'TidalApi: Successfully fetched playlist: "$playlistName"${creatorName != null ? ' by $creatorName' : ''}');
          return {
            'name': playlistName,
            if (creatorName != null) 'owner': creatorName,
          };
        }

        print('TidalApi: Missing playlist name in response');
        return null;
      } else {
        print(
            'TidalApi: API request failed: ${response.statusCode} ${response.body}');
        return null;
      }
    } catch (e) {
      print('TidalApi: Error fetching playlist info: $e');
      return null;
    }
  }

  /// Get information from any Tidal URL (album, playlist, or track)
  /// Returns a map with appropriate keys based on the resource type:
  /// - Album: {type: 'album', artist: '...', album: '...'}
  /// - Playlist: {type: 'playlist', name: '...', owner: '...' (optional)}
  /// - Track: {type: 'track', artist: '...', track: '...'}
  static Future<Map<String, String>?> getInfoFromUrl(String url) async {
    final resource = extractTidalResource(url);
    if (resource == null) {
      print('TidalApi: Could not extract resource from URL: $url');
      return null;
    }

    final type = resource['type']!;
    final id = resource['id']!;

    print('TidalApi: Extracted $type ID: $id from URL');

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

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// YouTube video information from the API
class YouTubeVideoInfo {
  final String title;
  final String description;
  final String channelTitle;
  final String publishedAt;
  final String? duration;
  final int? viewCount;

  YouTubeVideoInfo({
    required this.title,
    required this.description,
    required this.channelTitle,
    required this.publishedAt,
    this.duration,
    this.viewCount,
  });

  factory YouTubeVideoInfo.fromJson(Map<String, dynamic> json) {
    final snippet = json['snippet'] as Map<String, dynamic>;
    final statistics = json['statistics'] as Map<String, dynamic>?;
    final contentDetails = json['contentDetails'] as Map<String, dynamic>?;

    return YouTubeVideoInfo(
      title: snippet['title'] as String,
      description: snippet['description'] as String,
      channelTitle: snippet['channelTitle'] as String,
      publishedAt: snippet['publishedAt'] as String,
      duration: contentDetails?['duration'] as String?,
      viewCount: statistics != null ? int.tryParse(statistics['viewCount'] as String? ?? '') : null,
    );
  }
}

/// Service for interacting with YouTube Data API v3
class YouTubeApiService {
  static String? get apiKey {
    // For production builds, use compile-time environment variable
    const apiKeyFromBuild = String.fromEnvironment('YOUTUBE_API_KEY');
    if (apiKeyFromBuild.isNotEmpty) {
      return apiKeyFromBuild;
    }

    // For local development, try dotenv as fallback
    try {
      final apiKeyFromDotenv = dotenv.env['YOUTUBE_API_KEY'];
      if (apiKeyFromDotenv != null && apiKeyFromDotenv.isNotEmpty) {
        return apiKeyFromDotenv;
      }
    } catch (e) {
      print('YouTubeApiService: Could not access dotenv variables: $e');
    }

    return null;
  }
  static const String baseUrl = 'https://www.googleapis.com/youtube/v3';

  /// Extract video ID from YouTube URL
  static String? extractVideoId(String url) {
    // Handle various YouTube URL formats:
    // https://www.youtube.com/watch?v=VIDEO_ID
    // https://youtu.be/VIDEO_ID
    // https://youtube.com/watch?v=VIDEO_ID
    // https://m.youtube.com/watch?v=VIDEO_ID

    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    // For youtu.be short URLs
    if (uri.host == 'youtu.be') {
      return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    }

    // For standard YouTube URLs
    if (uri.host == 'www.youtube.com' || uri.host == 'youtube.com' || uri.host == 'm.youtube.com') {
      return uri.queryParameters['v'];
    }

    return null;
  }

  /// Fetch video information from YouTube Data API
  static Future<YouTubeVideoInfo?> getVideoInfo(String videoId) async {
    final key = apiKey;
    if (key == null || key.isEmpty) {
      print('YouTubeApiService: No API key configured');
      return null;
    }

    try {
      final url = '$baseUrl/videos?id=$videoId&key=$key&part=snippet,statistics,contentDetails';
      print('YouTubeApiService: Fetching video info for $videoId');

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final items = data['items'] as List<dynamic>?;

        if (items != null && items.isNotEmpty) {
          final videoData = items.first as Map<String, dynamic>;
          final videoInfo = YouTubeVideoInfo.fromJson(videoData);
          print('YouTubeApiService: Successfully fetched title: "${videoInfo.title}"');
          return videoInfo;
        } else {
          print('YouTubeApiService: No video found for ID: $videoId');
          return null;
        }
      } else {
        print('YouTubeApiService: API request failed with status ${response.statusCode}');
        print('YouTubeApiService: Response: ${response.body}');
        return null;
      }
    } catch (e) {
      print('YouTubeApiService: Error fetching video info: $e');
      return null;
    }
  }

  /// Get video info from YouTube URL
  static Future<YouTubeVideoInfo?> getVideoInfoFromUrl(String url) async {
    final videoId = extractVideoId(url);
    if (videoId == null) {
      print('YouTubeApiService: Could not extract video ID from URL: $url');
      return null;
    }

    return getVideoInfo(videoId);
  }

  /// Check if YouTube API is available (has valid API key)
  static bool get isAvailable {
    final key = apiKey;
    return key != null && key.isNotEmpty;
  }
}
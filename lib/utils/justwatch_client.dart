import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class JustWatchClient {
  static const String _identityApiKey =
      'AIzaSyDv6JIzdDvbTBS-JWdR4Kl22UvgWGAyuo8';
  static const String _baseUrl = 'https://apis.justwatch.com/graphql';
  static const Map<String, String> _baseHeaders = {
    'Content-Type': 'application/json',
  };

  String? _deviceId;
  String? _authToken;
  Map<String, String>? _authHeaders;

  /// Generate a JustWatch device ID
  String generateDeviceId({String tag = 'C'}) {
    final random = Random.secure();
    final bytes = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      bytes[i] = random.nextInt(256);
    }

    // Encode to base64 and format like Python
    String jwId = base64Url.encode(bytes);
    jwId = jwId.replaceAll('+', '-').replaceAll('/', '_');

    // Ensure it's exactly 22 characters
    if (jwId.length > 22) {
      jwId = jwId.substring(0, 22);
    } else if (jwId.length < 22) {
      jwId = jwId.padRight(22, '=');
    }

    // Insert the tag at position 16
    jwId = jwId.substring(0, 16) + tag + jwId.substring(17, 22);

    return jwId;
  }

  /// Register device ID with JustWatch
  Future<String> registerDevice(String deviceId) async {
    final payload = {
      'query':
          'mutation RegisterDeviceId { registerDeviceId(input: "$deviceId") { deviceId } }'
    };

    final response = await _apiCall(_baseUrl, _baseHeaders, payload);
    final deviceIdResult = response['data']['registerDeviceId']['deviceId'];

    _deviceId = deviceIdResult;
    _updateAuthHeaders();

    return deviceIdResult;
  }

  /// Login with email and password
  Future<Map<String, dynamic>> login(String email, String password) async {
    final url =
        'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$_identityApiKey';
    final payload = {
      'clientType': 'CLIENT_TYPE_WEB',
      'email': email,
      'password': password,
      'returnSecureToken': true,
    };

    final signinResponse = await _apiCall(url, _baseHeaders, payload);

    // Verify token
    final verifyUrl =
        'https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=$_identityApiKey';
    final verifyPayload = {'idToken': signinResponse['idToken']};

    await _apiCall(verifyUrl, _baseHeaders, verifyPayload);

    _authToken = signinResponse['idToken'];
    _updateAuthHeaders();

    return signinResponse;
  }

  /// Get home modules (no login required)
  Future<List<String>> getHomeModules({
    String country = 'US',
    String language = 'en',
    String appId = '3.9.3-webapp#9fae3ff',
  }) async {
    final payload = _buildHomeModulesPayload(country, language, appId);
    final data =
        await _apiCall(_baseUrl, _authHeaders ?? _baseHeaders, payload);

    final modules = <String>[];
    for (final module in data['data']['discoveryModulesV2']) {
      if (!module.toString().startsWith('__')) {
        modules.add(module.toString());
      }
    }

    return modules;
  }

  /// Get title list (requires login)
  Future<List<JustWatchTitle>> getTitleList({
    String cursor = '',
    String country = 'US',
    String language = 'en',
    int first = 20,
  }) async {
    if (_authToken == null) {
      throw Exception('Authentication required. Please login first.');
    }

    final titles = <JustWatchTitle>[];
    String currentCursor = cursor;

    while (true) {
      final payload = _buildTitleListPayload(
        cursor: currentCursor,
        country: country,
        language: language,
        first: first,
      );

      final data = await _apiCall(_baseUrl, _authHeaders!, payload);
      final titleList = data['data']['titleListV2'];

      for (final edge in titleList['edges']) {
        final node = edge['node'];
        final content = node['content'];

        if (content != null) {
          titles.add(JustWatchTitle.fromJson(node));
        }
      }

      final pageInfo = titleList['pageInfo'];
      if (!pageInfo['hasNextPage']) {
        break;
      }

      currentCursor = pageInfo['endCursor'];
    }

    return titles;
  }

  /// Update authentication headers
  void _updateAuthHeaders() {
    _authHeaders = Map.from(_baseHeaders);
    _authHeaders!['DEVICE-ID'] = _deviceId ?? '';

    if (_authToken != null) {
      _authHeaders!['Authorization'] = 'Bearer $_authToken';
    }
  }

  /// Make API call
  Future<Map<String, dynamic>> _apiCall(
    String url,
    Map<String, String> headers,
    Map<String, dynamic> payload,
  ) async {
    final data = json.encode(payload);

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: data,
      );

      if (response.statusCode != 200) {
        final errorBody = response.body;
        print(
            'API call failed: ${response.statusCode} ${response.reasonPhrase}');
        print('Response body: $errorBody');
        throw Exception(
            'API call failed: ${response.statusCode} ${response.reasonPhrase} - $errorBody');
      }

      final body = json.decode(response.body);

      // Check for GraphQL errors
      if (body['errors'] != null) {
        final errors = body['errors'] as List;
        final errorMessage = errors.map((e) => e['message']).join(', ');
        throw Exception('GraphQL errors: $errorMessage');
      }

      return body;
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('API call error: $e');
    }
  }

  /// Build home modules payload
  Map<String, dynamic> _buildHomeModulesPayload(
      String country, String language, String appId) {
    return {
      'operationName': 'GetHomeModulesV2',
      'variables': {
        'platform': 'WEB',
        'supportedContentTypes': [
          'TITLES',
          'TITLES_PER_PACKAGE',
          'TITLES_RELATED_TO_TITLE',
          'TITLES_ARTICLE',
          'SPORTS',
          'TEXT_RECOMMENDATION'
        ],
        'includeUnreleasedEpisodes': false,
        'excludeTextRecommendationTitle': false,
        'language': language,
        'country': country,
        'watchNowFilter': {
          'packages': ['dnp', 'nfx', 'prv'],
          'withFallback': true,
        },
        'testingMode': false,
        'backdropProfile': 'S1440',
        'format': 'WEBP',
        'allowSponsoredRecommendations': {
          'pageType': 'VIEW_HOME_USER',
          'placement': 'HOME',
          'language': language,
          'country': country,
          'applicationContext': {
            'appID': appId,
            'platform': appId.split('-').last.split('#').first,
            'version': appId.split('-').first,
            'build': appId.split('#').last,
            'isTestBuild': false,
          },
          'appId': appId,
          'platform': 'WEB',
          'supportedFormats': ['IMAGE', 'VIDEO'],
          'supportedObjectTypes': [
            'MOVIE',
            'SHOW',
            'GENERIC_TITLE_LIST',
            'SHOW_SEASON'
          ],
          'alwaysReturnBidID': true,
          'testingModeForceHoldoutGroup': false,
          'testingMode': false,
        }
      },
      'query': '''
        query GetHomeModulesV2(\$country: Country!, \$platform: Platform! = WEB, \$supportedContentTypes: [ModuleContentType!]! = [TITLES, TITLES_PER_PACKAGE, TITLES_RELATED_TO_TITLE, TITLES_ARTICLE, SPORTS, TEXT_RECOMMENDATION], \$language: Language!, \$testingMode: Boolean!, \$format: ImageFormat!, \$backdropProfile: BackdropProfile!, \$watchNowFilter: WatchNowOfferFilter!, \$includeUnreleasedEpisodes: Boolean = false, \$allowSponsoredRecommendations: SponsoredRecommendationsInput, \$excludeTextRecommendationTitle: Boolean = false) {
          discoveryModulesV2(
            country: \$country
            platform: \$platform
            supportedContentTypes: \$supportedContentTypes
            testingMode: \$testingMode
            allowSponsoredRecommendations: \$allowSponsoredRecommendations
          ) {
            sponsoredModule {
              sponsoredAd {
                bidId
                __typename
              }
              module {
                template {
                  technicalName
                  anchor
                  __typename
                }
                translations(language: \$language) {
                  title
                  badge
                  __typename
                }
                __typename
              }
              __typename
            }
            spotlightModules {
              template {
                technicalName
                anchor
                __typename
              }
              translations(language: \$language) {
                title
                badge
                __typename
              }
              __typename
            }
            mainModules {
              template {
                technicalName
                anchor
                __typename
              }
              translations(language: \$language) {
                title
                badge
                __typename
              }
              __typename
            }
            __typename
          }
        }
      '''
    };
  }

  /// Build title list payload
  Map<String, dynamic> _buildTitleListPayload({
    String cursor = '',
    String country = 'US',
    String language = 'en',
    int first = 20,
  }) {
    return {
      'operationName': 'GetTitleListV2',
      'variables': {
        'titleListSortBy': 'LAST_ADDED',
        'first': first,
        'sortRandomSeed': 0,
        'platform': 'WEB',
        'includeOffers': false,
        'titleListFilter': {
          'ageCertifications': [],
          'excludeGenres': [],
          'excludeProductionCountries': [],
          'objectTypes': [],
          'productionCountries': [],
          'subgenres': [],
          'genres': [],
          'packages': [],
          'excludeIrrelevantTitles': false,
          'presentationTypes': [],
          'monetizationTypes': [],
          'includeTitlesWithoutUrl': true
        },
        'watchNowFilter': {'packages': [], 'monetizationTypes': []},
        'language': language,
        'country': country,
        'titleListType': 'WATCHLIST',
        'titleListAfterCursor': cursor,
        'profile': 'S718',
        'backdropProfile': 'S1920',
        'format': 'WEBP'
      },
      'query': '''
        query GetTitleListV2(\$country: Country!, \$titleListFilter: TitleFilter, \$titleListSortBy: TitleListSortingV2! = LAST_ADDED, \$titleListType: TitleListTypeV2!, \$titleListAfterCursor: String, \$watchNowFilter: WatchNowOfferFilter!, \$first: Int! = 10, \$language: Language!, \$sortRandomSeed: Int! = 0, \$profile: PosterProfile, \$backdropProfile: BackdropProfile, \$format: ImageFormat, \$platform: Platform! = WEB, \$includeOffers: Boolean = false) {
          titleListV2(
            after: \$titleListAfterCursor
            country: \$country
            filter: \$titleListFilter
            sortBy: \$titleListSortBy
            first: \$first
            titleListType: \$titleListType
            sortRandomSeed: \$sortRandomSeed
          ) {
            totalCount
            pageInfo {
              startCursor
              endCursor
              hasPreviousPage
              hasNextPage
              __typename
            }
            edges {
              ...WatchlistTitleGraphql
              __typename
            }
            __typename
          }
        }

        fragment WatchlistTitleGraphql on TitleListEdgeV2 {
          cursor
          node {
            __typename
            id
            objectId
            objectType
            offerCount(country: \$country, platform: \$platform)
            offers(country: \$country, platform: \$platform, filter: {preAffiliate: true}) @include(if: \$includeOffers) {
              id
              presentationType
              monetizationType
              retailPrice(language: \$language)
              type
              package {
                id
                packageId
                clearName
                __typename
              }
              standardWebURL
              preAffiliatedStandardWebURL
              elementCount
              deeplinkRoku: deeplinkURL(platform: ROKU_OS)
              __typename
            }
            content(country: \$country, language: \$language) {
              title
              fullPath
              originalReleaseYear
              shortDescription
              scoring {
                imdbScore
                imdbVotes
                tmdbScore
                tmdbPopularity
                __typename
              }
              posterUrl(profile: \$profile, format: \$format)
              backdrops(profile: \$backdropProfile, format: \$format) {
                backdropUrl
                __typename
              }
              upcomingReleases(releaseTypes: [DIGITAL]) {
                releaseDate
                __typename
              }
              isReleased
              __typename
            }
            likelistEntry {
              createdAt
              __typename
            }
            dislikelistEntry {
              createdAt
              __typename
            }
            watchlistEntryV2 {
              createdAt
              __typename
            }
            customlistEntries {
              createdAt
              __typename
            }
            watchNowOffer(country: \$country, platform: \$platform, filter: \$watchNowFilter) {
              id
              standardWebURL
              preAffiliatedStandardWebURL
              package {
                id
                packageId
                clearName
                __typename
              }
              presentationType
              monetizationType
              __typename
            }
            ... on Movie {
              seenlistEntry {
                createdAt
                __typename
              }
              __typename
            }
            ... on Show {
              tvShowTrackingEntry {
                createdAt
                __typename
              }
              seenState(country: \$country) {
                seenEpisodeCount
                releasedEpisodeCount
                progress
                caughtUp
                lastSeenEpisodeNumber
                lastSeenSeasonNumber
                __typename
              }
              __typename
            }
          }
          __typename
        }
      '''
    };
  }
}

/// Model for JustWatch title data
class JustWatchTitle {
  final String id;
  final String objectId;
  final String objectType;
  final String title;
  final String fullPath;
  final int? originalReleaseYear;
  final String? shortDescription;
  final double? imdbScore;
  final int? imdbVotes;
  final double? tmdbScore;
  final double? tmdbPopularity;
  final String? posterUrl;
  final List<String> backdropUrls;
  final bool isReleased;
  final String? watchNowUrl;
  final String? packageName;
  final int? seenEpisodeCount;
  final int? releasedEpisodeCount;
  final double? progress;
  final bool? caughtUp;
  final int? lastSeenEpisodeNumber;
  final int? lastSeenSeasonNumber;

  JustWatchTitle({
    required this.id,
    required this.objectId,
    required this.objectType,
    required this.title,
    required this.fullPath,
    this.originalReleaseYear,
    this.shortDescription,
    this.imdbScore,
    this.imdbVotes,
    this.tmdbScore,
    this.tmdbPopularity,
    this.posterUrl,
    this.backdropUrls = const [],
    this.isReleased = true,
    this.watchNowUrl,
    this.packageName,
    this.seenEpisodeCount,
    this.releasedEpisodeCount,
    this.progress,
    this.caughtUp,
    this.lastSeenEpisodeNumber,
    this.lastSeenSeasonNumber,
  });

  factory JustWatchTitle.fromJson(Map<String, dynamic> json) {
    final content = json['content'] as Map<String, dynamic>? ?? {};
    final scoring = content['scoring'] as Map<String, dynamic>? ?? {};
    final watchNowOffer = json['watchNowOffer'] as Map<String, dynamic>?;
    final package = watchNowOffer?['package'] as Map<String, dynamic>?;
    final backdrops = content['backdrops'] as List<dynamic>? ?? [];
    final seenState = json['seenState'] as Map<String, dynamic>? ?? {};

    return JustWatchTitle(
      id: json['id']?.toString() ?? '',
      objectId: json['objectId']?.toString() ?? '',
      objectType: json['objectType']?.toString() ?? '',
      title: content['title']?.toString() ?? 'Unknown Title',
      fullPath: content['fullPath']?.toString() ?? '',
      originalReleaseYear: content['originalReleaseYear'] as int?,
      shortDescription: content['shortDescription']?.toString(),
      imdbScore: scoring['imdbScore']?.toDouble(),
      imdbVotes: scoring['imdbVotes'] as int?,
      tmdbScore: scoring['tmdbScore']?.toDouble(),
      tmdbPopularity: scoring['tmdbPopularity']?.toDouble(),
      posterUrl: content['posterUrl']?.toString(),
      backdropUrls: backdrops
          .map((b) => b['backdropUrl']?.toString() ?? '')
          .where((url) => url.isNotEmpty)
          .toList(),
      isReleased: content['isReleased'] as bool? ?? true,
      watchNowUrl: watchNowOffer?['standardWebURL']?.toString(),
      packageName: package?['clearName']?.toString(),
      seenEpisodeCount: seenState['seenEpisodeCount'] as int?,
      releasedEpisodeCount: seenState['releasedEpisodeCount'] as int?,
      progress: seenState['progress']?.toDouble(),
      caughtUp: seenState['caughtUp'] as bool?,
      lastSeenEpisodeNumber: seenState['lastSeenEpisodeNumber'] as int?,
      lastSeenSeasonNumber: seenState['lastSeenSeasonNumber'] as int?,
    );
  }

  /// Get the full JustWatch URL
  String get justWatchUrl => 'https://www.justwatch.com$fullPath';

  /// Get IMDB URL if IMDB ID is available
  String? get imdbUrl {
    if (objectId.isNotEmpty) {
      return 'https://www.imdb.com/title/$objectId/';
    }
    return null;
  }

  @override
  String toString() => 'JustWatchTitle(title: $title, objectType: $objectType)';
}

class UrlCanonicalizer {
  static const Set<String> _trackingParams = {
    'utm_source',
    'utm_medium',
    'utm_campaign',
    'utm_term',
    'utm_content',
    'fbclid',
    'gclid',
    'ref',
    'source',
    '_campaign',
    'si',
  };

  static String extractUrl(String input) {
    final trimmed = input.trim();
    final htmlMatch =
        RegExp(r'<a[^>]+href="([^"]+)"[^>]*>', caseSensitive: false)
            .firstMatch(trimmed);
    return htmlMatch?.group(1)?.trim() ?? trimmed;
  }

  static String normalize(String input) {
    final extracted = extractUrl(input);
    final uri = Uri.tryParse(extracted);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return extracted;
    }

    if (uri.host.contains('tidal.com')) {
      String path = uri.path;
      if (path.endsWith('/u/')) {
        path = path.substring(0, path.length - 3);
      } else if (path.endsWith('/u')) {
        path = path.substring(0, path.length - 2);
      }
      if (path.endsWith('/') && path.length > 1) {
        path = path.substring(0, path.length - 1);
      }
      return Uri(
        scheme: uri.scheme,
        userInfo: uri.userInfo,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: path,
        queryParameters:
            uri.queryParameters.isNotEmpty ? uri.queryParameters : null,
      ).toString();
    }

    if (uri.host.contains('justwatch.com')) {
      String path = uri.path;
      if (path.endsWith('/u/')) {
        path = path.substring(0, path.length - 3);
      } else if (path.endsWith('/u')) {
        path = path.substring(0, path.length - 2);
      }
      return Uri(
        scheme: uri.scheme,
        userInfo: uri.userInfo,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: path,
      ).toString();
    }

    if (uri.host.contains('imdb.com')) {
      final idMatch = RegExp(r'/title/(tt\d+)').firstMatch(uri.path);
      final imdbId = idMatch?.group(1);
      if (imdbId == null) return extracted;
      return Uri(
        scheme: uri.scheme,
        userInfo: uri.userInfo,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: '/title/$imdbId/',
      ).toString();
    }

    final cleanParams = Map<String, String>.from(uri.queryParameters)
      ..removeWhere((key, _) => _trackingParams.contains(key));

    // Pass the (possibly empty) map — empty map removes all query params.
    // Passing null would preserve the original query string.
    final cleanUri = uri.replace(queryParameters: cleanParams);

    var result = cleanUri.toString();
    if (result.endsWith('?')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}

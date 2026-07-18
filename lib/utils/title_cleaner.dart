/// Cleans boilerplate out of shared/fetched page titles so a task gets the
/// essential name. Two layers: per-site rules keyed by domain (most precise),
/// then a general fallback list tried for any site.
///
/// Example: Tidal shares arrive as "Listen to <album> on your streaming
/// service" → we extract "<album>".
class TitleCleaner {
  /// Per-site rules: a domain substring → rules applied in order.
  static final Map<String, List<_Rule>> _siteRules = {
    'tidal.com': [
      _Rule.extract(RegExp(r'^Listen to (.+?) on .+$', caseSensitive: false)),
    ],
    'justwatch.com': [
      // "Lolita streaming: where to watch movie online?" -> "Lolita".
      _Rule.extract(RegExp(r'^(.+?) streaming:.*$', caseSensitive: false)),
    ],
    'spotify.com': [
      _Rule.extract(RegExp(r'^Listen to (.+?) on .+$', caseSensitive: false)),
      _Rule.strip(RegExp(r'\s*[|–-]\s*Spotify$', caseSensitive: false)),
    ],
    'music.apple.com': [
      _Rule.strip(RegExp(r'\s+on Apple Music$', caseSensitive: false)),
    ],
    'youtube.com': [
      _Rule.strip(RegExp(r'\s*[-–]\s*YouTube$', caseSensitive: false)),
    ],
    'youtu.be': [
      _Rule.strip(RegExp(r'\s*[-–]\s*YouTube$', caseSensitive: false)),
    ],
  };

  /// General fallbacks, tried for every title after any site rules. Kept
  /// conservative so they don't mangle legitimate titles.
  static final List<_Rule> _generalRules = [
    // "Listen to X on <service>" / "Watch X on <service>" → X.
    _Rule.extract(RegExp(
        r'^(?:Listen to|Watch|Stream) (.+?) on (?:your streaming service|[A-Z][\w.& ]+)\.?$',
        caseSensitive: false)),
    // Trailing " | Site" / " - Site" boilerplate for a single trailing word.
    _Rule.strip(RegExp(r'\s*[|–]\s*[\w.& ]{1,20}$')),
  ];

  /// Clean [title] for the page at [url] (used to pick the site rules).
  static String clean(String title, {String? url}) {
    var t = title.trim();
    if (t.isEmpty) return t;

    final host =
        (url != null ? Uri.tryParse(url)?.host : null)?.toLowerCase() ?? '';

    for (final entry in _siteRules.entries) {
      if (host.contains(entry.key)) {
        for (final rule in entry.value) {
          t = rule.apply(t);
        }
      }
    }
    for (final rule in _generalRules) {
      t = rule.apply(t);
    }

    final cleaned = t.trim();
    // Never reduce a title to nothing — fall back to the original.
    return cleaned.isEmpty ? title.trim() : cleaned;
  }
}

/// A single title transform: either extract capture group 1, or strip the match.
class _Rule {
  final RegExp pattern;
  final bool extractGroup1;

  const _Rule._(this.pattern, this.extractGroup1);
  factory _Rule.extract(RegExp p) => _Rule._(p, true);
  factory _Rule.strip(RegExp p) => _Rule._(p, false);

  String apply(String s) {
    final match = pattern.firstMatch(s);
    if (match == null) return s;
    if (extractGroup1 && match.groupCount >= 1 && match.group(1) != null) {
      return match.group(1)!.trim();
    }
    return s.replaceAll(pattern, '').trim();
  }
}

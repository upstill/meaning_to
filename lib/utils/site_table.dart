/// Table-driven site configuration: fetch strategies and title extraction.
///
/// [kSiteTable] is the single source of truth.  Entries are evaluated
/// top-to-bottom; the first whose [SiteEntry.domain] the URL host contains
/// wins.  The final entry (domain: '') is the default fallback.
///
/// Wiring to link_processor.dart is a follow-on task — this file is pure
/// constants and introduces no runtime dependencies.

// ── Enums ─────────────────────────────────────────────────────────────────

/// Which runtime environment is fetching the URL.
/// 'supabase' is reserved for future edge-function use; entries may omit it
/// (empty list) until that context is wired up.
enum FetchContext { web, native, test, supabase }

/// A single fetch method to attempt.  Methods in a context list are tried
/// in order; the first that returns a valid response wins.
enum FetchMethod {
  direct, // HTTP GET with browser User-Agent
  allorigins, // https://api.allorigins.win/raw?url=
  corsproxy, // https://corsproxy.io/?url=
  corsanywhere, // https://cors-anywhere.herokuapp.com/
  youtubeApi, // YouTube Data API v3 (YouTube domain only)
}

/// How to locate the title text within the fetched HTML document.
enum TitleSource {
  metaName, // <meta name="X" content="...">   — selector = name value
  metaProperty, // <meta property="X" content="..."> — selector = property value
  cssText, // CSS selector → element.innerText (all descendants)
  cssDirectText, // CSS selector → direct text nodes only (skips nested elements)
  htmlTitle, // <title> tag text
  h1, // first <h1> text
  youtubeApi, // title returned directly by the YouTube API call
}

// ── TitleStrategy ──────────────────────────────────────────────────────────

class TitleStrategy {
  final TitleSource source;
  final String? selector;

  const TitleStrategy.metaName(String name)
      : source = TitleSource.metaName,
        selector = name;
  const TitleStrategy.metaProperty(String prop)
      : source = TitleSource.metaProperty,
        selector = prop;
  const TitleStrategy.css(String sel)
      : source = TitleSource.cssText,
        selector = sel;
  const TitleStrategy.cssDirectText(String sel)
      : source = TitleSource.cssDirectText,
        selector = sel;
  const TitleStrategy.htmlTitle()
      : source = TitleSource.htmlTitle,
        selector = null;
  const TitleStrategy.h1()
      : source = TitleSource.h1,
        selector = null;
  const TitleStrategy.youtubeApi()
      : source = TitleSource.youtubeApi,
        selector = null;
}

// ── SiteEntry ──────────────────────────────────────────────────────────────

class SiteEntry {
  final String domain; // matched via uri.host.contains(domain)
  final String displayName;

  /// Per-context ordered fetch methods.
  /// First method that returns a usable response wins.
  /// Omit a context key to fall through to the default entry.
  final Map<FetchContext, List<FetchMethod>> fetch;

  /// Ordered title extraction strategies.
  /// First strategy that yields a non-empty string wins.
  final List<TitleStrategy> title;

  /// Regex patterns applied in sequence to strip suffixes from the title.
  /// Each is matched case-insensitively and replaced with ''.
  final List<String> stripSuffixes;

  const SiteEntry({
    required this.domain,
    required this.displayName,
    required this.fetch,
    required this.title,
    this.stripSuffixes = const [],
  });
}

// ── kSiteTable ─────────────────────────────────────────────────────────────

/// Evaluated top-to-bottom; first entry whose domain matches wins.
/// The final entry (domain: '') is the default fallback.
const List<SiteEntry> kSiteTable = [
  SiteEntry(
    domain: 'justwatch.com',
    displayName: 'JustWatch',
    fetch: {
      FetchContext.web: [FetchMethod.allorigins, FetchMethod.corsproxy],
      FetchContext.native: [FetchMethod.direct],
      FetchContext.test: [FetchMethod.direct],
    },
    title: [
      TitleStrategy.cssDirectText('h1.title-detail-hero__details__title'),
      TitleStrategy.h1(),
    ],
    stripSuffixes: [
      r'\s*\(\d{4}\).*$', // remove year and trailing text
      r'\s*streaming:?\s*where to watch.*$', // remove streaming footer text
    ],
  ),

  SiteEntry(
    domain: 'letterboxd.com',
    displayName: 'Letterboxd',
    fetch: {
      FetchContext.web: [FetchMethod.allorigins, FetchMethod.corsproxy],
      FetchContext.native: [FetchMethod.direct],
      FetchContext.test: [FetchMethod.direct],
    },
    title: [
      TitleStrategy.css('h1.headline-1'),
      TitleStrategy.h1(),
    ],
    stripSuffixes: [r'\s*\(\d{4}\).*$'],
  ),

  SiteEntry(
    domain: 'boxd.it',
    displayName: 'Letterboxd (short link)',
    fetch: {
      FetchContext.web: [FetchMethod.allorigins, FetchMethod.corsproxy],
      FetchContext.native: [FetchMethod.direct],
      FetchContext.test: [FetchMethod.direct],
    },
    title: [
      TitleStrategy.css('h1.headline-1'),
      TitleStrategy.h1(),
    ],
    stripSuffixes: [r'\s*\(\d{4}\).*$'],
  ),

  SiteEntry(
    domain: 'youtube.com',
    displayName: 'YouTube',
    fetch: {
      FetchContext.web: [
        FetchMethod.youtubeApi,
        FetchMethod.corsproxy,
        FetchMethod.allorigins,
      ],
      FetchContext.native: [FetchMethod.youtubeApi, FetchMethod.direct],
      FetchContext.test: [FetchMethod.youtubeApi, FetchMethod.direct],
    },
    title: [
      TitleStrategy.youtubeApi(),
      TitleStrategy.metaName('title'),
      TitleStrategy.htmlTitle(),
    ],
    stripSuffixes: [r'\s*-\s*YouTube\s*$'],
  ),

  SiteEntry(
    domain: 'ted.com',
    displayName: 'TED',
    fetch: {
      FetchContext.web: [FetchMethod.allorigins, FetchMethod.corsproxy],
      FetchContext.native: [FetchMethod.direct],
      FetchContext.test: [FetchMethod.direct],
    },
    title: [
      TitleStrategy.metaName('title'),
      TitleStrategy.metaProperty('og:title'),
    ],
  ),

  SiteEntry(
    domain: 'tidal.com',
    displayName: 'TIDAL',
    fetch: {
      FetchContext.web: [FetchMethod.allorigins, FetchMethod.corsproxy],
      FetchContext.native: [FetchMethod.direct],
      FetchContext.test: [FetchMethod.direct],
    },
    title: [
      TitleStrategy.css('h2.wave-text-title-bold'),
      TitleStrategy.htmlTitle(),
    ],
  ),

  SiteEntry(
    domain: 'imdb.com',
    displayName: 'IMDb',
    fetch: {
      FetchContext.web: [FetchMethod.direct, FetchMethod.allorigins],
      FetchContext.native: [FetchMethod.direct],
      FetchContext.test: [FetchMethod.direct],
    },
    title: [
      TitleStrategy.htmlTitle(), // "The Shawshank Redemption (1994) - IMDb"
      TitleStrategy.metaProperty('og:title'),
    ],
    stripSuffixes: [r'\s*\(.*$'], // strips "(1994) - IMDb" and everything after
  ),

  SiteEntry(
    domain: 'amazon.com',
    displayName: 'Amazon',
    fetch: {
      FetchContext.web: [FetchMethod.allorigins, FetchMethod.corsproxy],
      FetchContext.native: [FetchMethod.direct],
      FetchContext.test: [
        FetchMethod.allorigins,
      ], // direct returns bot-detection page
    },
    title: [
      TitleStrategy.metaName('title'),
      TitleStrategy.metaProperty('og:title'),
    ],
  ),

  // ── Default (must be last) ───────────────────────────────────────────────
  SiteEntry(
    domain: '', // matches everything
    displayName: 'Generic',
    fetch: {
      FetchContext.web: [FetchMethod.direct, FetchMethod.allorigins],
      FetchContext.native: [FetchMethod.direct],
      FetchContext.test: [FetchMethod.direct],
    },
    title: [
      TitleStrategy.metaProperty('og:title'),
      TitleStrategy.metaName('title'),
      TitleStrategy.htmlTitle(),
      TitleStrategy.h1(),
    ],
  ),
];

// ── SiteTable lookup helper ────────────────────────────────────────────────

class SiteTable {
  /// Returns the first entry whose domain the URL host contains,
  /// or the default (last) entry.
  static SiteEntry entryForUrl(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    return kSiteTable.firstWhere(
      (e) => e.domain.isNotEmpty && host.contains(e.domain),
      orElse: () => kSiteTable.last,
    );
  }

  /// Ordered fetch methods for [url] in [context].
  static List<FetchMethod> fetchMethodsFor(String url, FetchContext context) =>
      entryForUrl(url).fetch[context] ?? [];
}

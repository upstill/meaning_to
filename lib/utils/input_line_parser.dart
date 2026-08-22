import 'package:meaning_to/utils/link_processor.dart';
import 'package:meaning_to/utils/text_importer.dart';

/// The result of parsing a single input line into the pieces every task-creation
/// path needs. Pure data — no network, no database.
class ParsedLine {
  /// The task title, taken from the text that remained after the link was
  /// removed. Falls back to [linkTitle] when there was no other text; may be
  /// empty (the enrich step then fills it from the fetched page title).
  final String headline;

  /// Optional notes parsed out of the remaining text (a "Title: notes" split or
  /// a trailing "(parenthetical)").
  final String? notes;

  /// The whole remaining text after the link was removed (whitespace-collapsed),
  /// BEFORE the colon/parenthetical split into [headline] + [notes]. Callers that
  /// carry only a single title string (e.g. the share pipeline) use this so the
  /// notes half isn't dropped. Empty when the line was only a link.
  final String rawTitle;

  /// The URL extracted from the line (bare URL, `<a>` href, or markdown target),
  /// or null when the line carried no link.
  final String? url;

  /// The label that travelled with the link (the `<a>` text or markdown `[label]`),
  /// used for the link's display title and as a headline fallback. Null for a
  /// bare URL (the page title is fetched later).
  final String? linkTitle;

  /// True when the line began with a checked checklist box (`[x]`).
  final bool finished;

  const ParsedLine({
    required this.headline,
    this.notes,
    this.rawTitle = '',
    this.url,
    this.linkTitle,
    this.finished = false,
  });

  bool get hasUrl => url != null && url!.isNotEmpty;

  /// The link as stored on a Task: `<a href="url">title</a>`. Uses [linkTitle]
  /// when present, else [fallbackTitle] (typically the headline or fetched
  /// title), else the URL itself. Returns null when there is no URL.
  String? htmlLink({String? fallbackTitle}) {
    if (!hasUrl) return null;
    final label = (linkTitle != null && linkTitle!.isNotEmpty)
        ? linkTitle!
        : (fallbackTitle != null && fallbackTitle.isNotEmpty
            ? fallbackTitle
            : url!);
    return '<a href="$url">$label</a>';
  }

  @override
  String toString() =>
      'ParsedLine(headline: "$headline", notes: $notes, url: $url, '
      'linkTitle: $linkTitle, finished: $finished)';
}

/// The single, shared "Step 1/2" for turning a line of input into a task's
/// parts, used by every entry point (incoming share, New Task headline paste,
/// multi-line/list import, and the future Home paste action).
///
/// The contract, in order:
///   1. strip a leading checklist checkbox (`[x]`/`[ ]`) → [ParsedLine.finished];
///   2. strip a leading markdown list marker (`- ` / `* `);
///   3. extract exactly one link — an HTML `<a>` tag, a markdown `[t](u)`, or a
///      bare `http(s)://…` URL — hold its URL + label, and REMOVE it from the line;
///   4. process the remaining text into headline + notes (a `Title: notes` split,
///      else a trailing `(parenthetical)` → notes);
///   5. if no text remained, fall back to the link's label as the headline.
class InputLineParser {
  // <a ... href="URL" ...>LABEL</a>  (non-greedy label, case-insensitive, dotAll)
  static final RegExp _anchorRe = RegExp(
    r'<a\s[^>]*?href="([^"]*)"[^>]*>(.*?)</a>',
    caseSensitive: false,
    dotAll: true,
  );

  // [LABEL](URL) markdown link.
  static final RegExp _markdownRe = RegExp(r'\[([^\]]+)\]\(([^)]*)\)');

  // A bare URL.
  static final RegExp _bareUrlRe = RegExp(r'https?://[^\s]+');

  /// Parse [line] into a [ParsedLine]. Pure; never touches the network.
  static ParsedLine parse(String line) {
    // 1. Checklist checkbox → finished.
    final checkbox = TextImporter.stripChecklistCheckbox(line);
    final bool finished = checkbox.done;
    var rest = checkbox.text.trim();

    // 2. Leading markdown list marker.
    if (rest.startsWith('- ') || rest.startsWith('* ')) {
      rest = rest.substring(2).trim();
    }

    String? url;
    String? linkTitle;

    // 3. Extract one link, by priority: <a> tag → markdown → bare URL.
    // 3a. Whole-line HTML link that is malformed (…<a> or missing </a>): repair
    // then treat the whole line as the link, matching prior behaviour.
    if (rest.startsWith('<a href="') &&
        rest.contains('">') &&
        !_anchorRe.hasMatch(rest)) {
      var html = rest;
      if (html.endsWith('<a>')) {
        html = html.replaceAll(RegExp(r'<a>$'), '</a>');
      } else if (!html.endsWith('</a>')) {
        html = html.contains('<a>') ? html.replaceAll('<a>', '</a>') : '$html</a>';
      }
      final (u, t) = LinkProcessor.parseHtmlLink(html);
      if (u != html) {
        url = u;
        linkTitle = (t != null && t.isNotEmpty) ? t : null;
        rest = '';
      }
    }

    // 3b. Well-formed <a> tag anywhere in the line.
    if (url == null) {
      final m = _anchorRe.firstMatch(rest);
      if (m != null) {
        url = m.group(1);
        final label = (m.group(2) ?? '').trim();
        linkTitle = label.isNotEmpty ? label : null;
        rest = (rest.substring(0, m.start) + rest.substring(m.end)).trim();
      }
    }

    // 3c. Markdown link.
    if (url == null) {
      final m = _markdownRe.firstMatch(rest);
      if (m != null) {
        final u = (m.group(2) ?? '').trim();
        final label = (m.group(1) ?? '').trim();
        if (u.isNotEmpty) {
          url = u;
          linkTitle = label.isNotEmpty ? label : null;
          rest = (rest.substring(0, m.start) + rest.substring(m.end)).trim();
        }
      }
    }

    // 3d. Bare URL.
    if (url == null) {
      final m = _bareUrlRe.firstMatch(rest);
      if (m != null) {
        // Strip trailing punctuation from the URL, but remove the WHOLE matched
        // span from the text (the match may include that trailing punctuation).
        url = m.group(0)!.replaceAll(RegExp(r'[.,;:!?]+$'), '');
        rest = (rest.substring(0, m.start) + rest.substring(m.end)).trim();
      }
    }

    // 4. Remaining text → headline + notes.
    rest = rest.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Removing a link often strands the separator that joined it to the title,
    // e.g. "Title (AQ) - <url>" → "Title (AQ) -". Trim a trailing/leading
    // separator (- : | – —) left behind.
    if (url != null) {
      rest = rest
          .replaceAll(RegExp(r'\s*[-:|–—]\s*$'), '')
          .replaceAll(RegExp(r'^\s*[-:|–—]\s*'), '')
          .trim();
    }
    final String rawTitle = rest;
    String headline = rest;
    String? notes;

    // Notes come only from an explicit "Title: notes" colon split. A trailing
    // parenthetical (e.g. an abbreviation like "(AQ)") stays part of the title.
    if (rest.isNotEmpty) {
      final colon = rest.indexOf(': ');
      if (colon > 0) {
        headline = rest.substring(0, colon).trim();
        final after = rest.substring(colon + 2).trim();
        notes = after.isNotEmpty ? after : null;
      }
    }

    // 5. Fall back to the link's label when no other text remained.
    if (headline.isEmpty && linkTitle != null) {
      headline = linkTitle;
    }

    return ParsedLine(
      headline: headline,
      notes: notes,
      rawTitle: rawTitle,
      url: url,
      linkTitle: linkTitle,
      finished: finished,
    );
  }
}

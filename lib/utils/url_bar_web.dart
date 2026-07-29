import 'dart:html' as html;

/// Removes [keys] from the browser address bar's query string via the History
/// API (replaceState — no navigation, no reload), so consumed launch params like
/// ?share= / ?invite= can't be re-read (e.g. on reload) and re-stashed.
void stripUrlQueryParams(List<String> keys) {
  final uri = Uri.parse(html.window.location.href);
  if (keys.every((k) => !uri.queryParameters.containsKey(k))) return;

  final remaining = Map<String, String>.from(uri.queryParameters)
    ..removeWhere((k, _) => keys.contains(k));

  // Reconstruct explicitly. (Uri.replace(queryParameters: null) does NOT clear
  // the query — null means "leave unchanged" — so build the string ourselves.)
  final buf = StringBuffer('${uri.scheme}://${uri.authority}${uri.path}');
  if (remaining.isNotEmpty) {
    buf.write('?');
    buf.write(remaining.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&'));
  }
  if (uri.fragment.isNotEmpty) buf.write('#${uri.fragment}');

  html.window.history.replaceState(null, '', buf.toString());
}

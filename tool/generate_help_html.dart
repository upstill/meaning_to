// Generates web/help.html from the single source docs/help.md.
//
//   dart run tool/generate_help_html.dart
//
// Run automatically by build_all.sh before `flutter build web`. Prose sections
// become <details> accordions; the app-only {{ideas-for-using}} section is
// skipped (it's interactive, app-only). Pure Dart — imports only the Flutter-
// free parser in lib/utils/help_markdown.dart.
import 'dart:io';

import 'package:meaning_to/utils/help_markdown.dart';

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

const _head = r'''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>RouzMe — Help</title>
  <link rel="icon" type="image/png" href="favicon.png"/>
  <style>
    :root { --blue: #2196F3; --ink: #1a1a1a; --muted: #555; }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      color: var(--ink);
      line-height: 1.6;
      background: #fff;
    }
    .wrap { max-width: 760px; margin: 0 auto; padding: 40px 20px 80px; }
    header { border-bottom: 3px solid var(--blue); padding-bottom: 16px; margin-bottom: 24px; }
    h1 { color: var(--blue); font-size: 2rem; margin: 0; }
    details {
      border: 1px solid #e2e2e2;
      border-radius: 8px;
      margin-bottom: 12px;
      overflow: hidden;
    }
    summary {
      cursor: pointer;
      padding: 14px 16px;
      font-size: 1.15rem;
      font-weight: 600;
      background: #f7f9fb;
      list-style: none; /* hide default marker (Firefox) */
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
    }
    summary::-webkit-details-marker { display: none; } /* hide default marker (Safari/Chrome) */
    /* Chevron drawn from two borders: points down (expand), rotates up (collapse). */
    summary::after {
      content: "";
      flex: none;
      width: 12px;
      height: 12px;
      margin: 0 6px 6px 0;
      border-right: 3px solid var(--blue);
      border-bottom: 3px solid var(--blue);
      transform: rotate(45deg);
      transition: transform 0.2s ease;
    }
    details[open] summary::after {
      transform: rotate(-135deg);
      margin: 6px 6px 0 0;
    }
    summary:hover { background: #eef4fa; }
    .body { padding: 4px 20px 16px; }
    .body p { margin: 12px 0; }
    ul { padding-left: 1.25rem; }
    li { margin-bottom: 4px; }
    .steps { margin: 12px 0; }
    .step { display: flex; gap: 8px; margin-bottom: 4px; }
    .step .marker { flex: none; min-width: 1.7em; font-variant-numeric: tabular-nums; }
    a { color: var(--blue); }
    pre {
      background: #f4f4f4;
      border-radius: 6px;
      padding: 12px;
      overflow-x: auto;
      font-size: 0.85rem;
      line-height: 1.4;
    }
    code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
    .shot { max-width: 100%; height: auto; border-radius: 8px; border: 1px solid #e2e2e2; margin: 8px 0; }
    footer { margin-top: 40px; color: var(--muted); font-size: 0.9rem; text-align: center; }
  </style>
</head>
<body>
''';

const _footer = '''    <footer>
      Need more help? Contact us at
      <a href="mailto:support@rouzme.com">support@rouzme.com</a><br>
      © 2026 RouzMe · <a href="https://rouzme.com">rouzme.com</a>
    </footer>
  </div>
</body>
</html>
''';

void main() {
  final doc = parseHelpMarkdown(File('docs/help.md').readAsStringSync());

  final b = StringBuffer()
    ..write(_head)
    ..writeln('  <div class="wrap">')
    ..writeln('    <header><h1>${_esc(doc.title)}</h1></header>')
    ..writeln();

  var first = true;
  var emitted = 0;
  for (final section in doc.sections) {
    if (section.isAppOnly) continue; // interactive Ideas section: app-only
    final open = first ? ' open' : '';
    first = false;
    emitted++;
    b
      ..writeln('    <details$open>')
      ..writeln('      <summary>${_esc(section.title)}</summary>')
      ..writeln('      <div class="body">')
      ..write(blocksToHtml(section.blocks))
      ..writeln('      </div>')
      ..writeln('    </details>')
      ..writeln();
  }

  b.write(_footer);
  File('web/help.html').writeAsStringSync(b.toString());
  stdout.writeln('Generated web/help.html ($emitted sections) from docs/help.md');
}

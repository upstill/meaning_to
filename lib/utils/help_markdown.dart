/// Minimal Markdown for RouzMe Help — the single source is `docs/help.md`, and
/// this pure-Dart module parses it into a small block model consumed by BOTH the
/// in-app renderer (lib/widgets/help_body.dart) and the static-page generator
/// (tool/generate_help_html.dart). No Flutter imports here so the `tool/` script
/// can use it.
///
/// Supported subset (all that docs/help.md needs):
///   `# Title`            page title (once)
///   `## Section`         accordion section heading
///   blank-line paragraphs, `- ` bullets, `1.` ordered lists, ```fenced code```,
///   inline `**bold**` and `[text](url)`.
///   A lone `{{ideas-for-using}}` line marks the app-only interactive section.
library;

/// An inline run: plain text, **bold**, a [link](href), or a named `{{icon}}`
/// (e.g. `{{share-icon}}`, `{{rouzme-icon}}` — see the renderers for the set).
class HelpInline {
  final String text;
  final bool bold;
  final String? href; // non-null => hyperlink
  final String? icon; // non-null => inline icon token name
  const HelpInline(this.text, {this.bold = false, this.href, this.icon});
}

sealed class HelpBlock {
  const HelpBlock();
}

class HelpParagraph extends HelpBlock {
  final List<HelpInline> spans;
  const HelpParagraph(this.spans);
}

class HelpBullets extends HelpBlock {
  final List<List<HelpInline>> items;
  const HelpBullets(this.items);
}

class HelpOrderedItem {
  final String marker; // literal marker as authored, e.g. "1", "4a"
  final List<HelpInline> spans;
  const HelpOrderedItem(this.marker, this.spans);
}

class HelpOrdered extends HelpBlock {
  final List<HelpOrderedItem> items;
  const HelpOrdered(this.items);
}

class HelpCode extends HelpBlock {
  final String text;
  const HelpCode(this.text);
}

/// A block image `![alt](src)`. [src] is a filename that lives in `web/` (served
/// at the site root; the app loads it as the bundled asset `web/<src>`).
class HelpImage extends HelpBlock {
  final String alt;
  final String src;
  const HelpImage(this.alt, this.src);
}

/// Placeholder for the app-only interactive "Ideas for Using" widget.
class HelpIdeasToken extends HelpBlock {
  const HelpIdeasToken();
}

class HelpSection {
  final String title;
  final List<HelpBlock> blocks;
  const HelpSection(this.title, this.blocks);

  /// True when the section is purely the app-only ideas widget (skipped on web).
  bool get isAppOnly =>
      blocks.isNotEmpty && blocks.every((b) => b is HelpIdeasToken);
}

class HelpDoc {
  final String title;
  final List<HelpSection> sections;
  const HelpDoc(this.title, this.sections);
}

final RegExp _orderedRe = RegExp(r'^(\d+[a-z]?)\.\s+');
final RegExp _imageRe = RegExp(r'^!\[([^\]]*)\]\(([^)]+)\)$');
final RegExp _inlineRe = RegExp(
    r'\*\*(.+?)\*\*|\[([^\]]+)\]\(([^)]+)\)|\{\{([a-z0-9-]+)\}\}');

HelpDoc parseHelpMarkdown(String md) {
  final lines = md.split('\n');
  var title = '';
  final sections = <HelpSection>[];
  String? curTitle;
  var curBody = <String>[];

  void flush() {
    final t = curTitle;
    if (t != null) {
      sections.add(HelpSection(t, _parseBlocks(curBody)));
    }
    curBody = <String>[];
  }

  for (final line in lines) {
    if (title.isEmpty && curTitle == null && line.startsWith('# ')) {
      title = line.substring(2).trim();
      continue;
    }
    if (line.startsWith('## ')) {
      flush();
      curTitle = line.substring(3).trim();
      continue;
    }
    if (curTitle != null) curBody.add(line);
  }
  flush();
  return HelpDoc(title, sections);
}

List<HelpBlock> _parseBlocks(List<String> lines) {
  final blocks = <HelpBlock>[];
  var i = 0;

  bool isSpecial(String t) =>
      t.isEmpty ||
      t == '```' ||
      t == '{{ideas-for-using}}' ||
      t.startsWith('- ') ||
      _orderedRe.hasMatch(t) ||
      _imageRe.hasMatch(t);

  while (i < lines.length) {
    final t = lines[i].trim();
    if (t.isEmpty) {
      i++;
      continue;
    }
    if (t == '```') {
      final buf = <String>[];
      i++;
      while (i < lines.length && lines[i].trim() != '```') {
        buf.add(lines[i]);
        i++;
      }
      if (i < lines.length) i++; // consume closing fence
      blocks.add(HelpCode(buf.join('\n')));
      continue;
    }
    if (t == '{{ideas-for-using}}') {
      blocks.add(const HelpIdeasToken());
      i++;
      continue;
    }
    final img = _imageRe.firstMatch(t);
    if (img != null) {
      blocks.add(HelpImage(img.group(1) ?? '', img.group(2)!));
      i++;
      continue;
    }
    if (t.startsWith('- ')) {
      final items = <List<HelpInline>>[];
      while (i < lines.length && lines[i].trim().startsWith('- ')) {
        items.add(parseInline(lines[i].trim().substring(2).trim()));
        i++;
      }
      blocks.add(HelpBullets(items));
      continue;
    }
    if (_orderedRe.hasMatch(t)) {
      final items = <HelpOrderedItem>[];
      while (i < lines.length) {
        final lt = lines[i].trim();
        final m = _orderedRe.firstMatch(lt);
        if (m == null) break;
        items.add(HelpOrderedItem(m.group(1)!, parseInline(lt.substring(m.end).trim())));
        i++;
      }
      blocks.add(HelpOrdered(items));
      continue;
    }
    // Paragraph: gather consecutive plain lines, joined with spaces.
    final buf = <String>[];
    while (i < lines.length && !isSpecial(lines[i].trim())) {
      buf.add(lines[i].trim());
      i++;
    }
    blocks.add(HelpParagraph(parseInline(buf.join(' '))));
  }
  return blocks;
}

List<HelpInline> parseInline(String s) {
  final spans = <HelpInline>[];
  var last = 0;
  for (final m in _inlineRe.allMatches(s)) {
    if (m.start > last) spans.add(HelpInline(s.substring(last, m.start)));
    if (m.group(1) != null) {
      spans.add(HelpInline(m.group(1)!, bold: true));
    } else if (m.group(2) != null) {
      spans.add(HelpInline(m.group(2)!, href: m.group(3)));
    } else {
      spans.add(HelpInline('', icon: m.group(4)));
    }
    last = m.end;
  }
  if (last < s.length) spans.add(HelpInline(s.substring(last)));
  if (spans.isEmpty) spans.add(HelpInline(s));
  return spans;
}

// ── HTML emission (for tool/generate_help_html.dart) ─────────────────────────

String _escape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String _escapeAttr(String s) => _escape(s).replaceAll('"', '&quot;');

/// Inline HTML for a named icon token. Unknown names render nothing.
String iconHtml(String name) {
  switch (name) {
    case 'share-icon':
      // Material "share" glyph, inherits the surrounding text colour.
      return '<svg viewBox="0 0 24 24" width="18" height="18" '
          'style="vertical-align:-0.2em;fill:currentColor" aria-label="Share">'
          '<path d="M18 16.08c-.76 0-1.44.3-1.96.77L8.91 12.7c.05-.23.09-.46.09-.7'
          's-.04-.47-.09-.7l7.05-4.11c.54.5 1.25.81 2.04.81 1.66 0 3-1.34 3-3s-1.34-3-3-3'
          '-3 1.34-3 3c0 .24.04.47.09.7L8.04 9.81C7.5 9.31 6.79 9 6 9c-1.66 0-3 1.34-3 3'
          's1.34 3 3 3c.79 0 1.5-.31 2.04-.81l7.12 4.16c-.05.21-.08.43-.08.65 0 1.61 1.31 '
          '2.92 2.92 2.92s2.92-1.31 2.92-2.92-1.31-2.92-2.92-2.92z"/></svg>';
    case 'rouzme-icon':
      return '<img src="rouzme_icon.png" alt="RouzMe" width="20" height="20" '
          'style="vertical-align:-0.35em;border-radius:4px"/>';
    default:
      return '';
  }
}

String _inlineHtml(List<HelpInline> spans) {
  final b = StringBuffer();
  for (final s in spans) {
    if (s.icon != null) {
      b.write(iconHtml(s.icon!));
      continue;
    }
    final esc = _escape(s.text);
    if (s.href != null) {
      b.write('<a href="${_escapeAttr(s.href!)}">$esc</a>');
    } else if (s.bold) {
      b.write('<strong>$esc</strong>');
    } else {
      b.write(esc);
    }
  }
  return b.toString();
}

/// Renders one section's blocks to HTML (skips app-only ideas tokens).
String blocksToHtml(List<HelpBlock> blocks) {
  final b = StringBuffer();
  for (final block in blocks) {
    switch (block) {
      case HelpParagraph(:final spans):
        b.writeln('        <p>${_inlineHtml(spans)}</p>');
      case HelpBullets(:final items):
        b.writeln('        <ul>');
        for (final it in items) {
          b.writeln('          <li>${_inlineHtml(it)}</li>');
        }
        b.writeln('        </ul>');
      case HelpOrdered(:final items):
        // Custom rows (not <ol>) so literal markers like "4a." render as authored.
        b.writeln('        <div class="steps">');
        for (final it in items) {
          b.writeln('          <div class="step">'
              '<span class="marker">${_escape(it.marker)}.</span>'
              '<span>${_inlineHtml(it.spans)}</span></div>');
        }
        b.writeln('        </div>');
      case HelpCode(:final text):
        b.writeln('        <pre><code>${_escape(text)}</code></pre>');
      case HelpImage(:final alt, :final src):
        b.writeln('        <p><img src="${_escapeAttr(src)}" '
            'alt="${_escapeAttr(alt)}" class="shot"/></p>');
      case HelpIdeasToken():
        break; // app-only
    }
  }
  return b.toString();
}

// One-off generator: build feed/feed.xml (RSS 2.0) from the Medium-export HTML
// files in this folder, for a Substack RSS import. Run from the repo root:
//
//   dart run feed/generate_feed.dart
//
// - Every *.html here becomes one <item> (published + drafts).
// - Full article body goes in <content:encoded> so Substack imports the writing.
// - Published files (with a <time class="dt-published">) keep their real date;
//   undated drafts get recent dates, newest-first.
// - link/guid point at the hosted page on rouzme.com.
//
// This file is not served (see .vercelignore `feed/*.dart`). Back out the whole
// feature by deleting the feed/ directory.

import 'dart:io';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';

// ---- Channel metadata (edit freely) ----------------------------------------
const String kChannelTitle = 'Steve Upstill';
const String kChannelDescription =
    'Essays and drafts, imported from Medium.';
const String kSiteBase = 'https://rouzme.com/feed';

const List<String> _weekdays = [
  'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun' // DateTime.weekday is 1..7
];
const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

/// RFC-822 date (e.g. "Wed, 27 Aug 2026 15:04:05 +0000"), always UTC.
String rfc822(DateTime dt) {
  final u = dt.toUtc();
  final wd = _weekdays[u.weekday - 1];
  final mon = _months[u.month - 1];
  String p(int n) => n.toString().padLeft(2, '0');
  return '$wd, ${p(u.day)} $mon ${u.year} '
      '${p(u.hour)}:${p(u.minute)}:${p(u.second)} +0000';
}

String xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String cdata(String s) =>
    '<![CDATA[${s.replaceAll(']]>', ']]]]><![CDATA[>')}]]>';

class Article {
  final String file;
  final String title;
  final String bodyHtml;
  final String description;
  DateTime date;
  final bool isDraft;
  Article(this.file, this.title, this.bodyHtml, this.description, this.date,
      this.isDraft);
}

/// Fix Medium image quirks in the body and drop tracking pixels.
void _sanitizeImages(Element body) {
  for (final img in body.querySelectorAll('img')) {
    final src = img.attributes['src'];
    if (src == null || src.isEmpty) {
      final dataSrc = img.attributes['data-src'] ?? img.attributes['data-image'];
      if (dataSrc != null && dataSrc.isNotEmpty) {
        img.attributes['src'] = dataSrc;
      }
    }
    final finalSrc = img.attributes['src'] ?? '';
    if (finalSrc.contains('medium.com/_/stat')) {
      img.remove(); // Medium analytics pixel
    }
  }
}

Article? parseFile(File f) {
  final name = f.uri.pathSegments.last;
  final doc = html_parser.parse(f.readAsStringSync());

  final title = (doc.querySelector('h1.p-name')?.text ??
          doc.querySelector('title')?.text ??
          name)
      .trim();

  final body = doc.querySelector('section.e-content') ??
      doc.querySelector('.e-content') ??
      doc.querySelector('article') ??
      doc.body;
  if (body == null) return null;
  _sanitizeImages(body);
  final bodyHtml = body.innerHtml.trim();

  // Short description from the first paragraph.
  final firstP = body.querySelector('p')?.text.trim() ?? '';
  final description = firstP.length > 280
      ? '${firstP.substring(0, 280).trimRight()}…'
      : firstP;

  final dtAttr =
      doc.querySelector('time.dt-published')?.attributes['datetime'];
  DateTime? date = dtAttr != null ? DateTime.tryParse(dtAttr) : null;

  return Article(name, title, bodyHtml, description,
      date ?? DateTime.now(), /*isDraft=*/ date == null);
}

String itemLink(String file) {
  // cleanUrls is on, so link to the extension-less path; encode the segment.
  final clean = file.endsWith('.html')
      ? file.substring(0, file.length - '.html'.length)
      : file;
  return '$kSiteBase/${Uri.encodeComponent(clean)}';
}

void main() {
  final dir = Directory('feed');
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.html'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final articles = <Article>[];
  for (final f in files) {
    final a = parseFile(f);
    if (a != null) articles.add(a);
  }

  // Assign recent, newest-first dates to the undated drafts (one per day,
  // counting back from today) so they import as recent posts in a stable order.
  final drafts = articles.where((a) => a.isDraft).toList()
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  final today = DateTime.now().toUtc();
  for (var i = 0; i < drafts.length; i++) {
    // 12:00Z keeps the calendar day stable across time zones.
    final d = DateTime.utc(today.year, today.month, today.day, 12)
        .subtract(Duration(days: i));
    drafts[i].date = d;
  }

  // Newest first overall.
  articles.sort((a, b) => b.date.compareTo(a.date));

  final now = rfc822(DateTime.now());
  final sb = StringBuffer();
  sb.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  sb.writeln('<rss version="2.0" '
      'xmlns:content="http://purl.org/rss/1.0/modules/content/" '
      'xmlns:atom="http://www.w3.org/2005/Atom">');
  sb.writeln('  <channel>');
  sb.writeln('    <title>${xmlEscape(kChannelTitle)}</title>');
  sb.writeln('    <link>$kSiteBase/</link>');
  sb.writeln('    <description>${xmlEscape(kChannelDescription)}</description>');
  sb.writeln('    <language>en-us</language>');
  sb.writeln('    <lastBuildDate>$now</lastBuildDate>');
  sb.writeln('    <atom:link href="$kSiteBase/feed.xml" '
      'rel="self" type="application/rss+xml"/>');

  for (final a in articles) {
    final link = itemLink(a.file);
    sb.writeln('    <item>');
    sb.writeln('      <title>${xmlEscape(a.title)}</title>');
    sb.writeln('      <link>${xmlEscape(link)}</link>');
    sb.writeln('      <guid isPermaLink="true">${xmlEscape(link)}</guid>');
    sb.writeln('      <pubDate>${rfc822(a.date)}</pubDate>');
    if (a.description.isNotEmpty) {
      sb.writeln('      <description>${cdata(a.description)}</description>');
    }
    sb.writeln('      <content:encoded>${cdata(a.bodyHtml)}</content:encoded>');
    sb.writeln('    </item>');
  }

  sb.writeln('  </channel>');
  sb.writeln('</rss>');

  File('feed/feed.xml').writeAsStringSync(sb.toString());
  stdout.writeln('Wrote feed/feed.xml with ${articles.length} items '
      '(${drafts.length} drafts, ${articles.length - drafts.length} published).');
}

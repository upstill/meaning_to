import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

final RegExp _urlRegex = RegExp(r'https?://[^\s<>"\)\]]+', caseSensitive: false);

/// Open [url] in the browser, trimming trailing prose punctuation first.
Future<void> openUrlExternal(String url) async {
  var clean = url;
  while (clean.isNotEmpty && '.,;:!?'.contains(clean[clean.length - 1])) {
    clean = clean.substring(0, clean.length - 1);
  }
  final uri = Uri.tryParse(clean);
  if (uri == null) return;
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Split [text] into spans, turning http(s) URLs into tappable links. Created
/// tap recognizers are appended to [recognizers] — the caller must dispose them
/// (e.g. in State.dispose). [baseStyle] drives the link colour/underline.
List<InlineSpan> linkifySpans(
  String text, {
  TextStyle? baseStyle,
  required List<TapGestureRecognizer> recognizers,
}) {
  final linkStyle = (baseStyle ?? const TextStyle()).copyWith(
    color: Colors.blue,
    decoration: TextDecoration.underline,
  );
  final spans = <InlineSpan>[];
  int last = 0;
  for (final m in _urlRegex.allMatches(text)) {
    if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
    final url = m.group(0)!;
    final recognizer = TapGestureRecognizer()..onTap = () => openUrlExternal(url);
    recognizers.add(recognizer);
    spans.add(TextSpan(text: url, style: linkStyle, recognizer: recognizer));
    last = m.end;
  }
  if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
  return spans;
}

/// Renders [text] with any http(s) URLs turned into tappable links.
class LinkifiedText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const LinkifiedText(this.text,
      {super.key,
      this.style,
      this.textAlign,
      this.maxLines,
      this.overflow});

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    return Text.rich(
      TextSpan(
        style: widget.style,
        children:
            linkifySpans(widget.text, baseStyle: widget.style, recognizers: _recognizers),
      ),
      textAlign: widget.textAlign,
      maxLines: widget.maxLines,
      overflow: widget.overflow ?? TextOverflow.clip,
    );
  }
}

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:meaning_to/theme/app_colors.dart';
import 'package:meaning_to/utils/help_markdown.dart';
import 'package:meaning_to/widgets/linkified_text.dart' show openUrlExternal;

/// Renders parsed Help [blocks] (from help_markdown) as Flutter widgets:
/// paragraphs, bullet/ordered lists, monospace code blocks, with **bold** and
/// tappable [links]. The app-only ideas token renders nothing here — the Help
/// screen swaps in the interactive widget for that section.
class HelpBody extends StatefulWidget {
  final List<HelpBlock> blocks;
  const HelpBody(this.blocks, {super.key});

  @override
  State<HelpBody> createState() => _HelpBodyState();
}

class _HelpBodyState extends State<HelpBody> {
  final List<TapGestureRecognizer> _recognizers = [];

  static const _bodyStyle =
      TextStyle(fontSize: 15, height: 1.5, color: AppColors.text);

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  /// Inline icon for a named token; null (nothing) for unknown names.
  Widget? _icon(String name) {
    switch (name) {
      case 'share-icon':
        return const Icon(Icons.share, size: 18, color: AppColors.text);
      case 'rouzme-icon':
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.asset('assets/icon/rouzme_icon_1024.png',
              width: 20, height: 20),
        );
      default:
        return null;
    }
  }

  List<InlineSpan> _spans(List<HelpInline> inlines) {
    final out = <InlineSpan>[];
    for (final s in inlines) {
      if (s.icon != null) {
        final w = _icon(s.icon!);
        if (w != null) {
          out.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: w,
            ),
          ));
        }
        continue;
      }
      if (s.href != null) {
        final r = TapGestureRecognizer()..onTap = () => openUrlExternal(s.href!);
        _recognizers.add(r);
        out.add(TextSpan(
          text: s.text,
          style: const TextStyle(
            color: AppColors.primary,
            decoration: TextDecoration.underline,
          ),
          recognizer: r,
        ));
      } else {
        out.add(TextSpan(
          text: s.text,
          style: s.bold ? const TextStyle(fontWeight: FontWeight.bold) : null,
        ));
      }
    }
    return out;
  }

  Widget _row(String marker, List<HelpInline> spans, double markerWidth) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: markerWidth, child: Text(marker, style: _bodyStyle)),
          Expanded(
            child: Text.rich(
                TextSpan(style: _bodyStyle, children: _spans(spans))),
          ),
        ],
      ),
    );
  }

  Widget _bullets(List<List<HelpInline>> items) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final it in items) _row('•', it, 24)],
        ),
      );

  Widget _ordered(List<HelpOrderedItem> items) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final it in items) _row('${it.marker}.', it.spans, 28),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    // Recreate recognizers on each rebuild; dispose the previous batch first.
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    final children = <Widget>[];
    for (final block in widget.blocks) {
      switch (block) {
        case HelpParagraph(:final spans):
          children.add(Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text.rich(
                TextSpan(style: _bodyStyle, children: _spans(spans))),
          ));
        case HelpBullets(:final items):
          children.add(_bullets(items));
        case HelpOrdered(:final items):
          children.add(_ordered(items));
        case HelpCode(:final text):
          children.add(Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              text,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.4,
                color: AppColors.text,
              ),
            ),
          ));
        case HelpImage(:final src):
          // Help images live in web/ (served at the site root) and are bundled
          // as the asset web/<src> for the app.
          children.add(Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'web/$src',
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ));
        case HelpIdeasToken():
          break; // the Help screen inserts the interactive widget instead
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:meaning_to/widgets/linkified_text.dart';

/// Displays [text] (with tappable links) clamped to [collapsedLines] lines,
/// adding a "(more)" affordance to expand and "(less)" to collapse again. The
/// toggle only appears when the text actually overflows the clamp. Used for
/// long Pursuit descriptions on the Home screen.
class ExpandableNotes extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final int collapsedLines;

  const ExpandableNotes(
    this.text, {
    super.key,
    this.style,
    this.collapsedLines = 3,
  });

  @override
  State<ExpandableNotes> createState() => _ExpandableNotesState();
}

class _ExpandableNotesState extends State<ExpandableNotes> {
  bool _expanded = false;

  @override
  void didUpdateWidget(ExpandableNotes oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Collapse again when the pursuit (text) changes.
    if (oldWidget.text != widget.text) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Measure whether the text exceeds the collapsed line count at this
        // width. Links don't change layout, so measuring the plain text is a
        // faithful proxy.
        final tp = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: widget.collapsedLines,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = tp.didExceedMaxLines;
        final showFull = _expanded || !overflows;

        final toggleStyle = (widget.style ?? const TextStyle()).copyWith(
          color: Colors.blue,
          fontStyle: FontStyle.normal,
          fontWeight: FontWeight.w600,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinkifiedText(
              widget.text,
              style: widget.style,
              maxLines: showFull ? null : widget.collapsedLines,
              overflow: showFull ? TextOverflow.clip : TextOverflow.ellipsis,
            ),
            if (overflows)
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(_expanded ? '(less)' : '(more)',
                      style: toggleStyle),
                ),
              ),
          ],
        );
      },
    );
  }
}

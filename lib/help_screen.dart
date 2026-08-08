import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:meaning_to/widgets/home_button.dart';
import 'package:meaning_to/widgets/ideas_for_using_section.dart';
import 'package:meaning_to/widgets/help_body.dart';
import 'package:meaning_to/utils/help_markdown.dart';

/// In-app Help. Content comes from the single source `docs/help.md` (also the
/// source for the static rouzme.com/help page, generated via
/// tool/generate_help_html.dart) — edit the Markdown, never this file's prose.
class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  int? _expandedIndex;
  late final Future<HelpDoc> _docFuture;

  @override
  void initState() {
    super.initState();
    _docFuture =
        rootBundle.loadString('docs/help.md').then(parseHelpMarkdown);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help'),
        // Force a high-contrast foreground so the leading/action icons are
        // visible on the light M3 AppBar.
        foregroundColor: Colors.black87,
        leading: const HomeButton(color: Colors.black87),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            color: Colors.black87,
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
      body: FutureBuilder<HelpDoc>(
        future: _docFuture,
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Could not load Help.'),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final doc = snap.data!;
          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 24.0),
                child: Text(
                  doc.title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              for (var i = 0; i < doc.sections.length; i++) ...[
                _buildSection(i, doc.sections[i]),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 24),
              const Center(
                child: Text(
                  'Need more help? Contact us at support@rouzme.com',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSection(int index, HelpSection section) {
    return ExpansionTile(
      key: ValueKey<String>('help_section_${index}_${_expandedIndex == index}'),
      initiallyExpanded: _expandedIndex == index,
      onExpansionChanged: (expanded) {
        setState(() => _expandedIndex = expanded ? index : null);
      },
      title: Text(
        section.title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The "Ideas for Using" section is the interactive picker, not prose.
        section.isAppOnly
            ? const IdeasForUsingSection()
            : HelpBody(section.blocks),
      ],
    );
  }
}

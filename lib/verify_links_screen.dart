import 'package:flutter/material.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/utils/supabase_client.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/utils/link_to_task_converter.dart';

class VerifyLinksScreen extends StatefulWidget {
  const VerifyLinksScreen({super.key});

  @override
  State<VerifyLinksScreen> createState() => _VerifyLinksScreenState();
}

class _VerifyLinksScreenState extends State<VerifyLinksScreen> {
  final _textController = TextEditingController();
  final _textFieldFocusNode = FocusNode();
  bool _isProcessing = false;
  bool _isLoadingLinks = false;
  List<LinkVerificationResult> _results = [];

  @override
  void initState() {
    super.initState();
    _loadAllLinksAndVerify();
  }

  @override
  void dispose() {
    _textController.dispose();
    _textFieldFocusNode.dispose();
    super.dispose();
  }

  List<LinkVerificationResult> _getNotFoundLinks() {
    return _results.where((result) => !result.hasTask).toList();
  }

  /// Extract URL from HTML link or return plain URL
  static String? _extractUrlFromLink(String linkText) {
    // If it's already a plain URL, return it
    if (linkText.trim().startsWith('http://') ||
        linkText.trim().startsWith('https://')) {
      return linkText.trim();
    }

    // Otherwise, try to extract from HTML format
    final regex = RegExp(r'href=["\x27]([^"\x27]+)["\x27]');
    final match = regex.firstMatch(linkText);
    return match?.group(1);
  }

  /// Normalize URL for comparison (same logic as duplicate check)
  static String? _normalizeUrl(String url) {
    try {
      return LinkToTaskConverter.normalizeUrl(url);
    } catch (e) {
      return null;
    }
  }

  /// Load all links from user's tasks and automatically verify them
  Future<void> _loadAllLinksAndVerify() async {
    setState(() {
      _isLoadingLinks = true;
    });

    try {
      final userId = AuthUtils.getCurrentUserId();
      final allLinks = <String>{};
      const from = 0;
      const batchSize = 100;

      // Limit to first 100 tasks (newest first)
      final to = from + batchSize - 1;
      final response = await supabase
          .from('Tasks')
          .select('*')
          .eq('owner_id', userId)
          .order('created_at', ascending: false)
          .range(from, to);

      final tasks = (response as List)
          .map((json) => Task.fromJson(json as Map<String, dynamic>))
          .toList();

      // Extract all links from this batch
      for (final task in tasks) {
        if (task.links != null && task.links!.isNotEmpty) {
          for (final linkText in task.links!) {
            final extractedUrl = _extractUrlFromLink(linkText);
            if (extractedUrl != null) {
              allLinks.add(extractedUrl);
            }
          }
        }
      }

      // Populate text field with all collected links
      final linksText = allLinks.join('\n');
      _textController.text = linksText;

      if (mounted) {
        setState(() {
          _isLoadingLinks = false;
        });

        // Automatically run verification if we found links
        if (allLinks.isNotEmpty) {
          _verifyLinks();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingLinks = false;
        });
      }
    }
  }

  Future<void> _verifyLinks() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      return;
    }

    setState(() {
      _isProcessing = true;
      _results = [];
    });

    final userId = AuthUtils.getCurrentUserId();
    final lines =
        text.split('\n').where((line) => line.trim().isNotEmpty).toList();
    final results = <LinkVerificationResult>[];

    try {
      // Step 1: Collect all normalized URLs from all user tasks (1000 at a time)
      final allNormalizedUrls = <String>{};
      int from = 0;
      const batchSize = 1000;
      bool hasMore = true;

      while (hasMore) {
        final to = from + batchSize - 1;
        final response = await supabase
            .from('Tasks')
            .select('*')
            .eq('owner_id', userId)
            .range(from, to);

        final tasks = (response as List)
            .map((json) => Task.fromJson(json as Map<String, dynamic>))
            .toList();

        // Extract and normalize all URLs from this batch
        for (final task in tasks) {
          if (task.links != null && task.links!.isNotEmpty) {
            for (final linkText in task.links!) {
              final extractedUrl = _extractUrlFromLink(linkText);
              if (extractedUrl != null) {
                final normalizedUrl = _normalizeUrl(extractedUrl);
                if (normalizedUrl != null) {
                  allNormalizedUrls.add(normalizedUrl);
                }
              }
            }
          }
        }

        hasMore = tasks.length == batchSize;
        from += batchSize;
      }

      // Step 2: For each input link, normalize it and check if it's in the set
      for (final line in lines) {
        final trimmedLine = line.trim();
        if (trimmedLine.isEmpty) continue;

        // Regular URL processing
        final extractedUrl = _extractUrlFromLink(trimmedLine);
        if (extractedUrl == null) {
          results.add(LinkVerificationResult(
            input: trimmedLine,
            url: null,
            hasTask: false,
            error: 'Could not extract URL from line',
          ));
          continue;
        }

        final normalizedUrl = _normalizeUrl(extractedUrl);
        if (normalizedUrl == null) {
          results.add(LinkVerificationResult(
            input: trimmedLine,
            url: extractedUrl,
            hasTask: false,
            error: 'Could not normalize URL',
          ));
          continue;
        }

        final hasTask = allNormalizedUrls.contains(normalizedUrl);

        results.add(LinkVerificationResult(
          input: trimmedLine,
          url: extractedUrl,
          hasTask: hasTask,
        ));
      }
    } catch (e) {
      // If collection fails, mark all as errors
      for (final line in lines) {
        final trimmedLine = line.trim();
        if (trimmedLine.isEmpty) continue;
        results.add(LinkVerificationResult(
          input: trimmedLine,
          url: null,
          hasTask: false,
          error: 'Error collecting tasks: $e',
        ));
      }
    }

    if (mounted) {
      // Collect unfound links and write them back to the text field
      final unfoundLinks = results
          .where((result) => !result.hasTask)
          .map((result) => result.url ?? result.input)
          .where((link) => link.isNotEmpty)
          .toList();

      if (unfoundLinks.isNotEmpty) {
        _textController.text = unfoundLinks.join('\n');
      }

      setState(() {
        _isProcessing = false;
        _results = results;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Links'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _textController,
                  focusNode: _textFieldFocusNode,
                  decoration: const InputDecoration(
                    hintText: 'Enter links (one per line)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 10,
                  minLines: 5,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: (_isProcessing || _isLoadingLinks)
                            ? null
                            : _verifyLinks,
                        child: _isProcessing
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                  SizedBox(width: 8),
                                  Text('Processing...'),
                                ],
                              )
                            : const Text('Verify Links'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: (_isProcessing || _isLoadingLinks)
                          ? null
                          : _loadAllLinksAndVerify,
                      child: const Text('Reload All'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoadingLinks
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Loading all links from database...'),
                      ],
                    ),
                  )
                : _isProcessing
                    ? const Center(child: CircularProgressIndicator())
                    : _getNotFoundLinks().isEmpty
                        ? const Center(
                            child: Text(
                              'All links found in database',
                              style: TextStyle(fontSize: 16),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16.0),
                            itemCount: _getNotFoundLinks().length,
                            itemBuilder: (context, index) {
                              final result = _getNotFoundLinks()[index];
                              final displayText = result.url ?? result.input;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: SelectableText(
                                  displayText,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class LinkVerificationResult {
  final String input;
  final String? url;
  final bool hasTask;
  final Task? task;
  final String? error;

  LinkVerificationResult({
    required this.input,
    required this.url,
    required this.hasTask,
    this.task,
    this.error,
  });
}

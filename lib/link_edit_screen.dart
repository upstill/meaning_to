import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:meaning_to/utils/link_processor.dart';
import 'package:meaning_to/utils/link_to_task_converter.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/utils/supabase_client.dart';
import 'package:meaning_to/utils/app_buttons.dart';

class LinkEditScreen extends StatefulWidget {
  final String? initialLink; // HTML link to edit, or null for new link
  final String? errorMessage; // Add error message parameter
  final Task? currentTask; // Current task being edited, if any
  final Category? currentCategory; // Current category context

  const LinkEditScreen({
    super.key,
    this.initialLink,
    this.errorMessage, // Add to constructor
    this.currentTask,
    this.currentCategory,
  });

  @override
  State<LinkEditScreen> createState() => _LinkEditScreenState();
}

class _LinkEditScreenState extends State<LinkEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _textController;
  late TextEditingController _urlController;
  bool _isLoading = false;
  String? _error;
  bool _hasUrlText = false; // Add state for URL text presence
  String? _lastAutoVerifiedUrl; // Track which URL we last auto-verified
  bool _isAutoVerifying = false; // Track if we're currently auto-verifying

  @override
  void initState() {
    super.initState();
    print('LinkEditScreen: initState called');
    print('LinkEditScreen: currentTask: ${widget.currentTask?.headline}');
    print(
        'LinkEditScreen: currentCategory: ${widget.currentCategory?.headline}');
    print(
        'LinkEditScreen: Task.currentTaskSet: ${Task.currentTaskSet?.length} tasks');

    // Parse initial link if provided
    if (widget.initialLink != null &&
        widget.initialLink!.startsWith('<a href="')) {
      final linkMatch = RegExp(r'<a href="([^"]+)"[^>]*>(.*?)</a>')
          .firstMatch(widget.initialLink!);
      if (linkMatch != null) {
        _urlController = TextEditingController(text: linkMatch.group(1));
        _textController = TextEditingController(text: linkMatch.group(2));
      } else {
        _urlController = TextEditingController(text: widget.initialLink);
        _textController = TextEditingController();
      }
    } else {
      _urlController = TextEditingController(text: widget.initialLink);
      _textController = TextEditingController();
    }
    print('LinkEditScreen: Initial URL text: "${_urlController.text}"');
    // Set initial error if provided
    _error = widget.errorMessage;
    // Set initial URL text state
    _hasUrlText = _urlController.text.trim().isNotEmpty;
    print('LinkEditScreen: Initial _hasUrlText: $_hasUrlText');
    // Add listener for URL text changes
    _urlController.addListener(_updateUrlTextState);
  }

  @override
  void dispose() {
    _urlController.removeListener(_updateUrlTextState);
    _urlController.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _updateUrlTextState() {
    final inputText = _urlController.text.trim();
    final hasText = inputText.isNotEmpty;
    print('URL text changed: "$inputText" -> hasText: $hasText');

    // Check if input looks like an HTML link
    if (hasText && inputText.startsWith('<a href="') && inputText.contains('">')) {
      _parseHtmlLinkInput(inputText);
      return; // HTML link parsing handles verification
    }

    if (hasText != _hasUrlText) {
      print('Updating _hasUrlText from $_hasUrlText to $hasText');
      setState(() {
        _hasUrlText = hasText;
        _error = null;
      });
    }

    // Auto-verify if we have a valid URL that we haven't verified yet
    if (hasText &&
        LinkProcessor.isValidUrl(inputText) &&
        inputText != _lastAutoVerifiedUrl &&
        !_isLoading &&
        !_isAutoVerifying) {
      print('LinkEditScreen: Auto-verifying URL: $inputText');
      _autoVerifyLink(inputText);
    }
  }

  void _parseHtmlLinkInput(String htmlInput) {
    print('LinkEditScreen: Detected HTML link input: "$htmlInput"');

    // Fix common malformed HTML patterns (similar to TaskEnricher and TaskEditScreen)
    String htmlToProcess = htmlInput;
    if (htmlToProcess.endsWith('<a>')) {
      htmlToProcess = htmlToProcess.replaceAll(RegExp(r'<a>$'), '</a>');
      print('LinkEditScreen: Fixed malformed HTML link - changed <a> to </a>');
    } else if (!htmlToProcess.endsWith('</a>')) {
      if (htmlToProcess.contains('<a>')) {
        htmlToProcess = htmlToProcess.replaceAll('<a>', '</a>');
        print('LinkEditScreen: Fixed malformed HTML link - changed <a> to </a>');
      } else {
        htmlToProcess = htmlToProcess + '</a>';
        print('LinkEditScreen: Added missing closing tag </a>');
      }
    }

    final (url, title) = LinkProcessor.parseHtmlLink(htmlToProcess);

    if (url.isNotEmpty && url != htmlInput) {
      print('LinkEditScreen: Parsed HTML - URL: "$url", title: "$title"');

      // Update both fields without triggering infinite loops
      _urlController.removeListener(_updateUrlTextState);

      _urlController.text = url;
      if (title != null && title.isNotEmpty) {
        _textController.text = title;
      }

      _urlController.addListener(_updateUrlTextState);

      // Update state
      setState(() {
        _hasUrlText = true;
        _error = null;
      });
    }
  }

  /// Automatically verify a link when it's pasted into the URL field
  Future<void> _autoVerifyLink(String url) async {
    setState(() {
      _isAutoVerifying = true;
      _isLoading = true;
      _error = null;
    });

    try {
      print('LinkEditScreen: Auto-verifying URL: $url');

      // Normalize the URL first (remove query parameters, etc.)
      final normalizedUrl = LinkToTaskConverter.normalizeUrl(url);
      print('LinkEditScreen: Normalized URL: $normalizedUrl');

      // Update the URL field with the normalized URL (without triggering listener)
      _urlController.removeListener(_updateUrlTextState);
      _urlController.text = normalizedUrl;
      _urlController.addListener(_updateUrlTextState);

      // Use LinkToTaskConverter to properly extract metadata with OMDb API for IMDb links
      final userId = AuthUtils.getCurrentUserId();
      final proposedTask = await LinkToTaskConverter.createProposedTaskFromLink(
        normalizedUrl,
        userId,
        currentCategory: widget.currentCategory,
      );

      // Also get the processed link for favicon display
      final processedLink = await LinkProcessor.processLinkForDisplay(
          '<a href="$normalizedUrl">${proposedTask.headline}</a>');

      // Update the Link Text field with the properly cleaned title
      // Extract link text from the HTML link in proposedTask.links (e.g., "Continuum by John Mayer on TIDAL")
      if (_textController.text.trim().isEmpty && proposedTask.links.isNotEmpty) {
        final htmlLink = proposedTask.links.first;
        final (_, linkText) = LinkProcessor.parseHtmlLink(htmlLink);
        if (linkText != null && linkText.isNotEmpty) {
          _textController.text = linkText;
        }
      }

      setState(() {
        _lastAutoVerifiedUrl = normalizedUrl; // Use normalized URL
        _isAutoVerifying = false;
        _isLoading = false;
      });

      print('LinkEditScreen: Auto-verification complete for: $normalizedUrl');
    } catch (e) {
      print('LinkEditScreen: Error during auto-verification: $e');
      setState(() {
        _error = 'Failed to verify URL: ${e.toString()}';
        _lastAutoVerifiedUrl = url; // Mark as attempted to avoid retry loops
        _isAutoVerifying = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveLink() async {
    if (!_formKey.currentState!.validate()) return;
    if (_urlController.text.trim().isEmpty) {
      setState(() {
        _error = 'Please enter a URL';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final url = _urlController.text.trim();

      // Normalize the URL (remove query parameters, etc.)
      final normalizedUrl = LinkToTaskConverter.normalizeUrl(url);
      print('LinkEditScreen: Save Link - Normalized URL: $normalizedUrl');

      String linkText = _textController.text.trim();

      // Only reach out to the web when we actually need a title — i.e. the user
      // supplied no link text. If they typed/edited the text, or it was already
      // filled in (from a paste/auto-verify), the URL is effectively validated
      // and we skip the slow re-fetch. The saved link is the URL + text either
      // way (the caller uses only the link, not the fetched metadata).
      ProposedTask? proposedTask;
      if (linkText.isEmpty) {
        // Cleaned metadata (including OMDb for IMDb) to derive a link title.
        final userId = AuthUtils.getCurrentUserId();
        proposedTask = await LinkToTaskConverter.createProposedTaskFromLink(
          normalizedUrl,
          userId,
          currentCategory: widget.currentCategory,
        );
        if (proposedTask.links.isNotEmpty) {
          final (_, extractedLinkText) =
              LinkProcessor.parseHtmlLink(proposedTask.links.first);
          linkText = extractedLinkText ?? proposedTask.headline;
        }
      }

      // Create HTML link with the user's (or derived) text.
      final customHtmlLink = '<a href="$normalizedUrl">$linkText</a>';

      final customProposedTask = ProposedTask(
        headline: proposedTask?.headline ?? linkText,
        notes: proposedTask?.notes,
        links: [customHtmlLink],
        synopsis: proposedTask?.synopsis,
        suggestedCategoryOriginalIds:
            proposedTask?.suggestedCategoryOriginalIds ?? const [],
        existingTaskOriginalId: proposedTask?.existingTaskOriginalId,
      );

      if (mounted) {
        Navigator.pop(context, customProposedTask);
      }
    } catch (e) {
      print('Error validating link: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }




  @override
  Widget build(BuildContext context) {
    print(
        'LinkEditScreen: Building with _hasUrlText: $_hasUrlText, URL text: "${_urlController.text}"');
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initialLink == null ? 'New Link' : 'Edit Link'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            if (_error != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
              const SizedBox(height: 8),
            ],
            TextFormField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'URL',
                hintText: 'https://example.com',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a URL';
                }
                if (!LinkProcessor.isValidUrl(value.trim())) {
                  return 'Invalid URL format';
                }
                return null;
              },
              enabled: !_isLoading,
              keyboardType: TextInputType.url,
              onChanged: (value) {
                print('URL field onChanged: "$value"');
                _updateUrlTextState();
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _textController,
              decoration: const InputDecoration(
                labelText: 'Link Text (optional)',
                hintText: 'Leave empty to use webpage title',
                border: OutlineInputBorder(),
              ),
              enabled: !_isLoading,
            ),
            if (_isLoading) ...[
              const SizedBox(height: 24),
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Checking if this link works...'),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading || !_hasUrlText ? null : _saveLink,
                    style: AppButtons.finalize(),
                    child: const Text('Save Link'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

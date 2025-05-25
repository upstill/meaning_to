import 'package:flutter/material.dart';
import 'package:meaning_to/utils/link_processor.dart';

class LinkEditScreen extends StatefulWidget {
  final String? initialLink;  // HTML link to edit, or null for new link
  final String? errorMessage;  // Add error message parameter

  const LinkEditScreen({
    super.key,
    this.initialLink,
    this.errorMessage,  // Add to constructor
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
  String? _testedUrl;
  String? _testedIcon;
  bool _hasUrlText = false;  // Add state for URL text presence

  @override
  void initState() {
    super.initState();
    print('LinkEditScreen: initState called');
    // Parse initial link if provided
    if (widget.initialLink != null && widget.initialLink!.startsWith('<a href="')) {
      final linkMatch = RegExp(r'<a href="([^"]+)"[^>]*>(.*?)</a>').firstMatch(widget.initialLink!);
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
    final hasText = _urlController.text.trim().isNotEmpty;
    print('URL text changed: "${_urlController.text}" -> hasText: $hasText');
    if (hasText != _hasUrlText) {
      print('Updating _hasUrlText from $_hasUrlText to $hasText');
      setState(() {
        _hasUrlText = hasText;
      });
    }
  }

  Future<void> _testLink() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _testedUrl = null;
      _testedIcon = null;
    });

    try {
      final url = _urlController.text.trim();
      if (!LinkProcessor.isValidUrl(url)) {
        setState(() {
          _error = 'Invalid URL format';
          _isLoading = false;
        });
        return;
      }

      // Test the link by processing it
      final processedLink = await LinkProcessor.processLinkForDisplay(
        '<a href="$url">${_textController.text.trim()}</a>'
      );

      // If we got a title from the webpage and the text field was empty,
      // update the text field with the fetched title
      if (_textController.text.trim().isEmpty && processedLink.title != null) {
        _textController.text = processedLink.title!;
      }

      setState(() {
        _testedUrl = processedLink.url;
        _testedIcon = processedLink.favicon;
        _isLoading = false;
      });
    } catch (e) {
      print('Error testing link: $e');
      setState(() {
        _error = 'Failed to validate URL: ${e.toString()}';
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
      final processedLink = await LinkProcessor.validateAndProcessLink(
        url,
        linkText: _textController.text.trim(),
      );

      // If we got a title from the webpage and the text field was empty,
      // update the text field with the fetched title
      if (_textController.text.trim().isEmpty) {
        _textController.text = processedLink.title!;
      }

      // Create HTML link and return
      final htmlLink = '<a href="$url">${_textController.text.trim()}</a>';
      if (mounted) {
        Navigator.pop(context, htmlLink);
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
    print('LinkEditScreen: Building with _hasUrlText: $_hasUrlText, URL text: "${_urlController.text}"');
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
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
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
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    ),
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
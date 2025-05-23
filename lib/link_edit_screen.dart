import 'package:flutter/material.dart';
import 'package:meaning_to/utils/link_processor.dart';

class LinkEditScreen extends StatefulWidget {
  final String? initialLink;  // HTML link to edit, or null for new link

  const LinkEditScreen({
    super.key,
    this.initialLink,
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

  @override
  void initState() {
    super.initState();
    // Parse initial link if provided
    if (widget.initialLink != null) {
      final (url, text) = LinkProcessor.parseHtmlLink(widget.initialLink!);
      _urlController = TextEditingController(text: url);
      _textController = TextEditingController(text: text);
    } else {
      _urlController = TextEditingController();
      _textController = TextEditingController();
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _textController.dispose();
    super.dispose();
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

  void _saveLink() {
    if (!_formKey.currentState!.validate()) return;
    if (_testedUrl == null) {
      setState(() {
        _error = 'Please test the link before saving';
      });
      return;
    }

    // Create HTML link
    final htmlLink = '<a href="${_urlController.text.trim()}">${_textController.text.trim()}</a>';
    Navigator.pop(context, htmlLink);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initialLink == null ? 'New Link' : 'Edit Link'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
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
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                'Error: $_error',
                style: const TextStyle(color: Colors.red),
              ),
            ],
            if (_testedUrl != null) ...[
              const SizedBox(height: 24),
              const Text(
                'Preview:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              LinkDisplayWidget(
                linkText: '<a href="${_urlController.text.trim()}">${_textController.text.trim()}</a>',
                showIcon: true,
                showTitle: true,
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _testLink,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Test Link'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading || _testedUrl == null ? null : _saveLink,
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
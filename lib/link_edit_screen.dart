import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:meaning_to/utils/link_processor.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/utils/supabase_client.dart';

/// Result of duplicate checking
enum DuplicateCheckResult {
  noDuplicate,
  currentTaskDuplicate,
  categoryDuplicate,
}

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
  String? _testedUrl;
  String? _testedIcon;
  bool _hasUrlText = false; // Add state for URL text presence
  String?
      _duplicateTaskName; // Store the name of the task that has the duplicate link
  DuplicateCheckResult?
      _lastDuplicateResult; // Store the last duplicate check result

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
    final hasText = _urlController.text.trim().isNotEmpty;
    print('URL text changed: "${_urlController.text}" -> hasText: $hasText');
    if (hasText != _hasUrlText) {
      print('Updating _hasUrlText from $_hasUrlText to $hasText');
      setState(() {
        _hasUrlText = hasText;
        // Clear duplicate task name when URL changes
        _duplicateTaskName = null;
        _lastDuplicateResult = null;
        _error = null;
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
          '<a href="$url">${_textController.text.trim()}</a>');

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

      // Create HTML link
      final htmlLink = '<a href="$url">${_textController.text.trim()}</a>';

      // Two-tier duplicate checking
      final duplicateCheckResult = await _checkForDuplicates(htmlLink);
      _lastDuplicateResult = duplicateCheckResult;

      if (duplicateCheckResult == DuplicateCheckResult.currentTaskDuplicate) {
        // First tier: Link already exists in current task
        setState(() {
          _error = 'This link is already in the current task';
          _isLoading = false;
        });
        return;
      } else if (duplicateCheckResult ==
          DuplicateCheckResult.categoryDuplicate) {
        // Second tier: Link exists in another task across all tasks
        setState(() {
          _error = 'This link already exists in task "${_duplicateTaskName}"';
          _isLoading = false;
        });
        return;
      }

      // No duplicates found
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

  Future<void> _saveLinkAnyway() async {
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

      // Create HTML link and return (bypassing duplicate checks)
      final htmlLink = '<a href="$url">${_textController.text.trim()}</a>';
      if (mounted) {
        Navigator.pop(context, htmlLink);
      }
    } catch (e) {
      print('Error saving link anyway: $e');
      setState(() {
        _error = 'Failed to save link: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  /// Checks for duplicates in current task and across all tasks
  Future<DuplicateCheckResult> _checkForDuplicates(String htmlLink) async {
    print('LinkEditScreen: _checkForDuplicates called for: $htmlLink');
    print('LinkEditScreen: currentTask: ${widget.currentTask?.headline}');
    print(
        'LinkEditScreen: currentCategory: ${widget.currentCategory?.headline}');

    // First check: current task duplicate
    if (widget.currentTask != null) {
      print('LinkEditScreen: Checking current task for duplicates...');
      if (widget.currentTask!.hasLink(htmlLink)) {
        print('LinkEditScreen: Found duplicate in current task');
        return DuplicateCheckResult.currentTaskDuplicate;
      }
    }

    // Second check: check across all tasks in the database
    print('LinkEditScreen: Checking all tasks for duplicates...');
    final duplicateTask = await _checkForDuplicateAcrossAllTasks(htmlLink);

    if (duplicateTask != null) {
      print(
          'LinkEditScreen: Found duplicate in task: ${duplicateTask.headline}');
      _duplicateTaskName = duplicateTask.headline;
      return DuplicateCheckResult.categoryDuplicate;
    }

    print('LinkEditScreen: No duplicates found');
    return DuplicateCheckResult.noDuplicate;
  }

  /// Check for duplicate link across all tasks in the database
  Future<Task?> _checkForDuplicateAcrossAllTasks(String htmlLink) async {
    try {
      final userId = AuthUtils.getCurrentUserId();

      // Extract URL from HTML link for comparison
      final url = _extractUrlFromHtmlLink(htmlLink);
      if (url == null) {
        print('LinkEditScreen: Could not extract URL from HTML link');
        return null;
      }

      print('LinkEditScreen: Checking for URL: $url across all tasks');

      // Query all tasks that have links containing this URL
      // Handle both PostgreSQL arrays and JSON array strings
      final response = await supabase
          .from('Tasks')
          .select(
              'id, headline, links, category_id, owner_id, created_at, finished, notes')
          .eq('owner_id', userId)
          .not('links', 'is', null);

      print('LinkEditScreen: Raw response length: ${response.length}');

      final tasks = <Task>[];
      for (final json in response) {
        try {
          // Handle links parsing manually to avoid PostgreSQL array errors
          final linksData = json['links'];
          List<String> parsedLinks = [];

          if (linksData is List) {
            // PostgreSQL array format
            parsedLinks = linksData
                .where((item) => item != null)
                .map((item) => item.toString())
                .toList();
          } else if (linksData is String) {
            // JSON array string format
            if (linksData.trim() == '[]' ||
                linksData.trim() == '{}' ||
                linksData.trim().isEmpty) {
              continue; // Skip empty arrays
            }
            try {
              final decoded = jsonDecode(linksData) as List;
              parsedLinks = decoded
                  .where((item) => item != null)
                  .map((item) => item.toString())
                  .toList();
            } catch (e) {
              print('LinkEditScreen: Error parsing JSON string: $e');
              continue; // Skip this task if parsing fails
            }
          }

          if (parsedLinks.isEmpty) continue;

          // Create a modified task JSON with parsed links and handle other null fields
          final modifiedTaskJson = Map<String, dynamic>.from(json);
          modifiedTaskJson['links'] = parsedLinks;

          // Handle other potentially null fields that might cause parsing errors
          if (modifiedTaskJson['notes'] == null) {
            modifiedTaskJson['notes'] = '';
          }
          if (modifiedTaskJson['processed_links'] == null) {
            modifiedTaskJson['processed_links'] = [];
          }

          // Add missing required fields if they're not present
          if (modifiedTaskJson['owner_id'] == null) {
            modifiedTaskJson['owner_id'] = AuthUtils.getCurrentUserId();
          }
          if (modifiedTaskJson['created_at'] == null) {
            modifiedTaskJson['created_at'] = DateTime.now().toIso8601String();
          }
          if (modifiedTaskJson['finished'] == null) {
            modifiedTaskJson['finished'] = false;
          }

          try {
            final task = Task.fromJson(modifiedTaskJson);
            tasks.add(task);
          } catch (e) {
            print('LinkEditScreen: Error creating Task object: $e');
            print('LinkEditScreen: Modified task JSON: $modifiedTaskJson');
            continue; // Skip this task if Task.fromJson fails
          }
        } catch (e) {
          print('LinkEditScreen: Error parsing task: $e');
          print('LinkEditScreen: Task JSON: $json');
          // Continue with other tasks
        }
      }

      print('LinkEditScreen: Checking ${tasks.length} tasks with valid links');

      for (final task in tasks) {
        // Skip the current task if we're editing
        if (widget.currentTask != null && task.id == widget.currentTask!.id) {
          print('LinkEditScreen: Skipping current task ${task.id}');
          continue;
        }

        print(
            'LinkEditScreen: Checking task "${task.headline}" with ${task.links!.length} links');

        for (final existingLink in task.links!) {
          final existingUrl = _extractUrlFromHtmlLink(existingLink);
          print('LinkEditScreen: Comparing $url with $existingUrl');
          if (existingUrl != null && existingUrl == url) {
            print(
                'LinkEditScreen: Found duplicate URL in task "${task.headline}" (ID: ${task.id})');
            return task;
          }
        }
      }

      print('LinkEditScreen: No duplicate links found across all tasks');
      return null;
    } catch (e) {
      print(
          'LinkEditScreen: Error checking for duplicates across all tasks: $e');
      return null;
    }
  }

  /// Helper method to extract URL from HTML link string
  String? _extractUrlFromHtmlLink(String htmlLink) {
    if (htmlLink.startsWith('<a href="') && htmlLink.contains('">')) {
      final startIndex = htmlLink.indexOf('href="') + 6;
      final endIndex = htmlLink.indexOf('">', startIndex);
      if (endIndex > startIndex) {
        return htmlLink.substring(startIndex, endIndex);
      }
    }
    // If it's not an HTML link, return as is (might be a plain URL)
    if (htmlLink.startsWith('http')) {
      return htmlLink;
    }
    return null;
  }

  /// Shows confirmation dialog for duplicate links
  Future<bool> _showDuplicateConfirmationDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Duplicate Link Found'),
            content: Text(
                'This link already exists in task "${_duplicateTaskName}". '
                'Do you want to add it anyway?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Add Anyway'),
              ),
            ],
          ),
        ) ??
        false;
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                    if (_lastDuplicateResult ==
                        DuplicateCheckResult.categoryDuplicate) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _isLoading ? null : _saveLinkAnyway,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                              ),
                              child: const Text('Save Anyway'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
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

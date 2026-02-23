import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/utils/cache_manager.dart';
import 'package:meaning_to/home_screen.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;

class LetterboxdImportScreen extends StatefulWidget {
  final Category category;

  const LetterboxdImportScreen({
    super.key,
    required this.category,
  });

  @override
  State<LetterboxdImportScreen> createState() => _LetterboxdImportScreenState();
}

class _LetterboxdImportScreenState extends State<LetterboxdImportScreen> {
  bool _isLoading = false;
  List<Map<String, String>> _parsedItems = [];
  String? _fileName;
  List<Task> _existingTasks = [];
  int _totalItemsParsed = 0;
  List<Map<String, dynamic>> _tasksToUpdate =
      []; // Tasks that need description updates

  @override
  void initState() {
    super.initState();
    _loadExistingTasks();
  }

  void _loadExistingTasks() {
    print(
        'LetterboxdImport: Loading existing tasks from cache for category: ${widget.category.headline}');
    try {
      final cacheManager = CacheManager();

      // Get tasks from cache if available
      final cachedTasks = cacheManager.currentTasks;
      if (cachedTasks != null) {
        // Filter for current category (cache might have all tasks)
        final categoryTasks = cachedTasks
            .where((task) => task.categoryId == widget.category.id)
            .toList();

        print(
            'LetterboxdImport: Loaded ${categoryTasks.length} existing tasks from cache');
        setState(() {
          _existingTasks = categoryTasks;
        });
      } else {
        print(
            'LetterboxdImport: No tasks in cache, proceeding without duplicate detection');
        setState(() {
          _existingTasks = [];
        });
      }
    } catch (e) {
      print('LetterboxdImport: Error loading existing tasks from cache: $e');
      // Don't throw - we can still proceed with import
      setState(() {
        _existingTasks = [];
      });
    }
  }

  /// Returns true if the item should be included, false to filter it out.
  bool _filterLetterboxdItem(String name, String uri) {
    // Check each existing task
    for (var task in _existingTasks) {
      // If task already has this link, skip it
      if (task.links?.any((link) => link.contains(uri)) ?? false) {
        print(
          'LetterboxdImport: Skipping $name because it already exists in task #${task.id}: ${task.headline}',
        );

        // Check if this existing task lacks a description and add it to update queue
        print(
            'LetterboxdImport: Task #${task.id} notes value: "${task.notes}" (length: ${task.notes?.length ?? 0})');
        if (task.notes == null || task.notes!.trim().isEmpty) {
          _tasksToUpdate.add({
            'task': task,
            'uri': uri,
          });
          print(
              'LetterboxdImport: Task #${task.id} lacks description - queued for description update');
        } else {
          print(
              'LetterboxdImport: Task #${task.id} already has description, skipping update');
        }

        return false;
      }

      // If task has matching headline, we could add this link to its links
      // For now, let's skip duplicates by headline too to keep it simple
      if (task.headline.trim().toLowerCase() == name.trim().toLowerCase()) {
        print(
          'LetterboxdImport: Skipping $name because task with same headline already exists: ${task.headline}',
        );

        // Check if this existing task lacks a description and add it to update queue
        print(
            'LetterboxdImport: Task ${task.headline} notes value: "${task.notes}" (length: ${task.notes?.length ?? 0})');
        if (task.notes == null || task.notes!.trim().isEmpty) {
          _tasksToUpdate.add({
            'task': task,
            'uri': uri,
          });
          print(
              'LetterboxdImport: Task ${task.headline} lacks description - queued for description update');
        } else {
          print(
              'LetterboxdImport: Task ${task.headline} already has description, skipping update');
        }

        return false;
      }
    }

    // No matches found, include this item
    return true;
  }

  /// Fetch description meta tag from a URL
  Future<String?> _fetchLetterboxdDescription(String url) async {
    // Skip description fetching for web platform due to CORS restrictions
    if (kIsWeb) {
      print(
          'LetterboxdImport: Skipping description fetch on web platform (CORS restriction) for: $url');
      return null;
    }

    try {
      print('LetterboxdImport: *** STARTING description fetch from: $url ***');

      // Handle boxd.it redirects by following them manually
      String finalUrl = url;
      if (url.contains('boxd.it')) {
        print(
            'LetterboxdImport: Detected boxd.it short URL, following redirect...');
        try {
          final redirectResponse = await http.head(Uri.parse(url));
          if (redirectResponse.headers.containsKey('location')) {
            finalUrl = redirectResponse.headers['location']!;
            print('LetterboxdImport: Redirect found, new URL: $finalUrl');
          } else {
            // If no location header, try GET request which should auto-redirect
            final testResponse = await http.get(Uri.parse(url));
            if (testResponse.request?.url != null) {
              finalUrl = testResponse.request!.url.toString();
              print('LetterboxdImport: Auto-redirected to: $finalUrl');
            }
          }
        } catch (e) {
          print(
              'LetterboxdImport: Error following redirect: $e, continuing with original URL');
        }
      }

      final response = await http.get(
        Uri.parse(finalUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.5',
          'Accept-Encoding': 'gzip, deflate, br',
          'DNT': '1',
          'Connection': 'keep-alive',
          'Upgrade-Insecure-Requests': '1',
        },
      );

      if (response.statusCode != 200) {
        print(
            'LetterboxdImport: HTTP status code ${response.statusCode} for URL: $url');
        return null;
      }

      final document = html_parser.parse(response.body);

      // Try different meta description tags in order of preference
      String? description;

      // First: Standard meta description
      description = document
          .querySelector('meta[name="description"]')
          ?.attributes['content']
          ?.trim();

      if (description != null && description.isNotEmpty) {
        print(
            'LetterboxdImport: Found description from meta[name="description"]: "$description"');
        return description;
      }

      // Second: Open Graph description (check both property formats)
      description = document
          .querySelector('meta[property="og:description"]')
          ?.attributes['content']
          ?.trim();

      if (description == null || description.isEmpty) {
        description = document
            .querySelector('meta[name="og:description"]')
            ?.attributes['content']
            ?.trim();
      }

      if (description != null && description.isNotEmpty) {
        print(
            'LetterboxdImport: Found description from og:description: "$description"');
        return description;
      }

      // Third: Twitter Card description
      description = document
          .querySelector('meta[name="twitter:description"]')
          ?.attributes['content']
          ?.trim();

      if (description != null && description.isNotEmpty) {
        print(
            'LetterboxdImport: Found description from twitter:description: "$description"');
        return description;
      }

      print(
          'LetterboxdImport: No meta description found, trying to extract main content...');

      // Try to get the film synopsis from the main content
      // Based on actual Letterboxd page structure, look for the synopsis section
      final synopsisSelectors = [
        'section[data-track-action="Synopsis"] .text-link p', // Main synopsis text
        '.synopsis .text-link p',
        '.film-synopsis p',
        'section:contains("Synopsis") p',
        '.body-text p',
        '.review.body-text.-prose.collapsible-text p', // Original selector
      ];

      for (final selector in synopsisSelectors) {
        final synopsisElement = document.querySelector(selector);
        if (synopsisElement != null) {
          final synopsis = synopsisElement.text.trim();
          if (synopsis.isNotEmpty && synopsis.length > 20) {
            print(
                'LetterboxdImport: Found synopsis using selector "$selector": "${synopsis.substring(0, synopsis.length > 100 ? 100 : synopsis.length)}..."');
            return synopsis;
          }
        }
      }

      // Alternative: Try other possible content selectors
      final alternatives = [
        '[data-original-text]',
        '.prose p',
        '.collapsible-text p',
      ];

      for (final selector in alternatives) {
        final element = document.querySelector(selector);
        if (element != null) {
          final text = element.text.trim();
          if (text.isNotEmpty && text.length > 20) {
            // Ensure it's substantial content
            print(
                'LetterboxdImport: Found description using selector "$selector": "${text.substring(0, text.length > 100 ? 100 : text.length)}..."');
            return text;
          }
        }
      }

      // Debug: Print meta tags to see what's available (focus on description-related tags)
      final metaTags = document.querySelectorAll('meta[name], meta[property]');
      print('LetterboxdImport: Found ${metaTags.length} meta tags for $url:');
      for (var meta in metaTags.take(10)) {
        // Show first 10
        final name = meta.attributes['name'] ?? meta.attributes['property'];
        final content = meta.attributes['content'];
        if (content != null) {
          // Show more content for description-related tags
          final isDescriptionTag =
              name?.toLowerCase().contains('description') ?? false;
          final maxLength = isDescriptionTag ? 200 : 80;
          print(
              '  $name: ${content.length > maxLength ? '${content.substring(0, maxLength)}...' : content}');
        }
      }

      print('LetterboxdImport: No description found for URL: $url');
      return null;
    } catch (e) {
      print('LetterboxdImport: Error fetching description for $url: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import from Letterboxd'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Instructions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'How to import your Letterboxd Watchlist:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '1. Go to letterboxd.com and sign in\n'
                    '2. Go to your profile and select "Watchlist"\n'
                    '3. Click the \'Export watchlist\' link (in the gray box on the right)\n'
                    '4. Save the CSV file to your computer\n'
                    '5. Come back here and click the \'Upload CSV File\' button below\n'
                    '6. Find the file you just downloaded and open it.',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Upload button
            Center(
              child: Column(
                children: [
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _selectFile,
                    icon: const Icon(Icons.upload_file),
                    label: Text(_fileName == null
                        ? 'Upload CSV File'
                        : 'Choose Different File'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(200, 48),
                    ),
                  ),
                  if (_fileName != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Selected: $_fileName',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Preview section
            if (_totalItemsParsed > 0) ...[
              if (_parsedItems.isNotEmpty) ...[
                Text(
                  'Preview (${_parsedItems.length} new items found):',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListView.builder(
                      itemCount:
                          _parsedItems.length > 10 ? 10 : _parsedItems.length,
                      itemBuilder: (context, index) {
                        final item = _parsedItems[index];
                        return ListTile(
                          leading: const Icon(Icons.movie),
                          title: Text(item['Name'] ?? 'Unknown'),
                          subtitle: Text(
                            item['Letterboxd URI'] ?? 'No link',
                            style: const TextStyle(fontSize: 12),
                          ),
                          dense: true,
                        );
                      },
                    ),
                  ),
                ),
              ] else ...[
                // All items are duplicates
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      border: Border.all(color: Colors.orange.shade200),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 43, // Reduced by one-third (64 * 2/3 ≈ 43)
                              color: Colors.orange.shade600,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'All ${_totalItemsParsed} items already exist!',
                              style: TextStyle(
                                fontSize:
                                    16, // Reduced by 4 points (20 - 4 = 16)
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade800,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'All the movies in your Letterboxd export are already in your "${widget.category.headline}" list.',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.orange.shade700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],

              if (_parsedItems.length > 10) ...[
                const SizedBox(height: 8),
                Text(
                  '... and ${_parsedItems.length - 10} more items',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],

              const SizedBox(height: 24),

              // Import/Update button
              if (_parsedItems.isNotEmpty) ...[
                Center(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _importItems,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download),
                    label: Text(_isLoading
                        ? 'Importing...'
                        : 'Import ${_parsedItems.length} Items'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(200, 48),
                    ),
                  ),
                ),
              ] else if (_tasksToUpdate.isNotEmpty) ...[
                // Tasks need description updates
                Center(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _importItems,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.description),
                    label: Text(_isLoading
                        ? 'Updating...'
                        : 'Update ${_tasksToUpdate.length} Descriptions'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(200, 48),
                    ),
                  ),
                ),
              ] else if (_totalItemsParsed > 0) ...[
                // All items are duplicates and no updates needed - show completion button
                Center(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.check),
                    label: const Text('All Items Already Added'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(200, 48),
                    ),
                  ),
                ),
              ],
            ],

            const Spacer(),
          ],
        ),
      ),
    );
  }

  Future<void> _selectFile() async {
    try {
      const typeGroup = XTypeGroup(
        label: 'CSV files',
        extensions: ['csv'],
      );

      final XFile? file = await openFile(
        acceptedTypeGroups: [typeGroup],
      );

      if (file != null) {
        setState(() {
          _fileName = file.name;
          _isLoading = true;
        });

        final String contents = await file.readAsString();
        final parsedItems = _parseLetterboxdCsv(contents);

        setState(() {
          _parsedItems = parsedItems;
          _isLoading = false;
          _tasksToUpdate.clear(); // Clear tasks to update when parsing new file
        });

        if (parsedItems.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'No valid items found in the CSV file. Make sure it has "Name" and "Letterboxd URI" columns.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error reading file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<Map<String, String>> _parseLetterboxdCsv(String csvContent) {
    final lines = csvContent.split('\n');
    if (lines.isEmpty) return [];

    // Find header line and column indices
    final headerLine = lines[0];
    final headers = _parseCsvLine(headerLine);

    print('LetterboxdImport: Parsing CSV with ${lines.length} lines');
    print('LetterboxdImport: Header line: "$headerLine"');
    print('LetterboxdImport: Parsed headers: $headers');

    final nameIndex =
        headers.indexWhere((h) => h.toLowerCase().contains('name'));
    final uriIndex =
        headers.indexWhere((h) => h.toLowerCase().contains('letterboxd uri'));

    print('LetterboxdImport: Name column index: $nameIndex');
    print('LetterboxdImport: URI column index: $uriIndex');

    if (nameIndex == -1 || uriIndex == -1) {
      print(
          'LetterboxdImport: Could not find required columns. Headers: $headers');
      return [];
    }

    final items = <Map<String, String>>[];
    int totalValidItems = 0;

    // Process data lines (skip header)
    for (int i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final fields = _parseCsvLine(line);
      print(
          'LetterboxdImport: Line ${i + 1}: ${fields.length} fields - $fields');

      if (fields.length > nameIndex && fields.length > uriIndex) {
        final name = fields[nameIndex].trim();
        final uri = fields[uriIndex].trim();

        print('LetterboxdImport: Extracted - Name: "$name", URI: "$uri"');

        if (name.isNotEmpty && uri.isNotEmpty) {
          totalValidItems++; // Count all valid items before filtering

          // Apply duplicate filtering
          if (_filterLetterboxdItem(name, uri)) {
            print('LetterboxdImport: Adding new item: $name');
            items.add({
              'Name': name,
              'Letterboxd URI': uri,
            });
          } else {
            print('LetterboxdImport: Skipping duplicate: $name');
          }
        } else {
          print('LetterboxdImport: Skipping empty name or URI');
        }
      } else {
        print(
            'LetterboxdImport: Skipping line - not enough fields (expected > ${[
          nameIndex,
          uriIndex
        ].reduce((a, b) => a > b ? a : b)})');
      }
    }

    _totalItemsParsed = totalValidItems;
    print(
        'LetterboxdImport: Parsed ${items.length} items from CSV (${totalValidItems} total, ${totalValidItems - items.length} duplicates skipped)');
    return items;
  }

  List<String> _parseCsvLine(String line) {
    final List<String> result = [];
    bool inQuotes = false;
    String currentField = '';

    for (int i = 0; i < line.length; i++) {
      final char = line[i];

      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        result.add(currentField);
        currentField = '';
      } else {
        currentField += char;
      }
    }

    // Add the last field
    result.add(currentField);

    return result;
  }

  Future<void> _importItems() async {
    if (_parsedItems.isEmpty && _tasksToUpdate.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final userId = AuthUtils.getCurrentUserId();
      final cacheManager = CacheManager();

      // Initialize cache manager with current category
      await cacheManager.initializeWithSavedCategory(widget.category, userId);

      int importedCount = 0;
      int updatedCount = 0;
      final now = DateTime.now();

      // Process new items
      for (final item in _parsedItems) {
        final name = item['Name']!;
        final uri = item['Letterboxd URI']!;

        print('LetterboxdImport: Processing new item: $name with URI: $uri');

        // Fetch description from the Letterboxd page
        final description = await _fetchLetterboxdDescription(uri);

        // Format notes similar to JustWatch imports
        String? formattedNotes;
        if (description != null && description.isNotEmpty) {
          // Truncate to first 100 characters
          String truncatedDescription = description.length > 100
              ? '${description.substring(0, 100)}...'
              : description;

          // Create formatted notes with description + Letterboxd link
          formattedNotes = '$truncatedDescription <a href="$uri">(more)</a>';
        } else {
          // Leave notes as null if no description is found
          // This allows the TaskDisplay widget to fetch descriptions dynamically
          formattedNotes = null;
        }

        // Create task with Letterboxd link
        final task = Task(
          id: now.millisecondsSinceEpoch + importedCount, // Ensure unique IDs
          categoryId: widget.category.id,
          ownerId: userId,
          headline: name,
          notes: formattedNotes,
          links: ['<a href="$uri">$name</a>'], // Create HTML link
          processedLinks: null,
          createdAt: now,
          suggestibleAt: null, // Make new tasks appear at the beginning
          finished: false,
        );

        // Add to cache and database
        await cacheManager.addTask(task);
        importedCount++;
      }

      // Process existing tasks that need description updates
      print(
          'LetterboxdImport: Processing ${_tasksToUpdate.length} tasks for description updates');
      for (final updateInfo in _tasksToUpdate) {
        final task = updateInfo['task'] as Task;
        final uri = updateInfo['uri'] as String;

        print(
            'LetterboxdImport: Updating description for existing task: ${task.headline}');

        // Fetch description from the Letterboxd page
        final description = await _fetchLetterboxdDescription(uri);

        String? formattedNotes;
        if (description != null && description.isNotEmpty) {
          // Truncate to first 100 characters
          String truncatedDescription = description.length > 100
              ? '${description.substring(0, 100)}...'
              : description;

          // Create formatted notes with description + Letterboxd link
          formattedNotes = '$truncatedDescription <a href="$uri">(more)</a>';
        } else {
          // Leave notes as null if no description is found
          // This allows the TaskDisplay widget to fetch descriptions dynamically
          formattedNotes = null;
        }

        // Update the task with the new description
        final updatedTask = Task(
          id: task.id,
          categoryId: task.categoryId,
          headline: task.headline,
          notes: formattedNotes,
          ownerId: task.ownerId,
          createdAt: task.createdAt,
          suggestibleAt: task.suggestibleAt,
          triggersAt: task.triggersAt,
          deferral: task.deferral,
          links: task.links,
          processedLinks: task.processedLinks,
          finished: task.finished,
          shared: task.shared,
          originalId: task.originalId,
          dirty: true, // Mark as dirty to trigger database update
        );
        await cacheManager.updateTask(updatedTask);
        updatedCount++;

        print(
            'LetterboxdImport: Successfully updated task #${task.id} with description');
      }

      if (mounted) {
        String message;
        if (importedCount > 0 && updatedCount > 0) {
          message =
              'Successfully imported $importedCount new items and updated $updatedCount existing items with descriptions!';
        } else if (importedCount > 0) {
          message =
              'Successfully imported $importedCount items from Letterboxd!';
        } else if (updatedCount > 0) {
          message =
              'Successfully updated $updatedCount existing items with descriptions!';
        } else {
          message = 'No changes made.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
          ),
        );

        // Mark data as modified so HomeScreen knows to refresh
        final homeScreenType = context
            .findAncestorWidgetOfExactType<HomeScreen>();
        if (homeScreenType != null) {
          HomeScreen.markDataModified();
          print('LetterboxdImport: Marked home screen data as modified');
        }

        // Return the updated category
        Navigator.pop(context, widget.category);
      }
    } catch (e) {
      print('LetterboxdImport: Error importing items: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error importing items: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}

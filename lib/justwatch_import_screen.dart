import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:meaning_to/models/category.dart' as models;
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/utils/justwatch_client.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/utils/supabase_client.dart';
import 'package:meaning_to/utils/cache_manager.dart';
import 'package:meaning_to/edit_category_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class JustWatchImportScreen extends StatefulWidget {
  final models.Category category;

  const JustWatchImportScreen({
    super.key,
    required this.category,
  });

  @override
  State<JustWatchImportScreen> createState() => _JustWatchImportScreenState();
}

class _JustWatchImportScreenState extends State<JustWatchImportScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _justWatchClient = JustWatchClient();

  bool _isLoading = false;
  bool _isLoggedIn = false;
  bool _obscurePassword = true;
  String? _error;
  List<JustWatchTitle> _filteredTitles = [];
  String? _titlesFoundMessage;
  int? _totalTitlesFound;
  int _redundantTitlesCount = 0;
  bool _isProcessingImport = false;
  Set<String> _existingJustWatchPaths = {};

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Convert JustWatch API data to the format expected by the existing import functionality
  List<Map<String, dynamic>> _convertToJsonFormat(List<JustWatchTitle> titles) {
    return titles
        .map((title) => {
              'node': {
                'id': title.id,
                'objectId': title.objectId,
                'objectType': title.objectType,
                'content': {
                  'title': title.title,
                  'fullPath': title.fullPath,
                  'originalReleaseYear': title.originalReleaseYear,
                  'shortDescription': title.shortDescription,
                  'scoring': {
                    'imdbScore': title.imdbScore,
                    'imdbVotes': title.imdbVotes,
                    'tmdbScore': title.tmdbScore,
                    'tmdbPopularity': title.tmdbPopularity,
                  },
                  'posterUrl': title.posterUrl,
                  'backdrops': title.backdropUrls
                      .map((url) => {'backdropUrl': url})
                      .toList(),
                  'isReleased': title.isReleased,
                },
                'watchNowOffer': title.watchNowUrl != null
                    ? {
                        'standardWebURL': title.watchNowUrl,
                        'package': title.packageName != null
                            ? {
                                'clearName': title.packageName,
                              }
                            : null,
                      }
                    : null,
                'seenState': {
                  'seenEpisodeCount': title.seenEpisodeCount,
                  'releasedEpisodeCount': title.releasedEpisodeCount,
                  'progress': title.progress,
                  'caughtUp': title.caughtUp,
                  'lastSeenEpisodeNumber': title.lastSeenEpisodeNumber,
                  'lastSeenSeasonNumber': title.lastSeenSeasonNumber,
                },
              }
            })
        .toList();
  }

  /// Directly import tasks from JSON data
  Future<void> _importTasksFromJsonData(dynamic jsonData) async {
    print('=== _importTasksFromJsonData START ===');
    print('JSON data type: ${jsonData.runtimeType}');

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      List<Task> tasks = [];
      String targetType = '';

      if (jsonData is List) {
        print('Processing JSON list with ${jsonData.length} items');

        for (var item in jsonData) {
          print('Processing item: $item');

          if (item is Map<String, dynamic>) {
            final node = item['node'] as Map<String, dynamic>?;
            if (node != null) {
              targetType = node['targetType']?.toString() ?? '';
              print('TargetType: $targetType');

              final content = node['content'];
              if (content is Map) {
                final title = content['title']?.toString() ?? 'Unknown Title';
                print('Processing title: "$title"');

                // Aggressive logging for "Andor" - regardless of type
                if (title.toLowerCase().contains('andor')) {
                  print('🎬🎬🎬 ANDOR FOUND - COMPREHENSIVE DEBUG 🎬🎬🎬');
                  print('Title: "$title"');
                  print('TargetType: $targetType');
                  print('Full node JSON: $node');
                  print('Content: $content');
                  print('🎬🎬🎬 END ANDOR COMPREHENSIVE DEBUG 🎬🎬🎬');
                }

                final fullPath =
                    'https://www.justwatch.com${content['fullPath']?.toString() ?? ''}';

                // Create JustWatch link
                final justWatchLink = '<a href="$fullPath">$title</a>';

                // Extract shortDescription and create formatted notes
                final shortDescription = content['shortDescription']?.toString() ?? '';
                String? formattedNotes;
                if (shortDescription.isNotEmpty) {
                  // Truncate to first 100 characters
                  String truncatedDescription = shortDescription.length > 100
                      ? '${shortDescription.substring(0, 100)}...'
                      : shortDescription;
                  
                  // Create formatted notes with description + JustWatch link
                  formattedNotes = '$truncatedDescription <a href="$fullPath">(more)</a>';
                }

                // Check if this is a TV show and determine if it's finished
                bool isFinished = false;
                if (targetType == 'SHOW') {
                  print('Processing as SHOW type for: "$title"');
                  final seenState = node['seenState'] as Map<String, dynamic>?;
                  if (seenState != null) {
                    print('Found seenState for: "$title"');
                    final releasedEpisodeCount =
                        seenState['releasedEpisodeCount'] as int?;
                    final lastSeenEpisodeNumber =
                        seenState['lastSeenEpisodeNumber'] as int?;

                    // Temporary logging for "Andor"
                    if (title.toLowerCase().contains('andor')) {
                      print('🎬🎬🎬 ANDOR DEBUG LOGGING 🎬🎬🎬');
                      print('Title: "$title"');
                      print('Full node JSON: $node');
                      print('SeenState: $seenState');
                      print('ReleasedEpisodeCount: $releasedEpisodeCount');
                      print('LastSeenEpisodeNumber: $lastSeenEpisodeNumber');
                      print(
                          'ReleasedEpisodeCount type: ${releasedEpisodeCount.runtimeType}');
                      print(
                          'LastSeenEpisodeNumber type: ${lastSeenEpisodeNumber.runtimeType}');
                      print(
                          'Are they equal? ${releasedEpisodeCount == lastSeenEpisodeNumber}');
                      print('🎬🎬🎬 END ANDOR DEBUG 🎬🎬🎬');
                    }

                    // If releasedEpisodeCount equals lastSeenEpisodeNumber, the show is finished
                    if (releasedEpisodeCount != null &&
                        lastSeenEpisodeNumber != null &&
                        releasedEpisodeCount == lastSeenEpisodeNumber) {
                      isFinished = true;
                      print('Setting finished to TRUE for: "$title"');

                      // Additional logging for Andor
                      if (title.toLowerCase().contains('andor')) {
                        print('🎬🎬🎬 ANDOR: Setting finished to TRUE 🎬🎬🎬');
                      }
                    } else {
                      print(
                          'Setting finished to FALSE for: "$title" (releasedEpisodeCount: $releasedEpisodeCount, lastSeenEpisodeNumber: $lastSeenEpisodeNumber)');
                      // Additional logging for Andor when not finished
                      if (title.toLowerCase().contains('andor')) {
                        print('🎬🎬🎬 ANDOR: Setting finished to FALSE 🎬🎬🎬');
                        print(
                            'Reason: releasedEpisodeCount ($releasedEpisodeCount) != lastSeenEpisodeNumber ($lastSeenEpisodeNumber)');
                      }
                    }
                  } else {
                    print('No seenState found for: "$title"');
                    // Additional logging for Andor when no seenState
                    if (title.toLowerCase().contains('andor')) {
                      print('🎬🎬🎬 ANDOR: No seenState found 🎬🎬🎬');
                    }
                  }
                } else {
                  print(
                      'Not a SHOW type for: "$title", targetType is: $targetType');
                  // Log if Andor is not a SHOW type
                  if (title.toLowerCase().contains('andor')) {
                    print(
                        '🎬🎬🎬 ANDOR: Not a SHOW type, targetType is: $targetType 🎬🎬🎬');
                  }
                }

                // No need to check for duplicates here since it's already done
                tasks.add(
                  Task(
                    id: -1,
                    categoryId: widget.category.id,
                    headline: title,
                    notes: formattedNotes,
                    ownerId: '',
                    createdAt: DateTime.now(),
                    suggestibleAt: DateTime.now(),
                    triggersAt: null,
                    deferral: null,
                    links: [justWatchLink],
                    processedLinks: null,
                    finished: isFinished,
                  ),
                );
              }
            }
          }
        }

        // Sort tasks by headline
        tasks.sort((a, b) => a.headline.compareTo(b.headline));

        // Import all available tasks
        final tasksToImport = tasks;

        if (tasksToImport.isEmpty) {
          setState(() {
            _error = 'No matching items found to import';
            _isLoading = false;
          });
          return;
        }

        // Import tasks to database
        await _importTasksToDatabase(tasksToImport);
      } else {
        setState(() {
          _error = 'Invalid JSON format: expected a list';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error processing data: $e';
        _isLoading = false;
      });
    }
  }

  /// Import tasks to database
  Future<void> _importTasksToDatabase(List<Task> tasks) async {
    try {
      final userId = AuthUtils.getCurrentUserId();

      for (var task in tasks) {
        final taskData = {
          'category_id': task.categoryId,
          'headline': task.headline,
          'notes': task.notes,
          'owner_id': userId,
          'created_at': task.createdAt.toIso8601String(),
          'suggestible_at': task.suggestibleAt?.toIso8601String(),
          'triggers_at': task.triggersAt?.toIso8601String(),
          'deferral': task.deferral,
          'links': Task.linksToArray(task.links ?? []),
          'finished': task.finished,
        };

        await supabase.from('Tasks').insert(taskData).select().single();
      }

      // Refresh the cache
      try {
        EditCategoryScreen.onImportComplete = () {
          // print('JustWatchImportScreen: Import complete callback triggered');
        };

        final cacheManager = CacheManager();
        await cacheManager.refreshCurrentCategoryTasks();
      } catch (e) {
        // print('Error refreshing cache: $e');
      }

      // Return to EditCategoryScreen
      if (mounted) {
        Navigator.pop(context, widget.category);
      }
    } catch (e) {
      setState(() {
        _error = 'Error importing tasks: $e';
        _isLoading = false;
      });
    }
  }

  /// Generate message based on number of titles found
  String _getTitlesFoundMessage(int totalTitles) {
    if (totalTitles == 0) {
      return 'No titles found in your JustWatch library.';
    } else if (totalTitles == 1) {
      return 'Found 1 title in your JustWatch library (movies and TV shows)! Processing...';
    } else if (totalTitles <= 10) {
      return 'Found $totalTitles titles in your JustWatch library (movies and TV shows)! Processing...';
    } else {
      return 'Found $totalTitles titles in your JustWatch library (movies and TV shows)! Give us a minute while we go through all that.';
    }
  }

  /// Generate the final status message with redundancy info
  String _getFinalStatusMessage() {
    final movieType = widget.category.originalId == 1 ? 'movie' : 'show';
    final movieTypePlural = widget.category.originalId == 1 ? 'movies' : 'shows';
    
    // If everything is redundant
    if (_filteredTitles.isEmpty && _redundantTitlesCount > 0) {
      return "Looks like everything's already here.";
    }
    
    // Build the main message
    String mainMessage;
    if (_filteredTitles.length == 1) {
      mainMessage = 'Found 1 $movieType ready to import';
    } else {
      mainMessage = 'Found ${_filteredTitles.length} $movieTypePlural ready to import';
    }
    
    return mainMessage;
  }

  /// Generate the redundancy message if there are redundant titles
  String? _getRedundancyMessage() {
    if (_redundantTitlesCount == 0) {
      return null;
    }
    
    if (_redundantTitlesCount == 1) {
      return '1 title is already here.';
    } else {
      return '$_redundantTitlesCount titles are already here.';
    }
  }

  /// Convert technical error messages to user-friendly messages
  String _getFriendlyLoginErrorMessage(String errorMessage) {
    final lowerError = errorMessage.toLowerCase();
    
    // Check for common authentication error patterns
    if (lowerError.contains('invalid_password') || 
        lowerError.contains('wrong password') ||
        lowerError.contains('password is invalid')) {
      return 'The password you entered is incorrect. Please check your password and try again.';
    }
    
    if (lowerError.contains('email_not_found') || 
        lowerError.contains('user not found') ||
        lowerError.contains('email address is not registered')) {
      return 'No account found with this email address. Please check your email or sign up for a new account.';
    }
    
    if (lowerError.contains('user_disabled') || 
        lowerError.contains('account has been disabled')) {
      return 'This account has been disabled. Please contact JustWatch support for assistance.';
    }
    
    if (lowerError.contains('too_many_attempts') || 
        lowerError.contains('too many failed attempts') ||
        lowerError.contains('temporarily disabled')) {
      return 'Too many failed login attempts. Please wait a while before trying again.';
    }
    
    if (lowerError.contains('invalid_email') || 
        lowerError.contains('email address is badly formatted')) {
      return 'Please enter a valid email address.';
    }
    
    if (lowerError.contains('network') || 
        lowerError.contains('connection') ||
        lowerError.contains('timeout')) {
      return 'Network error. Please check your internet connection and try again.';
    }
    
    if (lowerError.contains('400') && lowerError.contains('bad request')) {
      return 'Invalid login credentials. Please check your email and password.';
    }
    
    if (lowerError.contains('401') && lowerError.contains('unauthorized')) {
      return 'Login failed. Please check your email and password and try again.';
    }
    
    if (lowerError.contains('403') && lowerError.contains('forbidden')) {
      return 'Access denied. Your account may not have permission to access JustWatch.';
    }
    
    if (lowerError.contains('429') && lowerError.contains('too many requests')) {
      return 'Too many login attempts. Please wait a few minutes before trying again.';
    }
    
    // If no specific pattern matches, provide a generic but helpful message
    return 'Login failed. Please check your JustWatch email and password and try again. If the problem persists, verify your credentials on the JustWatch website.';
  }

  /// Build a cache of existing JustWatch paths from current tasks
  Future<void> _buildJustWatchPathsCache() async {
    try {
      final userId = AuthUtils.getCurrentUserId();
      final response = await supabase
          .from('Tasks')
          .select('links')
          .eq('category_id', widget.category.id)
          .eq('owner_id', userId);

      final paths = <String>{};
      
      for (final taskData in response) {
        final links = taskData['links'] as List<dynamic>?;
        if (links != null) {
          for (final link in links) {
            final linkStr = link.toString();
            // Extract href from HTML link tags like <a href="https://www.justwatch.com/us/movie/title">Title</a>
            final hrefMatch = RegExp(r'href="([^"]*)"').firstMatch(linkStr);
            if (hrefMatch != null) {
              final url = hrefMatch.group(1)!;
              // Extract path relative to justwatch.com
              if (url.contains('justwatch.com')) {
                final uri = Uri.parse(url);
                if (uri.host.contains('justwatch.com')) {
                  paths.add(uri.path);
                }
              }
            }
          }
        }
      }
      
      setState(() {
        _existingJustWatchPaths = paths;
      });
      
      print('JustWatch paths cache built: ${paths.length} existing paths found for fast duplicate detection');
    } catch (e) {
      print('Error building JustWatch paths cache: $e');
      // Continue without cache - fallback to existing behavior
      setState(() {
        _existingJustWatchPaths = {};
      });
    }
  }

  Future<void> _login() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() {
        _error = 'Please enter both email and password';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Generate and register device ID
      final deviceId = _justWatchClient.generateDeviceId();
      await _justWatchClient.registerDevice(deviceId);

      // Login
      await _justWatchClient.login(
          _emailController.text, _passwordController.text);

      setState(() {
        _isLoggedIn = true;
        // Don't set _isLoading = false here, keep loading until we have titles info
      });

      // Fetch titles
      await _fetchTitles();
    } catch (e) {
      String friendlyErrorMessage = _getFriendlyLoginErrorMessage(e.toString());
      setState(() {
        _error = friendlyErrorMessage;
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchTitles() async {
    // Don't reset loading state here since we're already loading from login
    setState(() {
      _error = null;
    });

    try {
      // Build cache of existing JustWatch paths before processing
      await _buildJustWatchPathsCache();
      
      final titles = await _justWatchClient.getTitleList();
      
      // Update UI to show titles found and continue processing
      setState(() {
        _titlesFoundMessage = _getTitlesFoundMessage(titles.length);
        _totalTitlesFound = titles.length;
      });
      
      final filteredTitles = await _filterTitlesAndRemoveDuplicates(titles);
      setState(() {
        _filteredTitles = filteredTitles;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to fetch titles: $e';
        _isLoading = false;
      });
    }
  }

  Future<List<JustWatchTitle>> _filterTitlesAndRemoveDuplicates(
      List<JustWatchTitle> titles) async {
    final targetType = widget.category.originalId == 1 ? 'MOVIE' : 'SHOW';
    final filteredTitles = titles
        .where((title) => title.objectType.toUpperCase() == targetType)
        .toList();

    // Remove duplicates by checking existing JustWatch paths cache
    final List<JustWatchTitle> nonDuplicateTitles = [];
    int redundantCount = 0;

    for (final title in filteredTitles) {
      // Quick check using the paths cache
      final isDuplicate = _existingJustWatchPaths.contains(title.fullPath);
      if (!isDuplicate) {
        nonDuplicateTitles.add(title);
      } else {
        redundantCount++;
        print('Fast duplicate detected: ${title.title} (path: ${title.fullPath})');
      }
    }

    // Update redundant count in state
    setState(() {
      _redundantTitlesCount = redundantCount;
    });

    return nonDuplicateTitles;
  }


  Future<void> _processTitles() async {
    setState(() {
      _isLoading = true;
      _isProcessingImport = true;
      _error = null;
    });

    try {
      // Process all filtered titles
      final titlesToProcess = _filteredTitles;

      // Convert to the format expected by the existing import functionality
      final jsonData = _convertToJsonFormat(titlesToProcess);

      // Directly import the tasks
      await _importTasksFromJsonData(jsonData);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to process titles: $e';
        _isLoading = false;
        _isProcessingImport = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isProcessingImport = false;
        });
      }
    }
  }

  /// Pick and parse a JSON file
  Future<void> _pickAndParseFile() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // Request permissions first (only on Android, not web)
      if (!kIsWeb && Platform.isAndroid) {
        try {
          await _requestAndroidPermissions();
        } catch (e) {
          setState(() {
            _error = e.toString();
            _isLoading = false;
          });
          return;
        }
      }

      try {
        if (kIsWeb) {
          // Web-specific file picker
          await _pickFileWeb();
        } else {
          // Mobile/Desktop file picker
          await _pickFileNative();
        }
      } catch (e) {
        setState(() {
          _error = 'Error processing file: $e';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _requestAndroidPermissions() async {
    final status = await Permission.storage.status;
    if (!status.isGranted) {
      final result = await Permission.storage.request();
      if (!result.isGranted) {
        throw Exception('Storage permission required to access files');
      }
    }
  }

  Future<void> _pickFileWeb() async {
    // For web, we'll use a simple approach - just show a message
    // In a real implementation, you'd use dart:js_interop or a web-specific package
    setState(() {
      _error =
          'Web file picking not implemented yet. Please use the API option or download the file and use a mobile/desktop app.';
      _isLoading = false;
    });
  }

  Future<void> _pickFileNative() async {
    const typeGroup = XTypeGroup(
      label: 'JSON files',
      extensions: ['json'],
    );

    final XFile? file = await openFile(
      acceptedTypeGroups: [typeGroup],
    );

    if (file == null) {
      return;
    }

    // Read file content
    final contents = await file.readAsString();
    await _importTasksFromJsonData(json.decode(contents));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Import from JustWatch - ${widget.category.headline}'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Always show the content section with both options
            _buildContentSection(),
            if (_isLoading) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: Colors.red.shade800),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildContentSection() {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // File import option
          // Card(
          //   child: Padding(
          //     padding: const EdgeInsets.all(16.0),
          //     child: Column(
          //       crossAxisAlignment: CrossAxisAlignment.stretch,
          //       children: [
          //         const Text(
          //           'Import from JSON File',
          //           style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          //         ),
          //         const SizedBox(height: 8),
          //         const Text(
          //           'Browse for a JustWatch JSON export file',
          //           style: TextStyle(fontSize: 14, color: Colors.grey),
          //         ),
          //         const SizedBox(height: 16),
          //         ElevatedButton.icon(
          //           onPressed: _isLoading ? null : _pickAndParseFile,
          //           icon: const Icon(Icons.folder_open),
          //           label: const Text('Browse for JSON File'),
          //           style: ElevatedButton.styleFrom(
          //             backgroundColor: Colors.blue,
          //             foregroundColor: Colors.white,
          //           ),
          //         ),
          //       ],
          //     ),
          //   ),
          // ),
          // const SizedBox(height: 16),
          // API import option
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_isLoggedIn) ...[
                    const Text(
                      'Login to JustWatch to fetch your titles',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                      obscureText: _obscurePassword,
                      enableInteractiveSelection: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      textInputAction: TextInputAction.done,
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _login,
                        icon: const Icon(Icons.login),
                        label: const Text('Login to JustWatch'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ] else ...[
                    // Show different states based on progress
                    if (_isProcessingImport) ...[
                      // Import/processing state - highest priority
                      Text(
                        'Processing ${_filteredTitles.length} ${_filteredTitles.length == 1 ? (widget.category.originalId == 1 ? 'movie' : 'show') : (widget.category.originalId == 1 ? 'movies' : 'shows')}...',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 16),
                      const CircularProgressIndicator(),
                    ] else if (_isLoading && _filteredTitles.isEmpty && _titlesFoundMessage == null) ...[
                      // Initial loading after login - fetching titles
                      const Text(
                        'Fetching your JustWatch library...',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 16),
                      const CircularProgressIndicator(),
                    ] else if (_titlesFoundMessage != null && _isLoading) ...[
                      // Processing titles after fetching
                      Text(
                        _titlesFoundMessage!,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 16),
                      const CircularProgressIndicator(),
                    ] else ...[
                      // Final state - ready to import
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Show redundancy message if there are redundant titles
                          if (_getRedundancyMessage() != null) ...[
                            Text(
                              _getRedundancyMessage()!,
                              style: const TextStyle(fontSize: 14, color: Colors.orange, fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 8),
                          ],
                          // Main status message
                          Text(
                            _getFinalStatusMessage(),
                            style: const TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                          const SizedBox(height: 16),
                          // Only show button if there are titles to import
                          if (_filteredTitles.isNotEmpty) ...[
                            ElevatedButton.icon(
                              onPressed: _isLoading ? null : _processTitles,
                              icon: const Icon(Icons.api),
                              label: const Text('Process All Titles'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Titles list (only show if we have titles from API)
          if (_filteredTitles.isNotEmpty) ...[
            Expanded(
              child: ListView.builder(
                itemCount: _filteredTitles.length,
                itemBuilder: (context, index) {
                  final title = _filteredTitles[index];

                  return Card(
                    color: Colors.blue.shade50, // All titles will be processed
                    child: ListTile(
                      leading: Stack(
                        children: [
                          if (title.posterUrl != null)
                            Image.network(
                              title.posterUrl!,
                              width: 50,
                              height: 75,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(Icons.movie),
                            )
                          else
                            const Icon(Icons.movie),
                          Positioned( // All titles will be processed
                              top: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: Colors.blue,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  '3',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      title: Text(
                        title.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold, // All titles will be processed
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (title.originalReleaseYear != null)
                            Text('${title.originalReleaseYear}'),
                          if (title.imdbScore != null)
                            Text(
                                'IMDB: ${title.imdbScore!.toStringAsFixed(1)}'),
                          if (title.packageName != null)
                            Text('Available on: ${title.packageName}'),
                          Text(
                            'Will be processed', // All titles will be processed
                            style: TextStyle(
                              color: Colors.blue.shade700,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      onTap: () {
                        // Show title details or toggle selection
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

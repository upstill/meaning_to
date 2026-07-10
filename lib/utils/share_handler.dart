import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:share_handler/share_handler.dart';
import 'dart:async';
import 'package:meaning_to/home_screen.dart';
import 'package:meaning_to/utils/pending_intent_store.dart';

class ShareHandler {
  static final ShareHandler _instance = ShareHandler._internal();
  factory ShareHandler() => _instance;

  ShareHandler._internal();

  StreamSubscription<SharedMedia?>? _shareSubscription;
  String? _sharedText;
  late GlobalKey<NavigatorState> _navigatorKey;
  String?
      _pendingContent; // Store content that needs processing when context is available

  /// Initialize the share handler and set up listeners
  void initialize({
    required void Function(String type, dynamic data) onIntentReceived,
    required GlobalKey<ScaffoldMessengerState> scaffoldKey,
    required GlobalKey<NavigatorState> navigatorKey,
  }) {
    _navigatorKey = navigatorKey;

    // share_handler has no web implementation — skip entirely on web
    if (kIsWeb) return;

    // Listen for shared content
    try {
      _shareSubscription =
          ShareHandlerPlatform.instance.sharedMediaStream.listen(
        (SharedMedia? media) {
          if (media?.content != null) {
            _sharedText = media!.content;
            _logContextAwareIntent('Text Share', media, onIntentReceived);
          }
        },
        onError: (err) {
          print('Share handler error: $err');
          _logContextAwareIntent(
              'Share Handler Error', err.toString(), onIntentReceived);
        },
      );
    } catch (e, stackTrace) {
      print('Share handler stream setup failed: $e');
      print('Share handler stream stack trace: $stackTrace');
    }

    // Get initial shared content if app was launched via share intent
    try {
      ShareHandlerPlatform.instance
          .getInitialSharedMedia()
          .then((SharedMedia? media) {
        if (media?.content != null) {
          _sharedText = media!.content;
          _logContextAwareIntent('Initial Text Share', media, onIntentReceived);
        }
      }).catchError((error, stackTrace) {
        print('Share handler initial media failed: $error');
        print('Share handler initial media stack trace: $stackTrace');
      });
    } catch (e, stackTrace) {
      print('Share handler initial setup threw: $e');
      print('Share handler initial setup stack trace: $stackTrace');
    }
  }

  /// Log intent with context awareness
  void _logContextAwareIntent(String type, dynamic data,
      void Function(String, dynamic) onIntentReceived) {
    print(
        '🚀🚀🚀 SHAREHANDLER: NEW CODE RUNNING - PROCESSING INTENT: $type 🚀🚀🚀');
    final context = _navigatorKey.currentContext;

    print(
        'ShareHandler: Context check - context is ${context != null ? 'AVAILABLE' : 'NULL'}');

    if (context == null) {
      print('ShareHandler: No context available, will process content later');
      // Still process the shared content, but schedule it for when context is available
      _scheduleContentProcessing(type, data);
      onIntentReceived(type, data);
      return;
    }

    print(
        'ShareHandler: Context is available, proceeding with normal processing');

    // Get the current route
    print('ShareHandler: STEP 1 - Getting current route...');
    final currentRoute = ModalRoute.of(context);
    print(
        'ShareHandler: STEP 2 - Current route: ${currentRoute?.settings.name ?? 'null'}');

    // Don't return early if currentRoute is null - we can still process shared content
    print(
        'ShareHandler: STEP 4 - Continuing with context info (route may be null during startup)...');

    // Add context information to the data
    print('ShareHandler: STEP 5 - Creating contextInfo object...');
    final contextInfo = <String, dynamic>{
      'data': data,
      'context': {
        'route': currentRoute?.settings.name ?? 'startup',
      }
    };
    print('ShareHandler: STEP 6 - contextInfo created successfully');

    // Add source app information if this is a SharedMedia object
    print('ShareHandler: STEP 7 - Checking if data is SharedMedia...');
    if (data is SharedMedia) {
      print(
          'ShareHandler: STEP 8 - Data is SharedMedia, adding source info...');
      contextInfo['source'] = <String, dynamic>{
        'content': data.content,
        'serviceName': data.serviceName,
        'senderIdentifier': data.senderIdentifier,
        'speakableGroupName': data.speakableGroupName,
        'conversationIdentifier': data.conversationIdentifier,
        'attachments': data.attachments?.length ?? 0,
      };
      print('ShareHandler: STEP 9 - Source info added successfully');
    } else {
      print(
          'ShareHandler: STEP 8 - Data is not SharedMedia, skipping source info');
    }

    // Add HomeScreen specific information
    print('ShareHandler: STEP 10 - Checking route for screen-specific info...');
    final routeName = currentRoute?.settings.name;
    if (routeName == '/home') {
      print(
          'ShareHandler: STEP 11 - On home route, looking for HomeScreenState...');
      final homeState = context.findAncestorStateOfType<HomeScreenState>();
      if (homeState != null) {
        print(
            'ShareHandler: STEP 12 - Found HomeScreenState, adding category info...');
        contextInfo['context']['currentCategory'] =
            homeState.selectedCategory?.headline;
        contextInfo['context']['hasCategory'] =
            homeState.selectedCategory != null;
        print('ShareHandler: STEP 13 - Home screen category info added');
      } else {
        print('ShareHandler: STEP 12 - No HomeScreenState found');
      }
    } else {
      print(
          'ShareHandler: STEP 11 - Not on home route: ${routeName ?? 'null'}');
    }

    // Log the intent with context information
    print('ShareHandler: STEP 17 - About to log intent details...');
    print('\n=== Intent Received with Context ===');
    print('Type: $type');
    print('Route: ${contextInfo['context']['route']}');
    if (contextInfo['context']['currentCategory'] != null) {
      print('Current Category: ${contextInfo['context']['currentCategory']}');
    }
    if (contextInfo['context']['hasCategory'] != null) {
      print('Has Category: ${contextInfo['context']['hasCategory']}');
    }

    // Log source app information
    print('ShareHandler: STEP 18 - Checking for source information...');
    if (contextInfo.containsKey('source')) {
      print('ShareHandler: STEP 19 - Logging source app information...');
      final source = contextInfo['source'] as Map<String, dynamic>;
      print('Source App Information:');
      if (source['serviceName'] != null) {
        print('  Service Name: ${source['serviceName']}');
      }
      if (source['senderIdentifier'] != null) {
        print('  Sender ID: ${source['senderIdentifier']}');
      }
      if (source['speakableGroupName'] != null) {
        print('  Group Name: ${source['speakableGroupName']}');
      }
      if (source['conversationIdentifier'] != null) {
        print('  Conversation ID: ${source['conversationIdentifier']}');
      }
      print('  Attachments: ${source['attachments']}');
    } else {
      print('ShareHandler: STEP 19 - No source information available');
    }

    print('ShareHandler: STEP 20 - Extracting shared content...');
    final sharedContent = contextInfo['data'] is SharedMedia
        ? (contextInfo['data'] as SharedMedia).content
        : contextInfo['data'].toString();
    print('Data: $sharedContent');
    print('===================================\n');
    print('ShareHandler: STEP 21 - Shared content extracted successfully');

    // Check if the shared content contains URLs and process them
    final contentPreview = sharedContent != null
        ? (sharedContent.length > 50
            ? sharedContent.substring(0, 50)
            : sharedContent)
        : 'null';
    print(
        'ShareHandler: STEP 22 - About to call _processSharedContent with content: $contentPreview...');

    try {
      _processSharedContent(context, sharedContent, contextInfo);
      print(
          'ShareHandler: STEP 23 - _processSharedContent completed successfully');
    } catch (e, stackTrace) {
      print('ShareHandler: ERROR in _processSharedContent: $e');
      print('ShareHandler: Stack trace: $stackTrace');
    }

    print('ShareHandler: STEP 24 - Calling onIntentReceived callback');
    try {
      onIntentReceived(type, contextInfo);
      print(
          'ShareHandler: STEP 25 - onIntentReceived callback completed successfully');
    } catch (e, stackTrace) {
      print('ShareHandler: ERROR in onIntentReceived: $e');
      print('ShareHandler: Stack trace: $stackTrace');
    }
  }

  /// Get the currently shared text
  String? get sharedText => _sharedText;

  /// Process shared content for URLs and trigger link processing workflow
  Future<void> _processSharedContent(BuildContext? context, String? content,
      Map<String, dynamic> contextInfo) async {
    print('ShareHandler: _processSharedContent called');
    print('ShareHandler: context = ${context != null ? 'not null' : 'NULL'}');
    print('ShareHandler: content = ${content ?? 'NULL'}');

    if (context == null || content == null || content.trim().isEmpty) {
      print('ShareHandler: Early return - context or content is null/empty');
      return;
    }

    List<String> urls = [];
    try {
      // Extract URLs from the shared content
      print('ShareHandler: About to extract URLs from content...');
      urls = _extractUrls(content);
      print('ShareHandler: URL extraction completed');

      if (urls.isEmpty) {
        print('ShareHandler: No URLs found in shared content');
        return;
      }

      print('ShareHandler: Found ${urls.length} URL(s) in shared content');
    } catch (e, stackTrace) {
      print('ShareHandler: ERROR in _processSharedContent URL extraction: $e');
      print('ShareHandler: Stack trace: $stackTrace');
      return;
    }

    try {
      // Process the first URL (could be enhanced to handle multiple URLs).
      final firstUrl = urls.first;
      print('ShareHandler: Processing first URL: $firstUrl');
      // Stash as a pending intent (no title) and nudge Home to process it via
      // the same robust pipeline as the browser extension (?addlink): survives
      // sign-in, and handles no-pursuit / single-pursuit / picker uniformly.
      await PendingIntentStore.set(firstUrl, '');
      HomeScreen.needsIntentProcessing.value =
          !HomeScreen.needsIntentProcessing.value;
      print('ShareHandler: Stashed intent and signalled Home');
    } catch (e, stackTrace) {
      print('ShareHandler: ERROR stashing shared URL: $e');
      print('ShareHandler: Stack trace: $stackTrace');
    }
  }


  /// Schedule content processing for when context becomes available
  void _scheduleContentProcessing(String type, dynamic data) {
    print('ShareHandler: Scheduling content processing for later');

    // Extract the shared content
    final sharedContent = data is SharedMedia ? data.content : data.toString();
    _pendingContent = sharedContent;

    // Retry processing periodically until context is available
    _retryContentProcessing();
  }

  /// Retry processing pending content when context becomes available
  void _retryContentProcessing() async {
    if (_pendingContent == null) return;

    print('ShareHandler: Attempting to process pending content...');

    // Wait a bit for the app to initialize
    await Future.delayed(const Duration(milliseconds: 1000));

    final context = _navigatorKey.currentContext;
    if (context != null) {
      print('ShareHandler: Context now available, processing pending content');

      // Create minimal context info for delayed processing
      final contextInfo = <String, dynamic>{
        'data': _pendingContent,
        'context': {'route': 'delayed_processing'},
      };

      _processSharedContent(context, _pendingContent, contextInfo);
      _pendingContent = null; // Clear after processing
    } else {
      print('ShareHandler: Context still not available, will retry...');
      // Retry with exponential backoff
      Future.delayed(const Duration(milliseconds: 2000), () {
        _retryContentProcessing();
      });
    }
  }

  /// Extract URLs from text content
  List<String> _extractUrls(String text) {
    final urlRegex = RegExp(
      r'https?://[^\s<>"{}|\\^`\[\]]+',
      caseSensitive: false,
      multiLine: true,
    );

    final matches = urlRegex.allMatches(text);
    return matches.map((match) => match.group(0)!).toList();
  }

  /// Clean up resources
  void dispose() {
    _shareSubscription?.cancel();
  }

  /// Show a detailed view of the shared content
  void showDetailsDialog(
      BuildContext context, String type, dynamic data, String timestamp) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Intent Details'),
          ),
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Type: $type',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Text('Time: $timestamp'),
                const SizedBox(height: 16),
                const Text('Data:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(data.toString()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

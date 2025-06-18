import 'package:flutter/material.dart';
import 'package:share_handler/share_handler.dart';
import 'dart:async';
import 'package:meaning_to/home_screen.dart';
import 'package:meaning_to/edit_category_screen.dart';

class ShareHandler {
  static final ShareHandler _instance = ShareHandler._internal();
  factory ShareHandler() => _instance;

  ShareHandler._internal();

  StreamSubscription<SharedMedia?>? _shareSubscription;
  String? _sharedText;
  late GlobalKey<NavigatorState> _navigatorKey;

  /// Initialize the share handler and set up listeners
  void initialize({
    required void Function(String type, dynamic data) onIntentReceived,
    required GlobalKey<ScaffoldMessengerState> scaffoldKey,
    required GlobalKey<NavigatorState> navigatorKey,
  }) {
    _navigatorKey = navigatorKey;

    // Listen for shared content
    _shareSubscription = ShareHandlerPlatform.instance.sharedMediaStream.listen(
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

    // Get initial shared content if app was launched via share intent
    ShareHandlerPlatform.instance
        .getInitialSharedMedia()
        .then((SharedMedia? media) {
      if (media?.content != null) {
        _sharedText = media!.content;
        _logContextAwareIntent('Initial Text Share', media, onIntentReceived);
      }
    });
  }

  /// Log intent with context awareness
  void _logContextAwareIntent(String type, dynamic data,
      void Function(String, dynamic) onIntentReceived) {
    final context = _navigatorKey.currentContext;
    if (context == null) {
      onIntentReceived(type, data);
      return;
    }

    // Get the current route
    final currentRoute = ModalRoute.of(context);
    if (currentRoute == null) {
      onIntentReceived(type, data);
      return;
    }

    // Add context information to the data
    final contextInfo = <String, dynamic>{
      'data': data,
      'context': {
        'route': currentRoute.settings.name,
      }
    };

    // Add source app information if this is a SharedMedia object
    if (data is SharedMedia) {
      contextInfo['source'] = <String, dynamic>{
        'content': data.content,
        'serviceName': data.serviceName,
        'senderIdentifier': data.senderIdentifier,
        'speakableGroupName': data.speakableGroupName,
        'conversationIdentifier': data.conversationIdentifier,
        'attachments': data.attachments?.length ?? 0,
      };
    }

    // Add HomeScreen specific information
    if (currentRoute.settings.name == '/home') {
      final homeState = context.findAncestorStateOfType<HomeScreenState>();
      if (homeState != null) {
        contextInfo['context']['currentCategory'] =
            homeState.selectedCategory?.headline;
        contextInfo['context']['hasCategory'] =
            homeState.selectedCategory != null;
      }
    }

    // Add EditCategoryScreen specific information
    else if (currentRoute.settings.name == '/edit-category') {
      final editState =
          context.findAncestorStateOfType<EditCategoryScreenState>();
      if (editState != null) {
        contextInfo['context']['currentCategory'] =
            editState.widget.category?.headline;
      }
    }

    // Log the intent with context information
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
    if (contextInfo.containsKey('source')) {
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
    }

    print(
        'Data: ${contextInfo['data'] is SharedMedia ? (contextInfo['data'] as SharedMedia).content : contextInfo['data']}');
    print('===================================\n');

    onIntentReceived(type, contextInfo);
  }

  /// Get the currently shared text
  String? get sharedText => _sharedText;

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

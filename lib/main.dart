import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:meaning_to/splash_screen.dart';
import 'package:meaning_to/auth_screen.dart';
import 'package:meaning_to/home_screen.dart';
import 'package:meaning_to/reset_password_screen.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';
import 'package:meaning_to/edit_category_screen.dart';
import 'package:meaning_to/import_justwatch_screen.dart';
import 'package:meaning_to/new_category_screen.dart';
import 'package:meaning_to/shop_endeavors_screen.dart';
import 'package:meaning_to/task_edit_screen.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/utils/share_handler.dart';

// Remove the instance creation since we'll use static methods
// final _receiveSharingIntent = ReceiveSharingIntent();

/// Widget that constrains width on web platform
class WebWidthWrapper extends StatelessWidget {
  final Widget child;

  const WebWidthWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (foundation.kIsWeb) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
              maxWidth: 500), // 50% of typical 1000px width
          child: child,
        ),
      );
    }
    return child;
  }
}

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    print(
        '🚨🚨🚨 NEW CODE RUNNING - Using serverless API for data operations 🚨🚨🚨');

    runApp(const MyApp());
  } catch (e) {
    print('Error during initialization: $e');
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('Error initializing app: $e'),
        ),
      ),
    ));
  }
}

class MyApp extends StatefulWidget {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  static bool isHandlingDeepLink =
      false; // Static flag for other widgets to check

  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late AppLinks _appLinks;
  StreamSubscription? _linkSubscription;
  final _scaffoldKey = GlobalKey<ScaffoldMessengerState>();
  final _shareHandler = ShareHandler();
  Uri? _pendingDeepLink; // Store the initial deep link

  void _logIntent(String type, dynamic data) {
    final timestamp = DateTime.now().toIso8601String();

    // Check if this is context-aware data from ShareHandler
    if (data is Map<String, dynamic> && data.containsKey('context')) {
      print('\n=== Intent Received with Context ===');
      print('Timestamp: $timestamp');
      print('Type: $type');
      print('Route: ${data['context']['route']}');
      if (data['context']['currentCategory'] != null) {
        print('Current Category: ${data['context']['currentCategory']}');
      }
      if (data['context']['hasCategory'] != null) {
        print('Has Category: ${data['context']['hasCategory']}');
      }

      // Display source app information
      if (data.containsKey('source')) {
        final source = data['source'] as Map<String, dynamic>;
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

      print('Data: ${data['data']}');
      print('===================================\n');
    } else {
      print('\n=== Intent Received ===');
      print('Timestamp: $timestamp');
      print('Type: $type');
      print('Data: $data');
      print('=====================\n');
    }

    // Show a snackbar to report the intent to the user
    if (mounted) {
      _scaffoldKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('Received $type intent'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Details',
            onPressed: () {
              _shareHandler.showDetailsDialog(
                MyApp.navigatorKey.currentContext!,
                type,
                data,
                timestamp,
              );
            },
          ),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _initDeepLinkListener();
    _shareHandler.initialize(
      onIntentReceived: _logIntent,
      scaffoldKey: _scaffoldKey,
      navigatorKey: MyApp.navigatorKey,
    );
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _shareHandler.dispose();
    super.dispose();
  }

  Future<void> _initDeepLinkListener() async {
    print('Initializing deep link listener');
    _appLinks = AppLinks();

    // Handle initial link
    final uri = await _appLinks.getInitialAppLink();
    if (uri != null) {
      print('Got initial app link: $uri');
      _pendingDeepLink = uri; // Store for later use
      _handleDeepLink(uri);
    } else {
      print('No initial app link found');
    }

    // Handle subsequent links
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      print('Received subsequent app link: $uri');
      _handleDeepLink(uri);
    }, onError: (err) {
      print('Error handling deep link: $err');
    });
  }

  Future<void> _handleDeepLink(Uri uri) async {
    MyApp.isHandlingDeepLink = true; // Set flag to prevent route conflicts

    _logIntent('Deep Link', {
      'scheme': uri.scheme,
      'host': uri.host,
      'path': uri.path,
      'queryParameters': uri.queryParameters,
    });

    print('=== Deep Link Processing ===');
    print('URI: $uri');
    print('Scheme: ${uri.scheme}');
    print('Host: ${uri.host}');
    print('Path: ${uri.path}');
    print('Query parameters: ${uri.queryParameters}');

    // For now, we'll just log deep links since we haven't implemented serverless auth yet
    print('Deep link received but authentication not implemented yet');
    print('=== End Deep Link Processing ===');
    MyApp.isHandlingDeepLink = false;
  }

  Uri? _getPendingDeepLink() {
    final link = _pendingDeepLink;
    _pendingDeepLink = null; // Clear after use
    return link;
  }

  @override
  Widget build(BuildContext context) {
    return WebWidthWrapper(
      child: MaterialApp(
        title: 'Meaning To',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        scaffoldMessengerKey: _scaffoldKey,
        navigatorKey: MyApp.navigatorKey,
        localizationsDelegates: const [
          DefaultMaterialLocalizations.delegate,
          DefaultWidgetsLocalizations.delegate,
          DefaultCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('en', 'US'),
        ],
        initialRoute: '/',
        onGenerateRoute: (settings) {
          print('onGenerateRoute called with: ${settings.name}');
          print('Arguments: ${settings.arguments}');
          print('Handling deep link: ${MyApp.isHandlingDeepLink}');
          print(
              'Current route stack: ${MyApp.navigatorKey.currentState?.widget.runtimeType}');

          // If we're handling a deep link, don't process normal routes
          if (MyApp.isHandlingDeepLink) {
            print('Deep link in progress, returning splash screen');
            return MaterialPageRoute(
              builder: (context) => const SplashScreen(),
            );
          }

          // Check if this is a deep link that should override normal routing
          if (settings.name == '/') {
            // Check for pending deep link
            final pendingDeepLink = _getPendingDeepLink();
            if (pendingDeepLink != null) {
              print('Found pending deep link: $pendingDeepLink');
              _handleDeepLink(pendingDeepLink);
              // Return splash screen - deep link will handle navigation
              return MaterialPageRoute(
                builder: (context) => const SplashScreen(),
              );
            }
          }

          // Normal route handling
          switch (settings.name) {
            case '/':
              return MaterialPageRoute(
                builder: (context) => const SplashScreen(),
              );
            case '/auth':
              return MaterialPageRoute(
                builder: (context) => const AuthScreen(),
              );
            case '/home':
              return MaterialPageRoute(
                builder: (context) => const HomeScreen(),
              );
            case '/reset-password':
              final args = settings.arguments as Map<String, dynamic>;
              return MaterialPageRoute(
                builder: (context) => ResetPasswordScreen(
                  token: args['token'] as String,
                  email: args['email'] as String?,
                  verified: args['verified'] as bool? ?? false,
                ),
              );
            case '/edit-category':
              final args = settings.arguments as Map<String, dynamic>?;
              return MaterialPageRoute(
                builder: (context) => EditCategoryScreen(
                  category: args?['category'] as Category?,
                  tasksOnly: args?['tasksOnly'] == true,
                ),
              );
            case '/new-category':
              return MaterialPageRoute(
                builder: (context) => const NewCategoryScreen(),
              );
            case '/shop-endeavors':
              final args = settings.arguments as Map<String, dynamic>?;
              return MaterialPageRoute(
                builder: (context) => ShopEndeavorsScreen(
                  existingCategory: args?['category'] as Category?,
                ),
              );
            case '/import-justwatch':
              final args = settings.arguments as Map<String, dynamic>;
              return MaterialPageRoute(
                builder: (context) => ImportJustWatchScreen(
                  category: args['category'] as Category,
                  jsonData: args['jsonData'],
                ),
              );
            case '/edit-task':
              final args = settings.arguments as Map<String, dynamic>;
              return MaterialPageRoute(
                builder: (context) => TaskEditScreen(
                  category: args['category'] as Category,
                  task: args['task'] as Task?,
                ),
              );
            default:
              return MaterialPageRoute(
                builder: (context) => const SplashScreen(),
              );
          }
        },
      ),
    );
  }
}

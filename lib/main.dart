import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meaning_to/splash_screen.dart';
import 'package:meaning_to/auth_screen.dart';
import 'package:meaning_to/home_screen.dart';
import 'package:meaning_to/reset_password_screen.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';
import 'package:meaning_to/edit_category_screen.dart';
import 'package:meaning_to/import_justwatch_screen.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/utils/share_handler.dart';

// Remove the instance creation since we'll use static methods
// final _receiveSharingIntent = ReceiveSharingIntent();

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    // Load environment variables
    await dotenv.load(fileName: '.env');

    // Initialize Supabase
    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL']!,
      anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
    );

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

  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late AppLinks _appLinks;
  StreamSubscription? _linkSubscription;
  final _scaffoldKey = GlobalKey<ScaffoldMessengerState>();
  final _shareHandler = ShareHandler();

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
    _logIntent('Deep Link', {
      'scheme': uri.scheme,
      'host': uri.host,
      'path': uri.path,
      'queryParameters': uri.queryParameters,
    });

    // Handle our custom URL scheme
    if (uri.scheme == 'meaningto' &&
        uri.host == 'auth' &&
        uri.path == '/callback') {
      try {
        // Check for error parameters first
        if (uri.queryParameters.containsKey('error')) {
          final error = uri.queryParameters['error']!;
          final errorCode = uri.queryParameters['error_code'];
          final errorDescription = uri.queryParameters['error_description'];

          _logIntent('Auth Error', {
            'error': error,
            'code': errorCode,
            'description': errorDescription,
          });

          // Show error message and navigate to auth screen
          _scaffoldKey.currentState?.showSnackBar(
            SnackBar(
              content:
                  Text(errorDescription ?? 'Authentication error occurred'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
          MyApp.navigatorKey.currentState?.pushReplacementNamed('/auth');
          return;
        }

        // Check if this is a verification token (signup or recovery)
        if (uri.queryParameters.containsKey('type') &&
            uri.queryParameters.containsKey('token')) {
          final type = uri.queryParameters['type']!;
          final token = uri.queryParameters['token']!;

          if (type == 'signup') {
            // Handle signup verification
            await Supabase.instance.client.auth.verifyOTP(
              token: token,
              type: OtpType.signup,
            );
            MyApp.navigatorKey.currentState?.pushReplacementNamed('/');
          } else if (type == 'recovery') {
            // Handle password recovery
            MyApp.navigatorKey.currentState?.pushReplacementNamed(
              '/reset-password',
              arguments: {'token': token},
            );
          }
        }
      } catch (e) {
        print('Error handling auth callback: $e');
        _scaffoldKey.currentState?.showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
        MyApp.navigatorKey.currentState?.pushReplacementNamed('/auth');
      }
    } else {
      print('URI not handled:');
      print('- Expected scheme: meaningto');
      print('- Expected host: auth');
      print('- Expected path: /callback');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        MyApp.navigatorKey.currentState?.pushReplacementNamed('/auth');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Meaning To',
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
      routes: {
        '/': (context) => const SplashScreen(),
        '/auth': (context) => const AuthScreen(),
        '/home': (context) => const HomeScreen(),
        '/reset-password': (context) {
          final args = ModalRoute.of(context)!.settings.arguments
              as Map<String, dynamic>;
          return ResetPasswordScreen(token: args['token'] as String);
        },
        '/edit-category': (context) {
          final args = ModalRoute.of(context)?.settings.arguments
              as Map<String, dynamic>?;
          return EditCategoryScreen(
            category: args?['category'] as Category?,
            tasksOnly: args?['tasksOnly'] == true,
          );
        },
        '/import-justwatch': (context) {
          final args = ModalRoute.of(context)!.settings.arguments
              as Map<String, dynamic>;
          return ImportJustWatchScreen(
            category: args['category'] as Category,
            jsonData: args['jsonData'],
          );
        },
      },
    );
  }
}

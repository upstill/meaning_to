import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/services.dart';
import 'package:meaning_to/splash_screen.dart';
import 'package:meaning_to/auth_screen.dart';
import 'package:meaning_to/home_screen.dart';
import 'package:meaning_to/reset_password_screen.dart';
import 'package:meaning_to/auth_verification_screen.dart';
import 'package:meaning_to/auth_otp_verification_screen.dart';
import 'package:meaning_to/password_reset_request_screen.dart';
import 'package:meaning_to/password_reset_otp_screen.dart';
import 'package:meaning_to/password_reset_new_screen.dart';
import 'package:meaning_to/letterboxd_import_screen.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';
import 'dart:io';
import 'package:meaning_to/new_category_screen.dart';
import 'package:meaning_to/new_content_screen.dart';
import 'package:meaning_to/shop_endeavors_screen.dart';
import 'package:meaning_to/task_edit_screen.dart';
import 'package:meaning_to/help_screen.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/utils/share_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meaning_to/utils/deep_link_generator.dart';
import 'package:meaning_to/utils/invite_token_store.dart';
import 'package:meaning_to/utils/api_client.dart';
import 'package:meaning_to/invite_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

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

    // Load environment variables
    try {
      // Debug: Try to read the .env file directly first
      try {
        final currentDir = Directory.current;
        print('DEBUG: Current working directory: ${currentDir.path}');
        final envFile = File('.env');
        final absolutePath = envFile.absolute.path;
        print('DEBUG: Looking for .env at: $absolutePath');

        if (await envFile.exists()) {
          final contents = await envFile.readAsString();
          final lines = contents.split('\n');
          print('DEBUG: .env file exists, ${lines.length} total lines');
          print('DEBUG: File size: ${contents.length} bytes');

          // Show all lines that contain TIDAL or SUPABASE
          print('DEBUG: Lines containing TIDAL or SUPABASE:');
          for (int i = 0; i < lines.length; i++) {
            final line = lines[i].trim();
            if (line.contains('TIDAL') || line.contains('SUPABASE')) {
              print('  Line ${i + 1}: $line');
            }
          }

          // Check for TIDAL keys in raw file
          final hasTidalId = contents.contains('TIDAL_CLIENT_ID');
          final hasTidalSecret = contents.contains('TIDAL_CLIENT_SECRET');
          print('DEBUG: Raw file contains TIDAL_CLIENT_ID: $hasTidalId');
          print(
              'DEBUG: Raw file contains TIDAL_CLIENT_SECRET: $hasTidalSecret');

          // Try to manually parse TIDAL keys
          final tidalIdMatch =
              RegExp(r'^TIDAL_CLIENT_ID=(.+)$', multiLine: true)
                  .firstMatch(contents);
          final tidalSecretMatch =
              RegExp(r'^TIDAL_CLIENT_SECRET=(.+)$', multiLine: true)
                  .firstMatch(contents);
          if (tidalIdMatch != null) {
            print(
                'DEBUG: Manually parsed TIDAL_CLIENT_ID: ${tidalIdMatch.group(1)?.trim()}');
          }
          if (tidalSecretMatch != null) {
            print(
                'DEBUG: Manually parsed TIDAL_CLIENT_SECRET: ${tidalSecretMatch.group(1)?.trim()}');
          }
        } else {
          print('DEBUG: .env file does NOT exist at: $absolutePath');
          // Try to find .env files
          final envFiles = await currentDir
              .list()
              .where((entity) => entity.path.contains('.env'))
              .toList();
          print(
              'DEBUG: Found .env files: ${envFiles.map((e) => e.path).toList()}');
        }
      } catch (e, stackTrace) {
        print('DEBUG: Error reading .env file directly: $e');
        print('DEBUG: Stack trace: $stackTrace');
      }

      // On web, try to read the bundled .env asset to see what's actually included
      if (foundation.kIsWeb) {
        try {
          final bundledEnv = await rootBundle.loadString('.env');
          final bundledLines = bundledEnv.split('\n');
          print('DEBUG: Bundled .env file has ${bundledLines.length} lines');
          print('DEBUG: Bundled .env file size: ${bundledEnv.length} bytes');
          print('DEBUG: ALL lines in bundled .env file:');
          for (int i = 0; i < bundledLines.length; i++) {
            final line = bundledLines[i];
            // Show first 100 chars of each line to avoid printing huge values
            final preview =
                line.length > 100 ? '${line.substring(0, 100)}...' : line;
            print('  Line ${i + 1} (${line.length} chars): $preview');
          }
          // Check for TIDAL keys in bundled file
          final hasTidalId = bundledEnv.contains('TIDAL_CLIENT_ID');
          final hasTidalSecret = bundledEnv.contains('TIDAL_CLIENT_SECRET');
          print('DEBUG: Bundled file contains TIDAL_CLIENT_ID: $hasTidalId');
          print(
              'DEBUG: Bundled file contains TIDAL_CLIENT_SECRET: $hasTidalSecret');
        } catch (e) {
          print('DEBUG: Error reading bundled .env asset: $e');
        }
      }

      await dotenv.load(fileName: '.env');
      final loadedKeys = dotenv.env.keys.toList();
      print('Environment variables loaded successfully from .env');
      print('Loaded ${loadedKeys.length} keys: $loadedKeys');

      // Debug: Check for specific keys we expect
      print('Checking for expected keys:');
      print(
          '  TIDAL_CLIENT_ID: ${dotenv.env['TIDAL_CLIENT_ID'] != null ? "FOUND (value length: ${dotenv.env['TIDAL_CLIENT_ID']!.length})" : "NOT FOUND"}');
      print(
          '  TIDAL_CLIENT_SECRET: ${dotenv.env['TIDAL_CLIENT_SECRET'] != null ? "FOUND (value length: ${dotenv.env['TIDAL_CLIENT_SECRET']!.length})" : "NOT FOUND"}');
      print(
          '  SPOTIFY_CLIENT_ID: ${dotenv.env['SPOTIFY_CLIENT_ID'] != null ? "FOUND" : "NOT FOUND"}');
      print(
          '  OMDB_API_KEY: ${dotenv.env['OMDB_API_KEY'] != null ? "FOUND" : "NOT FOUND"}');
    } catch (e, stackTrace) {
      print('Warning: Could not load .env file: $e');
      print('Stack trace: $stackTrace');
      // Continue without .env file - app should still work with hardcoded values
    }

    // Configure debug port for DeepLinkGenerator if running in debug mode
    if (foundation.kDebugMode && foundation.kIsWeb) {
      try {
        // Try to get the current port from the URL
        final currentUri = Uri.base;
        if (currentUri.port != 0) {
          DeepLinkGenerator.setDebugPort(currentUri.port);
          print(
              'DeepLinkGenerator: Auto-configured debug port to ${currentUri.port}');
        }
      } catch (e) {
        print(
            'DeepLinkGenerator: Could not auto-detect port, using default 8080');
      }
    }

    // Initialize Supabase with secure environment variables
    const supabaseUrl = String.fromEnvironment('SUPABASE_URL',
        defaultValue:
            'https://zhpxdayfpysoixxjjqik.supabase.co'); // Fallback for local dev
    const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY',
        defaultValue:
            'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpocHhkYXlmcHlzb2l4eGpqcWlrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDU0Mjk4MjAsImV4cCI6MjA2MTAwNTgyMH0.vWogNfl_98kZaTLFFf3sMSyddZBSjBt9D1yxTTiamVQ'); // Fallback for local dev

    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );

    print(
        '🚨🚨🚨 NEW CODE RUNNING - Using serverless API for data operations 🚨🚨🚨');

    runApp(const MyApp());
  } catch (e) {
    print('Error during initialization: $e');
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text('Error initializing app: $e'),
              const SizedBox(height: 16),
              const Text(
                'Failed to initialize Supabase',
                textAlign: TextAlign.center,
              ),
            ],
          ),
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
  static bool isStateRestored =
      false; // Flag to track if state restoration is complete

  /// Debug hook: set by _MyAppState so debug tools can inject a URI directly.
  static Future<void> Function(Uri)? handleDeepLink;

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
    // if (mounted) {
    //   _scaffoldKey.currentState?.showSnackBar(
    //     SnackBar(
    //       content: Text('Received $type intent'),
    //       duration: const Duration(seconds: 3),
    //       action: SnackBarAction(
    //         label: 'Details',
    //         onPressed: () {
    //           _shareHandler.showDetailsDialog(
    //             MyApp.navigatorKey.currentContext!,
    //             type,
    //             data,
    //             timestamp,
    //           );
    //         },
    //       ),
    //     ),
    //   );
    // }
  }

  @override
  void initState() {
    super.initState();
    MyApp.handleDeepLink = _handleDeepLink;
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

    // Supabase handles OAuth callbacks automatically with PKCE flow
    // No manual intervention needed for web OAuth callbacks

    // Handle initial link
    final uri = await _appLinks.getInitialAppLink();
    if (uri != null) {
      print('Got initial app link: $uri');

      // On non-web platforms, handle invite and category links immediately.
      // onGenerateRoute for '/' runs before this async call completes (race
      // condition), so _pendingDeepLink would be ignored. Instead we call
      // _handleDeepLink directly once the navigator is ready.
      final isInviteLink = uri.path == '/join' ||
          (uri.scheme == 'meaningto' && uri.host == 'join');
      if (!foundation.kIsWeb &&
          (uri.path.startsWith('/category/') || isInviteLink)) {
        print('Initial deep link detected, handling immediately');
        _handleDeepLink(uri);
      } else {
        _pendingDeepLink = uri; // Store for onGenerateRoute (web paths)
      }
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

    try {
      // Handle share-invitation links:
      //   https://meaning-to.me/join?invite=<token>  (path == '/join')
      //   meaningto://join?invite=<token>             (host == 'join')
      final isHttpsInvite = uri.path == '/join';
      final isCustomInvite = uri.scheme == 'meaningto' && uri.host == 'join';
      if (isHttpsInvite || isCustomInvite) {
        final token = uri.queryParameters['invite'];
        if (token != null) {
          // Reset the flag BEFORE navigation so onGenerateRoute isn't blocked.
          MyApp.isHandlingDeepLink = false;
          final session = Supabase.instance.client.auth.currentSession;
          if (session != null) {
            // Logged in — redeem directly, then jump to the shared category.
            try {
              final categoryId = await ApiClient.redeemInvitation(token);
              MyApp.navigatorKey.currentState?.pushReplacementNamed(
                '/category',
                arguments: {'categoryId': categoryId.toString()},
              );
            } catch (e) {
              print('Error redeeming invite in deep link: $e');
              MyApp.navigatorKey.currentState?.pushReplacementNamed('/home');
            }
          } else {
            // Not logged in — stash token and go to auth.
            await InviteTokenStore.set(token);
            MyApp.navigatorKey.currentState?.pushReplacementNamed('/auth');
          }
          return;
        }
      }

      // Handle category deep links
      if (uri.path.startsWith('/category/')) {
        print('Processing category deep link');
        final pathSegments = uri.pathSegments;
        if (pathSegments.length >= 2 && pathSegments[0] == 'category') {
          final categoryId = pathSegments[1];
          print('Category ID from deep link: $categoryId');

          // Navigate to home screen with the specified category
          if (mounted) {
            Navigator.pushReplacementNamed(context, '/category',
                arguments: {'categoryId': categoryId});
          }
          return;
        }
      }

      // Handle custom scheme category deep links (meaningto://category/123)
      if (uri.scheme == 'meaningto' && uri.host == 'category') {
        print('Processing custom scheme category deep link');
        final pathSegments = uri.pathSegments;
        if (pathSegments.isNotEmpty) {
          final categoryId = pathSegments[0];
          print('Category ID from custom scheme: $categoryId');

          // Navigate to home screen with the specified category
          if (mounted) {
            Navigator.pushReplacementNamed(context, '/category',
                arguments: {'categoryId': categoryId});
          }
          return;
        }
      }

      // Handle email confirmation links
      if (uri.scheme == 'meaningto' && uri.host == 'auth') {
        print('Processing auth deep link');

        // Check if this is a password reset link
        if (uri.path.contains('reset-password')) {
          print('Password reset link detected');

          // Navigate to password reset screen
          if (mounted) {
            Navigator.pushReplacementNamed(
              context,
              '/auth/reset-password',
              arguments: {
                'token': uri.queryParameters['token'],
                'type': uri.queryParameters['type'],
              },
            );
          }
          return;
        }

        // Check if this is an email confirmation link
        if (uri.path.contains('confirm') ||
            uri.queryParameters.containsKey('token')) {
          print('Email confirmation link detected');

          // Extract token and email from query parameters
          final token = uri.queryParameters['token'];
          final email = uri.queryParameters['email'];

          if (token != null) {
            print('Processing email confirmation with token');

            // Try to confirm the email and sign in the user
            try {
              final response = await Supabase.instance.client.auth.verifyOTP(
                email: email ?? '',
                token: token,
                type: OtpType.signup,
              );

              if (response.user != null && response.session != null) {
                print('Email confirmation successful, user signed in');

                // Redeem any pending invite token before navigating
                final pendingInvite = await InviteTokenStore.get();
                if (pendingInvite != null) {
                  try {
                    final categoryId =
                        await ApiClient.redeemInvitation(pendingInvite);
                    await InviteTokenStore.clear();
                    if (mounted) {
                      Navigator.pushReplacementNamed(
                        context,
                        '/category',
                        arguments: {'categoryId': categoryId.toString()},
                      );
                    }
                    return;
                  } catch (e) {
                    print('Error redeeming invite after email confirmation: $e');
                    await InviteTokenStore.clear();
                  }
                }

                // Navigate to home screen
                if (mounted) {
                  Navigator.pushReplacementNamed(context, '/home');
                }
              } else {
                print('Email confirmation failed - no user or session');
                // Navigate to auth screen with error
                if (mounted) {
                  Navigator.pushReplacementNamed(context, '/auth');
                }
              }
            } catch (e) {
              print('Error confirming email: $e');
              // Navigate to auth screen with error
              if (mounted) {
                Navigator.pushReplacementNamed(context, '/auth');
              }
            }
          } else {
            print('No token found in confirmation link');
            // Navigate to auth screen
            if (mounted) {
              Navigator.pushReplacementNamed(context, '/auth');
            }
          }
        } else if (uri.path == '/callback' &&
            uri.queryParameters.containsKey('code')) {
          print('OAuth callback detected - processing authentication code');

          try {
            // Exchange the code for a session
            final response =
                await Supabase.instance.client.auth.getSessionFromUrl(uri);

            print('OAuth session established successfully');
            print('User: ${response.session.user.email}');

            // Wait a moment for the Navigator to be ready, then navigate
            await Future.delayed(const Duration(milliseconds: 100));

            // Redeem any pending invite token before navigating
            final pendingInvite = await InviteTokenStore.get();
            if (pendingInvite != null) {
              try {
                final categoryId = await ApiClient.redeemInvitation(pendingInvite);
                await InviteTokenStore.clear();
                MyApp.navigatorKey.currentState?.pushReplacementNamed(
                  '/category',
                  arguments: {'categoryId': categoryId.toString()},
                );
                return;
              } catch (e) {
                print('Error redeeming invite after OAuth: $e');
                await InviteTokenStore.clear();
              }
            }

            // Use global navigator key to navigate
            MyApp.navigatorKey.currentState?.pushReplacementNamed('/home');
          } catch (e) {
            print('Error processing OAuth callback: $e');
            await Future.delayed(const Duration(milliseconds: 100));
            MyApp.navigatorKey.currentState?.pushReplacementNamed('/auth');
          }
        } else {
          print('Auth deep link but not confirmation - navigating to auth');
          // Navigate to auth screen for other auth links
          if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
            Navigator.pushReplacementNamed(context, '/auth');
          }
        }
      } else {
        print('Unknown deep link format - ignoring');
      }
    } catch (e) {
      print('Error handling deep link: $e');
      // Don't try to navigate on error - just log it
    } finally {
      // Always reset the flag so the app doesn't stay in loading state
      print('=== End Deep Link Processing ===');
      MyApp.isHandlingDeepLink = false;
    }
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
        title: 'I\'ve Been Meaning To',
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
          print('=== onGenerateRoute called ===');
          print('Route name: ${settings.name}');
          print('Arguments: ${settings.arguments}');
          print('Handling deep link: ${MyApp.isHandlingDeepLink}');
          print(
              'Current route stack: ${MyApp.navigatorKey.currentState?.widget.runtimeType}');
          print('Current URI: ${Uri.base}');
          print('Current path: ${Uri.base.path}');
          print('Current query: ${Uri.base.queryParameters}');
          print('=== End onGenerateRoute ===');

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

            // Check if this is a web category URL
            if (foundation.kIsWeb) {
              final currentPath = Uri.base.path;
              print('Web routing check - current path: $currentPath');
              if (currentPath.startsWith('/category/')) {
                print('Web category URL detected: $currentPath');
                final pathSegments = currentPath.split('/');
                print('Path segments: $pathSegments');
                if (pathSegments.length >= 3 && pathSegments[1] == 'category') {
                  final categoryId = pathSegments[2];
                  print('Category ID from web URL: $categoryId');
                  print('Creating HomeScreen with category ID: $categoryId');
                  return MaterialPageRoute(
                    builder: (context) =>
                        HomeScreen(initialCategoryId: categoryId),
                  );
                }
              }

              // Check for share-invitation link: /join?invite=<token>
              if (currentPath == '/join') {
                final token = Uri.base.queryParameters['invite'];
                if (token != null) {
                  return MaterialPageRoute(
                    builder: (context) => InviteScreen(token: token),
                  );
                }
              }

              // Check for share-invitation token at root URL (?invite=<token>)
              // This arrives when web/join/index.html redirects to /?invite=<token>
              final rootInviteToken = Uri.base.queryParameters['invite'];
              if (rootInviteToken != null) {
                return MaterialPageRoute(
                  builder: (context) => InviteScreen(token: rootInviteToken),
                );
              }

              // Check for Supabase authentication verification (password reset, email confirmation, etc.)
              final queryParams = Uri.base.queryParameters;
              final fragment = Uri.base.fragment;

              if (queryParams.containsKey('token') &&
                  queryParams.containsKey('type')) {
                print('Supabase verification URL detected');
                print('Query params: $queryParams');
                print('Fragment: $fragment');
                return MaterialPageRoute(
                  builder: (context) => AuthVerificationScreen(
                    token: queryParams['token'],
                    type: queryParams['type'],
                    redirectTo: queryParams['redirect_to'],
                  ),
                );
              }

              // Check for password reset URL
              if (currentPath == '/auth/reset-password') {
                print('Password reset URL detected');
                return MaterialPageRoute(
                  builder: (context) => ResetPasswordScreen(
                    token: queryParams['token'],
                    type: queryParams['type'],
                  ),
                );
              }

              // Also check for query parameter based category links
              if (queryParams.containsKey('category')) {
                final categoryId = queryParams['category'];
                print('Category ID from query parameter: $categoryId');
                return MaterialPageRoute(
                  builder: (context) =>
                      HomeScreen(initialCategoryId: categoryId),
                );
              }
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
            case '/auth/reset-password':
              final args = settings.arguments as Map<String, dynamic>?;
              return MaterialPageRoute(
                builder: (context) => ResetPasswordScreen(
                  token: args?['token'] as String?,
                  type: args?['type'] as String?,
                ),
              );
            case '/auth/verify':
              final args = settings.arguments as Map<String, dynamic>?;
              return MaterialPageRoute(
                builder: (context) => AuthVerificationScreen(
                  token: args?['token'] as String?,
                  type: args?['type'] as String?,
                  redirectTo: args?['redirect_to'] as String?,
                ),
              );
            case '/auth/verify-otp':
              return MaterialPageRoute(
                settings: settings,
                builder: (context) => const AuthOtpVerificationScreen(),
              );
            case '/auth/callback':
              print('Main: OAuth callback route detected');
              // Return a loading screen that will handle the OAuth callback
              return MaterialPageRoute(
                builder: (context) => const SplashScreen(),
              );

            case '/email-confirmation':
              final args = settings.arguments as Map<String, dynamic>;
              return MaterialPageRoute(
                builder: (context) => AuthVerificationScreen(
                  token: args['token'] as String?,
                  type: args['type'] as String?,
                ),
              );
            case '/password-reset-request':
              return MaterialPageRoute(
                builder: (context) => const PasswordResetRequestScreen(),
              );
            case '/password-reset-otp':
              final args = settings.arguments as Map<String, dynamic>;
              return MaterialPageRoute(
                builder: (context) => PasswordResetOtpScreen(
                  email: args['email'] as String,
                ),
              );
            case '/password-reset-new':
              final args = settings.arguments as Map<String, dynamic>;
              return MaterialPageRoute(
                builder: (context) => PasswordResetNewScreen(
                  email: args['email'] as String,
                ),
              );
            case '/home':
              return MaterialPageRoute(
                builder: (context) => const HomeScreen(),
              );
            case '/help':
              return MaterialPageRoute(
                builder: (context) => const HelpScreen(),
              );
            case '/join':
              final joinArgs = settings.arguments as Map<String, dynamic>?;
              final inviteToken = joinArgs?['token'] as String?;
              if (inviteToken != null) {
                return MaterialPageRoute(
                  builder: (context) => InviteScreen(token: inviteToken),
                );
              }
              return MaterialPageRoute(
                builder: (context) => const HomeScreen(),
              );
            case '/category':
              // Handle category deep link with ID parameter
              final args = settings.arguments as Map<String, dynamic>?;
              final categoryId = args?['categoryId'] as String?;
              return MaterialPageRoute(
                builder: (context) => HomeScreen(initialCategoryId: categoryId),
              );
            case '/new-category':
              return MaterialPageRoute(
                builder: (context) => const NewCategoryScreen(),
              );
            case '/new-content':
              final args = settings.arguments as Map<String, dynamic>?;
              return MaterialPageRoute(
                builder: (context) => NewContentScreen(
                  selectedCategory: args?['selectedCategory'] as Category?,
                  initialLinks: args?['initialLinks'] as List<String>?,
                  initialHeadline: args?['initialHeadline'] as String?,
                  initialNotes: args?['initialNotes'] as String?,
                  originalId: args?['originalId'] as String?,
                  categoryLocked: args?['categoryLocked'] as bool? ?? false,
                ),
              );
            case '/shop-endeavors':
              final args = settings.arguments as Map<String, dynamic>?;
              return MaterialPageRoute(
                builder: (context) => ShopEndeavorsScreen(
                  existingCategory: args?['category'] as Category?,
                ),
              );
            case '/edit-task':
              final args = settings.arguments as Map<String, dynamic>;
              final task = args['task'] as Task?;
              final category = args['category'] as Category;

              if (task == null) {
                // New task creation - use new content screen in locked mode
                return MaterialPageRoute(
                  builder: (context) => NewContentScreen(
                    selectedCategory: category,
                    categoryLocked: true,
                    initialLinks: args['initialLinks'] as List<String>?,
                    initialHeadline: args['initialHeadline'] as String?,
                    initialNotes: args['initialNotes'] as String?,
                    originalId: args['originalId'] as String?,
                  ),
                );
              } else {
                // Existing task editing - continue using TaskEditScreen
                return MaterialPageRoute(
                  builder: (context) => TaskEditScreen(
                    category: category,
                    task: task,
                  ),
                );
              }
            case '/letterboxd-import':
              final args = settings.arguments as Map<String, dynamic>;
              return MaterialPageRoute(
                builder: (context) => LetterboxdImportScreen(
                  category: args['category'] as Category,
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

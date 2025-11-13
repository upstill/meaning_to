import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:meaning_to/splash_screen.dart';
import 'package:meaning_to/auth_screen.dart';
import 'package:meaning_to/home_screen.dart';
import 'package:meaning_to/email_confirmation_screen.dart';
import 'package:meaning_to/forgot_password_screen.dart';
import 'package:meaning_to/reset_password_screen.dart';
import 'package:meaning_to/auth_verification_screen.dart';
import 'package:meaning_to/password_reset_request_screen.dart';
import 'package:meaning_to/password_reset_otp_screen.dart';
import 'package:meaning_to/password_reset_new_screen.dart';
import 'package:meaning_to/letterboxd_import_screen.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';
import 'package:meaning_to/edit_category_screen.dart';
import 'package:meaning_to/import_justwatch_screen.dart';
import 'package:meaning_to/new_category_screen.dart';
import 'package:meaning_to/new_content_screen.dart';
import 'package:meaning_to/shop_endeavors_screen.dart';
import 'package:meaning_to/task_edit_screen.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/utils/share_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meaning_to/utils/deep_link_generator.dart';
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
      await dotenv.load(fileName: '.env');
      print('Environment variables loaded successfully');
    } catch (e) {
      print('Warning: Could not load .env file: $e');
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

    // Handle OAuth callbacks
    if (foundation.kIsWeb) {
      final uri = Uri.base;
      print('=== OAuth Callback Check ===');
      print('Current URI: $uri');
      print('Path: ${uri.path}');
      print('Query parameters: ${uri.queryParameters}');
      print('Fragment: ${uri.fragment}');

      if (uri.path == '/auth/callback') {
        print('OAuth callback path detected!');
        try {
          print('Checking current session...');
          final session = Supabase.instance.client.auth.currentSession;
          print('Session: ${session != null ? "exists" : "null"}');

          if (session != null) {
            print('OAuth callback successful - navigating to home');
            if (mounted) {
              Navigator.of(context).pushReplacementNamed('/home');
            }
          } else {
            print('No session found after OAuth callback');
            // Try to get the session from the URL parameters
            final accessToken = uri.queryParameters['access_token'];
            final refreshToken = uri.queryParameters['refresh_token'];
            print(
                'Access token in URL: ${accessToken != null ? "present" : "missing"}');
            print(
                'Refresh token in URL: ${refreshToken != null ? "present" : "missing"}');

            if (accessToken != null) {
              print('Attempting to set session from URL parameters...');
              // You might need to manually set the session here
            }
          }
        } catch (e) {
          print('OAuth callback error: $e');
          print('Stack trace: ${StackTrace.current}');
        }
      } else {
        print('Not an OAuth callback path');
      }
      print('=== End OAuth Callback Check ===');
    }

    // Handle initial link
    final uri = await _appLinks.getInitialAppLink();
    if (uri != null) {
      print('Got initial app link: $uri');
      _pendingDeepLink = uri; // Store for later use

      // Check if this is a category deep link that should be handled immediately
      // Only handle non-web deep links immediately to avoid conflicts with web routing
      if (uri.path.startsWith('/category/') && !foundation.kIsWeb) {
        print('Initial category deep link detected, handling immediately');
        _handleDeepLink(uri);
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
        } else {
          print('Auth deep link but not confirmation - navigating to auth');
          // Navigate to auth screen
          if (mounted) {
            Navigator.pushReplacementNamed(context, '/auth');
          }
        }
      } else {
        print('Unknown deep link format - ignoring');
      }
    } catch (e) {
      print('Error handling deep link: $e');
      // Navigate to auth screen on error
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/auth');
      }
    }

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
            case '/forgot-password':
              return MaterialPageRoute(
                builder: (context) => const ForgotPasswordScreen(),
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
            case '/auth/callback':
              print('Main: OAuth callback route detected');
              // Return a loading screen that will handle the OAuth callback
              return MaterialPageRoute(
                builder: (context) => const SplashScreen(),
              );

            case '/email-confirmation':
              final args = settings.arguments as Map<String, dynamic>;
              return MaterialPageRoute(
                builder: (context) => EmailConfirmationScreen(
                  email: args['email'] as String,
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
            case '/category':
              // Handle category deep link with ID parameter
              final args = settings.arguments as Map<String, dynamic>?;
              final categoryId = args?['categoryId'] as String?;
              return MaterialPageRoute(
                builder: (context) => HomeScreen(initialCategoryId: categoryId),
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

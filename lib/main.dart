import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' as foundation;
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
import 'package:meaning_to/new_category_screen.dart';
import 'package:meaning_to/shop_endeavors_screen.dart';
import 'package:meaning_to/task_edit_screen.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/utils/share_handler.dart';
import 'package:meaning_to/utils/supabase_client.dart';

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
    await dotenv.load(fileName: '.env');

    // Initialize Supabase
    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL']!,
      anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
    );

    print(
        '🚨🚨🚨 NEW CODE RUNNING - Supabase initialized with URL: ${dotenv.env['SUPABASE_URL']} 🚨🚨🚨');
    print(
        '🚨🚨🚨 NEW CODE RUNNING - Supabase anon key: ${dotenv.env['SUPABASE_ANON_KEY']?.substring(0, 10)}... 🚨🚨🚨');

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
    _initAuthStateListener();
    _shareHandler.initialize(
      onIntentReceived: _logIntent,
      scaffoldKey: _scaffoldKey,
      navigatorKey: MyApp.navigatorKey,
    );
  }

  void _initAuthStateListener() {
    supabase.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final session = data.session;

      print('=== Auth State Change ===');
      print('Event: $event');
      print('Session: ${session != null ? 'exists' : 'null'}');
      print('User: ${session?.user.id ?? 'null'}');
      print('User email: ${session?.user.email ?? 'null'}');
      print('Timestamp: ${DateTime.now().toIso8601String()}');

      if (event == AuthChangeEvent.passwordRecovery) {
        print('=== PASSWORD_RECOVERY Event Detected ===');
        print('Navigating to reset password screen');

        // Navigate to reset password screen
        WidgetsBinding.instance.addPostFrameCallback((_) {
          MyApp.navigatorKey.currentState?.pushReplacementNamed(
            '/reset-password',
            arguments: {
              'token': '', // Will be handled by the reset password screen
              'email': null,
              'verified': false,
            },
          );
        });
      } else if (event == AuthChangeEvent.initialSession) {
        print('=== INITIAL_SESSION Event Detected ===');
        print(
            'This is normal on app startup when user is already authenticated');
        print('Splash screen will handle navigation after delay');
      } else {
        print('=== Other Auth Event: $event ===');
      }
    });
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

    // Handle our custom URL scheme
    if (uri.scheme == 'meaningto' &&
        uri.host == 'auth' &&
        uri.path == '/callback') {
      print('Processing meaningto://auth/callback');
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
        if (uri.queryParameters.containsKey('token') ||
            uri.queryParameters.containsKey('code')) {
          final token =
              uri.queryParameters['token'] ?? uri.queryParameters['code']!;
          final type = uri.queryParameters['type'];

          print('Processing auth callback with type: $type, token: $token');
          print('All query parameters: ${uri.queryParameters}');
          print('Full URI: $uri');
          print('Token length: ${token.length}');
          print('Token starts with: ${token.substring(0, 8)}...');
          print('URI fragment: ${uri.fragment}');
          print('URI has fragment: ${uri.hasFragment}');

          if (type == 'signup') {
            // Handle signup verification
            print('Handling signup verification');
            await supabase.auth.verifyOTP(
              token: token,
              type: OtpType.signup,
            );
            MyApp.navigatorKey.currentState?.pushReplacementNamed('/');
          } else if (type == 'recovery') {
            // Handle password recovery
            print('Handling password recovery with token: $token');
            // Don't verify the token here - let the reset password screen handle it
            // The user will need to enter their email in the reset password screen
            print('Navigating to reset password screen with recovery token');

            // Use a post-frame callback to ensure navigation happens after current frame
            WidgetsBinding.instance.addPostFrameCallback((_) {
              print('Post-frame callback: Navigating to reset password screen');
              MyApp.navigatorKey.currentState?.pushReplacementNamed(
                '/reset-password',
                arguments: {
                  'token': token,
                  'email':
                      uri.queryParameters['email'], // Pass email if available
                },
              ).then((_) {
                // Clear the flag only after navigation is complete
                print(
                    'Reset password navigation complete, clearing deep link flag');
                // Keep the flag true for a bit longer to prevent interference
                Future.delayed(const Duration(seconds: 2), () {
                  print('Delayed clearing of deep link flag');
                  MyApp.isHandlingDeepLink = false;
                });
              });
            });
            return; // Exit early, don't clear flag yet
          } else {
            // For password recovery, Supabase might not include type=recovery
            // Check if this looks like a recovery link (has access_token or refresh_token)
            if (uri.queryParameters.containsKey('access_token') ||
                uri.queryParameters.containsKey('refresh_token')) {
              print('Detected recovery link without type parameter');

              // Use a post-frame callback to ensure navigation happens after current frame
              WidgetsBinding.instance.addPostFrameCallback((_) {
                print(
                    'Post-frame callback: Navigating to reset password screen');
                MyApp.navigatorKey.currentState?.pushReplacementNamed(
                  '/reset-password',
                  arguments: {
                    'token': token,
                    'email':
                        uri.queryParameters['email'], // Pass email if available
                  },
                ).then((_) {
                  // Clear the flag only after navigation is complete
                  print(
                      'Reset password navigation complete, clearing deep link flag');
                  // Keep the flag true for a bit longer to prevent interference
                  Future.delayed(const Duration(seconds: 2), () {
                    print('Delayed clearing of deep link flag');
                    MyApp.isHandlingDeepLink = false;
                  });
                });
              });
              return; // Exit early, don't clear flag yet
            } else if (uri.queryParameters.containsKey('code') &&
                !uri.queryParameters.containsKey('type')) {
              // Supabase password recovery links often only have 'code' parameter
              print('Detected password recovery link with code parameter');

              // Check if this is a PKCE token (starts with 'pkce_')
              if (token.startsWith('pkce_')) {
                print('Detected PKCE token from verify endpoint');
                print(
                    'This token should be used with the verify endpoint, not recovery');
                print('Navigating to reset password screen with PKCE token');

                // Navigate to reset password screen - user will need to enter email
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  print(
                      'Post-frame callback: Navigating to reset password screen');
                  MyApp.navigatorKey.currentState?.pushReplacementNamed(
                    '/reset-password',
                    arguments: {
                      'token': token,
                      'email': uri
                          .queryParameters['email'], // Pass email if available
                      'verified': false, // Mark as not verified yet
                      'tokenType': 'pkce', // Mark as PKCE token
                    },
                  ).then((_) {
                    print(
                        'Reset password navigation complete, clearing deep link flag');
                    Future.delayed(const Duration(seconds: 2), () {
                      print('Delayed clearing of deep link flag');
                      MyApp.isHandlingDeepLink = false;
                    });
                  });
                });
                return; // Exit early, don't clear flag yet
              }

              // Immediately verify the token to avoid expiration
              print(
                  'Immediately verifying recovery token to prevent expiration');
              try {
                // We need the email to verify the token, but we don't have it yet
                // Let's try to verify without email first (some Supabase setups allow this)
                print('Attempting immediate verification without email...');
                print('Token: $token');
                print('Token type: ${token.runtimeType}');
                print('Token length: ${token.length}');

                await supabase.auth.verifyOTP(
                  token: token,
                  type: OtpType.recovery,
                );

                // Navigate to reset password screen with verified token
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  print(
                      'Post-frame callback: Navigating to reset password screen');
                  MyApp.navigatorKey.currentState?.pushReplacementNamed(
                    '/reset-password',
                    arguments: {
                      'token': token,
                      'email': uri
                          .queryParameters['email'], // Pass email if available
                      'verified': true, // Mark as already verified
                    },
                  ).then((_) {
                    print(
                        'Reset password navigation complete, clearing deep link flag');
                    Future.delayed(const Duration(seconds: 2), () {
                      print('Delayed clearing of deep link flag');
                      MyApp.isHandlingDeepLink = false;
                    });
                  });
                });
                return; // Exit early, don't clear flag yet
              } catch (e) {
                print('Immediate token verification failed: $e');
                print(
                    'Will try verification in reset password screen with user email');

                // Navigate to reset password screen - user will need to enter email
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  print(
                      'Post-frame callback: Navigating to reset password screen');
                  MyApp.navigatorKey.currentState?.pushReplacementNamed(
                    '/reset-password',
                    arguments: {
                      'token': token,
                      'email': uri
                          .queryParameters['email'], // Pass email if available
                      'verified': false, // Mark as not verified yet
                    },
                  ).then((_) {
                    print(
                        'Reset password navigation complete, clearing deep link flag');
                    Future.delayed(const Duration(seconds: 2), () {
                      print('Delayed clearing of deep link flag');
                      MyApp.isHandlingDeepLink = false;
                    });
                  });
                });
                return; // Exit early, don't clear flag yet
              }
            } else {
              // Default to signup if no type specified and no recovery indicators
              print('No type specified, defaulting to signup verification');
              await supabase.auth.verifyOTP(
                token: token,
                type: OtpType.signup,
              );
              MyApp.navigatorKey.currentState?.pushReplacementNamed('/');
            }
          }
        } else {
          print('No token or code parameter found in deep link');
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
        // Only navigate to /auth if this was actually an auth-related error
        // Otherwise, let the splash screen handle normal app startup
        if (uri.scheme == 'meaningto' && uri.host == 'auth') {
          MyApp.navigatorKey.currentState?.pushReplacementNamed('/auth');
        } else {
          // Clear the deep link flag for normal app startup
          MyApp.isHandlingDeepLink = false;
        }
      }
    } else {
      print('URI not handled:');
      print('- Expected scheme: meaningto');
      print('- Expected host: auth');
      print('- Expected path: /callback');
      print('- This is normal when app starts without a deep link');
      // Don't navigate to /auth automatically - let the splash screen handle it
      // Only clear the deep link flag so normal routing can proceed
      MyApp.isHandlingDeepLink = false;
    }
    print('=== End Deep Link Processing ===');
    // Note: _handlingDeepLink flag is cleared in individual navigation cases
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
            // Allow reset-password route to be processed even during deep link handling
            if (settings.name == '/reset-password') {
              print('Deep link in progress, but allowing reset-password route');
              final args = settings.arguments as Map<String, dynamic>;
              return MaterialPageRoute(
                builder: (context) => ResetPasswordScreen(
                  token: args['token'] as String,
                  email: args['email'] as String?,
                  verified: args['verified'] as bool? ?? false,
                ),
              );
            }
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

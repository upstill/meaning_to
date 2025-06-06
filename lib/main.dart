import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meaning_to/splash_screen.dart';
import 'package:meaning_to/auth_screen.dart';
import 'package:meaning_to/home_screen.dart';
import 'package:meaning_to/reset_password_screen.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';
import 'package:meaning_to/edit_category_screen.dart';
import 'package:meaning_to/task_edit_screen.dart';
import 'package:meaning_to/import_justwatch_screen.dart';
import 'package:meaning_to/download_screen.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';

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
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late AppLinks _appLinks;
  StreamSubscription? _linkSubscription;
  final _scaffoldKey = GlobalKey<ScaffoldMessengerState>();
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _initDeepLinkListener();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
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
    print('Handling deep link: $uri');
    print('URI scheme: ${uri.scheme}');
    print('URI host: ${uri.host}');
    print('URI path: ${uri.path}');
    print('URI query parameters: ${uri.queryParameters}');
    
    // Handle our custom URL scheme
    if (uri.scheme == 'meaningto' && uri.host == 'auth' && uri.path == '/callback') {
      try {
        // Check for error parameters first
        if (uri.queryParameters.containsKey('error')) {
          final error = uri.queryParameters['error']!;
          final errorCode = uri.queryParameters['error_code'];
          final errorDescription = uri.queryParameters['error_description'];
          
          print('Auth error detected:');
          print('- Error: $error');
          print('- Code: $errorCode');
          print('- Description: $errorDescription');
          
          // Show error message and navigate to auth screen
          _scaffoldKey.currentState?.showSnackBar(
            SnackBar(
              content: Text(errorDescription ?? 'Authentication error occurred'),
              backgroundColor: Colors.red,
            ),
          );
          _navigatorKey.currentState?.pushReplacementNamed('/auth');
          return;
        }

        // Check if this is a verification token (signup or recovery)
        if (uri.queryParameters.containsKey('type') && 
            uri.queryParameters.containsKey('token')) {
          final type = uri.queryParameters['type']!;
          final token = uri.queryParameters['token']!;
          
          print('Processing verification token:');
          print('- Type: $type');
          print('- Token: $token');
          
          // Exchange the token for a session
          print('Verifying OTP...');
          final response = await Supabase.instance.client.auth.verifyOTP(
            type: type == 'signup' ? OtpType.signup : OtpType.recovery,
            token: token,
          );
          print('Verification response:');
          print('- Session: ${response.session != null}');
          print('- User: ${response.session?.user.id}');
          print('- Metadata: ${response.session?.user.userMetadata}');
          
          if (response.session != null) {
            if (type == 'recovery') {
              print('Recovery session verified, navigating to reset password screen');
              // Use the navigator key to ensure we can navigate
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _navigatorKey.currentState?.pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const ResetPasswordScreen()),
                  (route) => false,
                );
              });
            } else {
              print('Signup verified, navigating to home');
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _navigatorKey.currentState?.pushReplacementNamed('/home');
              });
            }
          } else {
            print('No session in verification response');
            throw Exception('No session returned from verification');
          }
          return;
        }

        // Handle other auth callbacks
        final code = uri.queryParameters['code'];
        if (code != null) {
          print('Exchanging code for session');
          final response = await Supabase.instance.client.auth.exchangeCodeForSession(code);
          print('Code exchange response:');
          print('- Session: ${response.session != null}');
          print('- User: ${response.session?.user.id}');
          print('- Metadata: ${response.session?.user.userMetadata}');
          
          if (response.session != null) {
            // Check if this is a recovery session
            final type = response.session?.user.userMetadata?['type'] as String?;
            print('Session type from metadata: $type');
            
            if (type == 'recovery') {
              print('Recovery session detected, navigating to reset password screen');
              // Use post frame callback to ensure navigation happens after the current frame
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _navigatorKey.currentState?.pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const ResetPasswordScreen()),
                  (route) => false,
                );
              });
            } else {
              print('Regular session, navigating to home');
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _navigatorKey.currentState?.pushReplacementNamed('/home');
              });
            }
          }
        } else {
          print('No code parameter found in URI');
          // Navigate to auth screen if no valid parameters found
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _navigatorKey.currentState?.pushReplacementNamed('/auth');
          });
        }
      } catch (e) {
        print('Error handling deep link: $e');
        _scaffoldKey.currentState?.showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _navigatorKey.currentState?.pushReplacementNamed('/auth');
        });
      }
    } else {
      print('URI not handled:');
      print('- Expected scheme: meaningto');
      print('- Expected host: auth');
      print('- Expected path: /callback');
      // Navigate to auth screen for unhandled URIs
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigatorKey.currentState?.pushReplacementNamed('/auth');
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
      navigatorKey: _navigatorKey,
      initialRoute: '/',
      routes: {
        '/': (context) => HomeScreen(),
        '/auth': (context) => const AuthScreen(),
        '/edit-category': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
          return EditCategoryScreen(
            category: args?['category'] as Category?,
            tasksOnly: args?['tasksOnly'] == true,
          );
        },
        '/edit-task': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return TaskEditScreen(
            category: args['category'] as Category,
            task: args['task'] as Task?,
          );
        },
        '/import-justwatch': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return ImportJustWatchScreen(
            category: args['category'] as Category,
            jsonData: args['jsonData'],
          );
        },
        '/download': (context) {
          return const DownloadScreen();
        },
      },
    );
  }
}
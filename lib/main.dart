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
        '/': (context) => const SplashScreen(),
        '/auth': (context) => const AuthScreen(),
        '/home': (context) => const HomeScreen(),
        '/reset-password': (context) => const ResetPasswordScreen(),
        '/edit-category': (context) {
          final category = ModalRoute.of(context)?.settings.arguments as Category?;
          return EditCategoryScreen(category: category);
        },
        '/edit-task': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>;
          return TaskEditScreen(
            category: args['category'] as Category,
            task: args['task'] as Task?,
          );
        },
      },
    );
  }
}

/* 
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          //
          // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
          // action in the IDE, or press "p" in the console), to see the
          // wireframe for each widget.
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('You have pushed the button this many times:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
 */
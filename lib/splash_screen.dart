import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    print('SplashScreen: initState called');
    _checkSession();
  }

  Future<void> _checkSession() async {
    print('SplashScreen: Checking session...');
    try {
      // Get the current session
      final session = Supabase.instance.client.auth.currentSession;
      print('SplashScreen: Current session: ${session != null ? 'exists' : 'null'}');
      
      if (!mounted) {
        print('SplashScreen: Widget not mounted, returning');
        return;
      }

      // Wait for the next frame
      await Future.delayed(Duration.zero);
      
      if (!mounted) {
        print('SplashScreen: Widget not mounted after delay, returning');
        return;
      }

      if (session == null) {
        print('SplashScreen: No session found, navigating to auth screen');
        Navigator.pushReplacementNamed(context, '/auth');
      } else {
        print('SplashScreen: Session found, navigating to home screen');
        Navigator.pushReplacementNamed(context, '/home');
      }
    } catch (e) {
      print('SplashScreen: Error checking session: $e');
      if (!mounted) {
        print('SplashScreen: Widget not mounted after error, returning');
        return;
      }
      
      // If there's an error, go to auth screen
      print('SplashScreen: Navigating to auth screen due to error');
      Navigator.pushReplacementNamed(context, '/auth');
    }
  }

  @override
  Widget build(BuildContext context) {
    print('SplashScreen: Building widget');
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading...'),
          ],
        ),
      ),
    );
  }
}

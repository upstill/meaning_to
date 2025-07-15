import 'package:flutter/material.dart';
import 'package:meaning_to/main.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/models/task.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _showWelcomeScreen = false;
  final bool _forceWelcomeScreen = false; // Temporary debug flag

  @override
  void initState() {
    super.initState();
    print('SplashScreen: initState called');
    print(
        'SplashScreen: MyApp.isHandlingDeepLink = ${MyApp.isHandlingDeepLink}');

    // Check if we're handling a deep link
    if (MyApp.isHandlingDeepLink) {
      print(
          'SplashScreen: Deep link in progress, not auto-navigating to /home');
      return; // Don't navigate if deep link is being handled
    }

    // Add a delay to ensure everything is initialized
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;

      // Check authentication status
      final currentUser = AuthUtils.getCurrentUser();
      final isAuthenticated = currentUser != null;

      print('SplashScreen: Authentication check after delay');
      print('SplashScreen: Current user: ${currentUser?.id ?? 'null'}');
      print('SplashScreen: User email: ${currentUser?.email ?? 'null'}');
      print('SplashScreen: Is authenticated: $isAuthenticated');

      if (isAuthenticated) {
        print('SplashScreen: User is authenticated, navigating to home');
        Navigator.of(context).pushReplacementNamed('/home');
      } else {
        print('SplashScreen: Showing welcome screen (user not authenticated)');
        setState(() {
          _showWelcomeScreen = true;
        });
      }
    });
  }

  void _navigateToLogin() {
    print('SplashScreen: Navigating to login screen');
    Navigator.of(context).pushReplacementNamed('/auth');
  }

  void _navigateAsGuest() async {
    print('SplashScreen: Guest mode requested, resetting tasks first...');

    // Reset all guest tasks before navigating
    await Task.resetGuestTasks();

    print('SplashScreen: Navigating to home screen as guest');
    Navigator.of(context).pushReplacementNamed('/home');
  }

  void _signOutForTesting() async {
    print('SplashScreen: Signing out for testing');
    try {
      await AuthUtils.signOut();
      print('SplashScreen: Sign out successful');
      // Restart the app flow
      setState(() {
        _showWelcomeScreen = false;
      });
      initState();
    } catch (e) {
      print('SplashScreen: Sign out error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    print(
        'SplashScreen: build called, _showWelcomeScreen = $_showWelcomeScreen');

    if (_showWelcomeScreen) {
      print('SplashScreen: Rendering welcome screen');
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.deepPurple, Colors.purple],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // App logo/title
                  const Icon(
                    Icons.check_circle_outline,
                    size: 80,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'I\'ve Been Meaning To',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Roll the dice to pick something you\'ve been meaning to do',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 60),

                  // Welcome message
                  const Text(
                    'Welcome!',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'How would you like to get started?',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),

                  // Login button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _navigateToLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.deepPurple,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: const Text(
                        'Sign In',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Guest mode button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: OutlinedButton(
                      onPressed: _navigateAsGuest,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white, width: 2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Continue as Guest (Read Only)',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  // Debug section (only in debug mode)
                  if (const bool.fromEnvironment('dart.vm.product') ==
                      false) ...[
                    const SizedBox(height: 40),
                    const Divider(color: Colors.white30),
                    const SizedBox(height: 16),
                    const Text(
                      'Debug Options',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: OutlinedButton(
                        onPressed: _signOutForTesting,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side:
                              const BorderSide(color: Colors.white30, width: 1),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Sign Out (Debug)',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Loading screen
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.deepPurple, Colors.purple],
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
              SizedBox(height: 24),
              Text(
                'Loading...',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

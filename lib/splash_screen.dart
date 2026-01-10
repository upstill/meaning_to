import 'package:flutter/material.dart';
import 'package:meaning_to/main.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/utils/cache_manager.dart';
import 'package:meaning_to/utils/app_state_manager.dart';
import 'package:meaning_to/models/task.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _showWelcomeScreen = false;
  final bool _forceWelcomeScreen = false; // Temporary debug flag
  String _version = '';
  String _buildNumber = '';

  @override
  void initState() {
    super.initState();
    print('SplashScreen: initState called');
    print(
        'SplashScreen: MyApp.isHandlingDeepLink = ${MyApp.isHandlingDeepLink}');

    // Load version info
    _loadVersionInfo();

    // Check if we're handling a deep link
    if (MyApp.isHandlingDeepLink) {
      print(
          'SplashScreen: Deep link in progress, not auto-navigating to /home');
      return; // Don't navigate if deep link is being handled
    }

    // Add a delay to ensure everything is initialized
    Future.delayed(const Duration(seconds: 2), () async {
      if (!mounted) return;

      // Check authentication status
      final currentUser = AuthUtils.getCurrentUser();
      final isAuthenticated = currentUser != null;

      print('SplashScreen: Authentication check after delay');
      print('SplashScreen: Current user: ${currentUser?.id ?? 'null'}');
      print('SplashScreen: User email: ${currentUser?.email ?? 'null'}');
      print('SplashScreen: Is authenticated: $isAuthenticated');

      if (isAuthenticated) {
        print('🔥🔥🔥 SPLASH SCREEN: NEW CODE RUNNING - ATTEMPTING STATE RESTORATION 🔥🔥🔥');
        _navigateWithStateRestoration(currentUser!.id);
      } else {
        print('SplashScreen: Showing welcome screen (user not authenticated)');
        // Clear any saved state since user is not authenticated
        await AppStateManager.clearState();
        // Mark state restoration as complete for non-authenticated users
        MyApp.isStateRestored = true;
        setState(() {
          _showWelcomeScreen = true;
        });
      }
    });
  }

  Future<void> _loadVersionInfo() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      setState(() {
        _version = packageInfo.version;
        _buildNumber = packageInfo.buildNumber;
      });
    } catch (e) {
      print('Error loading version info: $e');
    }
  }

  void _navigateToLogin() {
    print('SplashScreen: Navigating to login screen');
    Navigator.of(context).pushReplacementNamed('/auth');
  }

  /// Attempt to restore the user's last state and navigate accordingly
  Future<void> _navigateWithStateRestoration(String userId) async {
    try {
      print('SplashScreen: Attempting to restore last category for user: $userId');

      final cacheManager = CacheManager();
      final restoredCategory = await cacheManager.restoreLastCategory(userId);

      print('SplashScreen: State restoration result: ${restoredCategory?.headline ?? 'null'}');

      // Mark state restoration as complete
      MyApp.isStateRestored = true;

      if (restoredCategory != null) {
        print('SplashScreen: State restored successfully');
        print('SplashScreen: Category ID: ${restoredCategory.id}');
        print('SplashScreen: Category headline: ${restoredCategory.headline}');
        print('SplashScreen: Navigating to /category with ID: ${restoredCategory.id}');

        // Navigate to home screen with the restored category
        Navigator.of(context).pushReplacementNamed('/category', arguments: {
          'categoryId': restoredCategory.id.toString(),
        });
      } else {
        print('SplashScreen: No category to restore, navigating to normal home screen');
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } catch (e, stackTrace) {
      print('SplashScreen: Error during state restoration: $e');
      print('SplashScreen: Stack trace: $stackTrace');
      // Mark state restoration as complete even if failed
      MyApp.isStateRestored = true;
      // Fallback to normal home screen
      print('SplashScreen: Falling back to normal home screen');
      Navigator.of(context).pushReplacementNamed('/home');
    }
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
                    'Enjoy a little randomness',
                    // 'Roll the dice to pick something you\'ve been meaning to do',
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

                  // Sign In/Sign Up button
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
                        'Sign In/Sign Up',
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

                  // Version display at the bottom
                  const Spacer(),
                  if (_version.isNotEmpty) ...[
                    Text(
                      'v$_version (Build $_buildNumber)',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white70,
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
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
              const SizedBox(height: 24),
              const Text(
                'Loading...',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              // Version display at the bottom
              if (_version.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    'v$_version (Build $_buildNumber)',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

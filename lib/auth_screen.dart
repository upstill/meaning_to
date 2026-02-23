import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:supabase_flutter/src/supabase_auth.dart';
import 'package:meaning_to/models/icon.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  bool _obscurePassword = true;

  // OAuth icon states
  DomainIcon? _googleIcon;
  DomainIcon? _githubIcon;
  DomainIcon? _appleIcon;
  bool _iconsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadOAuthIcons();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadOAuthIcons() async {
    try {
      print('AuthScreen: Loading OAuth icons...');

      // Load Google icon
      final googleIcon = await DomainIcon.getIconForDomain('google.com');
      if (googleIcon != null) {
        print('AuthScreen: Google icon loaded successfully');
        setState(() {
          _googleIcon = googleIcon;
        });
      } else {
        print('AuthScreen: Failed to load Google icon');
      }

      // Load GitHub icon
      final githubIcon = await DomainIcon.getIconForDomain('github.com');
      if (githubIcon != null) {
        print('AuthScreen: GitHub icon loaded successfully');
        print('AuthScreen: GitHub icon data size: ${githubIcon.iconData?.length} bytes');
        setState(() {
          _githubIcon = githubIcon;
        });
      } else {
        print('AuthScreen: Failed to load GitHub icon');
      }

      // Load Apple icon
      final appleIcon = await DomainIcon.getIconForDomain('apple.com');
      if (appleIcon != null) {
        print('AuthScreen: Apple icon loaded successfully');
        setState(() {
          _appleIcon = appleIcon;
        });
      } else {
        print('AuthScreen: Failed to load Apple icon');
      }

      setState(() {
        _iconsLoaded = true;
      });
      print('AuthScreen: OAuth icons loading complete');
    } catch (e) {
      print('AuthScreen: Error loading OAuth icons: $e');
      setState(() {
        _iconsLoaded = true; // Mark as loaded even if failed
      });
    }
  }

  Future<void> _handleSignIn() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Sign in
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (response.user != null && response.session != null) {
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/home');
        }
      } else {
        setState(() {
          _error = 'Sign in failed. Please check your credentials.';
        });
      }
    } catch (e) {
      setState(() {
        _error = _getFriendlyErrorMessage(e, isSignIn: true);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleSignUp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Proceed with sign up - let Supabase handle user existence check
      print(
          'AuthScreen: Attempting signup for email: ${_emailController.text.trim()}');
      final response = await Supabase.instance.client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      print(
          'AuthScreen: Signup response - user: ${response.user != null}, session: ${response.session != null}');
      if (response.user != null) {
        if (response.session != null) {
          // New user - email confirmations are disabled - user is automatically signed in
          if (mounted) {
            Navigator.pushReplacementNamed(context, '/home');
          }
        } else {
          // User exists but no session - this could be an existing user
          // Check if the user was actually created or if they already existed
          print(
              'AuthScreen: User exists but no session - checking if this is an existing user');

          // Try to sign in to see if the user actually exists
          try {
            await Supabase.instance.client.auth.signInWithPassword(
              email: _emailController.text.trim(),
              password: _passwordController.text,
            );
            // If we get here, the user exists and password is correct
            if (mounted) {
              Navigator.pushReplacementNamed(context, '/home');
            }
          } catch (signInError) {
            // User exists but password is wrong, or user doesn't exist
            final errorString = signInError.toString().toLowerCase();
            if (errorString.contains('invalid login credentials') ||
                errorString.contains('invalid email or password')) {
              // User exists but password is wrong
              setState(() {
                _error =
                    'An account with this email already exists.\nPlease try signing in instead.';
              });
            } else {
              // This might be a new user with email confirmations enabled
              print(
                  'AuthScreen: New user detected, navigating to OTP verification');
              if (mounted) {
                Navigator.pushNamed(
                  context,
                  '/auth/verify-otp',
                  arguments: {'email': _emailController.text.trim()},
                );
              }
            }
          }
        }
      } else {
        setState(() {
          _error = 'Sign up failed. Please try again.';
        });
      }
    } catch (e) {
      final errorString = e.toString().toLowerCase();
      print('AuthScreen: Signup failed with error: $errorString');

      // Check if user already exists during signup
      if (errorString.contains('user already registered') ||
          errorString.contains('already registered') ||
          errorString.contains('user already exists') ||
          errorString.contains('invalid_credentials')) {
        setState(() {
          _error =
              'An account with this email already exists.\nPlease try signing in instead.';
        });
      } else {
        setState(() {
          _error = _getFriendlyErrorMessage(e, isSignIn: false);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleForgotPassword() async {
    Navigator.pushNamed(context, '/password-reset-request');
  }

  // OAuth Sign-In Methods
  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Let Supabase handle the redirect URL automatically
      // It will use the Site URL configured in Supabase dashboard
      print('AuthScreen: Starting Google OAuth sign-in');

      // Use custom scheme for mobile, web URL for web
      final redirectTo = foundation.kIsWeb
          ? '${Uri.base.origin}/auth/callback'
          : 'meaningto://auth/callback';

      print('AuthScreen: Using redirect URL: $redirectTo');

      try {

        await Supabase.instance.client.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: redirectTo,
        );
        print('AuthScreen: OAuth sign-in initiated successfully');
      } catch (e) {
        print('AuthScreen: OAuth sign-in error: $e');
        print('AuthScreen: Error details: ${e.toString()}');
        rethrow;
      }

      // For OAuth, we don't immediately get a session
      // The user will be redirected to the OAuth provider
      // and then back to the app
    } catch (e) {
      print('AuthScreen: Google OAuth error: $e');
      setState(() {
        _error = 'Google sign-in failed. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleGitHubSignIn() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      print('AuthScreen: Starting GitHub OAuth sign-in');

      // Use custom scheme for mobile, web URL for web
      final redirectTo = foundation.kIsWeb
          ? '${Uri.base.origin}/auth/callback'
          : 'meaningto://auth/callback';

      print('AuthScreen: Using redirect URL: $redirectTo');

      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.github,
        redirectTo: redirectTo,
      );
      print('AuthScreen: GitHub OAuth sign-in initiated successfully');

      // For OAuth, we don't immediately get a session
      // The user will be redirected to the OAuth provider
      // and then back to the app
    } catch (e) {
      print('AuthScreen: GitHub OAuth error: $e');
      setState(() {
        _error = 'GitHub sign-in failed. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleAppleSignIn() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      print('AuthScreen: Starting Apple OAuth sign-in');

      // Use custom scheme for mobile, web URL for web
      final redirectTo = foundation.kIsWeb
          ? '${Uri.base.origin}/auth/callback'
          : 'meaningto://auth/callback';

      print('AuthScreen: Using redirect URL: $redirectTo');

      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: redirectTo,
      );
      print('AuthScreen: Apple OAuth sign-in initiated successfully');
    } catch (e) {
      print('AuthScreen: Apple OAuth error: $e');
      setState(() {
        _error = 'Apple sign-in failed. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _getFriendlyErrorMessage(dynamic error, {required bool isSignIn}) {
    final errorString = error.toString().toLowerCase();

    if (isSignIn) {
      // Sign in error messages
      if (errorString.contains('invalid login credentials') ||
          errorString.contains('invalid email or password') ||
          errorString.contains('credentials don\'t match')) {
        return 'Sorry! We have no match for that email/password combo.\nPlease check your credentials and try again.\nIf you haven\'t signed in before--and that\'s your email--sign up!';
      }
      if (errorString.contains('email not confirmed')) {
        return 'Please check your email and click the confirmation link before signing in.';
      }
      if (errorString.contains('too many requests')) {
        return 'Too many sign-in attempts. Please wait a moment before trying again.';
      }
    } else {
      // Sign up error messages
      if (errorString.contains('user already registered') ||
          errorString.contains('already registered') ||
          errorString.contains('user already exists')) {
        return 'An account with this email already exists. Please try signing in instead.';
      }
      if (errorString.contains('invalid email')) {
        return 'Please enter a valid email address.';
      }
      if (errorString.contains('password')) {
        return 'Password must be at least 6 characters long.';
      }
      if (errorString.contains('too many requests')) {
        return 'Too many sign-up attempts. Please wait a moment before trying again.';
      }
    }

    // Default fallback message
    return 'Something went wrong. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24.0, 96.0, 24.0, 24.0),
        children: [
          Column(
            children: [
              const Text(
                'I\'ve Been Meaning To',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 32,
                ),
              ),
              const SizedBox(height: 48.0),

              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter your email';
                        }
                        if (!value.contains('@')) {
                          return 'Please enter a valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                      obscureText: _obscurePassword,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your password';
                        }
                        if (value.length < 6) {
                          return 'Password must be at least 6 characters';
                        }
                        return null;
                      },
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 56,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _handleSignIn,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.deepPurple,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 2,
                              ),
                              child: _isLoading
                                  ? const CircularProgressIndicator(
                                      color: Colors.white)
                                  : const Text(
                                      'Sign In',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: SizedBox(
                            height: 56,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _handleSignUp,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.deepPurple,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 2,
                              ),
                              child: _isLoading
                                  ? const CircularProgressIndicator(
                                      color: Colors.deepPurple)
                                  : const Text(
                                      'Sign Up',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _isLoading ? null : _handleForgotPassword,
                        child: const Text(
                          'Forgot Password?',
                          style: TextStyle(
                            color: Colors.deepPurple,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Divider
                    const Divider(
                      thickness: 1,
                      color: Colors.grey,
                    ),

                    const SizedBox(height: 24),

                    // OAuth Sign-In Buttons (smaller, horizontal)
                    Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 48,
                                child: ElevatedButton.icon(
                                  onPressed:
                                      _isLoading ? null : _handleGoogleSignIn,
                                  icon: const Text(
                                    'G',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  label: const Text(
                                    'Google',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    elevation: 2,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SizedBox(
                                height: 48,
                                child: ElevatedButton.icon(
                                  onPressed:
                                      _isLoading ? null : _handleGitHubSignIn,
                                  icon: const Icon(
                                    Icons.code,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  label: const Text(
                                    'GitHub',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    elevation: 2,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        // Apple sign-in button commented out due to domain verification issues
                        // const SizedBox(height: 12),
                        // SizedBox(
                        //   width: double.infinity,
                        //   height: 48,
                        //   child: ElevatedButton.icon(
                        //     onPressed: _isLoading ? null : _handleAppleSignIn,
                        //     icon: _appleIcon?.iconData != null
                        //         ? Image.memory(
                        //             _appleIcon!.iconData!,
                        //             width: 26,
                        //             height: 26,
                        //             fit: BoxFit.contain,
                        //           )
                        //         : const Icon(Icons.apple,
                        //             color: Colors.white, size: 26),
                        //     label: const Text(
                        //       'Apple',
                        //       style: TextStyle(
                        //         fontSize: 14,
                        //         fontWeight: FontWeight.w600,
                        //         color: Colors.white,
                        //       ),
                        //     ),
                        //     style: ElevatedButton.styleFrom(
                        //       backgroundColor: Colors.black,
                        //       shape: RoundedRectangleBorder(
                        //         borderRadius: BorderRadius.circular(8),
                        //       ),
                        //       elevation: 2,
                        //     ),
                        //   ),
                        // ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

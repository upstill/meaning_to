import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:supabase_flutter/supabase_flutter.dart';

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

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
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
                  'AuthScreen: New user detected, showing email confirmation');
              if (mounted) {
                Navigator.pushReplacementNamed(
                  context,
                  '/email-confirmation',
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
                  fontSize: 24,
                ),
              ),
              const SizedBox(height: 24.0),
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
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
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
                    const SizedBox(height: 16),
                    Center(
                      child: TextButton(
                        onPressed: _isLoading
                            ? null
                            : () {
                                Navigator.pushNamed(context, '/reset-password');
                              },
                        child: const Text(
                          'Forgot Password?',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.deepPurple,
                          ),
                        ),
                      ),
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

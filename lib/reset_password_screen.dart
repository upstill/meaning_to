import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meaning_to/utils/supabase_client.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String token;
  final String? email; // Optional email parameter
  final bool verified; // Whether the token was already verified
  final String? tokenType; // Add token type parameter

  const ResetPasswordScreen({
    super.key,
    required this.token,
    this.email,
    this.verified = false,
    this.tokenType, // Add token type parameter
  });

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  String? _recoveryToken;
  bool _obscurePassword = false;
  bool _obscureConfirmPassword = false;

  @override
  void initState() {
    super.initState();
    print('🚨🚨🚨 ResetPasswordScreen - initState - NEW CODE RUNNING 🚨🚨🚨');

    // Pre-fill email if provided, otherwise use default for testing
    if (widget.email != null) {
      _emailController.text = widget.email!;
      print('ResetPasswordScreen - Using provided email: ${widget.email}');
    } else {
      _emailController.text = 'steve@upstill.net';
      print('ResetPasswordScreen - Using default email: steve@upstill.net');
    }

    // Pre-fill password fields for testing
    _passwordController.text = 'vw541sim';
    _confirmPasswordController.text = 'vw541sim';
    print('ResetPasswordScreen - Prefilled password fields with: vw541sim');

    _checkSession();

    // Auto-attempt password reset if we have a token but no email
    // This reduces the time delay that causes token expiration
    if (widget.email == null) {
      print(
          'ResetPasswordScreen - No email provided, will prompt user to enter email');
    }
  }

  Future<void> _checkSession() async {
    print('ResetPasswordScreen - Checking session');
    final user = supabase.auth.currentUser;
    final session = supabase.auth.currentSession;
    print('ResetPasswordScreen - Current user: ${user?.id}');
    print('ResetPasswordScreen - User metadata: ${user?.userMetadata}');
    print(
        'ResetPasswordScreen - Session: ${session?.accessToken != null ? 'exists' : 'null'}');

    // For password recovery, we might not have a full session yet
    // The token from the URL should be sufficient
    if (user == null && session == null) {
      print(
          'ResetPasswordScreen - No user or session, but continuing with token-based recovery');
      // Continue with token-based recovery
    } else if (user?.userMetadata?['type'] == 'recovery') {
      print('ResetPasswordScreen - Valid recovery session');
    } else {
      print(
          'ResetPasswordScreen - Regular session found, continuing with recovery');
      // Continue with recovery even if it's not marked as recovery type
    }
  }

  Future<void> _resetPassword() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        print('ResetPasswordScreen - Starting password reset');
        print(
            'ResetPasswordScreen - Current user: ${supabase.auth.currentUser}');
        print(
            'ResetPasswordScreen - User metadata: ${supabase.auth.currentUser?.userMetadata}');
        print('ResetPasswordScreen - Session: ${supabase.auth.currentSession}');

        final email = _emailController.text.trim();
        final newPassword = _passwordController.text;

        // Check if we're in a recovery session (from PASSWORD_RECOVERY event)
        final session = supabase.auth.currentSession;
        final user = supabase.auth.currentUser;

        if (session != null && user != null) {
          // We have a session, check if it's a recovery session
          print(
              'ResetPasswordScreen - Session exists, checking if it\'s a recovery session');

          // Try to update password directly if we have a valid session
          try {
            await supabase.auth.updateUser(
              UserAttributes(
                password: newPassword,
              ),
            );
            print(
                'ResetPasswordScreen - Password updated successfully with existing session');
            _showSuccessDialog();
            return;
          } catch (e) {
            print(
                'ResetPasswordScreen - Failed to update password with existing session: $e');
            // Continue with token-based recovery if direct update fails
          }
        }

        // No valid session or direct update failed, try token-based recovery
        print('ResetPasswordScreen - Attempting token-based recovery');

        if (widget.token.isNotEmpty) {
          print('ResetPasswordScreen - Attempting to verify recovery token');
          print(
              'ResetPasswordScreen - Timestamp: ${DateTime.now().toIso8601String()}');
          print('ResetPasswordScreen - Email: $email');
          print('ResetPasswordScreen - Token length: ${widget.token.length}');
          print(
              'ResetPasswordScreen - Token: ${widget.token.substring(0, 8)}...');
          print('ResetPasswordScreen - Full token: ${widget.token}');
          print(
              'ResetPasswordScreen - Token contains special chars: ${widget.token.contains(RegExp(r'[^a-zA-Z0-9\-]'))}');
          print('ResetPasswordScreen - Current time: ${DateTime.now()}');
          print(
              'ResetPasswordScreen - Note: Token verification should happen within 1-2 minutes of receiving the link');
          print('ResetPasswordScreen - Token type: ${widget.tokenType}');

          try {
            // Check if this is a PKCE token from the verify endpoint
            if (widget.tokenType == 'pkce' ||
                widget.token.startsWith('pkce_')) {
              print(
                  'ResetPasswordScreen - Handling PKCE token from verify endpoint');

              // For PKCE tokens, we need to use the verify endpoint
              // This should establish a session that allows password update
              await supabase.auth.verifyOTP(
                email: email,
                token: widget.token,
                type: OtpType.recovery,
              );
              print('ResetPasswordScreen - PKCE token verification successful');

              // Now update the password
              await supabase.auth.updateUser(
                UserAttributes(
                  password: newPassword,
                ),
              );
              print(
                  'ResetPasswordScreen - Password updated successfully after PKCE verification');

              _showSuccessDialog();
            } else {
              // Regular recovery token handling
              print('ResetPasswordScreen - Handling regular recovery token');

              // Try recovery verification first
              await supabase.auth.verifyOTP(
                email: email,
                token: widget.token,
                type: OtpType.recovery,
              );
              print('ResetPasswordScreen - Recovery verification successful');

              // Now update the password
              await supabase.auth.updateUser(
                UserAttributes(
                  password: newPassword,
                ),
              );
              print(
                  'ResetPasswordScreen - Password updated successfully after recovery verification');

              _showSuccessDialog();
            }
          } catch (e) {
            print('ResetPasswordScreen - Recovery verification failed: $e');
            print('ResetPasswordScreen - Error type: ${e.runtimeType}');
            print('ResetPasswordScreen - Error message: $e');
            print('🚨🚨🚨 ENHANCED DEBUGGING ACTIVE 🚨🚨🚨');

            // Enhanced error debugging
            if (e is AuthException) {
              print('ResetPasswordScreen - AuthException details:');
              print('  Status code: ${e.statusCode}');
              print('  Message: ${e.message}');
            } else if (e is AuthApiException) {
              print('ResetPasswordScreen - AuthApiException details:');
              print('  Status code: ${e.statusCode}');
              print('  Message: ${e.message}');
            }

            // Log the exact parameters being sent
            print('ResetPasswordScreen - Parameters sent:');
            print('  Email: $email');
            print('  Token: ${widget.token}');
            print('  Token length: ${widget.token.length}');
            print(
                '  Token format valid: ${RegExp(r'^[a-f0-9\-]{36}$').hasMatch(widget.token)}');

            // Try signup verification as fallback
            print(
                'ResetPasswordScreen - Trying signup verification as fallback');
            try {
              await supabase.auth.verifyOTP(
                email: email,
                token: widget.token,
                type: OtpType.signup,
              );
              print('ResetPasswordScreen - Signup verification successful');

              // Now update the password
              await supabase.auth.updateUser(
                UserAttributes(
                  password: newPassword,
                ),
              );
              print(
                  'ResetPasswordScreen - Password updated successfully after signup verification');

              _showSuccessDialog();
            } catch (signupError) {
              print(
                  'ResetPasswordScreen - Signup verification also failed: $signupError');
              print(
                  'ResetPasswordScreen - Signup error type: ${signupError.runtimeType}');
              print('ResetPasswordScreen - Signup error message: $signupError');

              // Try to get more diagnostic information
              print('ResetPasswordScreen - Attempting diagnostic tests...');

              // Test 1: Try with a different email format
              try {
                print(
                    'ResetPasswordScreen - Test 1: Trying with email in different case');
                await supabase.auth.verifyOTP(
                  email: email.toUpperCase(),
                  token: widget.token,
                  type: OtpType.recovery,
                );
                print(
                    'ResetPasswordScreen - Test 1 succeeded with uppercase email!');
              } catch (test1Error) {
                print('ResetPasswordScreen - Test 1 failed: $test1Error');
              }

              // Test 2: Try with trimmed token
              try {
                print(
                    'ResetPasswordScreen - Test 2: Trying with trimmed token');
                await supabase.auth.verifyOTP(
                  email: email,
                  token: widget.token.trim(),
                  type: OtpType.recovery,
                );
                print(
                    'ResetPasswordScreen - Test 2 succeeded with trimmed token!');
              } catch (test2Error) {
                print('ResetPasswordScreen - Test 2 failed: $test2Error');
              }

              // Test 3: Try to send a new reset email to see if the account exists
              try {
                print(
                    'ResetPasswordScreen - Test 3: Trying to send new reset email');
                await supabase.auth.resetPasswordForEmail(email);
                print(
                    'ResetPasswordScreen - Test 3 succeeded: New reset email sent successfully');
              } catch (test3Error) {
                print('ResetPasswordScreen - Test 3 failed: $test3Error');
                print(
                    'ResetPasswordScreen - This suggests the email/account might not exist');
              }

              // Test 4: Check if we can sign up with this email (to see if account exists)
              try {
                print(
                    'ResetPasswordScreen - Test 4: Trying to sign up with email to check if account exists');
                await supabase.auth.signUp(
                  email: email,
                  password: 'temporary_password_for_test',
                );
                print(
                    'ResetPasswordScreen - Test 4 succeeded: Account does not exist, signup worked');
              } catch (test4Error) {
                print('ResetPasswordScreen - Test 4 failed: $test4Error');
                if (test4Error.toString().contains('already registered')) {
                  print(
                      'ResetPasswordScreen - Account exists but is already registered');
                }
              }

              // Show error dialog with more specific guidance
              _showErrorDialog(
                  'Password reset failed. This could be due to:\n\n'
                  '• Token expiration (most likely)\n'
                  '• Email mismatch\n'
                  '• Invalid token format\n'
                  '• Account doesn\'t exist\n\n'
                  'Please try requesting a new reset link, or contact support if the issue persists.');
            }
          }
        } else {
          // No token provided, try to send a new recovery email
          print(
              'ResetPasswordScreen - No recovery token provided, sending new recovery email');
          await supabase.auth.resetPasswordForEmail(email);
          print('ResetPasswordScreen - Recovery email sent successfully');

          _showInfoDialog(
            'Password Reset Email Sent',
            'A new password reset link has been sent to your email. Please check your inbox and click the link to reset your password.',
          );
        }
      } catch (e) {
        print('ResetPasswordScreen - Error: $e');
        _showErrorDialog(
            'An error occurred while resetting your password. Please try again.');
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showSuccessDialog() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated successfully')),
      );
      Navigator.pushReplacementNamed(context, '/auth');
    }
  }

  void _showErrorDialog(String message) {
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Error'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close dialog
                  Navigator.pushReplacementNamed(context, '/auth');
                },
                child: const Text('Go to Login'),
              ),
            ],
          );
        },
      );
    }
  }

  void _showInfoDialog(String title, String message) {
    if (mounted) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close dialog
                  Navigator.pushReplacementNamed(
                      context, '/auth'); // Go back to auth screen
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    }
  }

  void _requestNewReset() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showErrorDialog('Please enter your email address first.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await supabase.auth.resetPasswordForEmail(email);
      _showInfoDialog(
        'Password Reset Email Sent',
        'A new password reset link has been sent to your email. Please check your inbox and click the link to reset your password.',
      );
    } catch (e) {
      print('Error sending reset email: $e');
      _showErrorDialog(
          'Failed to send password reset email. Please try again.');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Prevent going back to home screen
        Navigator.pushReplacementNamed(context, '/auth');
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Reset Password'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.pushReplacementNamed(context, '/auth');
            },
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Enter your email address and new password to reset your account.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  '⚠️ Please complete this quickly - the reset link expires in a few minutes.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.orange),
                ),
                const SizedBox(height: 24),
                // Debug info
                Text(
                  'Debug: Email="${_emailController.text}", Password="${_passwordController.text}"',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'New Password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
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
                      return 'Please enter a password';
                    }
                    if (value.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPasswordController,
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        });
                      },
                    ),
                  ),
                  obscureText: _obscureConfirmPassword,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please confirm your password';
                    }
                    if (value != _passwordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _resetPassword,
                    child: _isLoading
                        ? const CircularProgressIndicator()
                        : const Text('Reset Password'),
                  ),
                ),
                const SizedBox(height: 16),
                if (widget.token.isNotEmpty) ...[
                  const Text(
                    'If the reset link has expired, you can request a new one:',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : _requestNewReset,
                      child: const Text('Request New Reset Link'),
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
}

import 'package:flutter/material.dart';
import 'package:meaning_to/theme/app_colors.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthVerificationScreen extends StatefulWidget {
  final String? token;
  final String? tokenHash;
  final String? type;
  final String? redirectTo;

  const AuthVerificationScreen({
    super.key,
    this.token,
    this.tokenHash,
    this.type,
    this.redirectTo,
  });

  @override
  State<AuthVerificationScreen> createState() => _AuthVerificationScreenState();
}

class _AuthVerificationScreenState extends State<AuthVerificationScreen> {
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _handleVerification();
  }

  Future<void> _handleVerification() async {
    print('AuthVerificationScreen: Starting verification');
    print('Token: ${widget.token}');
    print('TokenHash: ${widget.tokenHash}');
    print('Type: ${widget.type}');
    print('RedirectTo: ${widget.redirectTo}');

    // If we're on web and this looks like a Supabase verification URL,
    // we need to parse the full URL to get the session
    if (foundation.kIsWeb) {
      final currentUri = Uri.base;
      print('Current URI: $currentUri');
      print('Current query params: ${currentUri.queryParameters}');
      print('Current fragment: ${currentUri.fragment}');

      // Check if we have session data in the URL fragment (common for OAuth and password reset)
      if (currentUri.fragment.isNotEmpty) {
        print('Found fragment data: ${currentUri.fragment}');
        final fragmentParams = Uri.splitQueryString(currentUri.fragment);
        print('Fragment params: $fragmentParams');

        // Check if this is a password reset token
        if (fragmentParams.containsKey('access_token') || 
            fragmentParams.containsKey('refresh_token')) {
          print('Session tokens found in fragment');
          
          // The session should already be set by Supabase automatically
          // Let's check if we have a session now
          await Future.delayed(const Duration(milliseconds: 500)); // Give Supabase time to process
          
          final session = Supabase.instance.client.auth.currentSession;
          print('Current session after fragment processing: ${session != null ? "exists" : "null"}');
          
          if (session != null) {
            print('Session found - checking if this is a password reset');
            // Check if this is a password reset flow
            if (widget.type == 'recovery' || fragmentParams.containsKey('type') && fragmentParams['type'] == 'recovery') {
              print('Password reset verified - navigating to reset password screen');
              if (mounted) {
                Navigator.pushReplacementNamed(
                  context,
                  '/auth/reset-password',
                  arguments: {
                    'token': widget.token ?? fragmentParams['access_token'],
                    'type': 'recovery',
                  },
                );
              }
              return;
            } else {
              print('Email confirmation verified - navigating to home');
              if (mounted) {
                Navigator.pushReplacementNamed(context, '/home');
              }
              return;
            }
          }
        }
      }

      // Check query parameters for token and type
      final queryParams = currentUri.queryParameters;
      if (queryParams.containsKey('token') && queryParams.containsKey('type')) {
        print('Found token and type in query params');
        final token = queryParams['token']!;
        final type = queryParams['type']!;
        
        try {
          print('Attempting to verify OTP with token: $token, type: $type');
          
          // Determine the OTP type
          OtpType otpType;
          switch (type) {
            case 'recovery':
              otpType = OtpType.recovery;
              break;
            case 'signup':
            case 'email':
              otpType = OtpType.signup;
              break;
            case 'invite':
              otpType = OtpType.invite;
              break;
            case 'magiclink':
              otpType = OtpType.magiclink;
              break;
            case 'email_change':
              otpType = OtpType.emailChange;
              break;
            default:
              throw Exception('Unknown OTP type: $type');
          }

          final response = await Supabase.instance.client.auth.verifyOTP(
            token: token,
            type: otpType,
          );

          print('OTP verification response: ${response.user != null ? "user exists" : "no user"}, ${response.session != null ? "session exists" : "no session"}');

          if (response.user != null && response.session != null) {
            print('Verification successful');
            
            if (type == 'recovery') {
              print('Password reset verified - navigating to reset password screen');
              if (mounted) {
                Navigator.pushReplacementNamed(
                  context,
                  '/auth/reset-password',
                  arguments: {
                    'token': token,
                    'type': type,
                  },
                );
              }
            } else {
              print('Email confirmation verified - navigating to home');
              if (mounted) {
                Navigator.pushReplacementNamed(context, '/home');
              }
            }
            return;
          } else {
            setState(() {
              _error = 'Verification failed. The link may have expired.';
              _isLoading = false;
            });
          }
        } catch (e) {
          print('Verification error: $e');
          setState(() {
            _error = 'Verification failed: ${e.toString()}';
            _isLoading = false;
          });
        }
      } else {
        print('No verification parameters found');
        setState(() {
          _error = 'Invalid verification link.';
          _isLoading = false;
        });
      }
    } else {
      // Mobile deep link handling
      if (widget.token != null && widget.type != null) {
        try {
          OtpType otpType;
          switch (widget.type!) {
            case 'recovery':
              otpType = OtpType.recovery;
              break;
            case 'signup':
            case 'email':
              otpType = OtpType.signup;
              break;
            case 'invite':
              otpType = OtpType.invite;
              break;
            case 'magiclink':
              otpType = OtpType.magiclink;
              break;
            case 'email_change':
              otpType = OtpType.emailChange;
              break;
            default:
              throw Exception('Unknown OTP type: ${widget.type}');
          }

          final response = await Supabase.instance.client.auth.verifyOTP(
            token: widget.token!,
            type: otpType,
          );

          if (response.user != null && response.session != null) {
            if (widget.type == 'recovery') {
              if (mounted) {
                Navigator.pushReplacementNamed(
                  context,
                  '/auth/reset-password',
                  arguments: {
                    'token': widget.token,
                    'type': widget.type,
                  },
                );
              }
            } else {
              if (mounted) {
                Navigator.pushReplacementNamed(context, '/home');
              }
            }
            return;
          } else {
            setState(() {
              _error = 'Verification failed. The link may have expired.';
              _isLoading = false;
            });
          }
        } catch (e) {
          setState(() {
            _error = 'Verification failed: ${e.toString()}';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _error = 'Invalid verification link.';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isLoading) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                const Text(
                  'Verifying...',
                  style: TextStyle(fontSize: 18),
                ),
              ] else if (_error != null) ...[
                const Icon(
                  Icons.error_outline,
                  size: 80,
                  color: Colors.red,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Verification Failed',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pushReplacementNamed(context, '/auth'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Back to Sign In'),
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
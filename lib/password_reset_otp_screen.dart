import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PasswordResetOtpScreen extends StatefulWidget {
  final String email;

  const PasswordResetOtpScreen({
    super.key,
    required this.email,
  });

  @override
  State<PasswordResetOtpScreen> createState() => _PasswordResetOtpScreenState();
}

class _PasswordResetOtpScreenState extends State<PasswordResetOtpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _otpController = TextEditingController();
  bool _isLoading = false;
  bool _isResending = false;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _verifyOTP() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final otp = _otpController.text.trim();

      print('PasswordResetOTP: Verifying OTP: $otp for email: ${widget.email}');

      // Verify the OTP for password recovery
      await Supabase.instance.client.auth.verifyOTP(
        email: widget.email,
        token: otp,
        type: OtpType.recovery,
      );

      print('PasswordResetOTP: OTP verified successfully');

      if (mounted) {
        // Navigate to new password screen
        Navigator.pushReplacementNamed(
          context,
          '/password-reset-new',
          arguments: {'email': widget.email},
        );
      }
    } catch (e) {
      print('PasswordResetOTP: Error verifying OTP: $e');

      if (mounted) {
        String errorMessage = 'Invalid verification code.';

        if (e is AuthException) {
          switch (e.message.toLowerCase()) {
            case 'token has expired or is invalid':
            case 'otp expired':
              errorMessage =
                  'Verification code has expired. Please request a new one.';
              break;
            case 'invalid otp':
              errorMessage =
                  'Invalid verification code. Please check and try again.';
              break;
            default:
              errorMessage = e.message;
          }
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _resendOTP() async {
    setState(() {
      _isResending = true;
    });

    try {
      print('PasswordResetOTP: Resending OTP to: ${widget.email}');

      // Resend OTP
      await Supabase.instance.client.auth.signInWithOtp(
        email: widget.email,
        emailRedirectTo: null,
      );

      print('PasswordResetOTP: OTP resent successfully');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verification code sent! Check your email.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('PasswordResetOTP: Error resending OTP: $e');

      if (mounted) {
        String errorMessage = 'Failed to resend verification code.';

        if (e is AuthException) {
          if (e.message.toLowerCase().contains('rate limit')) {
            errorMessage =
                'Too many requests. Please wait a few minutes before trying again.';
          } else {
            errorMessage = e.message;
          }
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isResending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Code'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pushReplacementNamed(
              context, '/password-reset-request'),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Enter Verification Code',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'We sent a 6-digit verification code to:',
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                widget.email,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              TextFormField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 8,
                ),
                decoration: const InputDecoration(
                  labelText: 'Verification Code',
                  hintText: '123456',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter the verification code';
                  }
                  if (value.length != 6) {
                    return 'Verification code must be 6 digits';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _verifyOTP,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 48),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Verify Code',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _isResending ? null : _resendOTP,
                child: _isResending
                    ? const Text('Sending...')
                    : const Text('Didn\'t receive the code? Send again'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pushReplacementNamed(
                    context, '/password-reset-request'),
                child: const Text('Use a different email address'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

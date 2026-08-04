import 'package:flutter/material.dart';
import 'package:meaning_to/theme/app_colors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meaning_to/utils/api_client.dart';
import 'package:meaning_to/utils/invite_token_store.dart';
import 'package:meaning_to/widgets/home_button.dart';

class AuthOtpVerificationScreen extends StatefulWidget {
  const AuthOtpVerificationScreen({super.key});

  @override
  State<AuthOtpVerificationScreen> createState() =>
      _AuthOtpVerificationScreenState();
}

class _AuthOtpVerificationScreenState extends State<AuthOtpVerificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _otpController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _verifyOtp(String email) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      print(
          'AuthOtpVerificationScreen: Verifying OTP for email: $email, token: ${_otpController.text.trim()}');
      final response = await Supabase.instance.client.auth.verifyOTP(
        email: email,
        token: _otpController.text.trim(),
        type: OtpType.email,
      );

      print(
          'AuthOtpVerificationScreen: OTP verification response - session: ${response.session != null}');

      if (response.session != null && mounted) {
        // Successfully verified - redeem any pending invite, then navigate
        print('AuthOtpVerificationScreen: Verification successful');
        final pendingToken = await InviteTokenStore.get();
        if (pendingToken != null && mounted) {
          try {
            await ApiClient.redeemPending(pendingToken);
          } catch (e) {
            print('AuthOtpVerificationScreen: Failed to redeem invite: $e');
          }
          await InviteTokenStore.clear();
        }
        if (mounted) Navigator.pushReplacementNamed(context, '/home');
      } else {
        setState(() {
          _error = 'Verification failed. Please try again.';
          _isLoading = false;
        });
      }
    } catch (e) {
      print('AuthOtpVerificationScreen: Verification error: $e');
      setState(() {
        _error = 'Invalid or expired code. Please try again.';
        _isLoading = false;
      });
    }
  }

  Future<void> _resendCode(String email) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      print('AuthOtpVerificationScreen: Resending code to $email');
      await Supabase.instance.client.auth.signInWithOtp(
        email: email,
        shouldCreateUser: false,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verification code resent!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('AuthOtpVerificationScreen: Resend error: $e');
      setState(() {
        _error = 'Failed to resend code. Please try again.';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final email = (args?['email'] as String?) ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Email'),
        leading: const HomeButton(),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                const Icon(
                  Icons.email_outlined,
                  size: 80,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 32),
                Text(
                  'Check Your Email',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'We sent a 6-digit verification code to:',
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  email,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                TextFormField(
                  controller: _otpController,
                  decoration: InputDecoration(
                    labelText: 'Verification Code',
                    hintText: '000000',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.security),
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 28,
                    letterSpacing: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  onChanged: (value) {
                    // Auto-submit when 6 digits are entered
                    if (value.length == 6 && RegExp(r'^\d+$').hasMatch(value)) {
                      print('AuthOtpVerificationScreen: Auto-submitting code');
                      _verifyOtp(email);
                    }
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter the code';
                    }
                    if (value.length != 6) {
                      return 'Code must be 6 digits';
                    }
                    if (!RegExp(r'^\d+$').hasMatch(value)) {
                      return 'Code must contain only numbers';
                    }
                    return null;
                  },
                  autofocus: true,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline,
                            color: Colors.red.shade700, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : () => _verifyOtp(email),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'Verify Email',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Didn\'t receive the code?',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    TextButton(
                      onPressed: _isLoading ? null : () => _resendCode(email),
                      child: const Text(
                        'Resend',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.info_outline,
                          color: Colors.blue.shade700, size: 20),
                      const SizedBox(height: 8),
                      Text(
                        'The code expires in 60 seconds. If you don\'t see the email, check your spam folder.',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

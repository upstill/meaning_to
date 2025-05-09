import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_auth_ui/supabase_auth_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Define the redirect URL based on platform
    final supabaseUrl = dotenv.env['SUPABASE_URL']!;
    // Use the app's custom URL scheme for deep linking
    final redirectUrl = 'meaningto://auth/callback';

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
              SupaEmailAuth(
                redirectTo: redirectUrl,
                onSignInComplete: (res) => Navigator.pushNamed(context, '/home'),
                onSignUpComplete: (res) => Navigator.pushNamed(context, '/home'),
                onError: (error) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(error.toString())),
                  );
                },
              ),
              const SizedBox(height: 16.0),
              TextButton(
                onPressed: () async {
                  final emailController = TextEditingController();
                  final result = await showDialog<String>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Reset Password'),
                      content: TextField(
                        controller: emailController,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          hintText: 'Enter your email address',
                        ),
                        keyboardType: TextInputType.emailAddress,
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, emailController.text),
                          child: const Text('Send Reset Link'),
                        ),
                      ],
                    ),
                  );

                  if (result != null && result.isNotEmpty) {
                    try {
                      await Supabase.instance.client.auth.resetPasswordForEmail(
                        result,
                        redirectTo: redirectUrl,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Password reset email sent! Check your inbox.'),
                          ),
                        );
                      }
                    } catch (error) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error sending reset email: $error')),
                        );
                      }
                    }
                  }
                },
                child: const Text('Forgot Password?'),
              ),
              const SizedBox(height: 24.0),
              SupaSocialsAuth(
                socialProviders: const [
                  OAuthProvider.google,
                  OAuthProvider.github,
                ],
                redirectUrl: redirectUrl,
                onSuccess: (session) => Navigator.pushNamed(
                  context,
                  '/home',
                ),
                onError: (error) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(error.toString())),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

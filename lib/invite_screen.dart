import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meaning_to/utils/api_client.dart';
import 'package:meaning_to/utils/invite_token_store.dart';

/// Handles landing on a share-invitation link (/join?invite=<token>).
///
/// If the user is already signed in, redeems the invitation immediately
/// and navigates to the shared category.
///
/// If not signed in, stashes the token in SharedPreferences and redirects
/// to the auth screen; post-sign-in flow picks it up and redeems it.
class InviteScreen extends StatefulWidget {
  final String token;

  const InviteScreen({super.key, required this.token});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  @override
  void initState() {
    super.initState();
    _handleInvite();
  }

  Future<void> _handleInvite() async {
    final session = Supabase.instance.client.auth.currentSession;

    if (session != null) {
      // Signed in — redeem immediately
      try {
        final categoryId = await ApiClient.redeemInvitation(widget.token);
        if (mounted) {
          Navigator.pushReplacementNamed(
            context,
            '/category',
            arguments: {'categoryId': categoryId.toString()},
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not accept invitation: $e')),
          );
          Navigator.pushReplacementNamed(context, '/home');
        }
      }
    } else {
      // Not signed in — stash token, redirect to auth
      await InviteTokenStore.set(widget.token);
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/auth');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meaning_to/utils/api_client.dart';
import 'package:meaning_to/utils/invite_token_store.dart';

/// Handles landing on a share link:
///   /join?share=<linkId>   (new unified reusable links)
///   /join?invite=<token>   (legacy single-category invitations)
///
/// [pending] is the value to redeem: a new share link encoded as 'share:<id>',
/// or a legacy invite token (raw uuid). If signed in, redeems immediately and
/// lands on /home (where the new-shares notification surfaces what was granted).
/// If not signed in, stashes [pending] and redirects to auth; the post-sign-in
/// flow picks it up and redeems it.
class InviteScreen extends StatefulWidget {
  final String pending;

  const InviteScreen({super.key, required this.pending});

  /// Builds an InviteScreen from raw URL query params, preferring a new
  /// `?share=` link over a legacy `?invite=` token.
  static InviteScreen? fromParams(Map<String, String> params, {Key? key}) {
    final shareId = params['share'];
    if (shareId != null) return InviteScreen(key: key, pending: 'share:$shareId');
    final token = params['invite'];
    if (token != null) return InviteScreen(key: key, pending: token);
    return null;
  }

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
      // Signed in — redeem immediately, then land on home.
      try {
        await ApiClient.redeemPending(widget.pending);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not accept invitation: $e')),
          );
        }
      }
      if (mounted) Navigator.pushReplacementNamed(context, '/home');
    } else {
      // Not signed in — stash pending value, redirect to auth.
      await InviteTokenStore.set(widget.pending);
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

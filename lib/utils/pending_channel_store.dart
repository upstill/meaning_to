import 'package:shared_preferences/shared_preferences.dart';

/// Records the share-link id just redeemed, so Home can — after the fact and
/// regardless of which redemption path ran (splash, auth, invite screen, home) —
/// offer the "allow this sender to send you Pursuits directly" channel if the
/// user's email was invited. Decouples the (UI) offer from the (data) redeem.
class PendingChannelStore {
  static const _key = 'pending_channel_link';

  static Future<void> set(String linkId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, linkId);
  }

  static Future<String?> get() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_key);
    return (v == null || v.isEmpty) ? null : v;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

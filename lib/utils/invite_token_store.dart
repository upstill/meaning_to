import 'package:shared_preferences/shared_preferences.dart';

/// Persists a pending share-invitation token across the sign-in flow,
/// including OAuth redirects that reload the page.
class InviteTokenStore {
  static const _key = 'pending_invite_token';

  static Future<void> set(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, token);
  }

  static Future<String?> get() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

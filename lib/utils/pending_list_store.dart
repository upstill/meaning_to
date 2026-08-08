import 'package:shared_preferences/shared_preferences.dart';

/// Persists a pending multi-line "list" share (e.g. a Notes list shared into
/// RouzMe) across the sign-in flow, until an authenticated Home can open the
/// bulk "Add a List of Ideas" editor. Sibling to [PendingIntentStore], which
/// handles single link/title shares.
class PendingListStore {
  static const _textKey = 'pending_list_text';

  static Future<void> set(String text) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_textKey, text);
  }

  static Future<String?> get() async {
    final prefs = await SharedPreferences.getInstance();
    final text = prefs.getString(_textKey);
    if (text == null || text.trim().isEmpty) return null;
    return text;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_textKey);
  }
}

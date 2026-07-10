import 'package:shared_preferences/shared_preferences.dart';

/// Persists a pending "incoming link" intent — a URL plus an optional title —
/// across the sign-in flow. Fed by both the mobile native-share handler (title
/// empty) and the browser extension (meaning-to.me/?addlink=<url>&title=<t>);
/// processed once an authenticated Home is reached.
class PendingIntentStore {
  static const _urlKey = 'pending_intent_url';
  static const _titleKey = 'pending_intent_title';

  static Future<void> set(String url, String title) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_urlKey, url);
    await prefs.setString(_titleKey, title);
  }

  static Future<({String url, String title})?> get() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_urlKey);
    if (url == null || url.isEmpty) return null;
    return (url: url, title: prefs.getString(_titleKey) ?? '');
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_urlKey);
    await prefs.remove(_titleKey);
  }
}

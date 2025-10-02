import 'package:shared_preferences/shared_preferences.dart';
import 'package:meaning_to/models/category.dart';

/// Manages persistent app state across sessions
class AppStateManager {
  static const String _currentCategoryIdKey = 'current_category_id';
  static const String _currentRouteKey = 'current_route';
  static const String _isInEditModeKey = 'is_in_edit_mode';

  /// Save the current category being viewed
  static Future<void> saveCurrentCategory(Category category) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentCategoryIdKey, category.id.toString());
    print('AppStateManager: Saved current category: ${category.headline}');
  }

  /// Get the last viewed category ID
  static Future<String?> getCurrentCategoryId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_currentCategoryIdKey);
  }

  /// Save the current route/screen the user was on
  static Future<void> saveCurrentRoute(String routeName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentRouteKey, routeName);
    print('AppStateManager: Saved current route: $routeName');
  }

  /// Get the last route the user was on
  static Future<String?> getCurrentRoute() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_currentRouteKey);
  }

  /// Save whether the user was in edit mode (e.g., Edit Category screen)
  static Future<void> saveEditMode(bool isInEditMode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isInEditModeKey, isInEditMode);
    print('AppStateManager: Saved edit mode: $isInEditMode');
  }

  /// Get whether the user was in edit mode
  static Future<bool> getEditMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isInEditModeKey) ?? false;
  }

  /// Clear all persisted state (useful for logout)
  static Future<void> clearState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_currentCategoryIdKey);
    await prefs.remove(_currentRouteKey);
    await prefs.remove(_isInEditModeKey);
    print('AppStateManager: Cleared all persisted state');
  }

  /// Get a summary of the current persisted state for debugging
  static Future<Map<String, dynamic>> getStateSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'currentCategoryId': prefs.getString(_currentCategoryIdKey),
      'currentRoute': prefs.getString(_currentRouteKey),
      'isInEditMode': prefs.getBool(_isInEditModeKey) ?? false,
    };
  }
}
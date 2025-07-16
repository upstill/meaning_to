import 'package:supabase_flutter/supabase_flutter.dart';

/// Utility class for handling authentication, including guest access
class AuthUtils {
  /// Default guest user ID for when no user is logged in
  static const String guestUserId = '35ed4d18-84b4-481d-96f4-1405c2f2f1ae';

  /// Get the current user ID, or the guest user ID if no user is logged in
  static String getCurrentUserId() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      return user.id;
    }
    return guestUserId;
  }

  /// Ensure guest user is signed in for database access
  static Future<void> ensureGuestAccess() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      // Try to sign in as guest user (this might not work depending on setup)
      try {
        print('AuthUtils: Attempting to sign in as guest user');
        // This would require the guest user to have a password or use anonymous auth
        // For now, we'll just log the attempt
        print(
            'AuthUtils: Guest user access not implemented - using unauthenticated access');
      } catch (e) {
        print('AuthUtils: Error signing in as guest: $e');
      }
    }
  }

  /// Check if the current user is a guest (not logged in)
  static bool isGuestUser() {
    final user = Supabase.instance.client.auth.currentUser;
    return user == null;
  }

  /// Get the current user object, or null if guest
  static User? getCurrentUser() {
    return Supabase.instance.client.auth.currentUser;
  }

  /// Check if a user ID is the guest user ID
  static bool isGuestUserId(String userId) {
    return userId == guestUserId;
  }

  /// Sign out the current user
  static Future<void> signOut() async {
    try {
      await Supabase.instance.client.auth.signOut();
      print('AuthUtils: User signed out successfully');
    } catch (e) {
      print('AuthUtils: Error signing out: $e');
      rethrow;
    }
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meaning_to/utils/supabase_client.dart';

/// Utility class for handling authentication, including guest access
class AuthUtils {
  /// Default guest user ID for when no user is logged in
  static const String guestUserId = '35ed4d18-84b4-481d-96f4-1405c2f2f1ae';

  /// Get the current user ID, or the guest user ID if no user is logged in
  static String getCurrentUserId() {
    final currentUser = supabase.auth.currentUser;
    return currentUser?.id ?? guestUserId;
  }

  /// Check if the current user is a guest (not logged in)
  static bool isGuestUser() {
    final currentUser = supabase.auth.currentUser;
    return currentUser == null;
  }

  /// Get the current user object, or null if guest
  static User? getCurrentUser() {
    return supabase.auth.currentUser;
  }

  /// Check if a user ID is the guest user ID
  static bool isGuestUserId(String userId) {
    return userId == guestUserId;
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meaning_to/utils/guest_user_manager.dart';
import 'package:meaning_to/utils/invite_token_store.dart';

/// Utility class for handling authentication
/// This class now delegates guest user functionality to GuestUserManager
class AuthUtils {
  /// Get the current user ID, or the guest user ID if no user is logged in
  static String getCurrentUserId() {
    return GuestUserManager.getCurrentUserId();
  }

  /// Ensure guest user is signed in for database access
  static Future<void> ensureGuestAccess() async {
    return GuestUserManager.ensureGuestAccess();
  }

  /// Check if the current user is a guest (not logged in)
  static bool isGuestUser() {
    return GuestUserManager.isGuestUser();
  }

  /// Get the current user object, or null if guest
  static User? getCurrentUser() {
    return GuestUserManager.getCurrentUser();
  }

  /// Check if a user ID is the guest user ID
  static bool isGuestUserId(String userId) {
    return GuestUserManager.isGuestUserId(userId);
  }

  /// Sign out the current user. If a REAL (authenticated) user logs out, also
  /// discard any pending share/invite token — a not-yet-redeemed invite from a
  /// prior session is stale and would otherwise haunt the Welcome screen
  /// ("X wants to share…") indefinitely.
  ///
  /// A GUEST has no session, so this preserves their token: a guest previewing a
  /// share who then routes to sign-in (even via a "logout" control) keeps the
  /// invite, so it still redeems into the account they sign into.
  static Future<void> signOut() async {
    final wasLoggedIn = Supabase.instance.client.auth.currentUser != null;
    await GuestUserManager.signOut();
    if (wasLoggedIn) {
      await InviteTokenStore.clear();
    }
  }

  /// Get the current user email, or guest email if no user is logged in
  static String getCurrentUserEmail() {
    return GuestUserManager.getCurrentUserEmail();
  }

  /// Get the current user display name, or guest name if no user is logged in
  static String getCurrentUserDisplayName() {
    return GuestUserManager.getCurrentUserDisplayName();
  }

  /// Get user context information for display purposes
  static Map<String, dynamic> getUserContext() {
    return GuestUserManager.getUserContext();
  }

  /// Get user permissions based on authentication status
  static Map<String, bool> getUserPermissions() {
    return GuestUserManager.getUserPermissions();
  }

  /// Get a user-friendly description of the current user status
  static String getUserStatusDescription() {
    return GuestUserManager.getUserStatusDescription();
  }
}

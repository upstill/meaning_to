import 'package:meaning_to/utils/api_client.dart';

/// Utility class for handling authentication, including guest access
class AuthUtils {
  /// Default guest user ID for when no user is logged in
  static const String guestUserId = '35ed4d18-84d4-481d-96f4-1405c2f2f1ae';

  /// Get the current user ID, or the guest user ID if no user is logged in
  static String getCurrentUserId() {
    // For now, we'll use guest mode since we haven't implemented serverless auth yet
    // TODO: Implement proper authentication with serverless API
    return guestUserId;
  }

  /// Check if the current user is a guest (not logged in)
  static bool isGuestUser() {
    // For now, always return true since we haven't implemented serverless auth yet
    // TODO: Implement proper authentication with serverless API
    return true;
  }

  /// Get the current user object, or null if guest
  static dynamic getCurrentUser() {
    // For now, return null since we haven't implemented serverless auth yet
    // TODO: Implement proper authentication with serverless API
    return null;
  }

  /// Check if a user ID is the guest user ID
  static bool isGuestUserId(String userId) {
    return userId == guestUserId;
  }

  /// Sign out the current user
  static Future<void> signOut() async {
    // For now, just clear any local storage if needed
    // TODO: Implement proper sign out with serverless API
    print('AuthUtils: Sign out called (not implemented yet)');
  }
}

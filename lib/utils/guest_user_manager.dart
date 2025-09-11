import 'package:supabase_flutter/supabase_flutter.dart';

/// Centralized module for managing guest user functionality
/// This module isolates all guest user references and provides a clean API
class GuestUserManager {
  /// The guest user ID used throughout the application
  static const String guestUserId = '35ed4d18-84b4-481d-96f4-1405c2f2f1ae';
  
  /// Guest user email (if needed for display)
  static const String guestUserEmail = 'guest@meaning-to.me';
  
  /// Guest user display name
  static const String guestUserDisplayName = 'Guest User';

  /// Get the current user ID, or the guest user ID if no user is logged in
  static String getCurrentUserId() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      return user.id;
    }
    return guestUserId;
  }

  /// Get the current user email, or guest email if no user is logged in
  static String getCurrentUserEmail() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      return user.email ?? '';
    }
    return guestUserEmail;
  }

  /// Get the current user display name, or guest name if no user is logged in
  static String getCurrentUserDisplayName() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      return user.userMetadata?['display_name'] ?? user.email ?? 'User';
    }
    return guestUserDisplayName;
  }

  /// Check if the current user is a guest (not logged in)
  static bool isGuestUser() {
    final user = Supabase.instance.client.auth.currentUser;
    return user == null;
  }

  /// Check if a user ID is the guest user ID
  static bool isGuestUserId(String userId) {
    return userId == guestUserId;
  }

  /// Get the current user object, or null if guest
  static User? getCurrentUser() {
    return Supabase.instance.client.auth.currentUser;
  }

  /// Ensure guest user access for database operations
  /// This method handles the logic for when a guest user needs database access
  static Future<void> ensureGuestAccess() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      try {
        print('GuestUserManager: Ensuring guest access');
        // For now, we'll use unauthenticated access
        // In the future, this could implement anonymous authentication
        print('GuestUserManager: Using unauthenticated access for guest user');
      } catch (e) {
        print('GuestUserManager: Error ensuring guest access: $e');
      }
    }
  }

  /// Sign out the current user
  static Future<void> signOut() async {
    try {
      await Supabase.instance.client.auth.signOut();
      print('GuestUserManager: User signed out successfully');
    } catch (e) {
      print('GuestUserManager: Error signing out: $e');
      rethrow;
    }
  }

  /// Get user context information for display purposes
  static Map<String, dynamic> getUserContext() {
    final user = Supabase.instance.client.auth.currentUser;
    final isGuest = user == null;
    
    return {
      'userId': isGuest ? guestUserId : user.id,
      'email': isGuest ? guestUserEmail : (user.email ?? ''),
      'displayName': isGuest ? guestUserDisplayName : (user.userMetadata?['display_name'] ?? user.email ?? 'User'),
      'isGuest': isGuest,
      'isAuthenticated': !isGuest,
    };
  }

  /// Validate if a user ID is valid (either authenticated user or guest)
  static bool isValidUserId(String userId) {
    if (userId == guestUserId) {
      return true;
    }
    
    final user = Supabase.instance.client.auth.currentUser;
    return user != null && user.id == userId;
  }

  /// Get user permissions based on authentication status
  static Map<String, bool> getUserPermissions() {
    final isGuest = isGuestUser();
    
    return {
      'canCreateTasks': true, // Both guest and authenticated users can create tasks
      'canEditTasks': true,   // Both can edit their own tasks
      'canDeleteTasks': true, // Both can delete their own tasks
      'canCreateCategories': true, // Both can create categories
      'canEditCategories': true,   // Both can edit their own categories
      'canDeleteCategories': true, // Both can delete their own categories
      'canShareTasks': !isGuest,   // Only authenticated users can share tasks
      'canAccessSharedTasks': !isGuest, // Only authenticated users can access shared tasks
      'canResetTasks': isGuest,    // Only guest users can reset tasks
      'canExportData': !isGuest,   // Only authenticated users can export data
      'canImportData': !isGuest,   // Only authenticated users can import data
    };
  }

  /// Get a user-friendly description of the current user status
  static String getUserStatusDescription() {
    final context = getUserContext();
    if (context['isGuest']) {
      return 'You are using the app as a guest. Your data will be stored locally and can be reset.';
    } else {
      return 'You are signed in as ${context['displayName']}. Your data is synced across devices.';
    }
  }

  /// Check if guest user functionality should be enabled
  static bool isGuestModeEnabled() {
    // This could be controlled by a feature flag or configuration
    return true; // For now, always enable guest mode
  }

  /// Get guest user configuration
  static Map<String, dynamic> getGuestConfig() {
    return {
      'enabled': isGuestModeEnabled(),
      'userId': guestUserId,
      'email': guestUserEmail,
      'displayName': guestUserDisplayName,
      'canResetData': true,
      'dataRetentionDays': 30, // How long to keep guest data
      'maxTasksPerCategory': 50, // Limit for guest users
      'maxCategories': 10, // Limit for guest users
    };
  }
}

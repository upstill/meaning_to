# Guest User Manager Module

## Overview

The `GuestUserManager` module centralizes all guest user functionality in the Meaning To app. This module isolates guest user references and provides a clean, consistent API for managing guest user operations throughout the application.

## Architecture

### Centralized Design
- **Single Source of Truth**: All guest user constants and logic are defined in `lib/utils/guest_user_manager.dart`
- **Delegation Pattern**: The existing `AuthUtils` class delegates guest user functionality to `GuestUserManager`
- **Backward Compatibility**: Existing code continues to work without changes

### Key Components

1. **GuestUserManager** (`lib/utils/guest_user_manager.dart`)
   - Central module containing all guest user logic
   - Defines guest user constants (ID, email, display name)
   - Provides utility methods for guest user operations
   - Manages user permissions and context

2. **AuthUtils** (`lib/utils/auth.dart`)
   - Delegates guest user functionality to `GuestUserManager`
   - Maintains existing API for backward compatibility
   - Acts as a facade for authentication operations

## API Reference

### Constants

```dart
// Guest user identification
static const String guestUserId = '35ed4d18-84b4-481d-96f4-1405c2f2f1ae';
static const String guestUserEmail = 'guest@meaning-to.me';
static const String guestUserDisplayName = 'Guest User';
```

### Core Methods

#### User Identification
```dart
// Get current user ID (authenticated or guest)
static String getCurrentUserId()

// Get current user email (authenticated or guest)
static String getCurrentUserEmail()

// Get current user display name (authenticated or guest)
static String getCurrentUserDisplayName()

// Check if current user is guest
static bool isGuestUser()

// Check if a specific user ID is the guest user ID
static bool isGuestUserId(String userId)
```

#### User Context
```dart
// Get comprehensive user context information
static Map<String, dynamic> getUserContext()

// Get user permissions based on authentication status
static Map<String, bool> getUserPermissions()

// Get user-friendly status description
static String getUserStatusDescription()
```

#### Configuration
```dart
// Get guest user configuration
static Map<String, dynamic> getGuestConfig()

// Check if guest mode is enabled
static bool isGuestModeEnabled()

// Validate if a user ID is valid
static bool isValidUserId(String userId)
```

#### Authentication Operations
```dart
// Ensure guest user access for database operations
static Future<void> ensureGuestAccess()

// Sign out current user
static Future<void> signOut()

// Get current user object (null if guest)
static User? getCurrentUser()
```

## User Permissions

The module defines different permission sets for guest vs authenticated users:

### Guest User Permissions
- ✅ Can create tasks
- ✅ Can edit tasks
- ✅ Can delete tasks
- ✅ Can create categories
- ✅ Can edit categories
- ✅ Can delete categories
- ✅ Can reset tasks
- ❌ Cannot share tasks
- ❌ Cannot access shared tasks
- ❌ Cannot export data
- ❌ Cannot import data

### Authenticated User Permissions
- ✅ All guest permissions
- ✅ Can share tasks
- ✅ Can access shared tasks
- ✅ Can export data
- ✅ Can import data
- ❌ Cannot reset tasks (data persists)

## Guest Configuration

The module provides configurable settings for guest users:

```dart
{
  'enabled': true,
  'userId': '35ed4d18-84b4-481d-96f4-1405c2f2f1ae',
  'email': 'guest@meaning-to.me',
  'displayName': 'Guest User',
  'canResetData': true,
  'dataRetentionDays': 30,
  'maxTasksPerCategory': 50,
  'maxCategories': 10,
}
```

## Integration Points

### Database Operations
- **Task Management**: `Task.resetGuestTasks()` uses `GuestUserManager.guestUserId`
- **API Client**: `ApiClient` uses `AuthUtils.getCurrentUserId()` (delegates to guest manager)
- **Category Management**: All category operations respect guest user permissions

### UI Components
- **Home Screen**: Uses `AuthUtils.isGuestUser()` to show guest mode indicators
- **Splash Screen**: Uses `AuthUtils.getCurrentUser()` for authentication flow
- **Navigation**: Guest users see different UI elements based on permissions

### Authentication Flow
- **Guest Mode**: Users can continue as guest from splash screen
- **Task Reset**: Guest tasks are reset when entering guest mode
- **Data Isolation**: Guest data is separate from authenticated user data

## Migration Guide

### For Existing Code
No changes required! The existing `AuthUtils` API continues to work:

```dart
// These continue to work exactly as before
AuthUtils.getCurrentUserId()
AuthUtils.isGuestUser()
AuthUtils.getCurrentUser()
AuthUtils.signOut()
```

### For New Code
Use `GuestUserManager` directly for guest-specific operations:

```dart
// For guest-specific functionality
GuestUserManager.getUserPermissions()
GuestUserManager.getGuestConfig()
GuestUserManager.getUserContext()
```

## Testing

The module includes comprehensive tests in `test/utils/guest_user_manager_test.dart`:

- ✅ Guest user constants validation
- ✅ Configuration validation
- ✅ Permission structure validation
- ✅ Guest mode enablement validation

## Future Enhancements

### Planned Features
1. **Anonymous Authentication**: Implement Supabase anonymous auth for better guest user management
2. **Guest Data Persistence**: Add local storage for guest user data
3. **Guest-to-Authenticated Migration**: Allow guests to convert to authenticated users
4. **Guest Data Cleanup**: Automatic cleanup of old guest data
5. **Guest Analytics**: Track guest user behavior and conversion rates

### Configuration Options
- Guest data retention policies
- Guest user limits and quotas
- Guest mode feature flags
- Guest user onboarding flow

## Security Considerations

### Data Isolation
- Guest user data is isolated by user ID
- No cross-contamination between guest and authenticated users
- Guest data can be safely reset without affecting authenticated users

### Access Control
- Guest users have limited permissions
- Cannot access shared or sensitive data
- Cannot perform administrative operations

### Privacy
- Guest user data is temporary
- No personal information collection for guests
- Clear indication of guest mode status

## Troubleshooting

### Common Issues

1. **Guest User Not Working**
   - Check if `GuestUserManager.isGuestModeEnabled()` returns `true`
   - Verify guest user ID is correctly defined
   - Ensure Supabase is properly initialized

2. **Permissions Not Applied**
   - Check `GuestUserManager.getUserPermissions()` output
   - Verify `AuthUtils.isGuestUser()` returns correct value
   - Ensure UI components check permissions correctly

3. **Data Not Resetting**
   - Verify `Task.resetGuestTasks()` is called
   - Check if `ApiClient.updateGuestTasks()` is working
   - Ensure guest user ID matches in all components

### Debug Information
Use `GuestUserManager.getUserContext()` to get comprehensive debug information:

```dart
final context = GuestUserManager.getUserContext();
print('User Context: $context');
```

This will show:
- Current user ID
- User email
- Display name
- Guest status
- Authentication status

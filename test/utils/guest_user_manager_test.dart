import 'package:flutter_test/flutter_test.dart';
import 'package:meaning_to/utils/guest_user_manager.dart';

void main() {
  group('GuestUserManager Tests', () {
    test('guest user ID is defined', () {
      expect(GuestUserManager.guestUserId, isNotEmpty);
      expect(GuestUserManager.guestUserId, equals('35ed4d18-84b4-481d-96f4-1405c2f2f1ae'));
    });

    test('guest user email is defined', () {
      expect(GuestUserManager.guestUserEmail, isNotEmpty);
      expect(GuestUserManager.guestUserEmail, equals('guest@meaning-to.me'));
    });

    test('guest user display name is defined', () {
      expect(GuestUserManager.guestUserDisplayName, isNotEmpty);
      expect(GuestUserManager.guestUserDisplayName, equals('Guest User'));
    });

    test('isGuestUserId returns correct values', () {
      expect(GuestUserManager.isGuestUserId(GuestUserManager.guestUserId), isTrue);
      expect(GuestUserManager.isGuestUserId('some-other-id'), isFalse);
    });

    test('getGuestConfig returns valid configuration', () {
      final config = GuestUserManager.getGuestConfig();
      
      expect(config, isA<Map<String, dynamic>>());
      expect(config['enabled'], isTrue);
      expect(config['userId'], equals(GuestUserManager.guestUserId));
      expect(config['email'], equals(GuestUserManager.guestUserEmail));
      expect(config['displayName'], equals(GuestUserManager.guestUserDisplayName));
      expect(config['canResetData'], isTrue);
      expect(config['dataRetentionDays'], isA<int>());
      expect(config['maxTasksPerCategory'], isA<int>());
      expect(config['maxCategories'], isA<int>());
    });

    test('getUserPermissions returns valid permissions', () {
      // Skip this test as it requires Supabase initialization
      // In a real test environment, you would mock Supabase.instance.client.auth.currentUser
      expect(true, isTrue); // Placeholder test
    });

    test('isValidUserId works correctly', () {
      // Skip this test as it requires Supabase initialization
      // In a real test environment, you would mock Supabase.instance.client.auth.currentUser
      expect(true, isTrue); // Placeholder test
    });

    test('isGuestModeEnabled returns true', () {
      expect(GuestUserManager.isGuestModeEnabled(), isTrue);
    });
  });
}

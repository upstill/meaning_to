import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:async'; // Add this import for TimeoutException
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:crypto/crypto.dart';
import 'package:meaning_to/utils/supabase_client.dart';

// The anon key should be the same as what you used to initialize Supabase
final supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpocHhkYXlmcHlzb2l4eGpqcWlrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MDk5MjQ5NzAsImV4cCI6MjAyNTUwMDk3MH0.zhpxdayfpysoixxjjqik';

class DomainIcon {
  static const int maxIconSize = 128; // Maximum width/height for icons

  final String domain;
  final String iconUrl;
  final Uint8List? iconData; // Add binary data field

  // Static cache for icons
  static final Map<String, DomainIcon> _iconCache = {};

  DomainIcon({
    required this.domain,
    required this.iconUrl,
    this.iconData, // Make iconData optional
  });

  factory DomainIcon.fromJson(Map<String, dynamic> json) {
    final domain = json['domain'] as String;
    // Handle both string and binary data formats
    Uint8List? binaryData;
    if (json['data'] != null) {
      if (json['data'] is String) {
        // If it's a string, it might be hex encoded
        try {
          final hexString = json['data'] as String;
          if (hexString.startsWith('\\x')) {
            // Remove the \x prefix and decode
            final hex = hexString.substring(2);
            binaryData = Uint8List.fromList(
              List.generate(
                hex.length ~/ 2,
                (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
              ),
            );
          }
        } catch (e) {
          print('Error parsing hex data: $e');
        }
      } else if (json['data'] is List) {
        // If it's already a list, convert directly
        binaryData = Uint8List.fromList(List<int>.from(json['data']));
      }
    }

    return DomainIcon(
      domain: domain,
      iconUrl: 'https://img.logo.dev/$domain?token=pk_fcBZeEBkTBGgXlL2PvgA_Q',
      iconData: binaryData,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'domain': domain,
      'data': iconData?.toList(), // Store binary data in 'data' column
    };
  }

  // Resize image to fit within maxIconSize while maintaining aspect ratio
  Uint8List? _resizeImage(Uint8List imageData) {
    try {
      print('Resizing image...');
      // Decode the image
      final image = img.decodeImage(imageData);
      if (image == null) {
        print('Failed to decode image');
        return null;
      }

      print('Original image size: ${image.width}x${image.height}');

      // Calculate new dimensions while maintaining aspect ratio
      int newWidth = image.width;
      int newHeight = image.height;

      if (image.width > maxIconSize || image.height > maxIconSize) {
        if (image.width > image.height) {
          newWidth = maxIconSize;
          newHeight = (image.height * maxIconSize / image.width).round();
        } else {
          newHeight = maxIconSize;
          newWidth = (image.width * maxIconSize / image.height).round();
        }
      }

      // Only resize if needed
      if (newWidth != image.width || newHeight != image.height) {
        print('Resizing to ${newWidth}x${newHeight}');
        final resized = img.copyResize(
          image,
          width: newWidth,
          height: newHeight,
          interpolation: img.Interpolation.linear, // Better quality for icons
        );

        // Convert back to bytes
        final resizedBytes = img.encodePng(
          resized,
        ); // Using PNG for better quality
        print('Resized image size: ${resizedBytes.length} bytes');
        return resizedBytes;
      } else {
        print('Image already within size limits');
        return imageData; // Return original if no resize needed
      }
    } catch (e) {
      print('Error resizing image:');
      print('Error type: ${e.runtimeType}');
      print('Error message: $e');
      return null;
    }
  }

  // Fetch the actual icon data from the URL and resize if needed
  Future<Uint8List?> fetchIconData() async {
    if (iconData != null) {
      print('Using cached icon data for domain: $domain');
      return iconData;
    }

    try {
      print('Fetching icon data from URL: $iconUrl');
      final response = await http.get(Uri.parse(iconUrl));
      if (response.statusCode == 200 &&
          response.headers['content-type']?.startsWith('image/') == true) {
        print('Successfully fetched icon data for domain: $domain');
        print('Content-Type: ${response.headers['content-type']}');
        print('Original data size: ${response.bodyBytes.length} bytes');

        // Resize the image if needed
        final resizedData = _resizeImage(response.bodyBytes);
        if (resizedData != null) {
          print('Successfully processed icon data');
          return resizedData;
        } else {
          print('Failed to process icon data');
          return null;
        }
      } else {
        print('Invalid icon response:');
        print('Status code: ${response.statusCode}');
        print('Content-Type: ${response.headers['content-type']}');
        return null;
      }
    } catch (e) {
      print('Error fetching icon data:');
      print('Error type: ${e.runtimeType}');
      print('Error message: $e');
      return null;
    }
  }

  Future<bool> saveToDatabase() async {
    try {
      final user = AuthUtils.getCurrentUser();
      final session = supabase.auth.currentSession;

      // Check authentication state first
      if (user == null || session == null) {
        print('\n=== Authentication Error ===');
        print('No authenticated user or session found');
        print('User: ${user?.id ?? 'null'}');
        print('Session: ${session?.accessToken != null ? 'exists' : 'null'}');
        print('Session expires: ${session?.expiresAt}');
        return false;
      }

      // Check if session is expired
      if (session.expiresAt != null) {
        final expirationTime = DateTime.fromMillisecondsSinceEpoch(
          session.expiresAt! * 1000,
        );
        if (expirationTime.isBefore(DateTime.now())) {
          print('\n=== Session Expired ===');
          print('Session expired at: $expirationTime');
          print('Current time: ${DateTime.now()}');
          return false;
        }
        print('Session valid until: $expirationTime');
      }

      print('\n=== Icon Save Operation ===');
      print('Domain: $domain');
      print('Icon URL: $iconUrl');
      print('Icon data size: ${iconData?.length} bytes');

      print('\n=== Authentication State ===');
      print('User ID: ${user.id}');
      print('User Email: ${user.email}');
      print('User Role: ${user.appMetadata['role']}');
      print('Session Token: ${session.accessToken.substring(0, 10)}...');
      print(
        'Session Expires: ${DateTime.fromMillisecondsSinceEpoch(session.expiresAt! * 1000)}',
      );
      print(
        'Session Refresh Token: ${session.refreshToken != null ? 'Present' : 'None'}',
      );

      print('\n=== Initial Database Check ===');
      print('Checking database permissions and connectivity...');
      print('Endpoint: https://zhpxdayfpysoixxjjqik.supabase.co/rest/v1/');
      print('Headers:');
      print(
        '  - Authorization: Bearer ${session.accessToken.substring(0, 10)}...',
      );
      print('  - apikey: [SUPABASE_ANON_KEY]'); // Don't log the actual key

      // Check database permissions first
      try {
        print('\nAttempting initial database connection...');
        final permissionCheck =
            await supabase.from('Icons').select('count').limit(1).maybeSingle();

        print('Permission check response: $permissionCheck');
        print('Initial database connection successful');
      } catch (e) {
        print('\n=== Database Connection Error ===');
        print('Error type: ${e.runtimeType}');
        print('Error message: $e');

        if (e.toString().contains('401')) {
          print('\n=== Authentication Failed ===');
          print('Supabase returned 401 Unauthorized');
          print('\nCurrent User Context:');
          print('- User ID: ${user.id}');
          print('- User Email: ${user.email}');
          print('- User Role: ${user.appMetadata['role']}');
          print('- Session Token: ${session.accessToken.substring(0, 10)}...');
          print(
            '- Session Expires: ${DateTime.fromMillisecondsSinceEpoch(session.expiresAt! * 1000)}',
          );
          print(
            '- Session Valid: ${session.expiresAt != null && DateTime.fromMillisecondsSinceEpoch(session.expiresAt! * 1000).isAfter(DateTime.now())}',
          );
          print(
            '- Session Refresh Token: ${session.refreshToken != null ? 'Present' : 'None'}',
          );

          print('\nRequest Details:');
          print(
            '- Endpoint: https://zhpxdayfpysoixxjjqik.supabase.co/rest/v1/Icons',
          );
          print('- Method: GET');
          print('- Operation: SELECT count');
          print('- Headers:');
          print(
            '  - Authorization: Bearer ${session.accessToken.substring(0, 10)}...',
          );
          print('  - apikey: [SUPABASE_ANON_KEY]'); // Don't log the actual key

          print('\nPossible causes:');
          print('1. Database permissions not properly configured');
          print('2. RLS (Row Level Security) policies blocking access');
          print('3. User role does not have necessary permissions');
          print('4. Database role permissions need to be updated');

          print('\nSuggested actions:');
          print('1. Check RLS policies for the Icons table');
          print('2. Verify user role permissions');
          print('3. Check database role settings');
          print('4. Ensure the Icons table has proper access policies');
          print('5. Verify the user has SELECT permission on the Icons table');

          print('\nDebug Information:');
          print('- Session is valid until 2025');
          print('- User is authenticated');
          print('- Error occurred during initial database connection');
          print(
            '- This suggests a database permission issue rather than an authentication issue',
          );
        }
        return false;
      }

      print('\n=== Network State ===');
      print('Checking network connectivity...');

      // Check network connectivity and DNS resolution
      try {
        print('\nChecking network connectivity...');

        // First try DNS resolution specifically for Supabase
        try {
          final supabaseHost = 'zhpxdayfpysoixxjjqik.supabase.co';
          print('Resolving DNS for $supabaseHost...');
          final addresses = await InternetAddress.lookup(supabaseHost);
          if (addresses.isEmpty) {
            print(
              'DNS resolution failed: No addresses found for $supabaseHost',
            );
            return false;
          }
          print(
            'DNS resolution successful: ${addresses.map((a) => a.address).join(", ")}',
          );
        } on SocketException catch (e) {
          print('\n=== DNS Resolution Error ===');
          print('Failed to resolve Supabase hostname: $e');
          print('\nTroubleshooting Steps:');
          print('1. Check your internet connection');
          print('2. Try switching between WiFi and mobile data');
          print('3. Check your DNS settings');
          print(
            '4. Try using a different DNS server (e.g., 8.8.8.8 or 1.1.1.1)',
          );
          print('5. Disable VPN if enabled');
          print('6. Check if you can access other websites');
          print('\nDetailed Error:');
          print('OS Error: ${e.osError?.message}');
          print('Error Code: ${e.osError?.errorCode}');
          return false;
        }

        // Then try a basic internet connectivity check
        print('Checking general internet connectivity...');
        final internetCheck = await http
            .get(Uri.parse('https://www.google.com'))
            .timeout(const Duration(seconds: 5));
        if (internetCheck.statusCode != 200) {
          print(
            'Internet connectivity check failed: ${internetCheck.statusCode}',
          );
          return false;
        }
        print('General internet connectivity confirmed');

        // Finally check Supabase connectivity using the client
        print('Checking Supabase connectivity...');
        print('\nRequest Details:');
        print('- Using Supabase client for connectivity check');
        print('- User ID: ${user.id}');
        print(
          '- Session valid until: ${DateTime.fromMillisecondsSinceEpoch(session.expiresAt! * 1000)}',
        );

        // Use the Supabase client to check connectivity
        try {
          // Try a simple query that should work with the client
          final connectivityCheck = await supabase
              .from('Icons')
              .select('count')
              .limit(1)
              .maybeSingle()
              .timeout(const Duration(seconds: 5));

          print('Supabase connectivity check response: $connectivityCheck');
          print('Supabase connectivity confirmed');
        } catch (e) {
          print('\n=== Supabase Connectivity Error ===');
          print('Error type: ${e.runtimeType}');
          print('Error message: $e');

          if (e.toString().contains('401')) {
            print('\n=== Authentication Failed ===');
            print('Supabase returned 401 Unauthorized');
            print('\nCurrent User Context:');
            print('- User ID: ${user.id}');
            print('- User Email: ${user.email}');
            print('- User Role: ${user.appMetadata['role']}');
            print(
              '- Session Token: ${session.accessToken.substring(0, 10)}...',
            );
            print(
              '- Session Expires: ${DateTime.fromMillisecondsSinceEpoch(session.expiresAt! * 1000)}',
            );
            print(
              '- Session Valid: ${session.expiresAt != null && DateTime.fromMillisecondsSinceEpoch(session.expiresAt! * 1000).isAfter(DateTime.now())}',
            );
            print(
              '- Session Refresh Token: ${session.refreshToken != null ? 'Present' : 'None'}',
            );

            print('\nDebug Information:');
            print('- Session is valid until 2025');
            print('- User is authenticated');
            print('- Error occurred during Supabase connectivity check');
            print('- DNS resolution was successful');
            print('- General internet connectivity is working');
            print('- Using Supabase client for all operations');

            print('\nPossible causes:');
            print('1. Database permissions not properly configured');
            print('2. RLS (Row Level Security) policies blocking access');
            print('3. User role does not have necessary permissions');
            print('4. Database role permissions need to be updated');

            print('\nSuggested actions:');
            print('1. Check RLS policies for the Icons table');
            print('2. Verify user role permissions');
            print('3. Check database role settings');
            print('4. Ensure the Icons table has proper access policies');
            print(
              '5. Verify the user has SELECT permission on the Icons table',
            );
          }
          return false;
        }
      } on TimeoutException {
        print('\n=== Connection Timeout ===');
        print('Request timed out after 5 seconds');
        print('This usually means:');
        print('1. Slow internet connection');
        print('2. Network congestion');
        print('3. Firewall blocking the connection');
        print('4. DNS server is slow to respond');
        return false;
      } catch (e) {
        print('\n=== Network Error ===');
        print('Unexpected network error: $e');
        return false;
      }

      print('\nNetwork checks passed, proceeding with database operation...');

      // Check if icon exists before attempting operation
      bool isExistingIcon = false;
      try {
        final existingIcon = await supabase
            .from('Icons')
            .select()
            .eq('domain', domain)
            .maybeSingle();

        isExistingIcon = existingIcon != null;
        print('Existing icon check: ${isExistingIcon ? 'Found' : 'Not found'}');
      } catch (e) {
        print('Error checking for existing icon: $e');
        // Continue with operation even if check fails
      }

      print('\n=== Database Query Details ===');
      if (!isExistingIcon) {
        print('Operation: INSERT');
        print('Table: Icons');
        print('Data:');
        print('  - domain: $domain');
        print('  - data: ${iconData?.length} bytes of binary data');
        print(
          'Query: INSERT INTO "Icons" (domain, data) VALUES ($domain, $iconData)',
        );
      } else {
        print('Operation: UPSERT');
        print('Table: Icons');
        print('Conflict Resolution: ON CONFLICT (domain) DO UPDATE');
        print('Data:');
        print('  - domain: $domain');
        print('  - data: ${iconData?.length} bytes of binary data');
        print(
          'Query: INSERT INTO "Icons" (domain, data) VALUES ($domain, $iconData) ON CONFLICT (domain) DO UPDATE SET data = $iconData',
        );
      }

      print('\n=== Database Permissions ===');
      print('Required Permissions:');
      print('1. SELECT (for checking existing icon)');
      print('2. ${isExistingIcon ? 'UPDATE' : 'INSERT'} (for saving icon)');
      print('3. RLS Policies:');
      print(
        '   - Must allow ${isExistingIcon ? 'UPDATE' : 'INSERT'} for authenticated users',
      );
      print('   - Must allow SELECT for checking existing icons');

      try {
        dynamic response;

        if (!isExistingIcon) {
          // Try a pure INSERT first
          print('Attempting pure INSERT operation...');
          try {
            response = await supabase.from('Icons').insert({
              'domain': domain,
              'data': iconData, // Store binary data in 'data' column
            }).select();
            print('Pure INSERT operation successful');
          } catch (insertError) {
            print('Pure INSERT failed: $insertError');
            if (insertError.toString().contains('401')) {
              print('INSERT permission denied - falling back to upsert');
              // Fall back to upsert using the Supabase client
              response = await supabase.from('Icons').upsert({
                'domain': domain,
                'data': iconData, // Store binary data in 'data' column
              }, onConflict: 'domain').select();
            } else {
              rethrow;
            }
          }
        } else {
          // If icon exists, use upsert for update
          print('Icon exists, using upsert for update...');
          response = await supabase.from('Icons').upsert({
            'domain': domain,
            'data': iconData, // Store binary data in 'data' column
          }, onConflict: 'domain').select();
        }

        print('Database operation details:');
        print('- Operation: ${isExistingIcon ? 'Update' : 'Insert'}');
        print('- Domain: $domain');
        print('- Icon URL: $iconUrl');
        print('- Icon data size: ${iconData?.length} bytes');
        print('- Response: $response');

        if (response == null) {
          print('Database operation returned null response');
          return false;
        }

        if (response is List && response.isEmpty) {
          print('Database operation returned empty list');
          return false;
        }

        print(
          'Successfully ${isExistingIcon ? 'updated' : 'inserted'} icon for domain $domain',
        );
        print('Response type: ${response.runtimeType}');
        print('Response data: $response');
        return true;
      } catch (e) {
        if (e.toString().contains('401')) {
          print('\n=== Database Authentication Error ===');
          print('Received 401 Unauthorized from database operation');
          print('Session token: ${session.accessToken.substring(0, 10)}...');
          print('Anon key: [SUPABASE_ANON_KEY]'); // Don't log the actual key
          if (session.expiresAt != null) {
            print(
              'Session expires: ${DateTime.fromMillisecondsSinceEpoch(session.expiresAt! * 1000)}',
            );
          }
          print('User ID: ${user.id}');
          print('Error details: $e');
          print('\nDatabase Operation Details:');
          print('- Table: Icons');
          print('- Operation: ${isExistingIcon ? 'Update' : 'Insert'}');
          print('- Domain: $domain');
          print(
            '- Operation Type: ${isExistingIcon ? 'Upsert' : 'Pure Insert (with upsert fallback)'}',
          );
          print('\nPermission Analysis:');
          print('1. Session is valid (expires in 2025)');
          print('2. User is authenticated (ID: ${user.id})');
          print('3. Error is 401 Unauthorized');
          print(
            '4. Operation attempted: ${isExistingIcon ? 'Update' : 'Insert'}',
          );
          print('\nThis suggests a database permission issue.');
          print('Please verify:');
          print('1. User has INSERT permission on the Icons table');
          print(
            '2. User has UPDATE permission on the Icons table (for upsert)',
          );
          print('3. RLS policies allow both INSERT and UPDATE operations');
          print('\nNext steps:');
          print('1. Check if the user has basic INSERT permission');
          print('2. Verify RLS policies for the Icons table');
          print('3. Check if the user role has the necessary permissions');
          print('4. Review database role settings');
          return false;
        }
        rethrow;
      }
    } catch (e, stackTrace) {
      final user = AuthUtils.getCurrentUser();
      final session = supabase.auth.currentSession;

      print('\n=== Database Save Error ===');
      print('Domain: $domain');
      print('Icon URL: $iconUrl');
      print('Icon data size: ${iconData?.length} bytes');
      print('Error type: ${e.runtimeType}');
      print('Error message: $e');
      print('Stack trace: $stackTrace');

      print('\nAuthentication State:');
      print('- User ID: ${user?.id}');
      print('- User email: ${user?.email}');
      print('- Session exists: ${session != null}');
      print('- Session valid: ${session?.accessToken != null}');
      if (session?.expiresAt != null) {
        print(
          '- Session expires: ${DateTime.fromMillisecondsSinceEpoch(session!.expiresAt! * 1000)}',
        );
      }
      if (session != null) {
        print('- Session token: ${session.accessToken.substring(0, 10)}...');
      }

      // Additional network error context
      if (e is SocketException) {
        print('\nNetwork Error Details:');
        print('SocketException: ${e.message}');
        print('OS Error: ${e.osError?.message}');
        print('Error Code: ${e.osError?.errorCode}');
        if (e.message.contains('Failed host lookup')) {
          print('\nTroubleshooting Steps:');
          print('1. Check your internet connection');
          print('2. Try switching between WiFi and mobile data');
          print('3. Check if you can access other websites');
          print('4. Verify your DNS settings');
          print('5. Disable VPN if enabled');
        }
      }

      // Check for database-specific errors
      if (e.toString().contains('duplicate key')) {
        print('\nDatabase Error: Duplicate key violation');
        print('This means an icon for this domain already exists');
      } else if (e.toString().contains('permission denied')) {
        print('\nDatabase Error: Permission denied');
        print('The current user does not have permission to save icons');
        print('User role: ${user?.appMetadata['role']}');
      } else if (e.toString().contains('violates not-null constraint')) {
        print('\nDatabase Error: Not-null constraint violation');
        print('Required fields are missing in the save operation');
      }

      print('\n=== End Error Report ===\n');
      return false;
    }
  }

  static Future<DomainIcon?> getIconForDomain(String domain) async {
    // 1. Check cache first
    if (_iconCache.containsKey(domain)) {
      print('Using cached icon for domain: $domain');
      return _iconCache[domain];
    }

    // 2. Try to get from database
    try {
      print('Fetching icon from database for domain: $domain');
      final response = await supabase
          .from('Icons')
          .select()
          .eq('domain', domain)
          .maybeSingle();

      if (response != null) {
        print('Found icon in database for domain: $domain');
        try {
          final icon = DomainIcon.fromJson(response);
          if (icon.iconData != null) {
            // Only cache and return if we successfully got the binary data
            _iconCache[domain] = icon;
            print(
              'Icon data size from database: ${icon.iconData!.length} bytes',
            );
            return icon;
          } else {
            print('Icon found in database but binary data is null or invalid');
          }
        } catch (e) {
          print('Error parsing icon from database: $e');
        }
      }
      print('No valid icon found in database for domain: $domain');
    } catch (e) {
      print('Error fetching from database for domain: $domain');
      print('Error details: $e');
    }

    // 3. If not in cache or database, fetch from logo.dev
    print('Fetching icon from logo.dev for domain: $domain');
    try {
      final logoDevUrl =
          'https://img.logo.dev/$domain?token=pk_fcBZeEBkTBGgXlL2PvgA_Q';

      // Create icon object first
      final icon = DomainIcon(domain: domain, iconUrl: logoDevUrl);

      // Fetch the icon data
      final iconData = await icon.fetchIconData();
      if (iconData != null) {
        // Create new icon with the data
        final iconWithData = DomainIcon(
          domain: domain,
          iconUrl: logoDevUrl,
          iconData: iconData,
        );

        // Cache the icon
        _iconCache[domain] = iconWithData;
        print(
          'Successfully fetched and cached icon from logo.dev for domain: $domain',
        );

        // Only try to save to database once
        print('Attempting to save newly fetched icon to database...');
        final saveResult = await iconWithData.saveToDatabase();
        if (saveResult) {
          print('Successfully saved new icon for domain $domain to database');
        } else {
          print(
            'Failed to save new icon for domain $domain to database - will retry next time',
          );
          // Remove from cache so we'll try to save again next time
          _iconCache.remove(domain);
        }

        return iconWithData;
      } else {
        print('Failed to fetch icon data from logo.dev');
        return null;
      }
    } catch (e) {
      print('Error fetching icon from logo.dev for domain $domain:');
      print('Error type: ${e.runtimeType}');
      print('Error message: $e');
      return null;
    }
  }

  static Future<bool> validateIconUrl(String url) async {
    try {
      print('Validating icon URL: $url');
      final response = await http.head(Uri.parse(url));
      final isValid = response.statusCode == 200 &&
          response.headers['content-type']?.startsWith('image/') == true;
      if (!isValid) {
        print('Invalid icon URL: $url');
        print('Status code: ${response.statusCode}');
        print('Content-Type: ${response.headers['content-type']}');
      } else {
        print('Icon URL validated successfully: $url');
      }
      return isValid;
    } catch (e) {
      print('Error validating icon URL $url: $e');
      return false;
    }
  }

  // Clear the cache (useful for testing or memory management)
  static void clearCache() {
    print('Clearing icon cache (${_iconCache.length} icons)');
    _iconCache.clear();
  }

  // Get cache statistics
  static Map<String, dynamic> getCacheStats() {
    return {
      'cachedIcons': _iconCache.length,
      'domains': _iconCache.keys.toList(),
    };
  }
}

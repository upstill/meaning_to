import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  // Initialize Supabase
  await Supabase.initialize(
    url: 'https://zhpxdayfpysoixxjjqik.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpocHhkYXlmcHlzb2l4eGpqcWlrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzQ5NzI5NzQsImV4cCI6MjA1MDU0ODk3NH0.Ej8Ej8Ej8Ej8Ej8Ej8Ej8Ej8Ej8Ej8Ej8Ej8Ej8Ej8',
  );

  final supabase = Supabase.instance.client;

  print('Testing database update...');

  try {
    // Test with a known task ID and user ID
    final taskId = 6; // "A Shop for Killers"
    final userId = '35ed4d18-84b4-481d-96f4-1405c2f2f1ae'; // Guest user ID

    print('Task ID: $taskId');
    print('User ID: $userId');

    // First, read the current value
    print('\n1. Reading current suggestible_at...');
    final readResponse = await supabase
        .from('Tasks')
        .select('suggestible_at')
        .eq('id', taskId)
        .eq('owner_id', userId)
        .single();

    print('Current suggestible_at: ${readResponse['suggestible_at']}');

    // Update the value
    print('\n2. Updating suggestible_at...');
    final testTime = DateTime.now().toUtc();
    print('New time: ${testTime.toIso8601String()}');

    final updateResponse = await supabase
        .from('Tasks')
        .update({
          'suggestible_at': testTime.toIso8601String(),
        })
        .eq('id', taskId)
        .eq('owner_id', userId);

    print('Update response: $updateResponse');

    // Verify the update
    print('\n3. Verifying update...');
    final verifyResponse = await supabase
        .from('Tasks')
        .select('suggestible_at')
        .eq('id', taskId)
        .eq('owner_id', userId)
        .single();

    print('New suggestible_at: ${verifyResponse['suggestible_at']}');

    if (verifyResponse['suggestible_at'] == testTime.toIso8601String()) {
      print('\n✅ SUCCESS: Database update worked!');
    } else {
      print('\n❌ FAILED: Database update did not work');
      print('Expected: ${testTime.toIso8601String()}');
      print('Got: ${verifyResponse['suggestible_at']}');
    }
  } catch (e) {
    print('\n❌ ERROR: $e');
    print('Error type: ${e.runtimeType}');
  }
}

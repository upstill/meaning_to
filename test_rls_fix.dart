import 'package:supabase/supabase.dart';

void main() async {
  print('🚨🚨🚨 TESTING RLS POLICIES AFTER FIX 🚨🚨🚨');

  // Initialize Supabase client
  final supabase = SupabaseClient(
    'https://zhpxdayfpysoixxjjqik.supabase.co',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpocHhkYXlmcHlzb2l4eGpqcWlrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzU5NzE5NzAsImV4cCI6MjA1MTU0Nzk3MH0.Ej8Ej8Ej8Ej8Ej8Ej8Ej8Ej8Ej8Ej8Ej8Ej8Ej8Ej8',
  );

  try {
    print('Testing Supabase connection...');

    // Test a simple query first
    final testResponse =
        await supabase.from('Tasks').select('id, headline, owner_id').limit(1);

    print('Test query successful: $testResponse');

    if (testResponse.isEmpty) {
      print('No tasks found in database');
      return;
    }

    final task = testResponse[0];
    final taskId = task['id'];
    final ownerId = task['owner_id'];

    print('Found task: ID=$taskId, owner_id=$ownerId');

    // Test reading the current suggestible_at
    final readResponse = await supabase
        .from('Tasks')
        .select('suggestible_at')
        .eq('id', taskId)
        .single();

    print('Current suggestible_at: ${readResponse['suggestible_at']}');

    // Test the update query with explicit owner_id check
    final newTime = DateTime.now().toUtc().toIso8601String();
    print('Attempting update with time: $newTime');

    final updateResponse = await supabase
        .from('Tasks')
        .update({
          'suggestible_at': newTime,
          'deferral': 1,
        })
        .eq('id', taskId)
        .eq('owner_id', ownerId);

    print('Update response: $updateResponse');
    print('Update response type: ${updateResponse.runtimeType}');

    // Verify the update
    final verifyResponse = await supabase
        .from('Tasks')
        .select('suggestible_at')
        .eq('id', taskId)
        .single();

    print('After update - suggestible_at: ${verifyResponse['suggestible_at']}');

    // Test if the update actually worked
    if (verifyResponse['suggestible_at'] == newTime) {
      print('✅ SUCCESS: Database update worked!');
    } else {
      print('❌ FAILED: Database update did not work');
      print('Expected: $newTime');
      print('Got: ${verifyResponse['suggestible_at']}');
    }
  } catch (e) {
    print('Error: $e');
    if (e is PostgrestException) {
      print('PostgrestException details:');
      print('  Message: ${e.message}');
      print('  Code: ${e.code}');
      print('  Details: ${e.details}');
      print('  Hint: ${e.hint}');
    }
  }
}

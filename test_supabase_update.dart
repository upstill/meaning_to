import 'package:supabase/supabase.dart';

void main() async {
  print('🚨🚨🚨 TESTING SUPABASE UPDATE DIRECTLY 🚨🚨🚨');

  // Initialize Supabase client
  final supabase = SupabaseClient(
    'https://zhpxdayfpysoixxjjqik.supabase.co',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpocHhkYXlmcHlzb2l4eGpqcWlrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzU5NzE5NzAsImV4cCI6MjA1MTU0Nzk3MH0.Ej8Ej8Ej8Ej8Ej8Ej8Ej8Ej8Ej8Ej8Ej8Ej8Ej8Ej8',
  );

  try {
    print('Testing Supabase connection...');

    // First, let's see what tasks exist in the database
    print('\n=== CHECKING EXISTING TASKS ===');
    final allTasksResponse = await supabase
        .from('Tasks')
        .select('id, headline, owner_id, suggestible_at, created_at')
        .order('created_at', ascending: false)
        .limit(10);

    print('Found ${allTasksResponse.length} tasks:');
    for (var task in allTasksResponse) {
      print(
          'Task ID: ${task['id']}, Headline: ${task['headline']}, Owner: ${task['owner_id']}, Suggestible: ${task['suggestible_at']}');
    }

    if (allTasksResponse.isEmpty) {
      print('No tasks found in database. Need to create test data first.');
      return;
    }

    // Find a task owned by the guest user
    final guestUserId = '35ed4d18-84b4-481d-96f4-1405c2f2f1ae';
    final guestTasks = allTasksResponse
        .where((task) => task['owner_id'] == guestUserId)
        .toList();

    if (guestTasks.isEmpty) {
      print('No tasks found for guest user. Creating a test task...');

      // Create a test task with future suggestible_at
      final futureTime =
          DateTime.now().add(Duration(hours: 24)).toUtc().toIso8601String();
      final insertResponse = await supabase.from('Tasks').insert({
        'headline': 'Test Task for Revive',
        'owner_id': guestUserId,
        'suggestible_at': futureTime,
        'category_id': 1, // Assuming category 1 exists
      }).select();

      print('Created test task: $insertResponse');

      if (insertResponse.isNotEmpty) {
        final taskId = insertResponse[0]['id'];
        print('Now testing update on task ID: $taskId');

        // Test the update
        final updateResponse = await supabase
            .from('Tasks')
            .update(
                {'suggestible_at': DateTime.now().toUtc().toIso8601String()})
            .eq('id', taskId)
            .eq('owner_id', guestUserId)
            .select();

        print('Update response: $updateResponse');

        // Verify the update
        final verifyResponse = await supabase
            .from('Tasks')
            .select('suggestible_at')
            .eq('id', taskId)
            .single();

        print(
            'Verification - suggestible_at: ${verifyResponse['suggestible_at']}');
      }
    } else {
      print(
          'Found ${guestTasks.length} tasks for guest user. Testing update on first task...');
      final taskId = guestTasks[0]['id'];
      final currentSuggestible = guestTasks[0]['suggestible_at'];

      print(
          'Testing update on task ID: $taskId, current suggestible_at: $currentSuggestible');

      // Test the update
      final updateResponse = await supabase
          .from('Tasks')
          .update({'suggestible_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', taskId)
          .eq('owner_id', guestUserId)
          .select();

      print('Update response: $updateResponse');

      // Verify the update
      final verifyResponse = await supabase
          .from('Tasks')
          .select('suggestible_at')
          .eq('id', taskId)
          .single();

      print(
          'Verification - suggestible_at: ${verifyResponse['suggestible_at']}');
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

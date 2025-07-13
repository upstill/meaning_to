import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  // Initialize Supabase
  await Supabase.initialize(
    url: 'https://zhpxdayfpysoixxjjqik.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpocHhkYXlmcHlzb2l4eGpqcWlrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDU0Mjk4MjAsImV4cCI6MjA2MTAwNTgyMH0.vWogNfl_98kZaTLFFf3sMSyddZBSjBt9D1yxTTiamVQ',
  );

  final supabase = Supabase.instance.client;

  // Test guest user ID
  final guestUserId = '35ed4d18-84d4-481d-96f4-1405c2f2f1ae';

  print('Testing guest user categories...');
  print('Guest user ID: $guestUserId');

  try {
    // Query categories for guest user
    final response = await supabase
        .from('categories')
        .select('*')
        .eq('owner_id', guestUserId);

    print('Categories found: ${response.length}');
    for (var category in response) {
      print('- ${category['headline']} (ID: ${category['id']})');
    }

    // Query tasks for guest user
    final tasksResponse =
        await supabase.from('tasks').select('*').eq('owner_id', guestUserId);

    print('Tasks found: ${tasksResponse.length}');
    for (var task in tasksResponse) {
      print('- ${task['headline']} (Category: ${task['category_id']})');
    }
  } catch (e) {
    print('Error: $e');
  }
}

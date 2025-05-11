import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

String userKey() {
  return userLoggedIn() ? supabase.auth.currentUser!.id : 'b522ada9-742b-4dcf-90ee-83f33da78ab2';
}

bool userLoggedIn() {
  return supabase.auth.currentUser?.id != null;
}

void ensureLoggedIn() {
  if (!userLoggedIn()) {
    throw Exception('No user logged in');
  }
} 
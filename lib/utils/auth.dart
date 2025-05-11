import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

String userKey() {
  return userLoggedIn() ? supabase.auth.currentUser!.id : '35ed4d18-84b4-481d-96f4-1405c2f2f1ae';
}

bool userLoggedIn() {
  return supabase.auth.currentUser?.id != null;
}

void ensureLoggedIn() {
  if (!userLoggedIn()) {
    throw Exception('No user logged in');
  }
} 
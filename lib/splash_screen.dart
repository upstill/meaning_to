import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meaning_to/auth_screen.dart';
import 'package:meaning_to/home_screen.dart';
import 'dart:async';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    print('SplashScreen: initState called');
    _checkSession();
  }

  void _checkSession() {
    print('SplashScreen: Checking session...');
    try {
      final session = Supabase.instance.client.auth.currentSession;
      print('SplashScreen: Session check result: ${session != null ? 'Session exists' : 'No session'}');
      
      if (!mounted) return;
      
      // Schedule navigation for after the build phase
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        
        if (session == null) {
          print('SplashScreen: Navigating to auth screen');
          Navigator.pushReplacementNamed(context, '/auth');
        } else {
          print('SplashScreen: Navigating to home screen');
          Navigator.pushReplacementNamed(context, '/home');
        }
      });
    } catch (e) {
      print('SplashScreen: Error checking session: $e');
      if (!mounted) return;
      
      // Schedule error navigation for after the build phase
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/auth');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    print('SplashScreen: Building widget');
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

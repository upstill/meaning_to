import 'package:flutter/material.dart';
import 'package:meaning_to/home_screen.dart';
import 'package:meaning_to/auth_screen.dart';
import 'package:meaning_to/task_edit_screen.dart';
import 'package:meaning_to/justwatch_import_screen.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';

class MeaningToApp extends StatelessWidget {
  const MeaningToApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'I\'ve Been Meaning To',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const HomeScreen(),
        '/auth': (context) => const AuthScreen(),
        '/edit-task': (context) {
          final args = ModalRoute.of(context)!.settings.arguments
              as Map<String, dynamic>;
          return TaskEditScreen(
            category: args['category'] as Category,
            task: args['task'] as Task?,
          );
        },
        '/justwatch-import': (context) {
          final args = ModalRoute.of(context)!.settings.arguments
              as Map<String, dynamic>;
          return JustWatchImportScreen(
            category: args['category'] as Category,
          );
        },
      },
    );
  }
}

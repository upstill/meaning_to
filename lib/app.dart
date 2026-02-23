import 'package:flutter/material.dart';
import 'package:meaning_to/home_screen.dart';
import 'package:meaning_to/auth_screen.dart';
import 'package:meaning_to/edit_category_screen.dart';
import 'package:meaning_to/task_edit_screen.dart';
import 'package:meaning_to/import_justwatch_screen.dart';
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
        '/edit-category': (context) {
          final args = ModalRoute.of(context)?.settings.arguments
              as Map<String, dynamic>?;
          return EditCategoryScreen(
            category: args?['category'] as Category?,
            tasksOnly: args?['tasksOnly'] == true,
            startInCategoryEditorPanel:
                args?['startInCategoryEditorPanel'] == true,
          );
        },
        '/edit-task': (context) {
          final args = ModalRoute.of(context)!.settings.arguments
              as Map<String, dynamic>;
          return TaskEditScreen(
            category: args['category'] as Category,
            task: args['task'] as Task?,
          );
        },
        '/import-justwatch': (context) {
          print('Route handler for /import-justwatch called');
          final args = ModalRoute.of(context)!.settings.arguments
              as Map<String, dynamic>;
          print('Route args: $args');
          print('Category: ${args['category']}');
          print('JSON data type: ${args['jsonData']?.runtimeType}');
          return ImportJustWatchScreen(
            category: args['category'] as Category,
            jsonData: args['jsonData'],
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

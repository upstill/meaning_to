import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meaning_to/widgets/task_display.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/utils/naming.dart';

void main() {
  group('TaskDisplay Tests', () {
    testWidgets('should gray out title for deferred task',
        (WidgetTester tester) async {
      // Create a task that is deferred (suggestibleAt in the future)
      final deferredTask = Task(
        id: 1,
        categoryId: 1,
        headline: 'Deferred Task',
        ownerId: 'user123',
        createdAt: DateTime.now(),
        suggestibleAt:
            DateTime.now().add(const Duration(hours: 1)), // Deferred for 1 hour
        finished: false,
      );

      // Build the TaskDisplay widget
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskDisplay(
              task: deferredTask,
              withControls: false,
            ),
          ),
        ),
      );

      // Find the text widget
      final textWidget = tester.widget<Text>(find.text('Deferred Task'));

      // Check that the text color is grey
      expect(textWidget.style?.color, Colors.grey);
    });

    testWidgets('should not gray out title for available task',
        (WidgetTester tester) async {
      // Create a task that is available (suggestibleAt in the past or null)
      final availableTask = Task(
        id: 2,
        categoryId: 1,
        headline: 'Available ${NamingUtils.tasksName(plural: true)}',
        ownerId: 'user123',
        createdAt: DateTime.now(),
        suggestibleAt: DateTime.now()
            .subtract(const Duration(hours: 1)), // Available (past)
        finished: false,
      );

      // Build the TaskDisplay widget
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskDisplay(
              task: availableTask,
              withControls: false,
            ),
          ),
        ),
      );

      // Find the text widget
      final textWidget = tester.widget<Text>(
          find.text('Available ${NamingUtils.tasksName(plural: true)}'));

      // Check that the text color is not grey (should be null, meaning default color)
      expect(textWidget.style?.color, isNull);
    });

    testWidgets('should not gray out title for task with null suggestibleAt',
        (WidgetTester tester) async {
      // Create a task with null suggestibleAt
      final nullTask = Task(
        id: 3,
        categoryId: 1,
        headline: 'Null Task',
        ownerId: 'user123',
        createdAt: DateTime.now(),
        suggestibleAt: null, // No deferral
        finished: false,
      );

      // Build the TaskDisplay widget
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskDisplay(
              task: nullTask,
              withControls: false,
            ),
          ),
        ),
      );

      // Find the text widget
      final textWidget = tester.widget<Text>(find.text('Null Task'));

      // Check that the text color is not grey (should be null, meaning default color)
      expect(textWidget.style?.color, isNull);
    });
  });
}

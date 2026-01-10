import 'package:flutter/material.dart';
import 'package:meaning_to/utils/naming.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Introduction
          const Padding(
            padding: EdgeInsets.only(bottom: 24.0),
            child: Text(
              'Welcome to I\'ve Been Meaning To!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // What Is This Thing?
          _buildHelpSection(
            context: context,
            title: 'What Is This Thing?',
            content: '''
I've Been Meaning To helps you organize and track the ideas, goals, and interests you've been meaning to explore.

Think of it as a way to keep track of all those things you say "I've been meaning to..." about - books you want to read, movies to watch, places to visit, projects to start, or anything else that catches your interest.

The app helps you:
• Keep all your ideas organized
• Get random suggestions when you're ready to act
• Track what you've accomplished
• Share your interests with others
''',
          ),

          const SizedBox(height: 8),

          // Compiling Pursuits
          _buildHelpSection(
            context: context,
            title: 'Compiling ${NamingUtils.categoriesName(capitalize: true)}',
            content: '''
${NamingUtils.categoriesName(capitalize: true)} are the main way to organize your ideas. Each ${NamingUtils.categoriesName(capitalize: false, plural: false)} represents a type of activity or interest.

Examples of ${NamingUtils.categoriesName(capitalize: false)}:
• "Watch a Movie"
• "Read a Book"
• "Try a Restaurant"
• "Learn a Skill"
• "Visit a Place"

Within each ${NamingUtils.categoriesName(capitalize: false, plural: false)}, you add individual ${NamingUtils.tasksName(capitalize: false)} - the specific things you want to do. For example, in "Watch a Movie", you might add "The Godfather", "Blade Runner", or "Spirited Away".

You can make your ${NamingUtils.categoriesName(capitalize: false)} public to share with others, or keep them private for your eyes only.
''',
          ),

          const SizedBox(height: 8),

          // Linking Elsewhere
          _buildHelpSection(
            context: context,
            title: 'Linking Elsewhere',
            content: '''
You can add links to external resources for your ${NamingUtils.tasksName(capitalize: false)}. This makes it easy to jump directly to relevant content.

Supported link types:
• Streaming services (Netflix, Amazon Prime, Apple TV+, etc.)
• Music services (Spotify, Apple Music, YouTube Music, Tidal)
• Websites and articles
• Any other URL you want to save

When you add a link, the app will try to automatically fetch information like titles and descriptions. For some services (like movies and music), it can even find where content is available to stream.

Just paste a URL when creating or editing an ${NamingUtils.tasksName(capitalize: false, plural: false)}, and the app will handle the rest!
''',
          ),

          const SizedBox(height: 32),

          // Footer
          const Center(
            child: Text(
              'Need more help? Contact us at support@example.com',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpSection({
    required BuildContext context,
    required String title,
    required String content,
  }) {
    return ExpansionTile(
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 16.0),
          child: Text(
            content,
            style: const TextStyle(
              fontSize: 15,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

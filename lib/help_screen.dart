import 'package:flutter/material.dart';
import 'package:meaning_to/utils/naming.dart';

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  int? _expandedIndex;

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
            index: 0,
            title: 'What Is This Thing?',
            content: '''
I've Been Meaning To helps you organize and track the ideas, goals, and interests you've been meaning to explore.

Think of it as a way to keep track of all those things you say "I've been meaning to..." about - books you want to read, movies to watch, places to visit, projects to start, or anything else that catches your interest.

The app helps you:
• Keep your ideas organized, with notes reminding you where they came from and/or why they're there
• Link your ideas to external resources like movies, books, music, and more
• Get random suggestions when you're ready to act
• Track what you've accomplished
• Get ideas from others and share yours
''',
          ),

          const SizedBox(height: 8),

          // Compiling Pursuits
          _buildHelpSection(
            context: context,
            index: 1,
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
            index: 2,
            title: 'Linking Elsewhere',
            content: '''
You can add links to external resources for your ${NamingUtils.tasksName(capitalize: false)}. This makes it easy to jump directly to relevant content.

Supported link types:
• Streaming services (Netflix, Amazon Prime, Apple TV+, etc.)
• Music services (Spotify, Apple Music, YouTube Music, Tidal)
• Websites and articles
• Any other URL you want to save

When you add a link, the app will try to automatically fetch information like titles and descriptions. For some services (like movies and music), it can even find where content is available to stream.

Pro tip: Just paste a URL into the headline when adding a new ${NamingUtils.tasksName(capitalize: false, plural: false)}, and the app will handle the rest!
''',
          ),

          const SizedBox(height: 8),

          // Turn Shares into Ideas
          _buildHelpSection(
            context: context,
            index: 3,
            title:
                'Turn Shares into ${NamingUtils.tasksName(capitalize: true)}',
            content: '''
On mobile, you can quickly capture content from other apps by using the Share feature.

How it works:
1. Find something interesting in another app (a website, article, video, etc.)
2. Tap the Share button
3. Select "I've Been Meaning To" from the share menu
4. Tell the app what ${NamingUtils.categoriesName(capitalize: false, plural: false)} it pertains to
5. The app will create a new ${NamingUtils.tasksName(capitalize: false, plural: false)} with the shared link

This is a fast way to capture ideas on the go without switching apps. The shared content will be automatically added as a link to your new ${NamingUtils.tasksName(capitalize: false, plural: false)}, and you can organize it into the appropriate ${NamingUtils.categoriesName(capitalize: false, plural: false)} later.

Perfect for saving articles to read, videos to watch, or anything else you come across while browsing!
''',
          ),

          const SizedBox(height: 8),

          // Import Ideas from Elsewhere
          _buildHelpSection(
            context: context,
            index: 4,
            title:
                'Import ${NamingUtils.tasksName(capitalize: true)} from Elsewhere',
            content: '''
Already have a list of things you've been meaning to do? You can import them in bulk from other sources.

Supported import formats:
• CSV files (spreadsheets exported from Excel, Google Sheets, etc.)
• Letterboxd (for movie watchlists)
• JustWatch (for streaming content)
• Other structured data formats

How to import:
1. On the home screen, select the ${NamingUtils.categoriesName(capitalize: false, plural: false)} you want to add to
2. Hit the "+" button to add a new ${NamingUtils.tasksName(capitalize: false, plural: false)}
3. Instead of entering a single ${NamingUtils.tasksName(capitalize: false, plural: false)}, hit the "Add a List of Ideas" button
4. Select your data source or file
5. The app will process your data and create ${NamingUtils.tasksName(capitalize: false)} automatically

This is perfect if you're migrating from another app or have been keeping lists in spreadsheets. Import hundreds of items at once instead of entering them one by one!
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
    required int index,
    required String title,
    required String content,
  }) {
    return ExpansionTile(
      initiallyExpanded: _expandedIndex == index,
      onExpansionChanged: (expanded) {
        setState(() {
          _expandedIndex = expanded ? index : null;
        });
      },
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

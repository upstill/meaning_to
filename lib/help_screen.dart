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
              'Welcome to ROUZME!',
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
ROUZME! moves you to actually do stuff. Use ROUZME! to help you organize and track the ideas, goals, and interests you've been meaning to pursue.

Think of it as a way to keep track of all those things you say "I've been meaning to..." about - books you want to read, movies to watch, places to visit, projects to start, or anything else that catches your interest.

The app helps you:
• Keep your ${NamingUtils.tasksName(capitalize: true, plural: true)} organized into collections (${NamingUtils.categoriesName(capitalize: true, plural: true)}), with notes reminding you where they came from and/or why they're here
• Link your ${NamingUtils.tasksName(capitalize: true, plural: true)} to external resources like movies, books, music, and more
• Get a random (more or less) suggestion when you're ready to act
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

Examples of ${NamingUtils.categoriesName(capitalize: true)}:
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
You can add links pointing to external resources for your ${NamingUtils.tasksName(capitalize: false)}. This makes it easy to jump directly to relevant content.

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

          // Take Shares from other apps
          _buildHelpSection(
            context: context,
            index: 3,
            title: 'Take Shares from other apps',
            contentWidget: RichText(
              text: TextSpan(
                style: const TextStyle(
                    fontSize: 15, height: 1.5, color: Colors.black),
                children: [
                  const TextSpan(
                    text:
                        'On mobile, you can quickly capture content from other apps by using the Share feature.\n\n'
                        'How it works:\n'
                        '1. Find something interesting in another app (a website, article, video, etc.)\n'
                        '2. Tap the Share ',
                  ),
                  const WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Icon(Icons.share, size: 16, color: Colors.black87),
                  ),
                  TextSpan(
                    text: ' button in that app\n'
                        '3. Select "ROUZME!" from the available targets.\n'
                        '4. Tell the app what ${NamingUtils.categoriesName(capitalize: false, plural: false)} it pertains to\n'
                        '5. The app will create a new ${NamingUtils.tasksName(capitalize: false, plural: false)} with the shared link\n\n'
                        'This is a fast way to capture ideas on the go in the course of regular browsing. '
                        'The shared content will be automatically added as a link to your new ${NamingUtils.tasksName(capitalize: false, plural: false)}, '
                        'and you can organize it into the appropriate ${NamingUtils.categoriesName(capitalize: false, plural: false)} later.\n\n'
                        'Perfect for saving articles to read, videos to watch, recordings to play, or anything else you come across in the wild world online!',
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Import Ideas from Elsewhere
          _buildHelpSection(
            context: context,
            index: 4,
            title:
                'Import a whole collection of ${NamingUtils.tasksName(capitalize: true, plural: true)}',
            content: '''
Already have a list of things you've been meaning to do? You can import them in bulk from other sources.

How to import:
1. On the home screen, select the ${NamingUtils.categoriesName(capitalize: false, plural: false)} you want to add to.
2. Hit the "Add ${NamingUtils.tasksName(capitalize: false, plural: false)}" button next to the ${NamingUtils.categoriesName(capitalize: false, plural: false)}'s title.
3. Instead of entering a single ${NamingUtils.tasksName(capitalize: false, plural: false)}, hit the "Add a List of Ideas" button.
4. Paste the list into the text box, or hit the Import button and select a data source file to upload.
5. The app will process your data and add the ${NamingUtils.tasksName(capitalize: false, plural: true)} automatically.

Supported import formats:
• Plain text files in a variety of formats (see **Example Formats below for details)
• JSON files (one item per line)
• CSV files (spreadsheets exported from Excel, Google Sheets, etc.)
• Letterboxd (for movie watchlists)
• JustWatch (for streaming content)
• Other structured data formats

This is perfect if you're migrating from another app or have been keeping lists in spreadsheets. Import hundreds of items at once instead of entering them one by one!

**Example Formats:
• Plain text:
Movie Title 1
Movie Title 2
https://www.justwatch.com/us/movie/inception

(That last is just a URL on a line; the app will automatically extract the title from the page it points to)

• JSON:
{"title": "Inception", "link": "https://www.justwatch.com/us/movie/inception"}
{"title": "The Matrix", "link": "https://www.justwatch.com/us/movie/the-matrix"}

• JSON array:
[{"title": "Inception"}, {"title": "The Matrix", "link": "https://www.justwatch.com/us/movie/the-matrix"}]

• Markdown links:
[Inception](https://example.com/inception)
[The Matrix](https://example.com/matrix)

• HTML links:
<a href="https://www.justwatch.com/us/movie/inception">Inception</a>
<a href="https://www.justwatch.com/us/movie/the-matrix">The Matrix</a>
''',
          ),

          const SizedBox(height: 8),

          // Share a Pursuit with a friend
          _buildHelpSection(
            context: context,
            index: 5,
            title:
                'Share ${NamingUtils.categoriesName(plural: false, capitalize: true, withArticle: true)} with a friend',
            content: '''
If you want to share your accumulated wisdom, you can let anyone see (but not change!) one of your ${NamingUtils.categoriesName(plural: true, capitalize: true)}. Here's how:

1. On the Home screen, pick the ${NamingUtils.categoriesName(plural: false, capitalize: true)} you want to share.
2. In the menu on the ${NamingUtils.categoriesName(plural: false, capitalize: true)} card, choose "Share this ${NamingUtils.categoriesName(plural: false, capitalize: true)}".
3. If you want to edit which which ${NamingUtils.tasksName(plural: true, capitalize: true)} will be visible to the sharee, tap the pencil icon.
4. Tap "Issue Link" to copy the invite link to your clipboard.
5. Paste the link into a message to your friend with flowery words about how great ROUZME! is. When they tap that link, they'll land in ROUZME! with the ${NamingUtils.categoriesName(plural: false, capitalize: true)} added to their account.

PS To manage all your shares, hit the "Manage Shares" item on the main menu (top right).
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
    String content = '',
    Widget? contentWidget,
  }) {
    return ExpansionTile(
      key: ValueKey<String>('help_section_${index}_${_expandedIndex == index}'),
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
          child: contentWidget ??
              Text(
                content,
                style: const TextStyle(fontSize: 15, height: 1.5),
              ),
        ),
      ],
    );
  }
}

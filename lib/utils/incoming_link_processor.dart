// ignore_for_file: unused_element, unused_local_variable

import 'package:flutter/material.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/utils/link_to_task_converter.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/utils/supabase_client.dart';
import 'package:meaning_to/utils/cache_manager.dart';
import 'package:meaning_to/utils/api_client.dart';
import 'package:meaning_to/utils/category_ordering.dart';
import 'package:meaning_to/task_edit_screen.dart';
import 'package:meaning_to/utils/naming.dart';
import 'package:meaning_to/utils/streaming_media_constants.dart';
import 'package:meaning_to/utils/category_suggestion_registry.dart';

/// Result of processing an incoming link
class LinkProcessingResult {
  final String url;
  final String? title;
  final String? description;
  final List<DuplicateMatch> duplicates;
  final bool hasValidMetadata;
  final ProposedTask? proposedTask;

  LinkProcessingResult({
    required this.url,
    this.title,
    this.description,
    required this.duplicates,
    required this.hasValidMetadata,
    this.proposedTask,
  });
}

/// Information about a duplicate link found in the system
class DuplicateMatch {
  final Task task;
  final Category category;
  final String matchingUrl;
  final String originalLinkText;

  DuplicateMatch({
    required this.task,
    required this.category,
    required this.matchingUrl,
    required this.originalLinkText,
  });
}

/// Actions user can take with an incoming link
enum LinkAction {
  createNewTask,
  addToExistingTask,
  viewExistingTask,
  cancel,
}

/// Outcome of [IncomingLinkProcessor.resolveSingleLineDuplicates].
enum SingleLineDupOutcome {
  /// The user chose "Edit Old"; the existing task was opened for editing, so the
  /// caller should abandon whatever new task it was about to create.
  handledExisting,

  /// No duplicate was found, or the user chose "Make New" — the caller should
  /// proceed to create its new task.
  makeNew,

  /// The user cancelled; the caller should abort without creating anything.
  cancelled,
}

/// Service for processing incoming shared links
class IncomingLinkProcessor {

  /// Process an incoming link and return comprehensive results
  static Future<LinkProcessingResult> processIncomingLink(String url,
      {String? preTitle}) async {
    print('IncomingLinkProcessor: Processing incoming link: $url');

    // Normalize and validate URL
    final normalizedUrl = _normalizeUrl(url);
    if (normalizedUrl == null) {
      throw ArgumentError('Invalid URL provided: $url');
    }

    final userId = AuthUtils.getCurrentUserId();

    // Run enrichment (via LinkToTaskConverter) and URL-duplicate search in parallel
    print('IncomingLinkProcessor: Starting parallel enrichment + duplicate check');
    final results = await Future.wait([
      LinkToTaskConverter.createProposedTaskFromLink(normalizedUrl, userId,
              preProvidedTitle: preTitle)
          .then<ProposedTask?>((t) => t)
          .catchError((e) {
        print('IncomingLinkProcessor: LinkToTaskConverter failed: $e');
        return null;
      }),
      findAllDuplicates(normalizedUrl),
    ]);

    final ProposedTask? proposedTask = results[0] as ProposedTask?;
    final duplicates = results[1] as List<DuplicateMatch>;

    // Derive title + description from the ProposedTask
    String? title = proposedTask?.headline.isNotEmpty == true ? proposedTask!.headline : null;
    String? description = proposedTask?.synopsis;
    final hasValidMetadata = title != null || description != null;

    if (proposedTask != null) {
      print('IncomingLinkProcessor: ProposedTask - Headline: "$title"');
    }

    print(
        'IncomingLinkProcessor: Found ${duplicates.length} duplicate(s) for URL: $normalizedUrl');
    if (duplicates.isNotEmpty) {
      for (final dup in duplicates) {
        print(
            '  - Duplicate: "${dup.task.headline}" in "${dup.category.headline}"');
      }
    }

    // If no URL match found, try matching by title in the suggested categories
    // (e.g. an IMDb share for "Sly" should find an existing "Sly" task in Watch a Movie)
    if (duplicates.isEmpty && title != null && title.isNotEmpty) {
      final suggestedIds =
          CategorySuggestionRegistry.getSuggestionsForUrl(normalizedUrl);
      if (suggestedIds.isNotEmpty) {
        print(
            'IncomingLinkProcessor: No URL match — trying title match for "$title" in suggested categories $suggestedIds');
        final userId = AuthUtils.getCurrentUserId();
        final titleMatch = await _findTaskByTitleInSuggestedCategories(
            title, userId, suggestedIds);
        if (titleMatch != null) {
          final (matchTask, matchCategory) = titleMatch;
          duplicates.add(DuplicateMatch(
            task: matchTask,
            category: matchCategory,
            matchingUrl: normalizedUrl,
            originalLinkText: '',
          ));
          print(
              'IncomingLinkProcessor: Title match added as duplicate: "${matchTask.headline}" in "${matchCategory.headline}"');
        }
      }
    }

    return LinkProcessingResult(
      url: normalizedUrl,
      title: title,
      description: description,
      duplicates: duplicates,
      hasValidMetadata: hasValidMetadata,
      proposedTask: proposedTask,
    );
  }

  /// Find all duplicate links across ALL tasks (not just user's tasks)
  static Future<List<DuplicateMatch>> findAllDuplicates(String url) async {
    final duplicates = <DuplicateMatch>[];

    try {
      final userId = AuthUtils.getCurrentUserId();

      print(
          'IncomingLinkProcessor: Checking for duplicates across ALL tasks in database');

      // Validate URL can be parsed
      final uri = Uri.tryParse(url);
      if (uri == null) {
        print('IncomingLinkProcessor: Could not parse URL: $url');
        return [];
      }

      // Escape URL for LIKE pattern matching
      final escapedUrl = url.replaceAll('%', '\\%').replaceAll('_', '\\_');

      // Use RPC function to efficiently query tasks with matching links
      try {
        final linkResponse = await supabase.rpc(
          'find_tasks_by_link_url',
          params: {'search_url_pattern': '%$escapedUrl%'},
        );

        final tasksWithLink = (linkResponse as List)
            .map((json) => Task.fromJson(json as Map<String, dynamic>))
            .where((task) => task.ownerId == userId) // Filter by owner
            .toList();

        print(
            'IncomingLinkProcessor: Found ${tasksWithLink.length} task(s) with potentially matching link');

        // Fetch categories for the matching tasks
        final categoryIds =
            tasksWithLink.map((t) => t.categoryId).toSet().toList();
        // Fetch all user categories and filter in memory (still efficient)
        final categoriesResponse =
            await supabase.from('Categories').select().eq('owner_id', userId);

        final categoriesMap = <int, Category>{};
        for (final catData in categoriesResponse as List<dynamic>) {
          final category = Category.fromJson(catData);
          // Only include categories that are in our list
          if (categoryIds.contains(category.id)) {
            categoriesMap[category.id] = category;
          }
        }

        // Check each task for exact URL match
        for (final task in tasksWithLink) {
          final category = categoriesMap[task.categoryId];
          if (category == null) {
            print(
                'IncomingLinkProcessor: Skipping task ${task.headline} - no category data');
            continue;
          }

          // Check each link in the task for exact match
          for (final linkText in task.links ?? []) {
            final linkUrl = _extractUrlFromHtmlLink(linkText);
            if (linkUrl != null) {
              final urlsMatch = _urlsMatch(url, linkUrl);
              if (urlsMatch) {
                print(
                    'IncomingLinkProcessor: Found duplicate in task "${task.headline}" in category "${category.headline}"');
                print('  Incoming URL: $url');
                print('  Existing URL: $linkUrl');
                duplicates.add(DuplicateMatch(
                  task: task,
                  category: category,
                  matchingUrl: linkUrl,
                  originalLinkText: linkText,
                ));
                break; // Only count each task once
              }
            }
          }
        }
      } catch (e) {
        print(
            'IncomingLinkProcessor: Error querying tasks by link (RPC may not exist): $e');
        print('IncomingLinkProcessor: Falling back to fetching all tasks...');

        // Fallback: page through ALL the user's tasks. A plain .select() is
        // capped at 1000 rows by PostgREST, which silently missed duplicates for
        // users with more tasks than that (URL matches on older tasks never
        // fired). Accumulate every page via .range() so the scan is complete.
        const pageSize = 1000;
        final userTasksData = <dynamic>[];
        for (var from = 0;; from += pageSize) {
          final page = await supabase
              .from('Tasks')
              .select('*, Categories!Tasks_category_id_fkey(*)')
              .eq('owner_id', userId)
              .range(from, from + pageSize - 1);
          final pageList = page as List<dynamic>;
          userTasksData.addAll(pageList);
          if (pageList.length < pageSize) break;
        }
        print(
            'IncomingLinkProcessor: Checking ${userTasksData.length} tasks across all user categories');

        // Check user's tasks for duplicates
        for (final taskData in userTasksData) {
          try {
            final task = Task.fromJson(taskData);
            final categoryData = taskData['Categories'];

            if (categoryData == null) {
              print(
                  'IncomingLinkProcessor: Skipping task ${task.headline} - no category data');
              continue;
            }

            final category = Category.fromJson(categoryData);

            // Check each link in the task
            for (final linkText in task.links ?? []) {
              final linkUrl = _extractUrlFromHtmlLink(linkText);
              if (linkUrl != null) {
                final urlsMatch = _urlsMatch(url, linkUrl);
                if (urlsMatch) {
                  print(
                      'IncomingLinkProcessor: Found duplicate in task "${task.headline}" in category "${category.headline}"');
                  print('  Incoming URL: $url');
                  print('  Existing URL: $linkUrl');
                  duplicates.add(DuplicateMatch(
                    task: task,
                    category: category,
                    matchingUrl: linkUrl,
                    originalLinkText: linkText,
                  ));
                  break; // Only count each task once
                }
              }
            }
          } catch (e) {
            print('IncomingLinkProcessor: Error processing task data: $e');
            continue;
          }
        }
      }

      print(
          'IncomingLinkProcessor: Found ${duplicates.length} duplicate(s) across all user categories');
    } catch (e) {
      print('IncomingLinkProcessor: Error during duplicate check: $e');
    }

    return duplicates;
  }

  /// Find the original_id for a link by checking all tasks in the database
  static Future<int?> findOriginalIdForLink(String url) async {
    try {
      print('IncomingLinkProcessor: Finding original_id for URL: $url');

      // Fetch ALL tasks in the database to find the original
      final response = await supabase
          .from('Tasks')
          .select()
          .order('created_at', ascending: true); // Oldest first

      final tasksData = response as List<dynamic>;
      print(
          'IncomingLinkProcessor: Checking ${tasksData.length} tasks for original_id');

      for (final taskData in tasksData) {
        try {
          final task = Task.fromJson(taskData);

          // Check each link in the task
          for (final linkText in task.links ?? []) {
            final linkUrl = _extractUrlFromHtmlLink(linkText);
            if (linkUrl != null && _urlsMatch(url, linkUrl)) {
              // Found a task with this link
              // If it has an original_id, use that; otherwise use its own id
              final originalId = task.originalId ?? task.id;
              print(
                  'IncomingLinkProcessor: Found original_id: $originalId (from task: "${task.headline}", created: ${task.createdAt})');
              return originalId;
            }
          }
        } catch (e) {
          print(
              'IncomingLinkProcessor: Error processing task for original_id: $e');
          continue;
        }
      }

      print('IncomingLinkProcessor: No existing task found with this link');
      return null;
    } catch (e) {
      print('IncomingLinkProcessor: Error finding original_id: $e');
      return null;
    }
  }

  /// Show the main link action dialog to the user
  static Future<void> showLinkActionDialog(
    BuildContext context,
    String url, {
    Category? defaultCategory,
    String? preTitle,
  }) async {
    print('IncomingLinkProcessor: Processing incoming link: $url');

    // Show processing dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Processing link...',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );

    // Declare result variable before try block so it's accessible after
    late final LinkProcessingResult result;

    try {
      // Parse the incoming text as if it's from an import
      result = await processIncomingLink(url, preTitle: preTitle);

      if (!context.mounted) return;

      // Dismiss processing dialog
      Navigator.of(context).pop();

      if (!context.mounted) return;

      // Check for URL duplicates first
      if (result.duplicates.isNotEmpty) {
        // Link exists - offer to edit it or keep as new. Pass the original
        // result so "Keep New" reuses the known title instead of re-fetching.
        await _navigateToEditExistingTask(context, result.duplicates.first,
            originalResult: result);
        return;
      }

    } catch (e) {
      print('IncomingLinkProcessor: Error processing link: $e');
      if (context.mounted) {
        Navigator.of(context).pop(); // Dismiss dialog on error
      }
      rethrow;
    }

    // No URL duplicate. For a normal (non-streaming) link, also check for a
    // TITLE duplicate — an existing task with the same headline but not this
    // link — mirroring the New Task headline-paste flow
    // (resolveSingleLineDuplicates). Without this, pasting a link whose resolved
    // title already exists (e.g. an IMDb link to a movie already on file) would
    // silently create a second task. Streaming links keep their artist-match
    // flow below. _navigateToEditExistingTask → _openExistingTaskForEdit adds
    // the pasted link to the matched task on "Edit Old".
    if (!isStreamingMediaUrl(result.url)) {
      final titleForDup = (result.title ?? preTitle ?? '').trim();
      if (titleForDup.isNotEmpty) {
        final headlineMatch = await _findOwnedTaskByHeadline(
            titleForDup, AuthUtils.getCurrentUserId());
        if (headlineMatch != null && context.mounted) {
          await _navigateToEditExistingTask(context, headlineMatch,
              originalResult: result);
          return;
        }
      }
    }

    // No URL duplicates - check if this is a Tidal link with artist matching
    ArtistWorkInfo? artistWorkInfo;
    if (isStreamingMediaUrl(result.url)) {
      if (result.proposedTask != null &&
          result.proposedTask!.notes != null &&
          result.proposedTask!.notes!.isNotEmpty) {
        artistWorkInfo = ArtistWorkInfo(
          artist: result.proposedTask!.headline,
          work: result.proposedTask!.notes!,
        );
      } else if (result.title != null) {
        artistWorkInfo = extractArtistAndWorkFromTidal(result.title!);
      }
    }

    if (artistWorkInfo != null) {
      print(
          'IncomingLinkProcessor: Detected Tidal link - Artist: "${artistWorkInfo.artist}", Work: "${artistWorkInfo.work}"');

      // Search for existing task with this artist
      final userId = AuthUtils.getCurrentUserId();
      final existingTask = await findTaskByArtistInStreamingCategories(
          artistWorkInfo.artist, userId);

      if (existingTask != null && context.mounted) {
        // Found exactly one matching artist task
        // Get the category for the existing task
        final categoryResponse = await supabase
            .from('Categories')
            .select()
            .eq('id', existingTask.categoryId)
            .single();

        final category = Category.fromJson(categoryResponse);

        // Show dialog asking if user wants to add to existing or create new
        final userChoice = await _showArtistMatchDialog(
          context,
          existingTask,
          category,
          artistWorkInfo.work,
        );

        if (!context.mounted) return;

        if (userChoice == 'add') {
          // User wants to add to existing task
          await _navigateToAddWorkToExistingTask(
            context,
            existingTask,
            category,
            artistWorkInfo.work,
            result.url,
            artistWorkInfo.work,
          );
          return;
        } else if (userChoice == 'new') {
          // User wants to create new task - continue with normal flow
          // but use artist as headline and work as notes
          await _navigateToTaskEditScreenWithArtistWork(
            context,
            result,
            defaultCategory,
            artistWorkInfo,
          );
          return;
        }
        // If userChoice is null, user dismissed dialog - do nothing
        return;
      }

      // No matching artist found or multiple matches - create new task with artist/work
      await _navigateToTaskEditScreenWithArtistWork(
        context,
        result,
        defaultCategory,
        artistWorkInfo,
      );
      return;
    }

    // Not a Tidal link or couldn't parse artist/work - use normal flow
    await _navigateToTaskEditScreen(context, result, defaultCategory);
  }

  /// Navigate to Edit Task screen for existing duplicate task
  static Future<void> _navigateToEditExistingTask(
    BuildContext context,
    DuplicateMatch duplicate, {
    LinkProcessingResult? originalResult,
  }) async {
    if (!context.mounted) return;

    try {
      print(
          'IncomingLinkProcessor: Navigating to edit existing task: ${duplicate.task.headline}');

      // Show dialog with three options
      final userChoice = await _showDuplicateOptionsDialog(context, duplicate);

      if (!context.mounted) return;

      if (userChoice == 'edit') {
        await _openExistingTaskForEdit(context, duplicate,
            originalResult: originalResult);
      } else if (userChoice == 'new') {
        // User chose to create a new task anyway. Reuse the original processing
        // result (which already has the correct title) rather than re-fetching
        // the page, which loses a supplied title and can yield a garbage one.
        print(
            'IncomingLinkProcessor: User chose to create new task despite duplicate');
        final result = originalResult ??
            await processIncomingLink(duplicate.matchingUrl);

        if (!context.mounted) return;

        // Navigate to new task screen (with the duplicate warning cleared).
        await _navigateToTaskEditScreen(
            context,
            LinkProcessingResult(
              url: result.url,
              title: result.title,
              description: result.description,
              duplicates: const [],
              hasValidMetadata: result.hasValidMetadata,
              proposedTask: result.proposedTask,
            ),
            null,
            forceCreate: true); // explicit "Make New" over the duplicate
      }
      // If userChoice is null or 'done', do nothing (user chose "All Done")
    } catch (e) {
      print(
          'IncomingLinkProcessor: Error navigating to edit existing task: $e');
    }
  }

  /// Open the existing (duplicate) task in the editor. Shared by the share
  /// "Edit Old" path and [resolveSingleLineDuplicates]. If the match was on
  /// headline alone, the task may lack the incoming link — pre-add it (with an
  /// info banner) so the user can Save to keep it.
  static Future<void> _openExistingTaskForEdit(
    BuildContext context,
    DuplicateMatch duplicate, {
    LinkProcessingResult? originalResult,
    bool replaceCurrentRoute = false,
  }) async {
    final categoryResponse = await supabase
        .from('Categories')
        .select()
        .eq('id', duplicate.task.categoryId)
        .single();
    final category = Category.fromJson(categoryResponse);

    // Offer the pursuit selector here too, so the user can move/copy the
    // existing task to another pursuit while editing it.
    final orderingResult = originalResult ??
        LinkProcessingResult(
          url: duplicate.matchingUrl,
          title: null,
          description: null,
          duplicates: const [],
          hasValidMetadata: false,
          proposedTask: null,
        );
    final ordered = await _orderedOwnedFor(orderingResult);
    final selectable = ordered.any((c) => c.id == category.id)
        ? ordered
        : [category, ...ordered];
    if (!context.mounted) return;

    // The match may have been on headline alone, so the existing task might not
    // contain the incoming link. If it doesn't, pre-add it and say so.
    final incomingUrl = originalResult?.url ?? duplicate.matchingUrl;
    final existingLinks = List<String>.from(duplicate.task.links ?? const []);
    final alreadyHasLink = existingLinks.any((l) {
      final u = _extractUrlFromHtmlLink(l);
      return u != null && incomingUrl.isNotEmpty && _urlsMatch(u, incomingUrl);
    });
    // Always apprise the user of what brought them here — the duplicate they
    // landed on — via the editor's info banner.
    final tasksNoun = NamingUtils.tasksName(capitalize: false, plural: false);
    List<String>? initialLinks;
    String? infoMessage;
    if (incomingUrl.isEmpty) {
      // Matched by title alone (no incoming link).
      infoMessage = 'You already have this $tasksNoun, with the same title.';
    } else if (!alreadyHasLink) {
      // The task existed under this title but without the shared link — add it.
      final proposed = originalResult?.proposedTask;
      final newLinks = (proposed != null && proposed.links.isNotEmpty)
          ? proposed.links
          : ['<a href="$incomingUrl">${originalResult?.title ?? incomingUrl}</a>'];
      initialLinks = [...existingLinks, ...newLinks];
      infoMessage =
          'This $tasksNoun didn\'t have that link, so we added it below. Save to keep it.';
    } else {
      // The task already carries this exact link — that's the duplicate.
      infoMessage = 'You\'re already tracking this link on this $tasksNoun.';
    }

    final route = MaterialPageRoute(
      builder: (context) => TaskEditScreen(
        category: category,
        task: duplicate.task,
        initialLinks: initialLinks,
        infoMessage: infoMessage,
        showPursuitSelector: selectable.isNotEmpty,
        selectableCategories: selectable.isNotEmpty ? selectable : null,
      ),
    );
    // From within the New Task editor (headline paste) we replace it, so the
    // abandoned new task doesn't linger under the existing-task editor.
    if (replaceCurrentRoute) {
      Navigator.of(context).pushReplacement(route);
    } else {
      Navigator.of(context).push(route);
    }
  }

  /// Find an owned task whose headline matches [headline] (case-insensitive),
  /// as a [DuplicateMatch] for the duplicate dialog. Used as the title-based
  /// duplicate check, complementing the URL check in [findAllDuplicates].
  static Future<DuplicateMatch?> _findOwnedTaskByHeadline(
    String headline,
    String userId,
  ) async {
    final h = headline.trim();
    if (h.isEmpty) return null;
    try {
      final tasksResponse = await supabase
          .from('Tasks')
          .select('*, Categories!Tasks_category_id_fkey(*)')
          .eq('owner_id', userId)
          .ilike('headline', h)
          .limit(1);
      final rows = tasksResponse as List<dynamic>;
      if (rows.isEmpty) return null;
      final row = rows.first;
      final categoryData = row['Categories'];
      if (categoryData == null) return null;
      return DuplicateMatch(
        task: Task.fromJson(row),
        category: Category.fromJson(categoryData),
        matchingUrl: '',
        originalLinkText: '',
      );
    } catch (e) {
      print('IncomingLinkProcessor: Error in title duplicate lookup: $e');
      return null;
    }
  }

  /// Reusable single-line duplicate resolution, shared by the incoming-share
  /// flow and the New Task headline-paste flow (and, later, a Home paste
  /// action). Checks a URL duplicate first (precise), then a title duplicate,
  /// and on a hit shows the same Make New / Edit Old / Cancel dialog.
  ///
  /// Returns what the user decided so the caller can act in its own context:
  /// [SingleLineDupOutcome.handledExisting] (edited the existing task — caller
  /// should abandon its pending new task), [SingleLineDupOutcome.makeNew]
  /// (no duplicate, or user chose Make New — caller proceeds to create), or
  /// [SingleLineDupOutcome.cancelled].
  static Future<SingleLineDupOutcome> resolveSingleLineDuplicates(
    BuildContext context, {
    required String headline,
    String? url,
    String? ownerId,
    LinkProcessingResult? enriched,
    bool replaceCurrentRoute = false,
  }) async {
    final userId = ownerId ?? AuthUtils.getCurrentUserId();

    DuplicateMatch? match;
    if (url != null && url.isNotEmpty) {
      final normalized = _normalizeUrl(url) ?? url;
      final dups = await findAllDuplicates(normalized);
      if (dups.isNotEmpty) match = dups.first;
    }
    match ??= await _findOwnedTaskByHeadline(headline, userId);

    if (match == null) return SingleLineDupOutcome.makeNew;
    if (!context.mounted) return SingleLineDupOutcome.cancelled;

    final choice = await _showDuplicateOptionsDialog(context, match);
    if (!context.mounted) return SingleLineDupOutcome.cancelled;

    if (choice == 'edit') {
      // Carry the incoming URL into the edit flow so a HEADLINE-only match (the
      // existing task has the same title but not this link) still gets the
      // pasted link added. Without this, a headline match has matchingUrl='' and
      // no enriched result, so the link would be silently dropped.
      final effective = enriched ??
          (url != null && url.isNotEmpty
              ? LinkProcessingResult(
                  url: url,
                  title: headline,
                  description: null,
                  duplicates: const [],
                  hasValidMetadata: true,
                  proposedTask: null,
                )
              : null);
      await _openExistingTaskForEdit(context, match,
          originalResult: effective, replaceCurrentRoute: replaceCurrentRoute);
      return SingleLineDupOutcome.handledExisting;
    } else if (choice == 'new') {
      return SingleLineDupOutcome.makeNew;
    }
    return SingleLineDupOutcome.cancelled;
  }

  /// Show dialog with options for handling duplicate task
  static Future<String?> _showDuplicateOptionsDialog(
    BuildContext context,
    DuplicateMatch duplicate,
  ) async {
    if (!context.mounted) return null;

    return await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Similar ${NamingUtils.tasksName(capitalize: true, plural: false)} Found',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'There\'s a similar ${NamingUtils.tasksName(capitalize: false, plural: false)} already on file. Do you really want to create a new one, just edit the old one, or stand pat?',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    duplicate.task.headline,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'in ${duplicate.category.headline}',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop('new'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 20),
                    SizedBox(height: 2),
                    Text('Make\nNew',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, height: 1.1)),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop('edit'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.edit, size: 20),
                    SizedBox(height: 2),
                    Text('Edit\nOld',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, height: 1.1)),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop('done'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 226, 85, 85),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.close, size: 20),
                    SizedBox(height: 2),
                    Text('Cancel',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, height: 1.1)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Navigate to edit existing task and add new work to it
  static Future<void> _navigateToAddWorkToExistingTask(
    BuildContext context,
    Task existingTask,
    Category category,
    String workTitle,
    String url,
    String linkTitle,
  ) async {
    if (!context.mounted) return;

    try {
      print(
          'IncomingLinkProcessor: Adding work "$workTitle" to existing task "${existingTask.headline}"');

      // Prepare the new notes: append work title to existing notes
      final existingNotes = existingTask.notes ?? '';
      final newNotes =
          existingNotes.isEmpty ? workTitle : '$existingNotes\n$workTitle';

      // Prepare the new link to add to links array
      final newLink = '<a href="$url">$linkTitle</a>';

      // Navigate to TaskEditScreen with pre-filled data
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => TaskEditScreen(
            category: category,
            task: existingTask,
            initialNotes: newNotes,
            initialLinks: [
              ...existingTask.links ?? [],
              newLink,
            ],
          ),
        ),
      );
    } catch (e) {
      print(
          'IncomingLinkProcessor: Error navigating to add work to existing task: $e');
    }
  }

  /// Navigate to TaskEditScreen with artist/work pre-filled for new task
  static Future<void> _navigateToTaskEditScreenWithArtistWork(
    BuildContext context,
    LinkProcessingResult result,
    Category? defaultCategory,
    ArtistWorkInfo artistWorkInfo,
  ) async {
    if (!context.mounted) return;

    try {
      // Open the New Task editor directly with a pursuit selector on top
      // (ordered by sensibility, defaulting to the most sensible) instead of a
      // separate "choose a pursuit" step.
      final ordered = await _orderedOwnedFor(result);
      if (ordered.isEmpty || !context.mounted) return;
      await _openTaskEditScreenWithArtistWork(
          context, result, defaultCategory ?? ordered.first, artistWorkInfo,
          selectable: ordered);
    } catch (e) {
      print(
          'IncomingLinkProcessor: Error navigating to task edit screen with artist/work: $e');
    }
  }

  /// Open TaskEditScreen with artist as headline and work in notes
  static Future<void> _openTaskEditScreenWithArtistWork(
    BuildContext context,
    LinkProcessingResult result,
    Category category,
    ArtistWorkInfo artistWorkInfo, {
    List<Category>? selectable,
  }) async {
    try {
      print(
          'IncomingLinkProcessor: Opening TaskEditScreen with artist: ${artistWorkInfo.artist}, work: ${artistWorkInfo.work}');

      final proposed = result.proposedTask;

      // Create HTML link(s) from the result or proposed task
      final List<String> initialLinks =
          (proposed != null && proposed.links.isNotEmpty)
              ? proposed.links
              : ['<a href="${result.url}">${artistWorkInfo.work}</a>'];

      // Navigate to TaskEditScreen with artist as headline and work as notes
      final taskSaved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (context) => TaskEditScreen(
            category: category,
            initialLinks: initialLinks,
            initialHeadline: proposed?.headline ??
                artistWorkInfo.artist, // Artist as headline
            initialNotes:
                proposed?.notes ?? artistWorkInfo.work, // Work as notes
            showAlternativeOptions: false,
            showPursuitSelector: selectable != null,
            selectableCategories: selectable,
            allowAddToExisting: true, // offer redirect to an existing task
          ),
        ),
      );

      // Refresh cache if task was saved
      if (taskSaved == true) {
        final cacheManager = CacheManager();
        if (cacheManager.currentCategory?.id == category.id) {
          await cacheManager.refreshCurrentCategoryTasks();
        }
      }
    } catch (e) {
      print(
          'IncomingLinkProcessor: Error opening TaskEditScreen with artist/work: $e');
    }
  }

  /// Owned pursuits ordered by sensibility for [result] (suggested → recent →
  /// domain-relevant → rest), for the New Task editor's pursuit selector.
  static Future<List<Category>> _orderedOwnedFor(
      LinkProcessingResult result) async {
    final all = await ApiClient.getCategories();
    final owned = all.where((c) => !c.isShared).toList();
    final ordering = await orderCategoriesBySensibility(
      owned,
      suggestedOriginalIds: result.proposedTask?.suggestedCategoryOriginalIds,
      linkUrl: result.url,
    );
    return ordering.ordered;
  }

  /// Navigate to TaskEditScreen with the processed link data
  static Future<void> _navigateToTaskEditScreen(
    BuildContext context,
    LinkProcessingResult result,
    Category? defaultCategory, {
    bool forceCreate = false,
  }) async {
    if (!context.mounted) return;

    try {
      // Open the New Task editor directly with a pursuit selector on top
      // (ordered by sensibility, defaulting to the most sensible) — no separate
      // "choose a pursuit" step.
      final ordered = await _orderedOwnedFor(result);
      if (ordered.isEmpty || !context.mounted) return;
      await _openTaskEditScreen(
          context, result, defaultCategory ?? ordered.first,
          selectable: ordered, forceCreate: forceCreate);
    } catch (e) {
      print('IncomingLinkProcessor: Error navigating to task edit screen: $e');
    }
  }

  /// Open the TaskEditScreen with the specified category and result data
  static Future<void> _openTaskEditScreen(
    BuildContext context,
    LinkProcessingResult result,
    Category category, {
    List<Category>? selectable,
    bool forceCreate = false,
  }) async {
    try {
      print(
          'IncomingLinkProcessor: Opening TaskEditScreen with category: ${category.headline}');
      print('IncomingLinkProcessor: URL: ${result.url}');
      print('IncomingLinkProcessor: Title: ${result.title}');

      final proposed = result.proposedTask;

      // Create HTML link from the result
      final List<String> initialLinks =
          (proposed != null && proposed.links.isNotEmpty)
              ? proposed.links
              : [
                  result.hasValidMetadata && result.title != null
                      ? '<a href="${result.url}">${result.title}</a>'
                      : '<a href="${result.url}">${result.url}</a>'
                ];

      // Note: Synopsis will be auto-fetched by SynopsisFetcher when the task is viewed
      // We don't pre-populate it here to keep the initial task creation simple

      // Navigate to TaskEditScreen with initial data and await the result
      final taskSaved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (context) => TaskEditScreen(
            category: category,
            initialLinks: initialLinks,
            initialHeadline: proposed?.headline ?? result.title ?? 'New Task',
            initialNotes: proposed?.notes,
            showAlternativeOptions:
                false, // Hide bulk import options for single task
            showPursuitSelector: selectable != null,
            selectableCategories: selectable,
            forceCreate: forceCreate,
            allowAddToExisting: true, // offer redirect to an existing task
          ),
        ),
      );

      // If task was saved successfully, refresh the cache for the current category
      // This ensures that if we're on the HomeScreen showing this category,
      // it will display the newly added task
      if (taskSaved == true) {
        print(
            'IncomingLinkProcessor: Task saved successfully, checking if HomeScreen needs refresh...');
        final cacheManager = CacheManager();

        // Check if the saved task's category matches the current category on HomeScreen
        if (cacheManager.currentCategory?.id == category.id) {
          print(
              'IncomingLinkProcessor: Saved task is in current category (${category.headline}), refreshing HomeScreen...');
          await cacheManager.refreshCurrentCategoryTasks();
          print('IncomingLinkProcessor: HomeScreen cache refreshed');
        } else {
          print(
              'IncomingLinkProcessor: Saved task category (${category.headline}) does not match current category (${cacheManager.currentCategory?.headline}), no refresh needed');
        }
      } else {
        print(
            'IncomingLinkProcessor: Task not saved (user cancelled or error occurred)');
      }
    } catch (e) {
      print('IncomingLinkProcessor: Error opening TaskEditScreen: $e');
    }
  }

  /// Format suggestible time for display
  static String _formatSuggestibleTime(DateTime date) {
    final now = DateTime.now();
    final difference = date.difference(now);

    if (difference.isNegative) {
      return 'now';
    } else if (difference.inDays > 0) {
      return 'in ${difference.inDays} day${difference.inDays == 1 ? '' : 's'}';
    } else if (difference.inHours > 0) {
      return 'in ${difference.inHours} hour${difference.inHours == 1 ? '' : 's'}';
    } else {
      return 'in ${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'}';
    }
  }

  /// Revive a finished task (set finished to false and reset suggestible_at)
  static Future<void> _reviveTask(BuildContext context, Task task) async {
    try {
      print('IncomingLinkProcessor: Reviving task: ${task.headline}');

      // Update task to make it available again
      final updatedTaskData = {
        'finished': false,
        'suggestible_at': null,
      };

      await supabase.from('Tasks').update(updatedTaskData).eq('id', task.id);

      // Refresh cache
      await CacheManager().refreshCurrentCategoryTasks();

      print('IncomingLinkProcessor: Task revived successfully');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Task revived and made available'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('IncomingLinkProcessor: Error reviving task: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error reviving task: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Navigate to edit the existing task
  static Future<void> _editExistingTask(BuildContext context, Task task) async {
    try {
      print('IncomingLinkProcessor: Editing existing task: ${task.headline}');

      // We need to fetch the category for the task
      final categoryResponse = await supabase
          .from('Categories')
          .select()
          .eq('id', task.categoryId)
          .single();

      final category = Category.fromJson(categoryResponse);

      // Navigate to TaskEditScreen with the existing task
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => TaskEditScreen(
            category: category,
            task: task,
          ),
        ),
      );
    } catch (e) {
      print('IncomingLinkProcessor: Error navigating to edit task: $e');
    }
  }

  /// Create a new task anyway despite the duplicate
  static Future<void> _createNewTaskAnyway(
      BuildContext context, DuplicateMatch duplicate) async {
    try {
      print('IncomingLinkProcessor: Creating new task despite duplicate');

      // Navigate to TaskEditScreen to create a new task
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => TaskEditScreen(
            category: duplicate.category,
          ),
        ),
      );
    } catch (e) {
      print('IncomingLinkProcessor: Error creating new task: $e');
    }
  }

  /// Show task selection dialog for adding to existing task
  static Future<void> _showTaskSelectionDialog(
    BuildContext context,
    LinkProcessingResult result,
  ) async {
    // TODO: Implement task selection dialog
    print('IncomingLinkProcessor: TODO - Show task selection dialog');
  }

  /// Normalize URL for comparison (remove tracking parameters, etc.)
  static String? _normalizeUrl(String url) {
    try {
      // Use LinkToTaskConverter's normalization for consistency
      final normalized = LinkToTaskConverter.normalizeUrl(url);
      // Only log for IMDb URLs to reduce noise
      if (url.contains('imdb.com')) {
        print('IncomingLinkProcessor._normalizeUrl:');
        print('  Input:  $url');
        print('  Output: $normalized');
      }
      return normalized;
    } catch (e) {
      print('IncomingLinkProcessor: Error normalizing URL "$url": $e');
      return null;
    }
  }

  /// Extract URL from HTML link string
  static String? _extractUrlFromHtmlLink(String htmlLink) {
    final match = RegExp(r'<a[^>]+href="([^"]*)"').firstMatch(htmlLink);
    return match?.group(1);
  }

  /// Compare two URLs for matching (handles normalization)
  static bool _urlsMatch(String url1, String url2) {
    final normalized1 = _normalizeUrl(url1);
    final normalized2 = _normalizeUrl(url2);

    if (normalized1 == null || normalized2 == null) {
      print('IncomingLinkProcessor._urlsMatch: Normalization failed');
      print('  url1: $url1 -> $normalized1');
      print('  url2: $url2 -> $normalized2');
      return false;
    }

    final matches = normalized1 == normalized2;
    if (!matches) {
      // Only log mismatches for IMDb URLs to reduce noise
      if (url1.contains('imdb.com') || url2.contains('imdb.com')) {
        print('IncomingLinkProcessor._urlsMatch: URLs do NOT match');
        print('  url1: $url1');
        print('  normalized1: $normalized1');
        print('  url2: $url2');
        print('  normalized2: $normalized2');
      }
    }

    return matches;
  }

  /// Get the currently active category from cache/context
  static Category? getCurrentCategory() {
    // TODO: Implement cache-aware category detection
    return null;
  }

  /// Search for a task by title in categories whose original_id is in [suggestedOriginalIds].
  /// Returns (Task, Category) if exactly one match is found, otherwise null.
  static Future<(Task, Category)?> _findTaskByTitleInSuggestedCategories(
    String title,
    String userId,
    List<int> suggestedOriginalIds,
  ) async {
    try {
      print(
          'IncomingLinkProcessor: Searching for title "$title" in categories with original_ids $suggestedOriginalIds');

      final categoriesResponse =
          await supabase.from('Categories').select().eq('owner_id', userId);

      final categoriesData = categoriesResponse as List<dynamic>;

      final matchingCategories = categoriesData.where((catData) {
        final originalId = catData['original_id'] as int?;
        return originalId != null && suggestedOriginalIds.contains(originalId);
      }).toList();

      final matchingCategoryIds =
          matchingCategories.map((c) => c['id'] as int).toList();

      if (matchingCategoryIds.isEmpty) {
        print(
            'IncomingLinkProcessor: User has no categories matching original_ids $suggestedOriginalIds');
        return null;
      }

      final tasksResponse = await supabase
          .from('Tasks')
          .select()
          .eq('owner_id', userId)
          .inFilter('category_id', matchingCategoryIds)
          .ilike('headline', title);

      final tasksData = tasksResponse as List<dynamic>;

      print(
          'IncomingLinkProcessor: Found ${tasksData.length} task(s) matching title "$title"');

      if (tasksData.length == 1) {
        final task = Task.fromJson(tasksData[0]);
        final catData = matchingCategories
            .firstWhere((c) => c['id'] == task.categoryId);
        final category = Category.fromJson(catData);
        print(
            'IncomingLinkProcessor: Title match: "${task.headline}" in "${category.headline}"');
        return (task, category);
      } else if (tasksData.length > 1) {
        print(
            'IncomingLinkProcessor: Multiple title matches (${tasksData.length}), skipping');
      }
      return null;
    } catch (e) {
      print('IncomingLinkProcessor: Error searching by title: $e');
      return null;
    }
  }

  /// Search for a task by artist name in streaming media categories
  /// Returns exactly one task if found, otherwise null
  static Future<Task?> findTaskByArtistInStreamingCategories(
    String artist,
    String userId,
  ) async {
    try {
      print(
          'IncomingLinkProcessor: Searching for artist "$artist" in streaming media categories');

      // Get all user's categories to filter for streaming media ones
      final categoriesResponse =
          await supabase.from('Categories').select().eq('owner_id', userId);

      final categoriesData = categoriesResponse as List<dynamic>;

      // Filter to only streaming media category IDs
      final streamingCategoryIds = categoriesData
          .where((catData) {
            final originalId = catData['original_id'] as int?;
            return originalId != null &&
                STREAMING_MEDIA_CATEGORY_IDS.contains(originalId);
          })
          .map((catData) => catData['id'] as int)
          .toList();

      if (streamingCategoryIds.isEmpty) {
        print('IncomingLinkProcessor: User has no streaming media categories');
        return null;
      }

      print(
          'IncomingLinkProcessor: Searching in category IDs: $streamingCategoryIds');

      // Search for tasks with matching artist name (case-insensitive)
      final tasksResponse = await supabase
          .from('Tasks')
          .select()
          .eq('owner_id', userId)
          .inFilter('category_id', streamingCategoryIds)
          .ilike('headline', artist); // Exact match, case-insensitive

      final tasksData = tasksResponse as List<dynamic>;

      print(
          'IncomingLinkProcessor: Found ${tasksData.length} tasks matching artist "$artist"');

      // Return exactly one match, or null if not exactly one
      if (tasksData.length == 1) {
        final task = Task.fromJson(tasksData[0]);
        print(
            'IncomingLinkProcessor: Found exactly one matching task: "${task.headline}"');
        return task;
      } else if (tasksData.length > 1) {
        print(
            'IncomingLinkProcessor: Found multiple tasks (${tasksData.length}), not showing match dialog');
        return null;
      } else {
        print('IncomingLinkProcessor: No tasks found for this artist');
        return null;
      }
    } catch (e) {
      print('IncomingLinkProcessor: Error searching for artist: $e');
      return null;
    }
  }

  /// Show dialog asking if user wants to add to existing artist task or create new
  static Future<String?> _showArtistMatchDialog(
    BuildContext context,
    Task existingTask,
    Category category,
    String workTitle,
  ) async {
    if (!context.mounted) return null;

    return await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Found Existing Artist',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You already have a ${NamingUtils.tasksName(capitalize: false, plural: false)} for this artist:',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    existingTask.headline,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'in ${category.headline}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  if (existingTask.notes != null &&
                      existingTask.notes!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      existingTask.notes!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Would you like to add "$workTitle" to this ${NamingUtils.tasksName(capitalize: false, plural: false)}?',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('new'),
            child: const Text('Create New'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop('add'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[700],
              foregroundColor: Colors.white,
            ),
            child: const Text('Add to Existing'),
          ),
        ],
      ),
    );
  }
}

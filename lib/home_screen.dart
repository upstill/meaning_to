import 'package:flutter/material.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/utils/api_client.dart';
import 'package:meaning_to/utils/error_dialog.dart';
import 'package:meaning_to/utils/invite_token_store.dart';
import 'package:meaning_to/utils/pending_intent_store.dart';
import 'package:meaning_to/utils/incoming_link_processor.dart';
import 'package:meaning_to/utils/category_ordering.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:meaning_to/utils/cache_manager.dart';
import 'package:meaning_to/utils/link_processor.dart';
import 'package:meaning_to/task_edit_screen.dart';
import 'package:meaning_to/widgets/edit_category_dialog.dart';
import 'package:meaning_to/dialogs/category_picker_dialog.dart';
import 'package:meaning_to/my_shares_screen.dart';
import 'package:meaning_to/share_any_pursuits_screen.dart';
import 'package:meaning_to/snag_pursuit_screen.dart';
import 'dart:async';

import 'package:meaning_to/utils/naming.dart';
import 'package:meaning_to/utils/borrow_explanation.dart';
import 'package:meaning_to/utils/app_buttons.dart';
import 'package:meaning_to/utils/synopsis_fetcher.dart';
import 'package:meaning_to/utils/supabase_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'package:meaning_to/widgets/task_display.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:meaning_to/widgets/linkified_text.dart';
import 'package:meaning_to/widgets/pursuit_switcher_sheet.dart';
import 'package:meaning_to/dialogs/allowed_senders_dialog.dart';
import 'package:meaning_to/utils/pending_channel_store.dart';

enum HomeTaskSortOption { alphabetical, priority, age }

class HomeScreen extends StatefulWidget {
  static final ValueNotifier<bool> needsTaskReload = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> needsDataReload = ValueNotifier<bool>(false);
  // Toggled when an incoming link intent (native share / extension) is stashed
  // while Home is already open, so it's processed promptly.
  static final ValueNotifier<bool> needsIntentProcessing =
      ValueNotifier<bool>(false);

  final String? initialCategoryId;

  const HomeScreen({super.key, this.initialCategoryId});

  @override
  HomeScreenState createState() => HomeScreenState();

  // Static variable to track if data has been modified
  static bool _dataModified = false;

  // Method to mark that data has been modified (call from other screens)
  static void markDataModified() {
    _dataModified = true;
    needsDataReload.value = true; // Notify listeners
  }

  // Method to check and reset the modified flag
  static bool checkAndResetDataModified() {
    final wasModified = _dataModified;
    _dataModified = false;
    return wasModified;
  }
}

/// Direct in-app sharing between users (the email-gated "accept future shares"
/// channel and the "Send To User" picker) is held back pending a minor-safety
/// design. Set true to re-enable; the machinery is left in place.
const bool kDirectSharingEnabled = false;

class HomeScreenState extends State<HomeScreen> {
  List<Category> _categories = [];
  Category? _selectedCategory;
  Task? _randomTask;
  bool _showTaskListMode = false;
  final TextEditingController _taskSearchController = TextEditingController();
  HomeTaskSortOption _taskListSortOption = HomeTaskSortOption.priority;
  bool _isSearchingTasks = false;
  bool _isTaskListSorting = false;
  List<Task> _listModeTasks = <Task>[];
  bool _isListModeLoading = false;
  bool _isListProgressiveLoading = false;
  int _visibleTaskCount = 0;
  static const int _initialListTaskCount = 16;
  static const int _listBatchSize = 24;
  Set<int> _snaggedOriginalIds = {}; // original_ids of tasks user already snagged
  bool _isLoading = true;
  bool _isLoadingTask = false;
  String? _error;
  bool _isReloading = false; // Guard to prevent concurrent reloads
  // Synopsis fetching state
  bool _isFetchingSynopsis = false;
  String? _fetchedSynopsis;

  // Non-null while edit panel is open
  Task? _editingTask;

  // CacheManager instance for managing current category and tasks
  final CacheManager _cacheManager = CacheManager();

  // Add getter for selected category
  Category? get selectedCategory => _selectedCategory;

  // True when viewing a shared (read-only) category
  bool get _isReadOnly => _selectedCategory?.isShared ?? false;

  // Non-null when a guest is previewing a share link's pursuits (its link id);
  // the preview's tasks are read via an anon RPC since RLS hides them otherwise.
  String? _guestPreviewLinkId;

  // Track if welcome dialog has been shown
  bool _welcomeDialogShown = false;
  // True while the "Welcome to RouzMe" dialog is pending/open, so the
  // new-shares advisory holds back until the greeting is dismissed.
  bool _welcomeDialogOpen = false;

  // Count of pending (unavailable) shared-with-me categories, shown on empty home screen

  // Track if this is the first load (to handle initial category selection from deep link)
  bool _isFirstLoad = true;

  // Inline search state
  bool _isSearchMode = false;
  bool _isShowingResults = false;
  late final TextEditingController _findController;
  List<Task> _findResults = [];
  bool _isFindSearching = false;
  Timer? _findDebounceTimer;

  /// Build AppBar actions
  List<Widget> _buildAppBarActions() {
    final actions = <Widget>[];

    if (_isSearchMode) {
      actions.add(
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: _closeSearch,
          tooltip: 'Cancel search',
        ),
      );
      return actions;
    }

    // Search button - always show
    actions.add(
      IconButton(
        icon: const Icon(Icons.search),
        onPressed: () {
          setState(() {
            _isSearchMode = true;
            _isShowingResults = false;
            _findResults = [];
            _findController.clear();
          });
        },
        tooltip: 'Search',
      ),
    );

    // Help button - always show
    actions.add(
      IconButton(
        icon: const _HelpIcon(size: 22),
        onPressed: () {
          Navigator.pushNamed(context, '/help');
        },
        tooltip: 'Help',
      ),
    );

    // Account menu - always show
    actions.add(
      Builder(
        builder: (context) => IconButton(
          icon: const Icon(Icons.menu),
          tooltip: 'Account',
          onPressed: () async {
            final RenderBox button = context.findRenderObject()! as RenderBox;
            final RenderBox overlay = Navigator.of(context)
                .overlay!
                .context
                .findRenderObject()! as RenderBox;
            final position = RelativeRect.fromRect(
              Rect.fromPoints(
                button.localToGlobal(Offset.zero, ancestor: overlay),
                button.localToGlobal(button.size.bottomRight(Offset.zero),
                    ancestor: overlay),
              ),
              Offset.zero & overlay.size,
            );
            final value = await showMenu<String>(
              context: context,
              position: position,
              items: [
                PopupMenuItem<String>(
                  enabled: false,
                  child: Text(
                    AuthUtils.getCurrentUserEmail(),
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                const PopupMenuDivider(),
                // Always available (even before any Pursuit is selected) so new
                // users can reach the Pursuits seeded into Shared With Me.
                if (!AuthUtils.isGuestUser())
                  const PopupMenuItem<String>(
                    value: 'shared_with_me',
                    child: ListTile(
                      leading: Icon(Icons.people_alt_outlined),
                      title: Text('Shared With Me'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                if (kDirectSharingEnabled && !AuthUtils.isGuestUser())
                  const PopupMenuItem<String>(
                    value: 'allowed_senders',
                    child: ListTile(
                      leading: Icon(Icons.mark_email_read_outlined),
                      title: Text('Who Can Send Me Things'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                if (_selectedCategory != null) ...[
                  PopupMenuItem<String>(
                    value: 'add_pursuit',
                    // Guests can't create their own pursuits — show it disabled.
                    enabled: !AuthUtils.isGuestUser(),
                    child: ListTile(
                      enabled: !AuthUtils.isGuestUser(),
                      leading: const Icon(Icons.add),
                      title: Text(
                          'New ${NamingUtils.categoriesName(capitalize: true, plural: false)}'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  if (!_isReadOnly)
                    PopupMenuItem<String>(
                      value: 'edit_pursuit',
                      child: ListTile(
                        leading: const Icon(Icons.edit),
                        title: Text(
                            'Edit ${NamingUtils.categoriesName(capitalize: true, plural: false)}'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  if (!_isReadOnly)
                    PopupMenuItem<String>(
                      value: 'share_pursuit',
                      child: ListTile(
                        leading: const Icon(Icons.share),
                        title: const Text('Share this Pursuit'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  if (!AuthUtils.isGuestUser())
                    const PopupMenuItem<String>(
                      value: 'share_out',
                      child: ListTile(
                        leading: Icon(Icons.ios_share),
                        title: Text('Share Any Pursuit(s)'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  if (!_isReadOnly)
                    PopupMenuItem<String>(
                      value: 'delete_pursuit',
                      child: ListTile(
                        leading: const Icon(Icons.delete, color: Colors.red),
                        title: Text(
                          'Delete ${NamingUtils.categoriesName(capitalize: true, plural: false)}',
                          style: const TextStyle(color: Colors.red),
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  if (_isReadOnly && !AuthUtils.isGuestUser())
                    PopupMenuItem<String>(
                      value: 'snag_all',
                      child: ListTile(
                        leading: const Icon(Icons.library_add_outlined),
                        title: Text(
                            'Snag this ${NamingUtils.categoriesName(capitalize: true, plural: false)}'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  if (_isReadOnly && !AuthUtils.isGuestUser())
                    const PopupMenuItem<String>(
                      value: 'release',
                      child: ListTile(
                        leading: Icon(Icons.link_off, color: Colors.red),
                        title: Text(
                          'Release this Pursuit',
                          style: TextStyle(color: Colors.red),
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  const PopupMenuDivider(),
                ],
                const PopupMenuItem<String>(
                  value: 'privacy',
                  child: ListTile(
                    leading: Icon(Icons.privacy_tip_outlined),
                    title: Text('Privacy Policy'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'logout',
                  child: ListTile(
                    leading: Icon(Icons.logout),
                    title: Text('Logout'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                if (!AuthUtils.isGuestUser())
                  const PopupMenuItem<String>(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_forever, color: Colors.red),
                      title: Text('Delete Account',
                          style: TextStyle(color: Colors.red)),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
              ],
            );
            if (value == 'privacy') {
              await openUrlExternal('https://rouzme.com/privacy');
            }
            if (value == 'allowed_senders') {
              await AllowedSendersDialog.show(context);
            }
            if (value == 'logout') await _handleLogout();
            if (value == 'delete') await _handleDeleteAccount();
            if (value == 'add_pursuit') _navigateToNewCategory();
            if (value == 'edit_pursuit' && _selectedCategory != null) {
              final updated = await showDialog<Category>(
                context: context,
                builder: (_) =>
                    EditCategoryDialog(category: _selectedCategory!),
              );
              if (updated != null) await _loadCategories();
            }
            if (value == 'share_pursuit' && _selectedCategory != null) {
              await _shareCategory(_selectedCategory!);
              await _loadTaskListDataInBackground();
            }
            if (value == 'share_out') {
              await ShareAnyPursuitsScreen.show(context, _categories);
              if (mounted) _loadCategories();
            }
            if (value == 'shared_with_me') {
              await MySharesScreen.show(
                context,
                _categories,
                (cat) async {
                  await _handleCategorySelection(cat);
                },
                onRefresh: _loadCategories,
              );
              if (mounted) _loadCategories();
            }
            if (value == 'delete_pursuit' && _selectedCategory != null) {
              _deleteCategory(_selectedCategory!);
            }
            if (value == 'snag_all' && _selectedCategory != null) {
              unawaited(_showSnagPursuitScreen(_selectedCategory!));
            }
            if (value == 'release' && _selectedCategory != null) {
              _releaseSharedCategory(_selectedCategory!);
            }
          },
        ),
      ),
    );

    return actions;
  }

  void _onFindChanged(String value) {
    _findDebounceTimer?.cancel();
    if (value.trim().isEmpty && _isShowingResults) {
      setState(() {
        _isShowingResults = false;
        _findResults = [];
      });
    }
  }

  void _submitSearch() {
    final query = _findController.text.trim();
    if (query.isEmpty) return;
    setState(() => _isShowingResults = true);
    _performFind();
  }

  Future<void> _performFind() async {
    final query = _findController.text.trim();
    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _findResults = [];
          _isFindSearching = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _isFindSearching = true);
    try {
      final tasks = await ApiClient.searchTasksByHeadline(query);
      if (mounted) {
        setState(() {
          _findResults = tasks;
          _isFindSearching = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isFindSearching = false);
    }
  }

  void _closeSearch() {
    setState(() {
      _isSearchMode = false;
      _isShowingResults = false;
      _findResults = [];
      _findController.clear();
    });
  }

  Widget _buildFindResults() {
    final Map<int, List<Task>> tasksByCategory = {};
    for (final task in _findResults) {
      tasksByCategory.putIfAbsent(task.categoryId, () => []).add(task);
    }
    final Map<int, Category> categoryMap = {
      for (final cat in _categories) cat.id: cat
    };

    if (_isFindSearching) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Searching...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (_findController.text.trim().isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Enter a search term to find tasks',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    if (_findResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('No tasks found',
                style: TextStyle(fontSize: 16, color: Colors.grey[600])),
            const SizedBox(height: 8),
            Text('Try a different search term',
                style: TextStyle(fontSize: 14, color: Colors.grey[500])),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: tasksByCategory.length,
      itemBuilder: (context, index) {
        final categoryId = tasksByCategory.keys.elementAt(index);
        final category = categoryMap[categoryId];
        final tasks = tasksByCategory[categoryId]!;
        if (category == null) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: InkWell(
                onTap: () {
                  final query = _findController.text.trim();
                  _taskSearchController.text = query;
                  _showTaskListMode = true;
                  _closeSearch();
                  _handleCategorySelection(category);
                },
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        category.headline,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios,
                        size: 16, color: Colors.grey),
                  ],
                ),
              ),
            ),
            ...tasks.map(
              (task) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: TaskDisplay(
                  key: ValueKey('find-task-${task.id}'),
                  task: task,
                  withControls: true,
                  onEdit: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            TaskEditScreen(category: category, task: task),
                      ),
                    );
                    _performFind();
                  },
                  onDelete: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete Task'),
                        content: Text('Delete "${task.headline}"?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await ApiClient.deleteTask(task.id.toString());
                      _performFind();
                    }
                  },
                  onTap: () async {
                    await ApiClient.updateTaskFinished(task.id, !task.finished);
                    _performFind();
                  },
                  onUpdateSuggestibleAt: (DateTime newTime) async {
                    await ApiClient.updateTaskSuggestibleAt(
                        task.id, newTime.toIso8601String());
                    _performFind();
                  },
                  onShareToggle: (bool newSharedState) async {
                    await ApiClient.updateTaskShared(task.id, newSharedState);
                    _performFind();
                  },
                  isCategoryPrivate: category.isPrivate,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  /// Handle logout action
  Future<void> _handleLogout() async {
    await AuthUtils.signOut();
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/');
    }
  }

  /// Handle delete account action
  Future<void> _handleDeleteAccount() async {
    // Show confirmation dialog
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.warning, color: Colors.red, size: 32),
              const SizedBox(width: 8),
              const Text('Delete Account'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                () {
                  final email = '...of ${AuthUtils.getCurrentUserEmail()}';
                  final name = Supabase.instance.client.auth.currentUser
                      ?.userMetadata?['display_name'] as String?;
                  return (name != null && name.isNotEmpty)
                      ? '$email ($name)'
                      : email;
                }(),
                style: const TextStyle(
                    fontSize: 18,
                    color: Colors.grey,
                    fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 12),
              const Text(
                'WARNING: This action cannot be undone!',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Deleting your account will permanently remove:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('• All your tasks'),
              const Text('• All your categories'),
              const Text('• Your user account'),
              const SizedBox(height: 16),
              const Text(
                'This data cannot be recovered.',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete My Account'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _deleteAccountData();
    }
  }

  /// Delete all user data and account
  Future<void> _deleteAccountData() async {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Deleting account...'),
            ],
          ),
        );
      },
    );

    try {
      // Full deletion happens server-side in delete_user(): it removes the user's
      // Tasks and Categories (the only NO ACTION foreign keys to auth.users) and
      // then the auth.users row itself — everything else (their subscriptions,
      // share links, invitations, sessions) cascades. Any failure propagates to
      // the catch below so it isn't silently ignored.
      await supabase.rpc('delete_user');

      // Discard any pending invite so the post-delete welcome screen shows the
      // normal greeting, not a stale "you've been invited" message.
      await InviteTokenStore.clear();

      // Sign out
      await AuthUtils.signOut();

      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        Navigator.pushReplacementNamed(context, '/');
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Error'),
              content: Text('Failed to delete account: $e'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _findController = TextEditingController();
    print('HomeScreen: initState called');
    // Listen for task reload requests
    HomeScreen.needsTaskReload.addListener(_handleTaskReloadRequest);
    // Listen for data reload requests (categories and tasks)
    HomeScreen.needsDataReload.addListener(_handleDataReloadRequest);
    // Process an incoming link intent that arrives while Home is already open.
    HomeScreen.needsIntentProcessing.addListener(_handleIntentProcessingRequest);

    // Load categories after first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Load categories FIRST: on first login this shows the "Welcome to
      // RouzMe" greeting, detected from the pre-redeem state (an unredeemed
      // account has no shares yet). THEN redeem any pending share link — the
      // single reliable choke point that redeems exactly once on every arrival
      // at Home (already logged in, post-sign-in/up, post-OAuth). The new-shares
      // advisory is deferred until after the greeting: for a first-login user it
      // fires when the welcome dialog is dismissed; otherwise it fires here.
      await _loadCategories();
      await _redeemPendingShareIfAny();
      if (mounted && !_welcomeDialogShown) _maybeNotifyNewShares();
      if (mounted) await _maybeProcessPendingIntent();
    });
  }

  /// Redeems a share/invite token stashed in [InviteTokenStore] (from following
  /// a share link) now that we've reached an authenticated Home. Idempotent —
  /// the underlying RPC uses ON CONFLICT DO NOTHING — and clears the token so it
  /// only fires once. No-op for guests / no session, so a "Continue as Guest"
  /// user keeps the token stashed until they actually sign up.
  Future<void> _redeemPendingShareIfAny() async {
    if (AuthUtils.isGuestUser()) return;
    final token = await InviteTokenStore.get();
    if (token == null) return;
    try {
      await ApiClient.redeemPending(token);
    } catch (e) {
      print('Error redeeming pending share at home: $e');
      if (mounted) {
        await showErrorDialog(
          context,
          'Could not accept the shared pursuit(s):\n\n$e',
          title: 'Could not accept invitation',
        );
      }
    }
    await InviteTokenStore.clear();
    if (mounted) _loadCategories();
  }

  /// From the "Send to RouzMe" browser extension: if a page (url + title) was
  /// stashed via ?addlink=, show the normal "add this link" picker with the
  /// title pre-filled so no page fetch is needed. Real signed-in users only.
  /// [targetCategory], when set (the pursuit the user just created for this
  /// task), files the task straight in — no picker.
  Future<void> _maybeProcessPendingIntent({Category? targetCategory}) async {
    if (AuthUtils.isGuestUser()) return;
    final pending = await PendingIntentStore.get();
    if (pending == null) return;
    final title = pending.title.isEmpty ? null : pending.title;
    final owned = _categories.where((c) => !c.isShared).toList();

    // A pursuit was created specifically for this task → file straight in.
    if (targetCategory != null) {
      await PendingIntentStore.clear();
      if (!mounted) return;
      await _fileIntentInto(pending.url, title, targetCategory);
      return;
    }

    // No pursuit of their own yet. On first login the Welcome dialog's "Create
    // a Pursuit" flow handles it (leave the link stashed until they've made one,
    // then _navigateToNewCategory re-runs with a target). On a later visit no
    // Welcome shows, so prompt here rather than silently dropping the share.
    if (owned.isEmpty) {
      if (_welcomeDialogShown) return; // Welcome is driving the create flow
      if (!mounted) return;
      final choice = await _confirmCreatePursuitForIntent(title);
      if (!mounted) return;
      if (choice == 'create') {
        _navigateToNewCategory(); // keeps stash; re-runs with a target on return
      } else {
        await PendingIntentStore.clear();
      }
      return;
    }

    // Otherwise (one pursuit or many) → the uniform New Task editor: a pursuit
    // selector on top defaulting to the most sensible pursuit, where the user
    // edits the title/links and confirms or cancels.
    await PendingIntentStore.clear();
    if (!mounted) return;
    await _fileIntentInto(pending.url, title, null);
  }

  /// A taken link arrived but the user has no pursuit of their own to file it
  /// into (and no first-login Welcome is driving the create flow). Prompt to
  /// create one; returns 'create' or null.
  Future<String?> _confirmCreatePursuitForIntent(String? taskTitle) {
    final pursuitName =
        NamingUtils.categoriesName(plural: false, capitalize: true);
    final label =
        (taskTitle == null || taskTitle.isEmpty) ? 'this link' : '"$taskTitle"';
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Create a $pursuitName'),
        content: Text(
            'To save $label you need a $pursuitName to put it in. Create one now?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Not now'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(ctx).pop('create'),
            icon: const Icon(Icons.add),
            label: Text('New $pursuitName'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[700],
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// Opens the uniform New Task editor for a taken link, defaulting the pursuit
  /// selector to [defaultCategory] (or the most sensible pursuit when null),
  /// then refreshes Home so a saved task shows immediately.
  Future<void> _fileIntentInto(
      String url, String? title, Category? defaultCategory) async {
    await IncomingLinkProcessor.showLinkActionDialog(context, url,
        defaultCategory: defaultCategory, preTitle: title);
    if (mounted) _handleEditComplete();
  }

  // New-shares notification state. Shown on Home and on key control hits; the
  // session guard avoids re-popping the same shares after the user picks "Later".
  final Set<int> _notifiedShareIds = {};
  bool _shareDialogOpen = false;
  DateTime? _lastShareCheck;

  /// Surface pursuits newly shared with this user (unseen) that we haven't
  /// already notified about this session. Called on Home load and on key
  /// control hits (Hit Me, pursuit selector, task-list toggle) so a share that
  /// arrives mid-session shows up promptly without needing a realtime channel.
  Future<void> _maybeNotifyNewShares() async {
    // Hold back while the first-login greeting is pending/open — it re-fires this
    // when the welcome dialog is dismissed, so "Welcome to RouzMe" comes first.
    if (AuthUtils.isGuestUser() || _shareDialogOpen || _welcomeDialogOpen) return;
    // Light throttle so rapid control hits don't hammer the database.
    final now = DateTime.now();
    if (_lastShareCheck != null &&
        now.difference(_lastShareCheck!) < const Duration(seconds: 8)) {
      return;
    }
    _lastShareCheck = now;

    final unseen = await ApiClient.getUnseenShares();
    if (!mounted || unseen.isEmpty) return;
    if (!unseen.any((c) => !_notifiedShareIds.contains(c.id))) return;
    _notifiedShareIds.addAll(unseen.map((c) => c.id));

    // If these shares came from following a link, check whether the sender
    // invited THIS user's email — drives the "also take future shares" checkbox
    // (on a match) or an advisory (invited, but a different email).
    final pendingLink = await PendingChannelStore.get();
    final channel = pendingLink == null
        ? null
        : await ApiClient.shareChannelStatus(pendingLink);
    if (!mounted) return;
    bool acceptChannel = false; // checkbox state (default off)

    // Show the first two, then "…and N more" — but never a lonely "…and 1
    // more"; if only one would be hidden, just list it too.
    final shownCount = (unseen.length - 2 == 1) ? unseen.length : 2;
    final shown = unseen.take(shownCount).toList();
    final extra = unseen.length - shown.length;
    final n = unseen.length;
    // If every share is from the same owner, name them in the header and drop
    // the per-pursuit "from …".
    final owners = unseen.map((c) => c.ownerName).whereType<String>().toSet();
    final singleOwner = owners.length == 1 ? owners.first : null;
    // "a Pursuit" for one, "N pursuits" for several.
    final countPhrase = n == 1
        ? 'a ${NamingUtils.categoriesName(capitalize: true, plural: false)}'
        : '$n ${NamingUtils.categoriesName(capitalize: false, plural: true)}';
    final title = singleOwner != null
        ? '$singleOwner wants to share $countPhrase with you'
        : '${countPhrase[0].toUpperCase()}${countPhrase.substring(1)} shared with you';

    _shareDialogOpen = true;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: StatefulBuilder(
          builder: (ctx, setInner) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final c in shown)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: '•  ${c.headline}'),
                        if (singleOwner == null && c.ownerName != null)
                          TextSpan(
                            text: '  — from ${c.ownerName}',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                      ],
                    ),
                  ),
                ),
              if (extra > 0)
                Text('…and $extra more',
                    style: const TextStyle(color: Colors.grey)),
              // Direct-send consent, only when the link carried invite emails.
              // Held back for now (kDirectSharingEnabled) pending minor safety.
              if (kDirectSharingEnabled &&
                  channel != null &&
                  channel.hasInvites) ...[
                const Divider(height: 20),
                if (channel.emailMatches)
                  CheckboxListTile(
                    value: acceptChannel,
                    onChanged: (v) =>
                        setInner(() => acceptChannel = v ?? false),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      'Also let ${channel.creatorName} send me '
                      '${NamingUtils.categoriesName(plural: true)} directly '
                      'in the future.',
                      style: const TextStyle(fontSize: 13),
                    ),
                  )
                else
                  Text(
                    '${channel.creatorName} tried to enable direct shares to '
                    'you, but for a different email. To allow that, have them '
                    'invite the email on this account.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await ApiClient.markSharesSeen();
              await PendingChannelStore.clear();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text(
                      'You can always see them by selecting "Shared With Me" on the home menu.'),
                ));
              }
            },
            child: const Text('Pass'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              for (final c in unseen) {
                await ApiClient.setSharedCategoryAvailable(c.id, true);
              }
              await ApiClient.markSharesSeen();
              // Open the direct-send channel if the user ticked the box.
              if (acceptChannel && pendingLink != null) {
                try {
                  await ApiClient.acceptShareChannel(pendingLink);
                } catch (e) {
                  print('Error accepting share channel: $e');
                }
              }
              await PendingChannelStore.clear();
              if (mounted) {
                await _loadCategories();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(
                      n == 1
                          ? "It's been added to your ${NamingUtils.categoriesName(plural: true, capitalize: true)}, but it's read-only."
                          : "They've been added to your ${NamingUtils.categoriesName(plural: true, capitalize: true)}, but they're read-only."),
                ));
              }
            },
            child: Text(n == 1 ? 'Accept' : 'Accept all'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              if (acceptChannel && pendingLink != null) {
                try {
                  await ApiClient.acceptShareChannel(pendingLink);
                } catch (e) {
                  print('Error accepting share channel: $e');
                }
              }
              await PendingChannelStore.clear();
              await MySharesScreen.show(
                context,
                _categories,
                (cat) async {
                  await _handleCategorySelection(cat);
                },
                onRefresh: _loadCategories,
                // Open the notifying sharer(s)' group(s) expanded.
                expandOwners:
                    unseen.map((c) => c.ownerName ?? 'Someone').toSet(),
              );
              if (mounted) _loadCategories();
            },
            child: const Text('Show Me'),
          ),
        ],
      ),
    );
    _shareDialogOpen = false;
  }

  /// Select the initial category if one was provided
  void _selectInitialCategory() {
    print(
        '_selectInitialCategory called with initialCategoryId: ${widget.initialCategoryId}');
    print('Categories available: ${_categories.length}');
    if (widget.initialCategoryId != null && _categories.isNotEmpty) {
      try {
        final categoryId = int.parse(widget.initialCategoryId!);
        print('Parsed category ID: $categoryId');
        print('Looking for category with ID: $categoryId');

        final category = _categories.firstWhere(
          (c) => c.id == categoryId,
          orElse: () => _categories.first,
        );

        print('Found category: ${category.headline} (ID: ${category.id})');

        if (category.id == categoryId) {
          print('Setting selected category to: ${category.headline}');
          setState(() {
            _selectedCategory = category;
          });
          _loadRandomTask(category);
          // Update last_access for the selected category
          _updateCategoryLastAccess(category);
        } else {
          print(
              'Category ID mismatch - expected: $categoryId, got: ${category.id}');
        }
      } catch (e) {
        print('Error parsing category ID: ${widget.initialCategoryId} - $e');
      }
    } else {
      print('No initial category ID or no categories available');
    }
  }

  @override
  void dispose() {
    HomeScreen.needsTaskReload.removeListener(_handleTaskReloadRequest);
    HomeScreen.needsDataReload.removeListener(_handleDataReloadRequest);
    HomeScreen.needsIntentProcessing
        .removeListener(_handleIntentProcessingRequest);
    _taskSearchController.dispose();
    _findController.dispose();
    _findDebounceTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Check if data was modified by other screens
    final dataModified = HomeScreen.checkAndResetDataModified();

    // Refresh cache when dependencies change (e.g., when returning from other screens)
    if (_selectedCategory != null) {
      _refreshCacheIfNeeded(forceDatabaseRefresh: dataModified);
    } else if (dataModified) {
      // If no category is selected but data was modified (e.g., new categories imported),
      // reload categories to pick up the new data
      print(
          'HomeScreen: No category selected but data was modified, reloading categories');
      _loadCategories();
    }
  }

  /// Smart refresh that can skip database calls when appropriate
  Future<void> _refreshCacheIfNeeded(
      {bool forceDatabaseRefresh = false}) async {
    // Guard: Skip if already reloading
    if (_isReloading) {
      print(
          'HomeScreen: Reload already in progress, skipping _refreshCacheIfNeeded');
      return;
    }

    _isReloading = true;
    try {
      final cacheManager = CacheManager();
      final currentTaskId = _randomTask?.id;

      if (cacheManager.currentCategory?.id != _selectedCategory!.id ||
          cacheManager.currentTasks == null) {
        print(
          'HomeScreen: Refreshing cache for category ${_selectedCategory!.headline}',
        );
        await _loadRandomTask(_selectedCategory!);
      } else {
        print(
          'HomeScreen: Cache is up to date for category ${_selectedCategory!.headline}',
        );

        if (forceDatabaseRefresh) {
          // Force refresh from database to ensure we have the latest data
          await cacheManager.refreshFromApi();
          print('HomeScreen: Forced database refresh completed');
        } else {
          // Use local cache refresh for better performance
          cacheManager.refreshLocalCache();
          print('HomeScreen: Local cache refresh completed');
        }

        // Check if the current task still exists before reloading
        if (currentTaskId != null) {
          final currentTaskStillExists = cacheManager.currentTasks?.any(
                (task) => task.id == currentTaskId && !task.finished,
              ) ??
              false;

          if (currentTaskStillExists) {
            // Current task still exists - just update it in case it was modified
            final updatedTask = cacheManager.currentTasks!.firstWhere(
              (task) => task.id == currentTaskId,
            );

            print('HomeScreen: Current task still valid, keeping it displayed');
            if (mounted) {
              setState(() {
                _randomTask = updatedTask;
                // Also refresh the task list view if it's visible
                if (_showTaskListMode) {
                  _rebuildTaskListFromCache();
                }
              });
            }
            return; // Don't load a new random task
          }
        }

        // Only reload the random task if current one doesn't exist or was finished
        await _loadRandomTask(_selectedCategory!);
      }
    } finally {
      _isReloading = false;
    }
  }

  Future<void> _loadRandomTask(Category category) async {
    print(
      'HomeScreen: Starting to load random task for category: ${category.headline}',
    );
    try {
      setState(() {
        _isLoadingTask = true;
        _error = null;
      });

      final userId = AuthUtils.getCurrentUserId();
      print(
        'HomeScreen: Using user ID: $userId (guest: ${AuthUtils.isGuestUser()})',
      );

      // Initialize CacheManager with the selected category
      if (!_cacheManager.isInitialized ||
          _cacheManager.currentCategory?.id != category.id) {
        print(
          'HomeScreen: Initializing CacheManager with category: ${category.headline}',
        );
        await _cacheManager.initializeWithSavedCategory(category, userId);
      }

      // Get a random unfinished task from the cache
      final task = _cacheManager.getRandomUnfinishedTask();
      print('HomeScreen: Task loaded: \'${task?.headline}\'');

      if (mounted) {
        setState(() {
          _randomTask = task;
          _isLoadingTask = false;
          _fetchedSynopsis = null; // Reset fetched synopsis for new task
        });
        print('HomeScreen: State updated with new task');

        // Try to fetch synopsis if the task has no synopsis but has links
        if (_shouldFetchNotes()) {
          _fetchSynopsisFromLinks();
        }
      } else {
        print('HomeScreen: Widget not mounted after loading task');
      }
    } catch (e) {
      print('HomeScreen: Error loading random task: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoadingTask = false;
        });
      }
      rethrow;
    }
  }

  Widget _buildViewToggle() {
    final toggleButtons = ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () {
              if (_showTaskListMode) _toggleTaskListMode();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13),
              height: 35,
              color: !_showTaskListMode ? Colors.green : Colors.grey.shade400,
              alignment: Alignment.center,
              child: const Text(
                '—',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          Container(width: 1, height: 35, color: Colors.grey.shade300),
          GestureDetector(
            onTap: () {
              if (!_showTaskListMode) _toggleTaskListMode();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13),
              height: 35,
              color: _showTaskListMode ? Colors.blue : Colors.grey.shade400,
              alignment: Alignment.center,
              child: const Icon(
                Icons.menu,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );

    if (!_showTaskListMode) return toggleButtons;

    // In list mode, drop the search box onto its own full-width row below.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(alignment: Alignment.centerLeft, child: toggleButtons),
        const SizedBox(height: 8),
        _buildTaskSearchField(),
      ],
    );
  }

  Widget _buildTaskSearchField() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 35,
        color: Colors.blue,
        child: TextField(
          controller: _taskSearchController,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
          ),
          decoration: InputDecoration(
            hintText:
                'Search ${_listModeTasks.length} ${NamingUtils.tasksName(capitalize: false, plural: _listModeTasks.length != 1)}',
            hintStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 14,
            ),
            prefixIcon: Icon(
              Icons.search,
              size: 18,
              color: Colors.white.withValues(alpha: 0.7),
            ),
            suffixIcon: _isSearchingTasks
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  )
                : _taskSearchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          Icons.clear,
                          size: 18,
                          color: Colors.white,
                        ),
                        onPressed: () {
                          setState(() {
                            _taskSearchController.clear();
                            _rebuildTaskListFromCache();
                          });
                        },
                      )
                    : null,
            border: InputBorder.none,
            isCollapsed: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 8,
            ),
          ),
          cursorColor: Colors.white,
          onChanged: (_) {
            setState(() {
              _isSearchingTasks = true;
              _rebuildTaskListFromCache();
            });
            Future.delayed(const Duration(milliseconds: 250), () {
              if (mounted) {
                setState(() {
                  _isSearchingTasks = false;
                });
              }
            });
          },
        ),
      ),
    );
  }

  void _toggleTaskListMode() {
    if (_selectedCategory == null) {
      return;
    }

    final turningOn = !_showTaskListMode;
    setState(() {
      _showTaskListMode = turningOn;
    });

    unawaited(_maybeNotifyNewShares());

    if (turningOn) {
      _rebuildTaskListFromCache();
      if (_cacheManager.currentCategory?.id != _selectedCategory?.id ||
          _cacheManager.currentTasks == null) {
        setState(() {
          _isListModeLoading = true;
        });
        unawaited(_loadTaskListDataInBackground());
      } else {
        setState(() {
          _isListModeLoading = false;
        });
      }
    }
  }

  Future<void> _loadTaskListDataInBackground() async {
    final category = _selectedCategory;
    if (category == null) {
      return;
    }

    try {
      final userId = AuthUtils.getCurrentUserId();
      await _cacheManager.initializeWithSavedCategory(category, userId);

      if (mounted && _showTaskListMode) {
        setState(() {
          _rebuildTaskListFromCache();
          _isListModeLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isListModeLoading = false;
        });
      }
      print('HomeScreen: Background list load failed: $e');
    }
  }

  List<Task> _computeTasksForSelectedCategory() {
    final categoryId = _selectedCategory?.id;
    if (categoryId == null) {
      return <Task>[];
    }

    var tasks = (_cacheManager.currentTasks ?? <Task>[])
        .where((task) => task.categoryId == categoryId)
        .toList();

    final query = _taskSearchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      tasks = tasks
          .where((task) => task.headline.toLowerCase().contains(query))
          .toList();
    }

    switch (_taskListSortOption) {
      case HomeTaskSortOption.alphabetical:
        tasks.sort(
          (a, b) => _compareTasksBySort(a, b, HomeTaskSortOption.alphabetical),
        );
        break;
      case HomeTaskSortOption.priority:
        tasks.sort(
          (a, b) => _compareTasksBySort(a, b, HomeTaskSortOption.priority),
        );
        break;
      case HomeTaskSortOption.age:
        tasks.sort((a, b) => _compareTasksBySort(a, b, HomeTaskSortOption.age));
        break;
    }

    return tasks;
  }

  int _compareTasksBySort(Task a, Task b, HomeTaskSortOption option) {
    switch (option) {
      case HomeTaskSortOption.alphabetical:
        return a.headline.toLowerCase().compareTo(b.headline.toLowerCase());
      case HomeTaskSortOption.priority:
        if (a.finished != b.finished) {
          return a.finished ? 1 : -1;
        }
        if (a.suggestibleAt == null && b.suggestibleAt == null) {
          return b.createdAt.compareTo(a.createdAt);
        }
        if (a.suggestibleAt == null) {
          return -1;
        }
        if (b.suggestibleAt == null) {
          return 1;
        }
        return a.suggestibleAt!.compareTo(b.suggestibleAt!);
      case HomeTaskSortOption.age:
        return b.createdAt.compareTo(a.createdAt);
    }
  }

  Future<void> _applySortOptionAsync(HomeTaskSortOption option) async {
    if (_taskListSortOption == option || _isTaskListSorting) {
      return;
    }

    setState(() {
      _taskListSortOption = option;
      _isTaskListSorting = true;
    });

    await Future.delayed(const Duration(milliseconds: 1));

    final previousVisibleCount = _visibleTaskCount;
    final sorted = List<Task>.from(_listModeTasks)
      ..sort((a, b) => _compareTasksBySort(a, b, option));

    if (!mounted) return;

    setState(() {
      _listModeTasks = sorted;
      _visibleTaskCount = previousVisibleCount.clamp(0, sorted.length);
      if (_visibleTaskCount == 0) {
        _prepareVisibleTaskCount();
      } else if (_visibleTaskCount < sorted.length &&
          !_isListProgressiveLoading) {
        unawaited(_loadMoreListTasksProgressively());
      }
      _isTaskListSorting = false;
    });
  }

  void _rebuildTaskListFromCache() {
    _listModeTasks = _computeTasksForSelectedCategory();
    _prepareVisibleTaskCount();
    if (_isReadOnly) {
      unawaited(_loadSnaggedOriginalIds());
    } else {
      _snaggedOriginalIds = {};
    }
  }

  /// For shared pursuits, load the original_ids of tasks the user has already
  /// snagged into the corresponding local category (or any owned category).
  Future<void> _loadSnaggedOriginalIds() async {
    final sharedCategory = _selectedCategory;
    if (sharedCategory == null) return;

    final userId = AuthUtils.getCurrentUserId();
    if (userId == null) return;

    try {
      final sharedOriginalId = sharedCategory.originalId ?? sharedCategory.id;
      // Find all owned categories with the same original_id
      final ownedCategoryIds = _categories
          .where((c) => !c.isShared && c.originalId == sharedOriginalId)
          .map((c) => c.id)
          .toList();

      if (ownedCategoryIds.isEmpty) {
        if (mounted) setState(() => _snaggedOriginalIds = {});
        return;
      }

      // Load tasks from those categories and collect their original_ids
      final Set<int> snagged = {};
      for (final catId in ownedCategoryIds) {
        final tasks = await ApiClient.getTasksByCategoryAndUser(catId, userId);
        for (final t in tasks) {
          if (t.originalId != null) snagged.add(t.originalId!);
        }
      }

      if (mounted) setState(() => _snaggedOriginalIds = snagged);
    } catch (e) {
      print('Error loading snagged IDs: $e');
    }
  }

  void _prepareVisibleTaskCount() {
    if (_listModeTasks.length > 50) {
      _visibleTaskCount = _initialListTaskCount.clamp(0, _listModeTasks.length);
      _isListProgressiveLoading = false;
      unawaited(_loadMoreListTasksProgressively());
    } else {
      _visibleTaskCount = _listModeTasks.length;
      _isListProgressiveLoading = false;
    }
  }

  Future<void> _loadMoreListTasksProgressively() async {
    if (_isListProgressiveLoading) return;
    _isListProgressiveLoading = true;

    while (mounted &&
        _showTaskListMode &&
        _visibleTaskCount < _listModeTasks.length) {
      await Future.delayed(const Duration(milliseconds: 45));

      if (!mounted || !_showTaskListMode) break;

      setState(() {
        _visibleTaskCount = (_visibleTaskCount + _listBatchSize)
            .clamp(0, _listModeTasks.length);
      });
    }

    _isListProgressiveLoading = false;
  }

  Future<void> _toggleTaskCompletionFromList(Task task) async {
    try {
      if (task.finished) {
        await _cacheManager.unfinishTask(task.id);
      } else {
        await _cacheManager.finishTask(task.id);
      }

      if (mounted) {
        setState(() {
          _rebuildTaskListFromCache();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating task: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteTaskFromList(Task task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Task'),
        content: Text('Are you sure you want to delete "${task.headline}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _cacheManager.removeTask(task.id);
      if (_randomTask?.id == task.id) {
        _randomTask = null;
      }
      if (mounted) {
        setState(() {
          _rebuildTaskListFromCache();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting task: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteCategory(Category category) async {
    final catName = NamingUtils.categoriesName(plural: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $catName'),
        content: Text(
          'Are you sure you want to delete "${category.headline}"? '
          'All ${NamingUtils.tasksName()} in this $catName will also be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await supabase.from('Categories').delete().eq('id', category.id);
      if (mounted) await _loadCategories();
    } catch (e, st) {
      debugPrint('Error deleting category "${category.headline}": $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting $catName: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showSnagPursuitScreen(Category category) async {
    // If the shared pursuit carries no shared tasks, the snag screen would be
    // empty (nothing to select, Snag disabled). Skip it: just note that and
    // offer to take an empty copy.
    final sharedTasks = (await ApiClient.getTasksByCategory(category.id))
        .where((t) => t.shared)
        .toList();
    if (!mounted) return;

    Category? result;
    if (sharedTasks.isEmpty) {
      final pursuit = NamingUtils.categoriesName(plural: false);
      final tasks = NamingUtils.tasksName(plural: true);
      final accept = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Copy this $pursuit?'),
          content: Text(
              'Note: this $pursuit doesn\'t come with any $tasks — '
              'you\'ll want to compile those yourself.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                foregroundColor: Colors.white,
              ),
              child: const Text('Accept Anyway'),
            ),
          ],
        ),
      );
      if (accept != true || !mounted) return;
      result = await _createOwnedCloneOf(category);
    } else {
      result = await SnagPursuitScreen.push(
        context,
        sharedCategory: category,
        allCategories: _categories,
      );
    }

    if (result != null && mounted) {
      await _loadCategories();
      if (mounted) {
        final r = result;
        final match = _categories.firstWhere(
          (c) => c.id == r.id,
          orElse: () => r,
        );
        await _handleCategorySelection(match);
      }
    }
  }

  /// Creates an owned, empty clone of a shared [category] (same headline /
  /// original_id / description), for snagging a task-less pursuit.
  Future<Category?> _createOwnedCloneOf(Category category) async {
    final userId = AuthUtils.getCurrentUserId();
    if (userId == null) return null;
    try {
      return await ApiClient.createCategory({
        'headline': category.headline,
        'owner_id': userId,
        'original_id': category.originalId ?? category.id,
        if (category.invitation != null) 'invitation': category.invitation,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create Pursuit: $e')),
        );
      }
      return null;
    }
  }

  /// Shows CategoryPickerDialog to pick a target, then copies all shared tasks
  /// from [sharedCategory] into the selected category.  Used by the
  /// "Snag this Pursuit" menu item.

  Future<void> _releaseSharedCategory(Category category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            "Release Shared ${NamingUtils.categoriesName(capitalize: true, plural: false)}"),
        content: Text(
            'Choosing Release will remove "${category.headline}" from your list of ${NamingUtils.categoriesName(capitalize: true, plural: true)}. You can get it back using the "Shared With Me" item in the ${NamingUtils.categoriesName(capitalize: true, plural: false)}\'s menu.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[700],
              foregroundColor: Colors.white,
            ),
            child: const Text('Release'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient.setSharedCategoryAvailable(category.id, false);
      category.isAvailable = false;
      if (mounted) await _loadCategories();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error releasing Pursuit: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _toggleTaskShareFromList(Task task, bool newSharedState) async {
    final updatedTask = Task(
      id: task.id,
      categoryId: task.categoryId,
      headline: task.headline,
      notes: task.notes,
      synopsis: task.synopsis,
      ownerId: task.ownerId,
      createdAt: task.createdAt,
      suggestibleAt: task.suggestibleAt,
      triggersAt: task.triggersAt,
      deferral: task.deferral,
      links: task.links,
      processedLinks: task.processedLinks,
      finished: task.finished,
      shared: newSharedState,
      originalId: task.originalId,
      dirty: true,
    );

    try {
      await _cacheManager.updateTask(updatedTask);
      if (_randomTask?.id == task.id) {
        _randomTask = updatedTask.markClean();
      }
      if (mounted) {
        setState(() {
          _rebuildTaskListFromCache();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating share state: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildListModeSortWidget() {
    Widget buildSortRow(HomeTaskSortOption option, String label) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Radio<HomeTaskSortOption>(
            value: option,
            groupValue: _taskListSortOption,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            onChanged: (HomeTaskSortOption? value) {
              if (value == null) return;
              unawaited(_applySortOptionAsync(value));
            },
          ),
          Text(label),
        ],
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Sort By:'),
          buildSortRow(HomeTaskSortOption.priority, 'Priority'),
          buildSortRow(HomeTaskSortOption.alphabetical, 'A-Z'),
          buildSortRow(HomeTaskSortOption.age, 'Age'),
        ],
      ),
    );
  }

  Widget _buildTaskListModeContent() {
    final tasks = _listModeTasks;
    final displayedTasks =
        (_visibleTaskCount <= 0 || _visibleTaskCount >= tasks.length)
            ? tasks
            : tasks.take(_visibleTaskCount).toList();

    if (_isListModeLoading && tasks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // When there are no tasks at all (not a search filter), show the full
    // empty-pursuit experience instead of sort controls + placeholder text.
    if (tasks.isEmpty && _taskSearchController.text.trim().isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 24),
            Text(
              'All out of ${NamingUtils.tasksName(plural: true, capitalize: false)}!',
              style: const TextStyle(fontSize: 21),
            ),
            if (_cacheManager.currentTasks?.isEmpty == true) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _isReadOnly
                    ? () => unawaited(_addIdeaViaPickedPursuit())
                    : _navigateToNewContent,
                icon: const Icon(Icons.add_task, size: 24),
                label: Text(
                  'Add ${NamingUtils.tasksName(plural: false, capitalize: false, withArticle: true)}',
                  style: const TextStyle(fontSize: 20),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(200, 56),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isTaskListSorting) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          ),
        ],
        if (tasks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'No matching ${NamingUtils.tasksName(plural: true, capitalize: false)} found.',
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ),
          )
        else ...[
          ...displayedTasks.map(
            (task) {
              final taskSnagged = _isReadOnly &&
                  _snaggedOriginalIds.contains(task.originalId ?? task.id);
              return TaskDisplay(
                key: ValueKey(
                    'home-task-${task.id}-${task.finished}-${task.shared}-$taskSnagged'),
                task: task,
                withControls: !_isReadOnly,
                onEdit: _isReadOnly ? null : () => _showEditPanel(task),
                onDelete: _isReadOnly ? null : () => _deleteTaskFromList(task),
                onTap: _isReadOnly
                    ? null
                    : () => _toggleTaskCompletionFromList(task),
                onShareToggle: _isReadOnly
                    ? null
                    : (newSharedState) =>
                        _toggleTaskShareFromList(task, newSharedState),
                isCategoryPrivate: _selectedCategory?.isPrivate ?? false,
                isSnagged: taskSnagged,
                onSnag: _isReadOnly &&
                        !taskSnagged &&
                        !AuthUtils.isGuestUser()
                    ? () => unawaited(_snagTaskFromList(task))
                    : null,
                onSnagAgain: _isReadOnly &&
                        taskSnagged &&
                        !AuthUtils.isGuestUser()
                    ? () => unawaited(_snagTaskToOtherPursuit(task))
                    : null,
              );
            },
          ),
          if (_isListProgressiveLoading && _visibleTaskCount < tasks.length)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ], // end else (tasks non-empty)
      ],
    );
  }

  /// Creates a share-invitation link for [category] and shows a dialog
  /// with a Copy button so the sharer can send it via email/message/etc.

  Future<void> _shareCategory(Category category) async {
    await ShareAnyPursuitsScreen.shareSingle(context, category);
  }

  /// Opens CategoryPickerDialog so the user can pick a destination pursuit,
  /// defaulting to an owned category that shares [originalId] with the shared one.
  /// Snag the single currently-displayed random task into an owned category.
  Future<void> _snagCurrentTask() async {
    final task = _randomTask;
    final sharedCategory = _selectedCategory;
    if (task == null || sharedCategory == null) return;

    final sharedOriginalId = sharedCategory.originalId ?? sharedCategory.id;
    final cloneCategory = _categories
        .where((c) => !c.isShared && c.originalId == sharedOriginalId)
        .firstOrNull;

    final topLabel = cloneCategory != null
        ? "My existing '${cloneCategory.headline}'"
        : "A new '${sharedCategory.headline}' Pursuit of my own";

    await CategoryPickerDialog.show(
      context,
      title: 'Copy to which Pursuit?',
      subtitle:
          'Select one of your own Pursuits to copy this ${NamingUtils.tasksName(plural: false, capitalize: false)} into.',
      showCreateNew: true,
      hideShared: true,
      excludeCategory: cloneCategory,
      topButtonLabel: topLabel,
      topButtonOnPressed: () async {
        if (cloneCategory != null) {
          await _copySelectedTasksTo(cloneCategory, overrideTasks: [task]);
        } else {
          await _snagTaskToNewClone(task, sharedCategory);
        }
      },
      onCategorySelected: (category, {bool? shouldMove, bool? applyToAll}) {
        unawaited(_copySelectedTasksTo(category, overrideTasks: [task]));
      },
    );
  }

  /// Snag a single task from a shared pursuit's list view into the
  /// corresponding local category (creating one if needed).
  Future<void> _snagTaskFromList(Task task) async {
    final sharedCategory = _selectedCategory;
    if (sharedCategory == null) return;

    final sharedOriginalId = sharedCategory.originalId ?? sharedCategory.id;
    final cloneCategory = _categories
        .where((c) => !c.isShared && c.originalId == sharedOriginalId)
        .firstOrNull;

    if (cloneCategory != null) {
      await _copySelectedTasksTo(cloneCategory, overrideTasks: [task]);
    } else {
      await _snagTaskToNewClone(task, sharedCategory);
    }
    // Refresh snagged IDs so the button updates
    await _loadSnaggedOriginalIds();
  }

  /// Snag a task that's already been snagged once into a different pursuit.
  /// Shows the category picker, excluding the corresponding local category.
  Future<void> _snagTaskToOtherPursuit(Task task) async {
    final sharedCategory = _selectedCategory;
    if (sharedCategory == null) return;

    final sharedOriginalId = sharedCategory.originalId ?? sharedCategory.id;
    final cloneCategory = _categories
        .where((c) => !c.isShared && c.originalId == sharedOriginalId)
        .firstOrNull;

    await CategoryPickerDialog.show(
      context,
      title: 'Snag to which Pursuit?',
      subtitle:
          'Select another Pursuit to copy this ${NamingUtils.tasksName(plural: false, capitalize: false)} into.',
      showCreateNew: true,
      hideShared: true,
      excludeCategory: cloneCategory,
      onCategorySelected: (category, {bool? shouldMove, bool? applyToAll}) {
        unawaited(_copySelectedTasksTo(category, overrideTasks: [task]));
      },
    );
  }

  /// For read-only (shared) categories with no tasks visible: explain that
  /// we'll create an owned copy of the pursuit, offer to copy existing tasks,
  /// then open the New Task editor in the new pursuit.
  Future<void> _addIdeaViaPickedPursuit() async {
    final sharedCategory = _selectedCategory;
    if (sharedCategory == null) return;

    final categoryName =
        NamingUtils.categoriesName(capitalize: false, plural: false);
    final tasksName = NamingUtils.tasksName(capitalize: false, plural: true);

    bool copyTasks = true;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Create your own "${sharedCategory.headline}"'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Since this is a shared $categoryName, adding an idea will '
                'create your own copy of "${sharedCategory.headline}" and add '
                'the idea there.',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Checkbox(
                    value: copyTasks,
                    onChanged: (v) => setLocal(() => copyTasks = v ?? true),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  Expanded(
                    child: Text(
                      'Also copy the existing shared $tasksName into my copy',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                foregroundColor: Colors.white,
              ),
              child: const Text('Proceed'),
            ),
          ],
        ),
      ),
    );

    if (proceed != true || !mounted) return;

    final target = await _createCloneCategory(sharedCategory);
    if (target == null || !mounted) return;

    if (copyTasks) {
      try {
        final tasks = await ApiClient.getTasksByCategory(sharedCategory.id);
        final shared = tasks.where((t) => t.shared).toList();
        final userId = AuthUtils.getCurrentUserId();
        for (final task in shared) {
          await ApiClient.createTask({
            'headline': task.headline,
            if (task.notes != null) 'notes': task.notes,
            if (task.synopsis != null) 'synopsis': task.synopsis,
            'owner_id': userId,
            'category_id': target.id,
            'original_id': task.id,
            if (task.links != null && task.links!.isNotEmpty)
              'links': task.links,
            'finished': false,
            'shared': false,
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not copy tasks: $e')),
          );
        }
      }
    }

    if (mounted) {
      await _loadCategories();
      if (!mounted) return;
      // Add a task to the just-created/cloned pursuit via the unified editor.
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TaskEditScreen(
            category: target,
            showAlternativeOptions: true,
          ),
        ),
      );
      if (mounted) await _loadCategories();
    }
  }

  Future<Category?> _createCloneCategory(Category sharedCategory) async {
    final userId = AuthUtils.getCurrentUserId();
    try {
      return await ApiClient.createCategory({
        'headline': sharedCategory.headline,
        'owner_id': userId,
        'original_id': sharedCategory.originalId ?? sharedCategory.id,
        if (sharedCategory.invitation != null)
          'invitation': sharedCategory.invitation,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create Pursuit: $e')),
        );
      }
      return null;
    }
  }

  Future<void> _snagTaskToNewClone(Task task, Category sharedCategory) async {
    final newCategory = await _createCloneCategory(sharedCategory);
    if (newCategory != null) {
      await _copySelectedTasksTo(newCategory, overrideTasks: [task]);
    }
  }

  /// Copies [overrideTasks] into [target] category as new tasks owned by current user.
  Future<void> _copySelectedTasksTo(Category target,
      {List<Task>? overrideTasks}) async {
    final userId = AuthUtils.getCurrentUserId();

    final tasksToCopy = overrideTasks ?? [];
    int copied = 0;

    for (final task in tasksToCopy) {
      try {
        await ApiClient.createTask({
          'headline': task.headline,
          if (task.notes != null) 'notes': task.notes,
          if (task.synopsis != null) 'synopsis': task.synopsis,
          'owner_id': userId,
          'category_id': target.id,
          'original_id': task.id,
          'links': task.links ?? <String>[],
          'finished': false,
          'shared': false,
        });
        copied++;
      } catch (e) {
        print('Error copying task "${task.headline}": $e');
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Copied $copied ${NamingUtils.tasksName(plural: copied != 1, capitalize: false)} to "${target.headline}"',
          ),
        ),
      );
    }
  }

  Future<void> _rejectCurrentTask() async {
    try {
      setState(() {
        _isLoadingTask = true;
        _error = null;
      });

      if (_randomTask == null) {
        throw Exception('No current task to reject');
      }

      // Use CacheManager to reject the task
      await _cacheManager.rejectTask(_randomTask!.id);

      // Load a new random task
      if (_selectedCategory != null) {
        await _loadRandomTask(_selectedCategory!);
      } else {
        setState(() {
          _randomTask = null;
          _isLoadingTask = false;
        });
      }
    } catch (e) {
      print('Error rejecting task: $e');
      setState(() {
        _error = e.toString();
        _isLoadingTask = false;
      });
    }
  }

  Future<void> _finishCurrentTask() async {
    try {
      setState(() {
        _isLoadingTask = true;
        _error = null;
      });

      if (_randomTask == null) {
        throw Exception('No current task to finish');
      }

      // Use CacheManager to finish the task
      await _cacheManager.finishTask(_randomTask!.id);

      // Load a new random task
      if (_selectedCategory != null) {
        await _loadRandomTask(_selectedCategory!);
      } else {
        setState(() {
          _randomTask = null;
          _isLoadingTask = false;
        });
      }
    } catch (e) {
      print('Error finishing task: $e');
      setState(() {
        _error = e.toString();
        _isLoadingTask = false;
      });
    }
  }

  Future<void> _reviveCurrentTask() async {
    try {
      if (_randomTask == null) {
        throw Exception('No current task to revive');
      }

      final userId = AuthUtils.getCurrentUserId();
      print(
        'HomeScreen: Using user ID: $userId (guest: ${AuthUtils.isGuestUser()})',
      );

      // Use CacheManager to revive the task
      await _cacheManager.reviveTask(_randomTask!.id);

      // Update the current task reference
      final updatedTask = _cacheManager.currentTasks?.firstWhere(
        (t) => t.id == _randomTask!.id,
        orElse: () => _randomTask!,
      );

      if (updatedTask != null) {
        setState(() {
          _randomTask = updatedTask;
        });
      }
    } catch (e) {
      print('Error reviving task: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error reviving task: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Update the last_access timestamp for a category when it's selected
  Future<void> _updateCategoryLastAccess(Category category) async {
    try {
      await supabase
          .from('Categories')
          .update({'last_access': DateTime.now().toUtc().toIso8601String()}).eq(
              'id', category.id);

      print('Updated last_access for category: ${category.headline}');

      // Move the selected category to the top of the list
      setState(() {
        final selectedIndex =
            _categories.indexWhere((c) => c.id == category.id);
        if (selectedIndex != -1) {
          // Remove the selected category from its current position
          final selectedCategory = _categories.removeAt(selectedIndex);
          // Add it to the beginning of the list (top of dropdown)
          _categories.insert(0, selectedCategory);
        }
      });
    } catch (e) {
      print('Error updating last_access for category: $e');
      // Don't show error to user as this is not critical functionality
    }
  }

  Future<void> _loadCategories() async {
    try {
      print('Starting to load categories...');

      // For now, we'll use guest mode since we haven't implemented serverless auth yet
      print('Using guest mode for category loading');
      final guestUserId = AuthUtils.getCurrentUserId();
      print('Guest user ID: $guestUserId');

      try {
        print('Fetching categories from API...');
        // A guest who followed a share link previews ONLY that link's pursuits,
        // read-only, instead of the demo categories.
        List<Category> categories;
        if (AuthUtils.isGuestUser()) {
          final token = await InviteTokenStore.get();
          if (token != null && token.startsWith('share:')) {
            _guestPreviewLinkId = token.substring('share:'.length);
            categories =
                await ApiClient.getShareLinkPursuits(_guestPreviewLinkId!);
          } else {
            _guestPreviewLinkId = null;
            categories = await ApiClient.getCategories();
          }
        } else {
          _guestPreviewLinkId = null;
          categories = await ApiClient.getCategories();
        }
        // Route preview task reads through the anon RPC (see CacheManager).
        _cacheManager.previewShareLinkId = _guestPreviewLinkId;
        print('API response: ${categories.length} categories');

        setState(() {
          _categories = categories;
          _isLoading = false;
        });
        print('Categories loaded successfully');

        // Only select initial category on first load (e.g., from deep link)
        // On subsequent reloads, preserve the user's dropdown selection
        if (_isFirstLoad) {
          _selectInitialCategory();
          _isFirstLoad = false;

          // If there's only one category and no category is selected, select it automatically
          if (categories.length == 1 && _selectedCategory == null) {
            print(
                'HomeScreen: Only one category available, selecting it automatically');
            setState(() {
              _selectedCategory = categories.first;
            });
            _loadRandomTask(categories.first);
            _updateCategoryLastAccess(categories.first);
          }
        } else {
          // On subsequent loads, update the selected category reference to the new object
          if (_selectedCategory != null) {
            final matches =
                categories.where((c) => c.id == _selectedCategory!.id);
            final updatedCategory = matches.isEmpty ? null : matches.first;
            if (updatedCategory != null &&
                (!updatedCategory.isShared || updatedCategory.isAvailable)) {
              setState(() {
                _selectedCategory = updatedCategory;
              });
            } else {
              // Selected category was removed, deleted, or released.
              setState(() {
                _selectedCategory = null;
                _randomTask = null;
              });
            }
          }
          if (_selectedCategory == null && categories.length == 1) {
            // Auto-select if there's only one category and none is currently selected
            // This handles the case where a user imports their first category
            print(
                'HomeScreen: Only one category available on reload, selecting it automatically');
            setState(() {
              _selectedCategory = categories.first;
            });
            _loadRandomTask(categories.first);
            _updateCategoryLastAccess(categories.first);
          }
        }

        // Ensure we always have an actively selected category when categories exist.
        // This guarantees task selection on startup even with multiple categories.
        if (categories.isNotEmpty && _selectedCategory == null) {
          setState(() {
            _selectedCategory = categories.first;
          });
          _loadRandomTask(categories.first);
          _updateCategoryLastAccess(categories.first);
        }

        // Show onboarding dialogs on first login; fall back to welcome
        // dialog for authenticated users who have no categories. Awaited so
        // _welcomeDialogShown is set before _loadCategories returns.
        if (!AuthUtils.isGuestUser()) {
          await _handleFirstLoginOrEmptyCategories(categories);
        }
      } catch (e) {
        print('Error loading categories: $e');
        setState(() {
          _categories = [];
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      print('Error loading categories: $e');
      print('Stack trace: $stackTrace');

      // Check if it's a network error
      String errorMessage;
      if (e.toString().contains('Failed host lookup') ||
          e.toString().contains('SocketException') ||
          e.toString().contains('Network is unreachable')) {
        errorMessage =
            "Sorry, but we can't connect to the cloud. Are you online?";
      } else {
        errorMessage = e.toString();
      }

      setState(() {
        _error = errorMessage;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleCategorySelection(Category? newValue) async {
    // If the edit panel is open, intercept and show copy/move dialog instead
    if (_editingTask != null && newValue != null) {
      await _handleEditPanelCategoryChange(_editingTask!, newValue);
      return;
    }

    // Evaluate before setState so _isListModeLoading can be set in the same
    // frame — preventing a "No tasks yet" flash while the load is pending.
    final needsLoad = _showTaskListMode &&
        newValue != null &&
        (_cacheManager.currentCategory?.id != newValue.id ||
            _cacheManager.currentTasks == null);

    setState(() {
      _selectedCategory = newValue;
      _randomTask = null;
      if (_showTaskListMode) {
        _rebuildTaskListFromCache();
        if (needsLoad) _isListModeLoading = true;
      }
    });

    if (newValue != null) {
      unawaited(_maybeNotifyNewShares());
      await _updateCategoryLastAccess(newValue);
      if (newValue.isShared && mounted) {
        await showBorrowExplanationIfNeeded(context);
      }
      if (_showTaskListMode) {
        if (needsLoad) {
          unawaited(_loadTaskListDataInBackground());
        }
      } else {
        _loadRandomTask(newValue);
      }
    }
  }

  void _handleIntentProcessingRequest() {
    if (mounted) unawaited(_maybeProcessPendingIntent());
  }

  void _handleTaskReloadRequest() {
    print('HomeScreen: Task reload requested');
    if (HomeScreen.needsTaskReload.value && mounted) {
      print('HomeScreen: Handling task reload request');
      print('HomeScreen: Current category: \'${_selectedCategory?.headline}\'');
      print('HomeScreen: Current task: \'${_randomTask?.headline}\'');

      HomeScreen.needsTaskReload.value = false; // Reset the flag
      _handleEditComplete();
    } else {
      print(
        'HomeScreen: Task reload requested but widget not mounted or flag not set',
      );
      print(
        'HomeScreen: mounted: $mounted, needsTaskReload: ${HomeScreen.needsTaskReload.value}',
      );
    }
  }

  void _handleDataReloadRequest() {
    print('HomeScreen: Data reload requested');
    if (HomeScreen.needsDataReload.value && mounted) {
      print('HomeScreen: Handling data reload request');
      HomeScreen.needsDataReload.value = false; // Reset the flag

      // Reload categories and tasks
      _loadCategories().then((_) {
        // After categories are loaded, reload the current task if we have a selected category
        if (_selectedCategory != null && mounted) {
          _loadRandomTask(_selectedCategory!);
        }
      });
    } else {
      print(
        'HomeScreen: Data reload requested but widget not mounted or flag not set',
      );
      print(
        'HomeScreen: mounted: $mounted, needsDataReload: ${HomeScreen.needsDataReload.value}',
      );
    }
  }

  void _navigateToNewCategory() {
    print('HomeScreen: Starting navigation to new category screen...');

    if (!mounted) {
      print('HomeScreen: Not mounted before navigation');
      return;
    }

    Navigator.pushNamed(context, '/new-category').then((result) {
      if (result != null) {
        print(
            'HomeScreen: Category was created or imported, reloading categories');
        _loadCategories().then((_) async {
          if (result is Category && mounted) {
            await _handleCategorySelection(result);
          }
          // If a task was waiting for a pursuit (the ?addlink first-login flow),
          // file it straight into the pursuit just created — no picker.
          if (mounted) {
            await _maybeProcessPendingIntent(
                targetCategory: result is Category ? result : null);
          }
        });
      }
    });
  }

  /// Only a brand-new user (no pursuits yet) who taps "+" sees this — it
  /// explains the idea and offers to create their first pursuit.
  Future<bool?> _confirmNewbieCreatePursuit() {
    final pursuit = NamingUtils.categoriesName(plural: false, capitalize: true);
    final pursuits = NamingUtils.categoriesName(plural: true);
    final task = NamingUtils.tasksName(plural: false);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Create your first $pursuit'),
        content: Text(
            'RouzMe keeps track of what you\'ve been meaning to do, organized '
            'into $pursuits — things like "Watch a Movie" or "Read a Book". '
            'Before you can add $task, you\'ll need a $pursuit to put it in. '
            'Create one now?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Not now'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.add),
            label: Text('Create a $pursuit'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[700],
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToNewContent() async {
    print('HomeScreen: Starting navigation to new content screen...');

    if (!mounted) {
      print('HomeScreen: Not mounted before navigation');
      return;
    }

    final owned = _categories.where((c) => !c.isShared).toList();

    // No pursuit of one's own yet (only a brand-new user reaches this) → a
    // newbie-oriented prompt to create their first pursuit, then continue into
    // the New Task editor.
    if (owned.isEmpty) {
      final create = await _confirmNewbieCreatePursuit();
      if (!mounted || create != true) return;
      final result = await Navigator.pushNamed(context, '/new-category');
      if (!mounted || result is! Category) return;
      await _loadCategories();
      if (!mounted) return;
      _handleCategorySelection(result);
      _navigateToNewContent(); // a pursuit now exists → the New Task editor
      return;
    }

    // Otherwise → the unified New Task editor (identical to the incoming-share
    // flow): a pursuit selector on top defaulting to the current pursuit, with
    // the Alternative Options (bulk import, JustWatch, Letterboxd) below.
    final ordering = await orderCategoriesBySensibility(owned);
    if (!mounted) return;
    final ordered = ordering.ordered;
    final defaultCat = (_selectedCategory != null &&
            owned.any((c) => c.id == _selectedCategory!.id))
        ? _selectedCategory!
        : ordered.first;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TaskEditScreen(
          category: defaultCat,
          selectableCategories: ordered,
          showPursuitSelector: true,
          showAlternativeOptions: true,
        ),
      ),
    );
    if (!mounted || result == null) return;

    // A task was created (true) or an import returned its pursuit (Category):
    // reload and drop into the list so the new content shows.
    await _loadCategories();
    if (!mounted) return;
    if (result is Category) _handleCategorySelection(result);
    setState(() => _showTaskListMode = false);
    _toggleTaskListMode();
  }

  Future<void> _showEditPanel(Task task) async {
    print('HomeScreen: Showing edit panel for task: ${task.headline}');
    if (!mounted || _selectedCategory == null) {
      print('HomeScreen: Not mounted or no category selected');
      return;
    }

    setState(() => _editingTask = task);

    TaskEditScreen.onEditComplete = () {
      print('HomeScreen: Task edit complete callback received');
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              HomeScreen.needsTaskReload.value = true;
            });
          }
        });
      }
    };

    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 480,
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: TaskEditScreen(
            category: _selectedCategory!,
            task: task,
            isPanel: true,
            onCategoryChange: (newCategory) =>
                _handleEditPanelCategoryChange(task, newCategory),
          ),
        ),
      ),
    );

    TaskEditScreen.onEditComplete = null;
    // Rebuild the list immediately from the already-updated cache.
    // cacheManager.updateTask was called before the panel closed, so the
    // cache is correct at this point — no need to wait for _handleEditComplete.
    setState(() {
      _editingTask = null;
      if (_showTaskListMode) _rebuildTaskListFromCache();
    });
  }

  Future<void> _handleEditPanelCategoryChange(
      Task task, Category newCategory) async {
    bool shouldMove = true;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text(
              'Change ${NamingUtils.categoriesName(capitalize: false, plural: false)}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Move "${task.headline}" to "${newCategory.headline}"?'),
              const SizedBox(height: 16),
              RadioListTile<bool>(
                title: const Text('Move'),
                subtitle: Text('Remove from "${_selectedCategory!.headline}"'),
                value: true,
                groupValue: shouldMove,
                onChanged: (v) => setDlgState(() => shouldMove = v ?? true),
              ),
              RadioListTile<bool>(
                title: const Text('Copy'),
                subtitle: Text(
                    'Keep in both "${_selectedCategory!.headline}" and "${newCategory.headline}"'),
                value: false,
                groupValue: shouldMove,
                onChanged: (v) => setDlgState(() => shouldMove = v ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, shouldMove),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    // Close the edit panel
    if (mounted) Navigator.pop(context);

    try {
      if (result) {
        // Move: update category_id
        await supabase
            .from('Tasks')
            .update({'category_id': newCategory.id}).eq('id', task.id);
      } else {
        // Copy: insert new row
        final userId = AuthUtils.getCurrentUserId();
        await supabase.from('Tasks').insert({
          'headline': task.headline,
          'notes': task.notes,
          'category_id': newCategory.id,
          'owner_id': userId,
          'finished': false,
          'shared': task.shared,
          'links': task.links ?? [],
          'synopsis': task.synopsis,
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }

    // Refresh current view (stay in original category)
    if (mounted) {
      setState(() {
        HomeScreen.needsTaskReload.value = true;
      });
    }
  }

  /// Called after every category load for authenticated users.
  /// On first login silently subscribes the user to shares from supstill@mac.com
  /// (available=false so they appear in My Shares but not the main list).
  /// A readable stand-in title for a shared link with no title of its own
  /// (e.g. a native share that was just a bare URL): its host, or a generic.
  String _shareLabelFromUrl(String url) {
    try {
      final host = Uri.parse(url).host;
      return host.isNotEmpty ? host : 'the page you shared';
    } catch (_) {
      return 'the page you shared';
    }
  }

  Future<void> _handleFirstLoginOrEmptyCategories(
      List<Category> categories) async {
    if (_welcomeDialogShown) return;

    final prefs = await SharedPreferences.getInstance();
    final userId = AuthUtils.getCurrentUserId();
    if (userId == null) return;

    // Use local pref as a fast check, but verify against server state to handle
    // new-device / cleared-browser-data scenarios. Only the user's OWN
    // categories mean they've used the app before — borrowed shares do NOT
    // count, since a brand-new user who followed a share link already has shares
    // but is still seeing the app (and needs the welcome) for the first time.
    final localOnboarded = prefs.getBool('onboarded_$userId') ?? false;
    bool isFirstLogin = !localOnboarded;
    if (isFirstLogin && categories.isNotEmpty) {
      isFirstLogin = false;
      await prefs.setBool('onboarded_$userId', true);
    }
    if (isFirstLogin) {
      await prefs.setBool('onboarded_$userId', true);
      // If they arrived while taking a task (?addlink from the extension) and
      // have no pursuit of their own to file it into, the greeting explains
      // they must create one and offers "Create a Pursuit".
      final pending = await PendingIntentStore.get();
      final takingTitle = (pending != null &&
              !categories.any((c) => !c.isShared))
          ? (pending.title.isNotEmpty
              ? pending.title
              : _shareLabelFromUrl(pending.url))
          : null;
      _showWelcomeDialog(
          takingTaskTitle: takingTitle); // non-blocking; sets _welcomeDialogShown
      await ApiClient.redeemSampleShares(available: false);
      if (mounted) await _loadCategories();
    }
  }

  Future<void> _checkAndShowWelcomeDialog() async {
    if (!_welcomeDialogShown) {
      _showWelcomeDialog();
    }
  }

  /// [takingTaskTitle] is set when a brand-new user arrived while taking a task
  /// (an ?addlink intent) and has no pursuit yet to file it into: the greeting
  /// then explains they must create a pursuit and offers a "Create a Pursuit"
  /// button instead of "Got It".
  void _showWelcomeDialog({String? takingTaskTitle}) {
    if (_welcomeDialogShown) return;

    _welcomeDialogShown = true;
    _welcomeDialogOpen = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: true,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Welcome to RouzMe',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              content: RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 16, color: Colors.black),
                  children: [
                    const TextSpan(
                        text: 'The basic idea is simple: we keep track of '),
                    TextSpan(
                      text: NamingUtils.categoriesName(
                          plural: true, capitalize: true),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const TextSpan(
                        text:
                            ' like \'Watch a Movie\' or \'Read a Book\', with '),
                    TextSpan(
                      text:
                          NamingUtils.tasksName(plural: true, capitalize: true),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (takingTaskTitle != null) ...[
                      const TextSpan(
                          text: ' for each one, like "The Godfather" or '
                              '"Moby Dick".\n\n'),
                      TextSpan(
                          text: 'What ${NamingUtils.categoriesName(plural: false)} does "$takingTaskTitle" serve? '
                              'Create it now to save this ${NamingUtils.tasksName(plural: false)}.\n\n'),
                      TextSpan(
                          text:
                              'PS: a starter set of ${NamingUtils.categoriesName(plural: true, capitalize: true)} '
                              'have also been shared with you. '
                              'Hit the "Shared With Me" item on the main menu to peruse them.'),
                    ] else
                      TextSpan(
                          text:
                              ' for each one, like "The Godfather" or "Moby Dick".\n\nTo make it easier getting started, some ${NamingUtils.categoriesName(plural: true, capitalize: true)} have been shared with you. You can snag them using the "Shared With Me" item on the main menu.\n\n(The Help button below will explain more.)'),
                  ],
                ),
              ),
              actions: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const _HelpIcon(size: 28),
                      onPressed: () {
                        Navigator.of(context).pop();
                        Navigator.pushNamed(context, '/help');
                      },
                      tooltip: 'Help',
                    ),
                    const SizedBox(width: 8),
                    if (takingTaskTitle != null)
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _navigateToNewCategory();
                        },
                        icon: const Icon(Icons.add),
                        label: Text(
                            'Create a ${NamingUtils.categoriesName(plural: false, capitalize: true)}'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[700],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                      )
                    else
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                        child: const Text(
                          'Got It',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        );
      }
      // Greeting dismissed — now surface any new-shares advisory (e.g. pursuits
      // from a share link the user just followed).
      _welcomeDialogOpen = false;
      if (mounted) _maybeNotifyNewShares();
    });
  }

  void _showGuestSignupDialog({String content = 'Your message here'}) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title:
              Text('Add Your Own ${NamingUtils.categoriesName(plural: false)}'),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.pushNamed(context, '/auth');
              },
              child: const Text('Sign Up'),
            ),
          ],
        );
      },
    );
  }

  void _handleEditComplete() async {
    print('HomeScreen: Handling edit complete');

    // Guard: Skip if already reloading
    if (_isReloading) {
      print(
          'HomeScreen: Reload already in progress, skipping _handleEditComplete');
      return;
    }

    _isReloading = true;
    try {
      // Store the current task ID before reloading
      final currentTaskId = _randomTask?.id;
      final previousSelectedCategory = _selectedCategory;

      // Reload categories first
      print('HomeScreen: Reloading categories...');
      await _loadCategories();
      print('HomeScreen: Categories reloaded');

      // Check if the previously selected category still exists
      if (previousSelectedCategory != null) {
        final categoryStillExists = _categories
            .any((category) => category.id == previousSelectedCategory.id);

        if (!categoryStillExists) {
          print(
              'HomeScreen: Previously selected category was deleted, clearing selection');
          setState(() {
            _selectedCategory = null;
            _randomTask = null;
          });
          return; // Exit early since the category was deleted
        }
      }

      // Then check if we need to reload the task
      if (_selectedCategory != null) {
        // The cache was already updated by cacheManager.updateTask() in _saveTask.
        // Re-fetching from the API risks returning a differently-filtered set and
        // causing the edited task to temporarily disappear. Just use the cache.

        // Check if the current task still exists and is valid
        if (currentTaskId != null) {
          final currentTaskStillExists = _cacheManager.currentTasks?.any(
                (task) => task.id == currentTaskId && !task.finished,
              ) ??
              false;

          if (currentTaskStillExists) {
            // Current task still exists - just update it in case it was modified
            final updatedTask = _cacheManager.currentTasks!.firstWhere(
              (task) => task.id == currentTaskId,
            );

            print(
                'HomeScreen: Current task still exists, keeping it displayed');
            if (mounted) {
              setState(() {
                _randomTask = updatedTask;
                // Also refresh the task list view if it's visible
                if (_showTaskListMode) {
                  _rebuildTaskListFromCache();
                }
              });
            }
            return; // Don't load a new random task
          } else {
            print(
                'HomeScreen: Current task was deleted or finished, loading new task');
          }
        }

        // Only load a new random task if the current one was deleted/finished or doesn't exist
        await _loadRandomTask(_selectedCategory!);

        if (mounted) {
          print(
            'HomeScreen: New random task loaded: \'${_randomTask?.headline}\'',
          );
          // Rebuild the task list even in the fallthrough case (e.g. _randomTask was null)
          if (_showTaskListMode) {
            setState(() => _rebuildTaskListFromCache());
          }
        }
      } else {
        print('HomeScreen: No category selected, skipping task load');
      }
    } catch (e) {
      print('HomeScreen: Error handling edit complete: $e');
    } finally {
      _isReloading = false;
    }
  }

  /// Fetch synopsis from task links using the SynopsisFetcher utility
  Future<void> _fetchSynopsisFromLinks() async {
    // Skip if already fetching or no task
    if (_isFetchingSynopsis || _randomTask == null) {
      return;
    }

    setState(() {
      _isFetchingSynopsis = true;
    });

    try {
      final result = await SynopsisFetcher.fetchSynopsisForTask(_randomTask!);

      if (result != null && mounted) {
        setState(() {
          _fetchedSynopsis = result.synopsis;
        });
        print('HomeScreen: Synopsis fetched from ${result.source.name}');
      }
    } catch (e) {
      print('HomeScreen: Error fetching synopsis: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingSynopsis = false;
        });
      }
    }
  }

  /// Check if we should fetch synopsis for the current task
  bool _shouldFetchNotes() {
    return _randomTask != null &&
        (_randomTask!.synopsis == null ||
            _randomTask!.synopsis!.trim().isEmpty) &&
        _randomTask!.links != null &&
        _randomTask!.links!.isNotEmpty;
  }

  /// Preprocess notes text for HTML rendering
  /// Converts plain text newlines to HTML <br> tags if text doesn't already contain HTML
  String _preprocessNotesForHtml(String notes) {
    // Check if the text already contains HTML tags
    final hasHtmlTags = RegExp(r'<[^>]+>').hasMatch(notes);

    if (hasHtmlTags) {
      // Already has HTML, return as-is
      return notes;
    }

    // Plain text - convert newlines to <br> tags
    return notes.replaceAll('\n', '<br>');
  }

  @override
  Widget build(BuildContext context) {
    // Check if data was modified after this frame completes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final dataModified = HomeScreen.checkAndResetDataModified();
      if (dataModified && mounted) {
        print('HomeScreen.build: Data was modified, triggering reload');
        if (_selectedCategory != null) {
          _refreshCacheIfNeeded(forceDatabaseRefresh: true);
        } else {
          print('HomeScreen.build: No category selected, reloading categories');
          _loadCategories();
        }
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: _isSearchMode
            ? TextField(
                controller: _findController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search ideas…',
                  border: InputBorder.none,
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: _onFindChanged,
                onSubmitted: (_) => _submitSearch(),
              )
            : const Text('RouzMe'),
        automaticallyImplyLeading: false,
        actions: _buildAppBarActions(),
      ),
      body: _isShowingResults
          ? _buildFindResults()
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_isLoading)
                      const Center(child: CircularProgressIndicator())
                    else if (_error != null)
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.cloud_off,
                                size: 48, color: Colors.grey),
                            const SizedBox(height: 16),
                            Text(
                              _error!,
                              style: const TextStyle(fontSize: 16),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () {
                                _loadCategories();
                                if (_selectedCategory != null) {
                                  _loadRandomTask(_selectedCategory!);
                                }
                              },
                              icon: const Icon(Icons.refresh),
                              label: const Text('Try Again'),
                            ),
                          ],
                        ),
                      )
                    else if (_categories.isEmpty)
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: const _HelpIcon(size: 48),
                              onPressed: () {
                                Navigator.pushNamed(context, '/help');
                              },
                              tooltip: 'Help',
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No ${NamingUtils.categoriesName(plural: true)} available',
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w600),
                              textAlign: TextAlign.center,
                            ),
                            if (AuthUtils.isGuestUser()) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Guest users can only view demo data. Sign up/in to create your own ${NamingUtils.categoriesName()}.',
                                style: const TextStyle(
                                    fontSize: 14, color: Colors.grey),
                                textAlign: TextAlign.center,
                              ),
                            ],
                            const SizedBox(height: 16),
                            if (AuthUtils.isGuestUser())
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        Navigator.pushNamed(context, '/auth');
                                      },
                                      icon: const Icon(Icons.login),
                                      label: const Text('Sign In'),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        Navigator.pushNamed(context, '/auth');
                                      },
                                      icon: const Icon(Icons.person_add),
                                      label: const Text('Sign Up'),
                                    ),
                                  ),
                                ],
                              )
                            else ...[
                              ElevatedButton.icon(
                                onPressed: () async {
                                  await MySharesScreen.show(
                                    context,
                                    _categories,
                                    (cat) async {
                                      await _handleCategorySelection(cat);
                                    },
                                    onRefresh: _loadCategories,
                                  );
                                  if (mounted) _loadCategories();
                                },
                                icon: const Icon(Icons.inbox),
                                label: const Text('Take a Shared Pursuit'),
                                style: AppButtons.goForth(),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: _navigateToNewCategory,
                                icon: const Icon(Icons.add),
                                label: const Text('Create My Own Pursuit'),
                                style: AppButtons.finalize(),
                              ),
                            ],
                          ],
                        ),
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        'Rouse me to...',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontStyle: FontStyle.italic,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ),
                                    // Add Idea button — moved to Hit Me row as '+'
                                    // if (!_isReadOnly)
                                    //   TextButton.icon(
                                    //     icon: const Icon(Icons.add_task,
                                    //         color: Colors.deepPurple),
                                    //     label: const Text(
                                    //       'Add Idea',
                                    //       style: TextStyle(
                                    //           color: Colors.deepPurple,
                                    //           fontWeight:
                                    //               FontWeight.bold),
                                    //     ),
                                    //     onPressed: () {
                                    //       if (AuthUtils.isGuestUser()) {
                                    //         _showGuestSignupDialog(
                                    //           content:
                                    //               'Here\'s where you can add ${NamingUtils.tasksName()} once you\'re logged in. Sign up to create your own ${NamingUtils.categoriesName()} and ${NamingUtils.tasksName()}!',
                                    //         );
                                    //         return;
                                    //       }
                                    //       _navigateToNewContent();
                                    //     },
                                    //   ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    Flexible(
                                      fit: FlexFit.loose,
                                      child: () {
                                        final cat = _selectedCategory ??
                                            _categories.first;
                                        final headlineFontSize =
                                            (Theme.of(context)
                                                        .textTheme
                                                        .bodyLarge
                                                        ?.fontSize ??
                                                    16) +
                                                10;
                                        final headlineStyle = TextStyle(
                                          fontSize: headlineFontSize,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF1A237E),
                                        );
                                        if (cat.isShared) {
                                          return Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(cat.headline,
                                                  style: headlineStyle),
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    'from ${cat.ownerName}',
                                                    style: TextStyle(
                                                      fontSize:
                                                          headlineFontSize *
                                                              0.7,
                                                      fontStyle:
                                                          FontStyle.italic,
                                                      color: Color(0xFF1A237E),
                                                    ),
                                                  ),
                                                  // Guests can't own or borrow,
                                                  // so hide Copy/Remove for them.
                                                  if (!AuthUtils
                                                      .isGuestUser()) ...[
                                                    const SizedBox(width: 6),
                                                    IconButton(
                                                      onPressed: () async {
                                                        await showBorrowExplanationIfNeeded(
                                                            context);
                                                        if (mounted)
                                                          unawaited(
                                                              _showSnagPursuitScreen(
                                                                  cat));
                                                      },
                                                      icon: const Icon(
                                                          Icons.copy,
                                                          size: 22),
                                                      tooltip: 'Copy for Me',
                                                      color: Colors.green[800],
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                      padding: EdgeInsets.zero,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    IconButton(
                                                      onPressed: () =>
                                                          _releaseSharedCategory(
                                                              cat),
                                                      icon: const Icon(
                                                          Icons.playlist_remove,
                                                          size: 22),
                                                      tooltip:
                                                          'Remove from My List',
                                                      color: Colors.red[700],
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                      padding: EdgeInsets.zero,
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ],
                                          );
                                        }
                                        return Text(cat.headline,
                                            style: headlineStyle);
                                      }(),
                                    ),
                                    IconButton(
                                      tooltip:
                                          'Choose ${NamingUtils.categoriesName(capitalize: false, plural: false)}',
                                      icon: const Icon(
                                        Icons.arrow_drop_down,
                                        size: 32,
                                      ),
                                      // Enabled even at N==1 for non-guests so the
                                      // "New Pursuit" option is always reachable.
                                      onPressed: (_categories.length > 1 ||
                                              !AuthUtils.isGuestUser())
                                          ? () => PursuitSwitcherSheet.show(
                                                context,
                                                categories: _categories
                                                    .where((c) =>
                                                        !c.isShared ||
                                                        c.isAvailable)
                                                    .toList(),
                                                onSelect: (c) => unawaited(
                                                    _handleCategorySelection(c)),
                                                onNewPursuit:
                                                    AuthUtils.isGuestUser()
                                                        ? null
                                                        : _navigateToNewCategory,
                                              )
                                          : null,
                                    ),
                                  ],
                                ),
                                if ((_selectedCategory?.invitation ?? '')
                                    .trim()
                                    .isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  LinkifiedText(
                                    _selectedCategory!.invitation!,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (_selectedCategory != null) ...[
                            if (_cacheManager.currentTasks?.isNotEmpty ==
                                true) ...[
                              const SizedBox(height: 20),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Center(
                                      child: Row(
                                        mainAxisSize: _showTaskListMode
                                            ? MainAxisSize.max
                                            : MainAxisSize.min,
                                        children: [
                                          ElevatedButton.icon(
                                            onPressed: () async {
                                              try {
                                                setState(() {
                                                  _showTaskListMode = false;
                                                  _isLoadingTask = true;
                                                  _error = null;
                                                });
                                                if (_randomTask != null) {
                                                  await _rejectCurrentTask();
                                                }
                                                if (_selectedCategory != null) {
                                                  await _loadRandomTask(
                                                      _selectedCategory!);
                                                }
                                                unawaited(
                                                    _maybeNotifyNewShares());
                                              } catch (e) {
                                                print('Error in Hit Me: $e');
                                                setState(() {
                                                  _error = e.toString();
                                                  _isLoadingTask = false;
                                                });
                                              }
                                            },
                                            icon: const Icon(Icons.refresh),
                                            label: const Text(
                                              'Hit Me',
                                              style: TextStyle(fontSize: 18),
                                            ),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.green,
                                              foregroundColor: Colors.white,
                                              minimumSize: const Size(0, 44),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          if (_showTaskListMode)
                                            Expanded(
                                              child: _buildViewToggle(),
                                            )
                                          else
                                            _buildViewToggle(),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (!_isReadOnly) ...[
                                    const SizedBox(width: 12),
                                    SizedBox(
                                      width: 37,
                                      height: 37,
                                      child: ElevatedButton(
                                        onPressed: () {
                                          if (AuthUtils.isGuestUser()) {
                                            _showGuestSignupDialog(
                                              content:
                                                  'Here\'s where you can add ${NamingUtils.tasksName()} once you\'re logged in. Sign up to create your own ${NamingUtils.categoriesName()} and ${NamingUtils.tasksName()}!',
                                            );
                                            return;
                                          }
                                          _navigateToNewContent();
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.deepPurple,
                                          foregroundColor: Colors.white,
                                          padding: EdgeInsets.zero,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                        ),
                                        child: const Icon(Icons.add, size: 24),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 12),
                            ],
                          ],
                        ],
                      ),
                    // Sort controls — fixed above the divider
                    if (_showTaskListMode && _listModeTasks.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: _buildListModeSortWidget(),
                      ),
                    // Divider + scrollable content area
                    if (!_isLoading && _error == null && _categories.isNotEmpty && _selectedCategory != null) ...[
                      const Divider(height: 1),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                            if (_showTaskListMode)
                              _buildTaskListModeContent()
                            else if (_isLoadingTask ||
                                (_cacheManager.currentCategory?.id !=
                                        _selectedCategory?.id ||
                                    _cacheManager.currentTasks == null))
                              const Center(child: CircularProgressIndicator())
                            else if (_randomTask != null)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 14),
                                  SizedBox(
                                    width:
                                        MediaQuery.of(context).size.width - 32,
                                    child: Card(
                                      key: ValueKey(
                                        'task_${_randomTask!.id}_${_randomTask!.headline}',
                                      ),
                                      color: const Color(0xFF4A148C),
                                      child: Stack(
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              16,
                                              16,
                                              16,
                                              0,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Expanded(
                                                      child: GestureDetector(
                                                        onTap: () =>
                                                            _showEditPanel(
                                                          _randomTask!,
                                                        ),
                                                        child: Text(
                                                          _randomTask!.headline,
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .bodyLarge
                                                                  ?.copyWith(
                                                                    fontSize:
                                                                        22,
                                                                    fontWeight: _randomTask!.suggestibleAt ==
                                                                                null ||
                                                                            !_randomTask!.suggestibleAt!
                                                                                .isAfter(
                                                                              DateTime.now(),
                                                                            )
                                                                        ? FontWeight
                                                                            .bold
                                                                        : FontWeight
                                                                            .normal,
                                                                    color: _randomTask!.suggestibleAt !=
                                                                                null &&
                                                                            _randomTask!.suggestibleAt!
                                                                                .isAfter(
                                                                              DateTime.now(),
                                                                            )
                                                                        ? Colors
                                                                            .white70
                                                                        : Colors
                                                                            .white,
                                                                  ),
                                                        ),
                                                      ),
                                                    ),
                                                    if (!AuthUtils
                                                            .isGuestUser() &&
                                                        !_isReadOnly) ...[
                                                      PopupMenuButton<String>(
                                                        icon: const Icon(
                                                            Icons.more_vert,
                                                            size: 20,
                                                            color:
                                                                Colors.white),
                                                        padding:
                                                            EdgeInsets.zero,
                                                        onSelected: (value) {
                                                          switch (value) {
                                                            case 'edit':
                                                              _showEditPanel(
                                                                  _randomTask!);
                                                            case 'delete':
                                                              _deleteTaskFromList(
                                                                  _randomTask!);
                                                          }
                                                        },
                                                        itemBuilder: (_) => [
                                                          const PopupMenuItem<
                                                              String>(
                                                            value: 'edit',
                                                            child: ListTile(
                                                              leading: Icon(
                                                                  Icons.edit),
                                                              title:
                                                                  Text('Edit'),
                                                              contentPadding:
                                                                  EdgeInsets
                                                                      .zero,
                                                            ),
                                                          ),
                                                          const PopupMenuItem<
                                                              String>(
                                                            value: 'delete',
                                                            child: ListTile(
                                                              leading: Icon(
                                                                  Icons.delete,
                                                                  color: Colors
                                                                      .red),
                                                              title: Text(
                                                                  'Delete',
                                                                  style: TextStyle(
                                                                      color: Colors
                                                                          .red)),
                                                              contentPadding:
                                                                  EdgeInsets
                                                                      .zero,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                                if (_randomTask!.finished) ...[
                                                  const SizedBox(width: 8),
                                                  const Icon(
                                                    Icons.check_circle,
                                                    color: Colors.green,
                                                    size: 28,
                                                  ),
                                                ],
                                                // Show notes if they exist (user-entered content)
                                                if (_randomTask!.notes !=
                                                        null &&
                                                    _randomTask!
                                                        .notes!.isNotEmpty) ...[
                                                  const SizedBox(height: 8),
                                                  Html(
                                                    data:
                                                        _preprocessNotesForHtml(
                                                            _randomTask!
                                                                .notes!),
                                                    style: {
                                                      "body": Style(
                                                        fontSize: FontSize(
                                                          Theme.of(context)
                                                                  .textTheme
                                                                  .bodyMedium
                                                                  ?.fontSize ??
                                                              14,
                                                        ),
                                                        color: _randomTask!
                                                                        .suggestibleAt !=
                                                                    null &&
                                                                _randomTask!
                                                                    .suggestibleAt!
                                                                    .isAfter(
                                                                        DateTime
                                                                            .now())
                                                            ? Colors.white70
                                                            : Colors.white,
                                                        margin: Margins.zero,
                                                        padding:
                                                            HtmlPaddings.zero,
                                                      ),
                                                      "a": Style(
                                                        color: Colors.white,
                                                        textDecoration:
                                                            TextDecoration
                                                                .underline,
                                                      ),
                                                    },
                                                    onLinkTap: (url,
                                                        htmlContext,
                                                        attributes) async {
                                                      if (url != null) {
                                                        try {
                                                          final uri =
                                                              Uri.parse(url);
                                                          if (await canLaunchUrl(
                                                              uri)) {
                                                            await launchUrl(uri,
                                                                mode: LaunchMode
                                                                    .externalApplication);
                                                          }
                                                        } catch (e) {
                                                          // Error handling without verbose logging
                                                        }
                                                      }
                                                    },
                                                  ),
                                                ],
                                                // Show synopsis if it exists (auto-fetched or stored)
                                                if ((_randomTask!.synopsis !=
                                                            null &&
                                                        _randomTask!.synopsis!
                                                            .isNotEmpty) ||
                                                    (_fetchedSynopsis != null &&
                                                        _fetchedSynopsis!
                                                            .isNotEmpty)) ...[
                                                  const SizedBox(height: 8),
                                                  Html(
                                                    data: _fetchedSynopsis ??
                                                        _randomTask!.synopsis ??
                                                        '',
                                                    style: {
                                                      "body": Style(
                                                        fontSize: FontSize(
                                                          Theme.of(context)
                                                                  .textTheme
                                                                  .bodyMedium
                                                                  ?.fontSize ??
                                                              14,
                                                        ),
                                                        fontStyle:
                                                            FontStyle.italic,
                                                        color: _randomTask!
                                                                        .suggestibleAt !=
                                                                    null &&
                                                                _randomTask!
                                                                    .suggestibleAt!
                                                                    .isAfter(
                                                                        DateTime
                                                                            .now())
                                                            ? Colors.white70
                                                            : Colors.white,
                                                        margin: Margins.zero,
                                                        padding:
                                                            HtmlPaddings.zero,
                                                      ),
                                                      "a": Style(
                                                        color: Colors.white,
                                                        textDecoration:
                                                            TextDecoration
                                                                .underline,
                                                        fontStyle:
                                                            FontStyle.italic,
                                                      ),
                                                    },
                                                    onLinkTap: (url,
                                                        htmlContext,
                                                        attributes) async {
                                                      if (url != null) {
                                                        try {
                                                          final uri =
                                                              Uri.parse(url);
                                                          if (await canLaunchUrl(
                                                              uri)) {
                                                            await launchUrl(uri,
                                                                mode: LaunchMode
                                                                    .externalApplication);
                                                          }
                                                        } catch (e) {
                                                          // Error handling without verbose logging
                                                        }
                                                      }
                                                    },
                                                  ),
                                                ],
                                                // Show loading indicator if fetching synopsis
                                                if (_isFetchingSynopsis) ...[
                                                  const SizedBox(height: 8),
                                                  Row(
                                                    children: [
                                                      const SizedBox(
                                                        width: 16,
                                                        height: 16,
                                                        child:
                                                            CircularProgressIndicator(
                                                                strokeWidth: 2),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        'Fetching description...',
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .bodySmall
                                                            ?.copyWith(
                                                              fontStyle:
                                                                  FontStyle
                                                                      .italic,
                                                              color: Colors
                                                                  .white70,
                                                            ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                                if (_randomTask!.links !=
                                                        null &&
                                                    _randomTask!
                                                        .links!.isNotEmpty) ...[
                                                  /* if (_randomTask!.notes != null)
                                            const SizedBox(height: 16)
                                          else
                                           */
                                                  const SizedBox(height: 14),
                                                  Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: _randomTask!
                                                        .links!
                                                        .map((link) => Padding(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .only(
                                                                      bottom:
                                                                          4),
                                                              child:
                                                                  LinkDisplayWidget(
                                                                linkText: link,
                                                                showIcon: true,
                                                                showTitle: true,
                                                              ),
                                                            ))
                                                        .toList(),
                                                  ),
                                                ],
                                                if (_randomTask!.triggersAt !=
                                                    null) ...[
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    'Triggers at: ${_randomTask!.triggersAt!.toLocal().toString().split('.')[0]}',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          color: Colors.white70,
                                                        ),
                                                  ),
                                                ],
                                                if (_randomTask!
                                                            .suggestibleAt !=
                                                        null &&
                                                    _randomTask!.suggestibleAt!
                                                        .isAfter(
                                                      DateTime.now(),
                                                    )) ...[
                                                  const SizedBox(height: 8),
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          _randomTask!
                                                              .getSuggestibleTimeDisplay()!,
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .bodySmall
                                                                  ?.copyWith(
                                                                    color: Colors
                                                                        .lightBlueAccent,
                                                                  ),
                                                        ),
                                                      ),
                                                      if (!_isReadOnly)
                                                        TextButton.icon(
                                                          onPressed: () async {
                                                            await _reviveCurrentTask();
                                                          },
                                                          icon: const Icon(
                                                            Icons.refresh,
                                                            size: 16,
                                                          ),
                                                          label: const Text(
                                                              'Revive'),
                                                          style: TextButton
                                                              .styleFrom(
                                                            foregroundColor: Colors
                                                                .lightBlueAccent,
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                              horizontal: 8,
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ],
                                                if (!_isReadOnly) ...[
                                                  const SizedBox(height: 2),
                                                  Center(
                                                    child: TextButton.icon(
                                                      onPressed:
                                                          _finishCurrentTask,
                                                      icon: const Icon(
                                                          Icons.check),
                                                      label: const Text(
                                                        'Actually, I\'m done with this',
                                                      ),
                                                      style:
                                                          TextButton.styleFrom(
                                                        foregroundColor:
                                                            Colors.white,
                                                        padding:
                                                            EdgeInsets.zero,
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                      ),
                                                    ),
                                                  ),
                                                ] else if (!AuthUtils
                                                    .isGuestUser()) ...[
                                                  // Guests preview read-only —
                                                  // no snag button.
                                                  const SizedBox(height: 8),
                                                  Center(
                                                    child: ElevatedButton.icon(
                                                      onPressed: () =>
                                                          _snagCurrentTask(),
                                                      icon: const Icon(
                                                          Icons.download,
                                                          size: 18),
                                                      label: const Text(
                                                          'Snag this'),
                                                      style: ElevatedButton
                                                          .styleFrom(
                                                        backgroundColor:
                                                            Colors.white,
                                                        foregroundColor:
                                                            const Color(
                                                                0xFF4A148C),
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 16,
                                                                vertical: 8),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 16),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                ],
                              )
                            else
                              Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(height: 24),
                                    Text(
                                      'All out of ${NamingUtils.tasksName(plural: true, capitalize: false)}!',
                                      style: const TextStyle(fontSize: 21),
                                    ),
                                    if (_cacheManager.currentTasks?.isEmpty ==
                                        true) ...[
                                      const SizedBox(height: 24),
                                      ElevatedButton.icon(
                                        onPressed: _isReadOnly
                                            ? () => unawaited(
                                                _addIdeaViaPickedPursuit())
                                            : _navigateToNewContent,
                                        icon: const Icon(Icons.add_task,
                                            size: 24),
                                        label: Text(
                                          'Add ${NamingUtils.tasksName(plural: false, capitalize: false, withArticle: true)}',
                                          style: const TextStyle(fontSize: 20),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          foregroundColor: Colors.white,
                                          minimumSize: const Size(200, 56),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                          // Guest mode indicator
                          if (AuthUtils.isGuestUser()) ...[
                      const SizedBox(height: 24),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.orange.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: Colors.orange[700],
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'You\'re in guest mode, so you can play with demo data. Sign up/in for full access to making your own ${NamingUtils.categoriesName()} and ${NamingUtils.tasksName()}.',
                                    style: TextStyle(
                                      color: Colors.orange[700],
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pushNamed(context, '/auth');
                                },
                                icon: const Icon(Icons.login, size: 18),
                                label: const Text('Sign Up / Sign In'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange[700],
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                          ],  // close guest ...[
                        ],  // close Column.children
                      ),    // close Column
                    ),      // close SingleChildScrollView
                  ),        // close Expanded
                    ],      // close if (!_isLoading...) ...[
                  ],
                ),
              ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_selectedCategory != null && !AuthUtils.isGuestUser()) ...[
              // Info and Share buttons commented out for simplified interface
              // FloatingActionButton(
              //   onPressed: () => _showCategoryInfo(_selectedCategory!),
              //   tooltip: 'Show category information',
              //   backgroundColor: Colors.orange[600],
              //   foregroundColor: Colors.white,
              //   child: const Icon(Icons.info_outline),
              // ),
              // const SizedBox(width: 16),
              // FloatingActionButton(
              //   onPressed: () => _shareCategory(_selectedCategory!),
              //   tooltip: 'Share category',
              //   backgroundColor: Colors.green[600],
              //   foregroundColor: Colors.white,
              //   child: const Icon(Icons.share),
              // ),
              // const SizedBox(width: 16),
            ],
          ],
        ),
      ),
    );
  }
}

/// A circled question-mark rendered with Flutter primitives.
/// Avoids dependency on the MaterialIcons font, which is tree-shaken on web.
class _HelpIcon extends StatelessWidget {
  final double size;
  const _HelpIcon({this.size = 20});

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? Colors.white;
    final fontSize = size * 0.6;
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: size * 0.08),
        ),
        child: Center(
          child: Text(
            '?',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              color: color,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

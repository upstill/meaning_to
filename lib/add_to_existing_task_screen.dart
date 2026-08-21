import 'dart:async';
import 'package:flutter/material.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/utils/api_client.dart';
import 'package:meaning_to/utils/naming.dart';
import 'package:meaning_to/widgets/task_search_results.dart';

/// Full-screen picker: search across all owned pursuits by headline and choose
/// an existing task. Pops with the selected `(Task, Category)` record, or null
/// if the user backs out.
///
/// Reuses [ApiClient.searchTasksByHeadline] and the shared [TaskSearchResults]
/// grouped-results rendering (same UX as Home's global search).
class AddToExistingTaskScreen extends StatefulWidget {
  const AddToExistingTaskScreen({super.key});

  @override
  State<AddToExistingTaskScreen> createState() =>
      _AddToExistingTaskScreenState();
}

class _AddToExistingTaskScreenState extends State<AddToExistingTaskScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  List<Category> _categories = [];
  List<Task> _results = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await ApiClient.getCategories();
      if (!mounted) return;
      // Only owned pursuits can receive a link.
      setState(() =>
          _categories = categories.where((c) => !c.isShared).toList());
    } catch (e) {
      print('AddToExistingTaskScreen: Error loading categories: $e');
    }
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _results = [];
        _isSearching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), _performSearch);
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _results = [];
          _isSearching = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _isSearching = true);
    try {
      final tasks = await ApiClient.searchTasksByHeadline(query);
      if (!mounted) return;
      // Restrict to owned pursuits we know about (borrowed shares can't receive).
      final ownedIds = _categories.map((c) => c.id).toSet();
      setState(() {
        _results = tasks.where((t) => ownedIds.contains(t.categoryId)).toList();
        _isSearching = false;
      });
    } catch (e) {
      print('AddToExistingTaskScreen: Error searching: $e');
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _selectTask(Task task, Category category) {
    Navigator.of(context).pop((task: task, category: category));
  }

  @override
  Widget build(BuildContext context) {
    final tasksNoun = NamingUtils.tasksName(capitalize: false, plural: false);
    return Scaffold(
      appBar: AppBar(
        title: Text('Add to which $tasksNoun?'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search your ${NamingUtils.tasksName(plural: true)}...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onChanged: _onQueryChanged,
              onSubmitted: (_) => _performSearch(),
            ),
          ),
          Expanded(
            child: TaskSearchResults(
              results: _results,
              isSearching: _isSearching,
              query: _searchController.text,
              categories: _categories,
              taskTileBuilder: (task, category) {
                final linkCount = task.links?.length ?? 0;
                return ListTile(
                  leading: Icon(Icons.task_alt,
                      color: Theme.of(context).colorScheme.primary),
                  title: Text(
                    task.headline,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '$linkCount link${linkCount == 1 ? '' : 's'}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  dense: true,
                  onTap: () => _selectTask(task, category),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

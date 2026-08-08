import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meaning_to/utils/api_client.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/home_screen.dart';

/// A group of suggested Pursuits sharing a declared category.
typedef _Idea = ({int id, String headline});
typedef _Group = ({String category, List<_Idea> items});

/// "Ideas for Using RouzMe" Help content: a curated set of starter Pursuits,
/// grouped by category. Signed-in users can tick the ones they want and create
/// them (each new Pursuit records the source id as its `original_id`); guests
/// and logged-out users see the same list as plain, read-only text.
///
/// Source of truth: documents/Categories.csv (rows with a non-empty `category`).
/// Kept as a constant here because the app can't read that file at runtime.
class IdeasForUsingSection extends StatefulWidget {
  const IdeasForUsingSection({super.key});

  @override
  State<IdeasForUsingSection> createState() => _IdeasForUsingSectionState();
}

class _IdeasForUsingSectionState extends State<IdeasForUsingSection> {
  static const List<_Group> _groups = [
    (
      category: 'Media & Entertainment',
      items: [
        (id: 1, headline: 'Watch A Movie'),
        (id: 2, headline: 'Start a TV Series'),
        (id: 41, headline: 'Try Out Some New Music'),
        (id: 54, headline: 'Play a Favorite Record'),
        (id: 74, headline: 'Put on a Playlist'),
      ],
    ),
    (
      category: 'Living',
      items: [
        (id: 3, headline: 'Reach out to someone'),
        (id: 20, headline: 'Go on an Outing'),
        (id: 43, headline: 'Try Out a New Restaurant'),
        (id: 45, headline: 'Cook Something New'),
        (id: 48, headline: 'Tackle a Project'),
        (id: 53, headline: "Do Something I've Been Putting Off"),
        (id: 223, headline: 'Give a Great Gift'),
      ],
    ),
    (
      category: 'Thinking and Learning',
      items: [
        (id: 35, headline: 'Pick Up a Book'),
        (id: 42, headline: 'Absorb a Thought'),
        (id: 44, headline: 'Read an Article'),
        (id: 46, headline: 'Watch a TED Talk'),
        (id: 47, headline: 'Read a Poem'),
        (id: 49, headline: 'Sign Up for a Course'),
        (id: 50, headline: 'Take a Lesson'),
        (id: 51, headline: 'Think for a Minute'),
        (id: 224, headline: 'Ponder One Idea Today'),
      ],
    ),
    (
      category: 'Self-care',
      items: [
        (id: 40, headline: 'Limber Up'),
        (id: 52, headline: 'Take a Hit of Awe'),
        (id: 65, headline: 'Do Something Nice for Myself'),
        (id: 225, headline: 'Get Out Of My Chair and Move'),
      ],
    ),
  ];

  /// `original_id`s of Pursuits the current user already owns.
  Set<int> _ownedOriginalIds = {};
  final Set<int> _selected = {};
  bool _loading = true;
  bool _creating = false;

  bool get _signedIn =>
      Supabase.instance.client.auth.currentUser != null &&
      !AuthUtils.isGuestUser();

  @override
  void initState() {
    super.initState();
    if (_signedIn) {
      _loadOwned();
    } else {
      _loading = false;
    }
  }

  Future<void> _loadOwned() async {
    try {
      final categories = await ApiClient.getCategories();
      // Only the user's OWN creations count as "added" — a borrowed/sample
      // share (new users get these seeded) shouldn't lock the idea, since the
      // whole point here is to let them build their own starting set. Borrowed
      // source rows are self-referential (id == original_id), so without this
      // filter every seeded sample would show "(added)" and disable Create.
      final owned = categories
          .where((c) => !c.isShared)
          .map((c) => c.originalId)
          .whereType<int>()
          .toSet();
      if (mounted) {
        setState(() {
          _ownedOriginalIds = owned;
          _loading = false;
        });
      }
    } catch (e) {
      print('IdeasForUsingSection: Error loading owned categories: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createSelected() async {
    if (_selected.isEmpty || _creating) return;
    setState(() => _creating = true);

    final userId = AuthUtils.getCurrentUserId();
    // Snapshot the chosen ideas so a concurrent rebuild can't shift them.
    final chosen = [
      for (final g in _groups)
        for (final item in g.items)
          if (_selected.contains(item.id)) item,
    ];

    int created = 0;
    for (final idea in chosen) {
      try {
        await ApiClient.createCategory({
          'headline': idea.headline,
          'owner_id': userId,
          'original_id': idea.id,
        });
        created++;
      } catch (e) {
        print('IdeasForUsingSection: Error creating "${idea.headline}": $e');
      }
    }

    if (!mounted) return;
    _selected.clear();
    await _loadOwned();
    if (created > 0) HomeScreen.markDataModified();

    if (mounted) {
      setState(() => _creating = false);
      if (created > 0) {
        await _showCreatedReminder(created);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nothing created.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  /// After creating starter Pursuits, remind the user they arrive EMPTY — it's
  /// on them to stock each one with their own Ideas.
  Future<void> _showCreatedReminder(int created) async {
    final pursuits = created == 1 ? 'Pursuit' : 'Pursuits';
    final them = created == 1 ? 'it' : 'them';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Created $created $pursuits'),
        content: Text(
          "Your new $pursuits start out empty — it's up to you to fill $them "
          'with your own Ideas! Pick a Pursuit on the Home screen and tap '
          '"Add an Idea" to get going.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const bodyStyle = TextStyle(fontSize: 15, height: 1.5);

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    // For signed-in users, drop ideas they've already created their own copy
    // of (and any group left empty) — no point offering what's already there.
    final visibleGroups = _signedIn
        ? [
            for (final g in _groups)
              if (g.items.any((i) => !_ownedOriginalIds.contains(i.id)))
                (
                  category: g.category,
                  items: [
                    for (final i in g.items)
                      if (!_ownedOriginalIds.contains(i.id)) i
                  ]
                ),
          ]
        : _groups;

    final children = <Widget>[
      const Text(
        'So you can get a feel for what RouzMe can do for you, here are some '
        'Pursuits that have turned up so far.',
        style: bodyStyle,
      ),
    ];

    // Signed in but nothing left to offer → they've added them all.
    if (_signedIn && visibleGroups.isEmpty) {
      children.add(const SizedBox(height: 8));
      children.add(const Text(
        "You've added all of these to your own collection. Nice!",
        style: bodyStyle,
      ));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      );
    }

    if (_signedIn) {
      children.add(const SizedBox(height: 8));
      children.add(const Text(
        "Build yourself a starting set by ticking the ones you'd like for "
        'your own and hit the Create button.',
        style: bodyStyle,
      ));
    }

    for (final group in visibleGroups) {
      children.add(const SizedBox(height: 20));
      children.add(Text(
        group.category,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ));
      children.add(const SizedBox(height: 4));
      for (final item in group.items) {
        children.add(_signedIn ? _buildCheckItem(item) : _buildTextItem(item));
      }
    }

    if (_signedIn) {
      children.add(const SizedBox(height: 20));
      children.add(Align(
        alignment: Alignment.centerLeft,
        child: ElevatedButton.icon(
          onPressed:
              (_selected.isEmpty || _creating) ? null : _createSelected,
          icon: _creating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add),
          label: Text(_creating
              ? 'Creating...'
              : _selected.isEmpty
                  ? 'Create'
                  : 'Create ${_selected.length}'),
        ),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildCheckItem(_Idea item) {
    final owned = _ownedOriginalIds.contains(item.id);
    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: owned || _selected.contains(item.id),
      // Owned Pursuits are shown ticked and locked so they can't be re-created.
      onChanged: owned
          ? null
          : (checked) {
              setState(() {
                if (checked ?? false) {
                  _selected.add(item.id);
                } else {
                  _selected.remove(item.id);
                }
              });
            },
      title: Text(
        owned ? '${item.headline}  (added)' : item.headline,
        style: TextStyle(
          fontSize: 15,
          color: owned ? Colors.grey : null,
        ),
      ),
    );
  }

  Widget _buildTextItem(_Idea item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Text('•  ${item.headline}',
          style: const TextStyle(fontSize: 15, height: 1.5)),
    );
  }
}

import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/utils/cache_manager.dart';
import 'package:meaning_to/utils/supabase_client.dart';

/// Result of ordering owned pursuits by "sensibility" for a taken/incoming task.
/// [ordered] is the full list most-sensible first (element 0 is the default
/// pick); [suggested]/[recent]/[domainScores] are the component signals, exposed
/// so a UI (e.g. CategoryPickerDialog) can render them in sections if it wants.
class CategoryOrdering {
  final List<Category> ordered;
  final List<Category> suggested;
  final List<Category> recent;
  final Map<int, int> domainScores; // category id -> tasks linking the domain

  const CategoryOrdering({
    required this.ordered,
    required this.suggested,
    required this.recent,
    required this.domainScores,
  });
}

/// Order [owned] pursuits by sensibility for a task about to be filed:
/// suggested (by original_id) → recently used → remaining sorted by how many of
/// their tasks already link the same domain, then alphabetically. This is the
/// single source of truth shared by the pursuit selector (TaskEditScreen) and
/// the CategoryPickerDialog so both "favor those that appeared before".
Future<CategoryOrdering> orderCategoriesBySensibility(
  List<Category> owned, {
  List<int>? suggestedOriginalIds,
  String? linkUrl,
}) async {
  final suggested = _suggestedCategories(owned, suggestedOriginalIds);
  final recent = await _recentCategories(owned);
  final domainScores = await _domainRelevanceScores(owned, linkUrl);

  final prioritized = <Category>[];
  for (final s in suggested) {
    if (!prioritized.contains(s)) prioritized.add(s);
  }
  for (final r in recent) {
    if (owned.contains(r) && !prioritized.contains(r)) prioritized.add(r);
  }

  final remaining = owned.where((c) => !prioritized.contains(c)).toList();
  if (domainScores.isNotEmpty) {
    remaining.sort((a, b) {
      final sa = domainScores[a.id] ?? 0;
      final sb = domainScores[b.id] ?? 0;
      if (sb != sa) return sb.compareTo(sa);
      return a.headline.compareTo(b.headline);
    });
  }

  return CategoryOrdering(
    ordered: [...prioritized, ...remaining],
    suggested: suggested,
    recent: recent,
    domainScores: domainScores,
  );
}

List<Category> _suggestedCategories(
    List<Category> owned, List<int>? suggestedOriginalIds) {
  if (suggestedOriginalIds == null || suggestedOriginalIds.isEmpty) return [];
  final suggested = <Category>[];
  for (final id in suggestedOriginalIds) {
    final match = owned.where((c) => c.originalId == id).firstOrNull;
    if (match != null && !suggested.contains(match)) suggested.add(match);
  }
  return suggested;
}

Future<List<Category>> _recentCategories(List<Category> owned) async {
  try {
    final recentIds = await CacheManager.getRecentCategoryIds();
    final recent = <Category>[];
    for (final id in recentIds) {
      final match = owned.where((c) => c.id == id).firstOrNull;
      if (match != null) recent.add(match);
    }
    return recent;
  } catch (e) {
    print('CategoryOrdering: Error loading recent categories: $e');
    return [];
  }
}

/// For each category, count how many of its tasks (and tasks of categories
/// sharing its original_id) already link the taken URL's domain.
Future<Map<int, int>> _domainRelevanceScores(
    List<Category> owned, String? linkUrl) async {
  final scores = <int, int>{};
  if (linkUrl == null || linkUrl.isEmpty) return scores;

  try {
    final uri = Uri.tryParse(linkUrl);
    if (uri == null) return scores;
    final domain = uri.host;
    if (domain.isEmpty) return scores;

    for (final category in owned) {
      final relatedIds = <int>{category.id};
      if (category.originalId != null) {
        for (final other in owned) {
          if (other.originalId == category.originalId) relatedIds.add(other.id);
        }
      }
      for (final other in owned) {
        if (other.originalId == category.id) relatedIds.add(other.id);
      }

      final response = await supabase
          .from('Tasks')
          .select('id, links')
          .inFilter('category_id', relatedIds.toList());

      int matchCount = 0;
      for (final taskData in (response as List<dynamic>)) {
        final links = taskData['links'] as List<dynamic>?;
        if (links == null) continue;
        for (final link in links) {
          if (link is String && link.contains(domain)) {
            matchCount++;
            break;
          }
        }
      }
      scores[category.id] = matchCount;
    }
  } catch (e) {
    print('CategoryOrdering: Error calculating domain relevance scores: $e');
  }

  return scores;
}

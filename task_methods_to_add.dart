// Methods to add to the Task class in lib/models/task.dart

/// Evaluates whether this task is currently suggestible.
/// A task is suggestible if:
/// 1. It is not finished
/// 2. It has no suggestibleAt time set, OR the suggestibleAt time has passed
///
/// This method handles timezone conversion from UTC to local time for consistent comparison.
bool get isSuggestible {
  if (finished) return false;

  if (suggestibleAt == null) return true;

  // Convert UTC time to local time for comparison
  final suggestibleAtLocal = suggestibleAt!.toLocal();
  final now = DateTime.now();

  return !suggestibleAtLocal.isAfter(now);
}

/// Evaluates whether this task is currently deferred (not suggestible).
/// A task is deferred if it has a suggestibleAt time that is in the future.
///
/// This method handles timezone conversion from UTC to local time for consistent comparison.
bool get isDeferred {
  if (finished) return false;

  if (suggestibleAt == null) return false;

  // Convert UTC time to local time for comparison
  final suggestibleAtLocal = suggestibleAt!.toLocal();
  final now = DateTime.now();

  return suggestibleAtLocal.isAfter(now);
}

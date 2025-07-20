class NamingUtils {
  // Const fields for base names
  static const String _pursuitSingular = 'pursuit';
  static const String _pursuitPlural = 'pursuits';
  static const String _ideaSingular = 'idea';
  static const String _ideaPlural = 'ideas';

  // Const fields for capitalized versions
  static const String _pursuitSingularCapitalized = 'Pursuit';
  static const String _pursuitPluralCapitalized = 'Pursuits';
  static const String _ideaSingularCapitalized = 'Idea';
  static const String _ideaPluralCapitalized = 'Ideas';

  // Const fields for articles
  static const String _aPursuitSingular = 'a pursuit';
  static const String _aPursuitPlural = 'a pursuits';
  static const String _anIdeaSingular = 'an idea';
  static const String _anIdeaPlural = 'an ideas';

  /// Get the name for categories with configurable case and pluralization
  static String categoriesName(
      {bool capitalize = true, bool plural = true, bool withArticle = false}) {
    if (withArticle) {
      if (plural) {
        return capitalize ? _aPursuitPlural : _aPursuitPlural;
      } else {
        return capitalize ? _aPursuitSingular : _aPursuitSingular;
      }
    }

    if (plural) {
      return capitalize ? _pursuitPluralCapitalized : _pursuitPlural;
    } else {
      return capitalize ? _pursuitSingularCapitalized : _pursuitSingular;
    }
  }

  /// Get the name for tasks with configurable case and pluralization
  static String tasksName(
      {bool capitalize = true, bool plural = true, bool withArticle = false}) {
    if (withArticle) {
      if (plural) {
        return capitalize ? _anIdeaPlural : _anIdeaPlural;
      } else {
        return capitalize ? _anIdeaSingular : _anIdeaSingular;
      }
    }

    if (plural) {
      return capitalize ? _ideaPluralCapitalized : _ideaPlural;
    } else {
      return capitalize ? _ideaSingularCapitalized : _ideaSingular;
    }
  }

  // Const fields for common use cases
  static const String categoriesNamePlural = _pursuitPluralCapitalized;
  static const String categoriesNameSingular = _pursuitSingularCapitalized;
  static const String tasksNamePlural = _ideaPluralCapitalized;
  static const String tasksNameSingular = _ideaSingularCapitalized;
}

class NamingUtils {
  /// Get the name for categories with configurable case and pluralization
  static String categoriesName(
      {bool capitalize = true, bool plural = true, bool withArticle = false}) {
    String base = 'pursuit';

    if (plural) {
      base = 'pursuits';
    }

    if (capitalize) {
      base = base[0].toUpperCase() + base.substring(1);
    }

    if (withArticle) {
      final firstLetter = base[0].toLowerCase();
      if (firstLetter == 'a' ||
          firstLetter == 'e' ||
          firstLetter == 'i' ||
          firstLetter == 'o' ||
          firstLetter == 'u') {
        return 'an $base';
      } else {
        return 'a $base';
      }
    }

    return base;
  }

  /// Get the name for tasks with configurable case and pluralization
  static String tasksName(
      {bool capitalize = true, bool plural = true, bool withArticle = false}) {
    String base = 'idea';

    if (plural) {
      base = 'ideas';
    }

    if (capitalize) {
      base = base[0].toUpperCase() + base.substring(1);
    }

    if (withArticle) {
      final firstLetter = base[0].toLowerCase();
      if (firstLetter == 'a' ||
          firstLetter == 'e' ||
          firstLetter == 'i' ||
          firstLetter == 'o' ||
          firstLetter == 'u') {
        return 'an $base';
      } else {
        return 'a $base';
      }
    }

    return base;
  }
}

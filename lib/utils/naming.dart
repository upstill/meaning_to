class NamingUtils {
  /// Get the name for categories with configurable case and pluralization
  static String categoriesName({bool capitalize = true, bool plural = true}) {
    String base = 'pursuit';

    if (plural) {
      base = 'pursuits';
    }

    if (capitalize) {
      return base[0].toUpperCase() + base.substring(1);
    }

    return base;
  }

  /// Get the name for tasks with configurable case and pluralization
  static String tasksName({bool capitalize = true, bool plural = true}) {
    String base = 'idea';

    if (plural) {
      base = 'ideas';
    }

    if (capitalize) {
      return base[0].toUpperCase() + base.substring(1);
    }

    return base;
  }
}

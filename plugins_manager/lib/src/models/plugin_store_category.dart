import 'package:equatable/equatable.dart';

/// קטגוריה מנוהלת בחנות התוספים של האתר — היחידה שהחליפה את התגיות
/// כניווט הראשי (`/api/plugins/store-home` ו-`/api/plugins/categories/<slug>`).
///
/// ה-slug הוא המפתח היציב: הוא זה שנשמר על כל תוסף בקטלוג ולפיו מסננים.
/// מזהה מסד-הנתונים והאייקון (שם Material Symbols של האתר) אינם נשמרים —
/// אין להם שימוש בלאנצ'ר.
class PluginStoreCategory extends Equatable {
  const PluginStoreCategory({
    required this.slug,
    required this.name,
    this.description = '',
    this.showOnHome = false,
    this.homeLimit = defaultHomeLimit,
    this.pluginIds = const [],
  });

  /// ברירת המחדל של האתר לכמות בשורת דף-הבית.
  static const int defaultHomeLimit = 6;

  final String slug;
  final String name;
  final String description;

  /// האם הקטגוריה מקבלת שורה משלה בדף הבית של החנות.
  final bool showOnHome;

  /// כמה תוספים מוצגים באותה שורה לפני "לכל הקטגוריה".
  final int homeLimit;

  /// מזהי התוספים המשובצים, **בסדר התצוגה הידני** שנקבע באתר.
  final List<String> pluginIds;

  int get pluginCount => pluginIds.length;

  PluginStoreCategory copyWith({List<String>? pluginIds}) =>
      PluginStoreCategory(
        slug: slug,
        name: name,
        description: description,
        showOnHome: showOnHome,
        homeLimit: homeLimit,
        pluginIds: pluginIds ?? this.pluginIds,
      );

  /// בונה קטגוריה מתשובת האתר. `plugins` קיים רק בדף הקטגוריה ובקטגוריות
  /// שמסומנות להצגה בדף הבית — בשאר המקרים החברות נשלפת בנפרד.
  factory PluginStoreCategory.fromApi(Map<String, dynamic> json) {
    return PluginStoreCategory(
      slug: json['slug'] is String ? json['slug'] as String : '',
      name: json['name'] is String ? json['name'] as String : '',
      description:
          json['description'] is String ? json['description'] as String : '',
      showOnHome: json['showOnHome'] == true,
      homeLimit: _homeLimit(json['homeLimit']),
      pluginIds: _idsFrom(json['plugins']),
    );
  }

  Map<String, dynamic> toJson() => {
        'slug': slug,
        'name': name,
        'description': description,
        'showOnHome': showOnHome,
        'homeLimit': homeLimit,
        'plugins': pluginIds,
      };

  /// רשומה בלי slug אינה שמישה (אין לפיה סינון) ולכן מדולגת.
  static PluginStoreCategory? fromJson(Object? json) {
    if (json is! Map) return null;
    final slug = json['slug'];
    if (slug is! String || slug.isEmpty) return null;
    return PluginStoreCategory(
      slug: slug,
      name: json['name'] is String ? json['name'] as String : slug,
      description:
          json['description'] is String ? json['description'] as String : '',
      showOnHome: json['showOnHome'] == true,
      homeLimit: _homeLimit(json['homeLimit']),
      pluginIds: json['plugins'] is List
          ? (json['plugins'] as List)
              .whereType<String>()
              .toList(growable: false)
          : const [],
    );
  }

  static int _homeLimit(Object? value) =>
      value is int && value > 0 ? value : defaultHomeLimit;

  static List<String> _idsFrom(Object? plugins) {
    if (plugins is! List) return const [];
    return [
      for (final raw in plugins)
        if (raw is Map &&
            raw['id'] is String &&
            (raw['id'] as String).isNotEmpty)
          raw['id'] as String,
    ];
  }

  @override
  List<Object?> get props =>
      [slug, name, description, showOnHome, homeLimit, pluginIds];
}

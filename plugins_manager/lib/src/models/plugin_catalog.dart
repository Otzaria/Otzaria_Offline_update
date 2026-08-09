import 'plugin_store_category.dart';
import 'plugin_store_home.dart';
import 'store_plugin.dart';

/// הקטלוג המקומי כולו — מה שנשמר ל-`catalog.json` בתוך המראה.
class PluginCatalog {
  const PluginCatalog({
    this.lastSync,
    this.plugins = const [],
    this.categories = const [],
    this.home = PluginStoreHome.empty,
  });

  static const PluginCatalog empty = PluginCatalog();

  /// מועד הסנכרון האחרון (UTC ISO-8601), או null אם מעולם לא סונכרן.
  final DateTime? lastSync;
  final List<StorePlugin> plugins;

  /// קטגוריות החנות, בסדר שנקבע באתר. ריק במראה שסונכרנה לפני שהאתר
  /// הכניס קטגוריות, וזה מצב תקין — הממשק פשוט לא מציג שורת קטגוריות.
  final List<PluginStoreCategory> categories;

  /// הכותרת והתקציר של דף הבית של החנות, כפי שנאצרו באתר.
  final PluginStoreHome home;

  PluginStoreCategory? categoryBySlug(String slug) {
    for (final category in categories) {
      if (category.slug == slug) return category;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'lastSync': lastSync?.toIso8601String(),
        'home': home.toJson(),
        'categories': categories.map((c) => c.toJson()).toList(growable: false),
        'plugins': plugins.map((p) => p.toJson()).toList(growable: false),
      };

  /// קורא קטלוג מ-JSON. רשומה בודדת שלא ניתן לפענח מדולגת בשקט — עדיף
  /// קטלוג חלקי על פני מסך ריק.
  factory PluginCatalog.fromJson(Map<String, dynamic> json) {
    final rawPlugins = json['plugins'];
    final plugins = <StorePlugin>[];
    if (rawPlugins is List) {
      for (final raw in rawPlugins) {
        if (raw is! Map) continue;
        try {
          plugins.add(StorePlugin.fromJson(Map<String, dynamic>.from(raw)));
        } catch (_) {
          continue;
        }
      }
    }

    final rawCategories = json['categories'];
    final categories = <PluginStoreCategory>[];
    if (rawCategories is List) {
      for (final raw in rawCategories) {
        final category = PluginStoreCategory.fromJson(raw);
        if (category != null) categories.add(category);
      }
    }

    return PluginCatalog(
      lastSync: json['lastSync'] is String
          ? DateTime.tryParse(json['lastSync'] as String)
          : null,
      plugins: plugins,
      categories: categories,
      home: PluginStoreHome.fromJson(json['home']),
    );
  }
}

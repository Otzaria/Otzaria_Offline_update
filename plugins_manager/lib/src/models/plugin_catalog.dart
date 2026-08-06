import 'store_plugin.dart';

/// הקטלוג המקומי כולו — מה שנשמר ל-`catalog.json` בתוך המראה.
class PluginCatalog {
  const PluginCatalog({this.lastSync, this.plugins = const []});

  static const PluginCatalog empty = PluginCatalog();

  /// מועד הסנכרון האחרון (UTC ISO-8601), או null אם מעולם לא סונכרן.
  final DateTime? lastSync;
  final List<StorePlugin> plugins;

  Map<String, dynamic> toJson() => {
        'lastSync': lastSync?.toIso8601String(),
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

    return PluginCatalog(
      lastSync: json['lastSync'] is String
          ? DateTime.tryParse(json['lastSync'] as String)
          : null,
      plugins: plugins,
    );
  }
}

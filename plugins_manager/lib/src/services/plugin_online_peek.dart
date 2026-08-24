import '../models/plugin_catalog.dart';
import '../models/plugin_version_entry.dart';
import '../models/plugins_online_status.dart';
import '../models/store_plugin.dart';
import 'plugin_mirror_store.dart';
import 'plugin_store_client.dart';

/// "יש משהו חדש בחנות?" — קריאת מטא-דאטה אחת מול הקטלוג שכבר במראה, בלי
/// להוריד נכס ובלי לכתוב דבר. המקבילה של `peekLatestOnlineVersion` בספרייה,
/// והיא זו שמזינה את הנדנוד "יש עדכונים ברשת" שבדף הבית.
class PluginOnlinePeek {
  const PluginOnlinePeek({required this.client, required this.store});

  final PluginStoreClient client;
  final PluginMirrorStore store;

  /// [appVersions] — אותן גרסאות אוצריא שהסנכרון יקבל. חובה שיהיו זהות:
  /// ההצצה אמורה לדווח בדיוק על מה שסנכרון היה מביא.
  Future<PluginsOnlineStatus> peek({
    List<String> appVersions = const [],
  }) async {
    final remote = await client.fetchCatalog();
    final local = await store.load();

    // הקטלוג אינו עדות לקיום הקובץ: מחיקה ידנית, העתקה חלקית של הכונן או
    // הורדה שנכשלה משאירות רשומה מלאה בלי קובץ. `PluginMirrorSync` בודק
    // דיסק לפני שהוא מוריד, וההצצה חייבת לשאול בדיוק אותה שאלה.
    final present = <String, Set<String>>{};
    for (final plugin in local.plugins) {
      final have = <String>{};
      for (final entry in plugin.localFiles.entries) {
        if (await store.hasAsset(entry.value.relativePath)) have.add(entry.key);
      }
      present[plugin.id] = have;
    }

    return compare(
      remote: remote,
      local: local,
      presentBuilds: present,
      baseUrl: client.baseUrl,
      appVersions: appVersions,
    );
  }

  /// ההשוואה עצמה, בלי רשת ובלי דיסק — [presentBuilds] הן, לכל מזהה תוסף,
  /// גרסאות הבילד שהקובץ שלהן נמצא בפועל במראה.
  ///
  /// השאלה הנשאלת כאן היא **בדיוק** זו של `PluginMirrorSync._plan`: לכל
  /// גרסת אוצריא שהכונן נושא נבחר הבילד התואם, ונבדק אם הוא כבר במראה.
  /// כל השוואה "חכמה" אחרת הייתה מדווחת עדכון שסנכרון לא מביא, או להפך.
  static PluginsOnlineStatus compare({
    required List<Map<String, dynamic>> remote,
    required PluginCatalog local,
    required String baseUrl,
    required Map<String, Set<String>> presentBuilds,
    List<String> appVersions = const [],
  }) {
    final mirrored = {for (final plugin in local.plugins) plugin.id: plugin};
    final fresh = <String>[];
    final updated = <String>[];
    final missing = <String>[];

    for (final raw in remote) {
      final plugin = StorePlugin.fromApi(raw, baseUrl);
      if (plugin.id.isEmpty) continue;

      final targets = [
        // תוסף שאין לו קובץ להוריד בכלל אינו "חסר" — אין מה להביא לו.
        for (final target in plugin.targetsFor(appVersions))
          if (target.downloadUrl.isNotEmpty) target,
      ];

      final known = mirrored[plugin.id];
      if (known == null) {
        // תוסף שאין לו אף בילד שירוץ על מה שבכונן אינו "חדש": סנכרון לא
        // יביא לו כלום, וההצצה חייבת לומר את מה שהסנכרון יעשה.
        if (targets.isNotEmpty || plugin.remoteDownloadUrl.isEmpty) {
          fresh.add(plugin.name);
        }
        continue;
      }

      final have = presentBuilds[plugin.id] ?? const <String>{};
      final needsWork =
          targets.any((target) => _needsFetch(target, known, have));
      if (!needsWork) continue;

      // **גרסה חדשה** באתר לעומת **קובץ שחסר** מהכונן. השניים נראים אחרת
      // למשתמש ולכן נספרים בנפרד: בילד שהמראה כבר מתארת כשלה (הגרסה שנרשמה
      // בקטלוג, או בילד שנרשם לו קובץ) ואינו על הדיסק הוא חוסר — נמחק, לא
      // הועתק, או הורדה שנכשלה. כל בילד אחר הוא גרסה חדשה.
      final describes = targets.any((target) =>
          target.version == known.version ||
          known.localFiles.containsKey(target.version));
      if (describes) {
        missing.add(plugin.name);
      } else {
        updated.add(plugin.name);
      }
    }

    return PluginsOnlineStatus(
      newPlugins: fresh,
      updatedPlugins: updated,
      missingPlugins: missing,
      totalOnline: remote.length,
    );
  }

  /// המקבילה של `PluginMirrorSync._buildUnchanged`, בלי גישה לדיסק.
  static bool _needsFetch(
    PluginVersionEntry target,
    StorePlugin known,
    Set<String> have,
  ) {
    if (!have.contains(target.version)) return true;
    final recorded = _recorded(known, target.version);
    // כתובת ריקה ברשומה הקודמת = קטלוג ישן, לא כתובת שהשתנתה.
    return recorded != null &&
        recorded.downloadUrl.isNotEmpty &&
        recorded.downloadUrl != target.downloadUrl;
  }

  static PluginVersionEntry? _recorded(StorePlugin known, String version) =>
      known.versionEntries
          .where((entry) => entry.version == version)
          .firstOrNull;
}

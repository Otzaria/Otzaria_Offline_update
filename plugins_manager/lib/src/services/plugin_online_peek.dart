import '../models/plugin_catalog.dart';
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

  Future<PluginsOnlineStatus> peek() async {
    final remote = await client.fetchCatalog();
    final local = await store.load();

    // הקטלוג אינו עדות לקיום הקובץ: מחיקה ידנית, העתקה חלקית של הכונן או
    // הורדה שנכשלה משאירות רשומה מלאה בלי קובץ. `PluginMirrorSync` בודק
    // דיסק לפני שהוא מוריד, וההצצה חייבת לשאול בדיוק אותה שאלה.
    final present = <String>{
      for (final plugin in local.plugins)
        if (await store.hasLocalFile(plugin)) plugin.id,
    };

    return compare(
      remote: remote,
      local: local,
      presentFiles: present,
      baseUrl: client.baseUrl,
    );
  }

  /// ההשוואה עצמה, בלי רשת ובלי דיסק — [presentFiles] הם המזהים שקובץ
  /// ההתקנה שלהם נמצא בפועל במראה.
  ///
  /// השוואת הגרסאות היא על **מחרוזת** ולא על סדר סמנטי, כי זו בדיוק הבדיקה
  /// ש-`PluginMirrorSync` עושה לפני שהוא מוריד קובץ מחדש: מה שההצצה מדווחת
  /// הוא בדיוק מה שסנכרון היה מביא.
  static PluginsOnlineStatus compare({
    required List<Map<String, dynamic>> remote,
    required PluginCatalog local,
    required Set<String> presentFiles,
    required String baseUrl,
  }) {
    final mirrored = {for (final plugin in local.plugins) plugin.id: plugin};
    final fresh = <String>[];
    final updated = <String>[];
    final missing = <String>[];

    for (final raw in remote) {
      final plugin = StorePlugin.fromApi(raw, baseUrl);
      if (plugin.id.isEmpty) continue;

      final known = mirrored[plugin.id];
      if (known == null) {
        fresh.add(plugin.name);
      } else if (known.version != plugin.version) {
        updated.add(plugin.name);
      } else if (plugin.remoteDownloadUrl.isNotEmpty &&
          !presentFiles.contains(plugin.id)) {
        // תוסף שאין לו קובץ להוריד בכלל אינו "חסר" — אין מה להביא לו.
        missing.add(plugin.name);
      }
    }

    return PluginsOnlineStatus(
      newPlugins: fresh,
      updatedPlugins: updated,
      missingPlugins: missing,
      totalOnline: remote.length,
    );
  }
}

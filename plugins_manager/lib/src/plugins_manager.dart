import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'models/plugin_catalog.dart';
import 'models/plugin_sync_progress.dart';
import 'models/store_plugin.dart';
import 'services/installed_plugins_scanner.dart';
import 'services/plugin_direct_installer.dart';
import 'services/plugin_manifest_reader.dart';
import 'services/plugin_mirror_store.dart';
import 'services/plugin_mirror_sync.dart';
import 'services/plugin_store_client.dart';

/// תמונת מצב אחת של החנות, כפי שהממשק צריך אותה.
class PluginStoreView {
  const PluginStoreView({
    required this.catalog,
    required this.installed,
    required this.pluginsDir,
  });

  final PluginCatalog catalog;

  /// `manifestId -> גרסה מותקנת` מתוך ההתקנה האמיתית של אוצריא.
  final Map<String, String> installed;

  /// שורש קובצי החנות במראה — הממשק מרכיב ממנו נתיבים מוחלטים לתמונות.
  final String pluginsDir;
}

/// נקודת הכניסה היחידה שמודול ה-UI אמור להשתמש בה לחנות התוספים.
///
/// שני מסלולים, כמו בכל שאר הריפו: **סנכרון** ([sync]) רץ במחשב שיש בו
/// אינטרנט וממלא את המראה, ואילו **טעינה והתקנה** ([load], [directInstall])
/// עובדות מול המראה בלבד ולכן פועלות במחשב לא-מקוון.
///
/// תיקיית המראה נמסרת כ-callback כדי שהחבילה לא תצטרך להכיר את מבנה
/// התיקיות של הלאנצ'ר. בפועל הלאנצ'ר מחזיר נתיב קבוע לצד קובץ ההרצה.
///
/// ```dart
/// final manager = PluginsManager(
///   resolveMirrorDir: () async => p.join(appPaths.dataDir, 'mirror'),
/// );
/// final view = await manager.load();          // מקומי בלבד
/// await manager.sync(onProgress: print);      // דורש אינטרנט
/// await manager.directInstall(view.catalog.plugins.first);
/// ```
class PluginsManager {
  PluginsManager({
    required this.resolveMirrorDir,
    this.resolvePluginsDir,
    String baseUrl = PluginStoreClient.defaultBaseUrl,
    http.Client? httpClient,
  }) : _client = PluginStoreClient(baseUrl: baseUrl, client: httpClient);

  /// שורש המראה — הקטלוג יושב תחת `<mirrorDir>/plugins/`.
  final Future<String> Function() resolveMirrorDir;

  /// דריסה של תיקיית התוספים של אוצריא, לבדיקות. הלאנצ'ר אינו מעביר אותה:
  /// המיקום מתגלה אוטומטית ואין הגדרת נתיבים בממשק.
  final Future<String?> Function()? resolvePluginsDir;

  final PluginStoreClient _client;

  Future<PluginMirrorStore> _store() async =>
      PluginMirrorStore(await resolveMirrorDir());

  /// קורא את הקטלוג המקומי וסורק את ההתקנה האמיתית. **לא נוגע ברשת** —
  /// זו הפעולה שרצה בפתיחת המסך.
  Future<PluginStoreView> load() async {
    final store = await _store();
    final scanner = InstalledPluginsScanner(
      customPluginsDir: await resolvePluginsDir?.call(),
    );

    return PluginStoreView(
      catalog: await store.load(),
      installed: await scanner.scan(),
      pluginsDir: store.pluginsDir,
    );
  }

  /// מסנכרן את הקטלוג והקבצים מהאתר אל המראה. דורש אינטרנט.
  Future<PluginCatalog> sync({
    void Function(PluginSyncProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final store = await _store();
    final sync = PluginMirrorSync(client: _client, store: store);
    return sync.sync(onProgress: onProgress, isCancelled: isCancelled);
  }

  /// נתיב מוחלט לנכס שנשמר בקטלוג כנתיב יחסי, או null אם אין נכס.
  Future<String?> assetPath(String? relativePath) async {
    if (relativePath == null || relativePath.isEmpty) return null;
    return (await _store()).absolutePath(relativePath);
  }

  /// מעתיק את קובץ ה-`.otzplugin` ליעד שהמשתמש בחר. הבחירה עצמה נעשית
  /// בשכבת ה-UI (file picker), כי היא תלוית-Flutter.
  Future<PluginInstallResult> saveCopy(
    StorePlugin plugin,
    String destPath,
  ) async {
    final store = await _store();
    final local = plugin.localFile;
    if (local == null || !await store.hasLocalFile(plugin)) {
      return const PluginInstallResult.failure(
        'הקובץ אינו זמין באופן מקומי. יש לבצע סנכרון קודם.',
      );
    }

    try {
      await File(store.absolutePath(local.relativePath)).copy(destPath);
      return const PluginInstallResult.ok();
    } catch (e) {
      return PluginInstallResult.failure('שמירת הקובץ נכשלה: $e');
    }
  }

  /// שם הקובץ המוצע לשמירה, לפי מה שהאתר החזיר ב-`Content-Disposition`.
  String suggestedFileName(StorePlugin plugin) =>
      plugin.localFile?.fileName ??
      '${plugin.name}${plugin.localFile?.ext ?? '.otzplugin'}';

  /// מתקין את התוסף באוצריא דרך `otzaria://plugin/install-local`.
  ///
  /// אם קובץ התוסף חסר מהמראה (למשל הסנכרון דילג עליו) הוא מורד עכשיו —
  /// וזה הצעד היחיד כאן שדורש אינטרנט. כשהקובץ כבר במראה, ההתקנה עובדת
  /// בלי רשת בכלל.
  Future<PluginInstallResult> directInstall(StorePlugin plugin) async {
    final store = await _store();
    var target = plugin;

    if (!await store.hasLocalFile(target)) {
      final fetched = await _fetchMissingFile(store, target);
      if (fetched == null) {
        return const PluginInstallResult.failure(
          'קובץ התוסף אינו זמין. יש לבצע סנכרון קודם.',
        );
      }
      target = fetched;
    }

    return PluginDirectInstaller.install(
      store.absolutePath(target.localFile!.relativePath),
    );
  }

  /// מוריד קובץ תוסף חסר ומעדכן את הקטלוג. מחזיר null אם לא הצליח.
  Future<StorePlugin?> _fetchMissingFile(
    PluginMirrorStore store,
    StorePlugin plugin,
  ) async {
    if (plugin.remoteDownloadUrl.isEmpty) return null;

    try {
      final dir = store.pluginDir(plugin.id);
      await Directory(dir).create(recursive: true);
      final asset = await _client.downloadAsset(
        plugin.remoteDownloadUrl,
        p.join(dir, 'plugin'),
        preferredExt: '.otzplugin',
      );

      final updated = plugin.copyWith(
        localFile: PluginLocalFile(
          relativePath: store.relativePath(asset.path),
          fileName: asset.originalName ?? '${plugin.name}${asset.ext}',
          ext: asset.ext,
          size: asset.size,
        ),
        manifestId: PluginManifestReader.readId(asset.path),
      );

      final catalog = await store.load();
      await store.save(PluginCatalog(
        lastSync: catalog.lastSync,
        plugins: [
          for (final entry in catalog.plugins)
            entry.id == updated.id ? updated : entry,
        ],
      ));
      return updated;
    } catch (_) {
      return null;
    }
  }

  /// פותח קישור חיצוני (עמוד המקור של התוסף) בדפדפן ברירת המחדל — אותו
  /// מנגנון מסירה למערכת ההפעלה כמו ההתקנה הישירה.
  Future<PluginInstallResult> openExternalUrl(String url) =>
      PluginDirectInstaller.openProtocolUrl(url);

  void dispose() => _client.dispose();
}

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

import 'models/plugin_catalog.dart';
import 'models/plugin_sync_outcome.dart';
import 'models/plugin_sync_progress.dart';
import 'models/plugins_online_status.dart';
import 'models/store_plugin.dart';
import 'services/installed_plugins_scanner.dart';
import 'services/plugin_direct_installer.dart';
import 'services/plugin_manifest_reader.dart';
import 'services/plugin_mirror_store.dart';
import 'services/plugin_mirror_sync.dart';
import 'services/plugin_online_peek.dart';
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
    this.otzariaLaunchPath,
    String baseUrl = PluginStoreClient.defaultBaseUrl,
    http.Client? httpClient,
  }) : _client = PluginStoreClient(baseUrl: baseUrl, client: httpClient);

  /// שורש המראה — הקטלוג יושב תחת `<mirrorDir>/plugins/`.
  final Future<String> Function() resolveMirrorDir;

  /// דריסה של תיקיית התוספים של אוצריא, לבדיקות. הלאנצ'ר אינו מעביר אותה:
  /// המיקום מתגלה אוטומטית ואין הגדרת נתיבים בממשק.
  final Future<String?> Function()? resolvePluginsDir;

  /// נתיב ההפעלה של אוצריא שהלאנצ'ר זיהה. ממנו נגזרת תיקיית התוספים של
  /// התקנה ניידת ([InstalledPluginsScanner]), ואליו נמסרת ההתקנה הישירה
  /// ([PluginDirectInstaller]). `null` = ברירות המחדל של הפלטפורמה ומטפל
  /// הפרוטוקול, כמו קודם.
  final Future<String?> Function()? otzariaLaunchPath;

  final PluginStoreClient _client;

  /// הזמן הקצוב לכל פעולת רשת של החנות — נכנס לתוקף בבקשה הבאה.
  set networkTimeout(Duration value) => _client.timeout = value;

  Future<PluginMirrorStore> _store() async =>
      PluginMirrorStore(await resolveMirrorDir());

  /// קורא את הקטלוג המקומי וסורק את ההתקנה האמיתית. **לא נוגע ברשת** —
  /// זו הפעולה שרצה בפתיחת המסך.
  Future<PluginStoreView> load() async {
    final store = await _store();

    return PluginStoreView(
      catalog: await store.load(),
      installed: await scanInstalled(),
      pluginsDir: store.pluginsDir,
    );
  }

  /// סורק **רק** את ההתקנה של אוצריא, בלי לקרוא את הקטלוג. קיים בנפרד כדי
  /// שהלאנצ'ר יוכל לרענן את המפה אחרי שנתיב ההתקנה התברר — לפניו הסריקה
  /// קראה תיקייה אחרת לגמרי.
  Future<Map<String, String>> scanInstalled() async => InstalledPluginsScanner(
        customPluginsDir: await resolvePluginsDir?.call(),
        otzariaLaunchPath: await otzariaLaunchPath?.call(),
      ).scan();

  /// מסנכרן את הקטלוג והקבצים מהאתר אל המראה. דורש אינטרנט. מוריד **רק**
  /// את מה שחסר או השתנה — ראו [PluginSyncOutcome].
  Future<PluginSyncOutcome> sync({
    void Function(PluginSyncProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final store = await _store();
    final sync = PluginMirrorSync(client: _client, store: store);
    return sync.sync(onProgress: onProgress, isCancelled: isCancelled);
  }

  /// בודק ברשת אם יש בחנות תוסף חדש או גרסה חדשה — **בקשה קלה אחת**, בלי
  /// להוריד קובץ ובלי לגעת במראה. זורק כמו [sync] כשאין רשת; המתקשר הוא
  /// שמחליט שזה מצב תקין.
  Future<PluginsOnlineStatus> peekOnlineUpdates() async =>
      PluginOnlinePeek(client: _client, store: await _store()).peek();

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
    final strings = AppL10n.strings.pluginsDomain;
    if (local == null || !await store.hasLocalFile(plugin)) {
      return PluginInstallResult.failure(strings.fileNotAvailableSyncFirst);
    }

    try {
      await File(store.absolutePath(local.relativePath)).copy(destPath);
      return const PluginInstallResult.ok();
    } catch (e) {
      return PluginInstallResult.failure(strings.saveFailed('$e'));
    }
  }

  /// שם הקובץ המוצע לשמירה, לפי מה שהאתר החזיר ב-`Content-Disposition`.
  String suggestedFileName(StorePlugin plugin) =>
      plugin.localFile?.fileName ??
      '${plugin.name}${plugin.localFile?.ext ?? '.otzplugin'}';

  /// מתקין את התוסף באוצריא דרך `otzaria://plugin/install-local` — ישירות
  /// אל ההתקנה ש-[otzariaLaunchPath] מצביע עליה, כשהיא ידועה.
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
        return PluginInstallResult.failure(
          AppL10n.strings.pluginsDomain.pluginFileNotAvailable,
        );
      }
      target = fetched;
    }

    return PluginDirectInstaller.install(
      store.absolutePath(target.localFile!.relativePath),
      otzariaLaunchPath: await otzariaLaunchPath?.call(),
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

      // הקטגוריות וטקסטי דף הבית **חייבים** לנסוע איתם: בלעדיהם השמירה הזו
      // מוחקת את כל מבנה החנות מהמראה בגלל הורדה של קובץ בודד.
      final catalog = await store.load();
      await store.save(PluginCatalog(
        lastSync: catalog.lastSync,
        plugins: [
          for (final entry in catalog.plugins)
            entry.id == updated.id ? updated : entry,
        ],
        categories: catalog.categories,
        home: catalog.home,
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

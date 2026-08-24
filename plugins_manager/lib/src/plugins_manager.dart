import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:otzaria_l10n/otzaria_l10n.dart';

import 'models/plugin_catalog.dart';
import 'models/plugin_sync_outcome.dart';
import 'models/plugin_sync_progress.dart';
import 'models/plugin_version_entry.dart';
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
  ///
  /// [appVersions] הן גרסאות אוצריא שהכונן נושא; לכל אחת יורד בילד התוסף
  /// שתואם לה. ראו `plugin_compatibility.dart`.
  Future<PluginSyncOutcome> sync({
    List<String> appVersions = const [],
    void Function(PluginSyncProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final store = await _store();
    final sync = PluginMirrorSync(client: _client, store: store);
    return sync.sync(
      appVersions: appVersions,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
  }

  /// בודק ברשת אם יש בחנות תוסף חדש או גרסה חדשה — **בקשה קלה אחת**, בלי
  /// להוריד קובץ ובלי לגעת במראה. זורק כמו [sync] כשאין רשת; המתקשר הוא
  /// שמחליט שזה מצב תקין.
  ///
  /// [appVersions] חייבות להיות אותן גרסאות ש-[sync] יקבל.
  Future<PluginsOnlineStatus> peekOnlineUpdates({
    List<String> appVersions = const [],
  }) async =>
      PluginOnlinePeek(client: _client, store: await _store())
          .peek(appVersions: appVersions);

  /// נתיב מוחלט לנכס שנשמר בקטלוג כנתיב יחסי, או null אם אין נכס.
  Future<String?> assetPath(String? relativePath) async {
    if (relativePath == null || relativePath.isEmpty) return null;
    return (await _store()).absolutePath(relativePath);
  }

  /// מעתיק את קובץ ה-`.otzplugin` ליעד שהמשתמש בחר. הבחירה עצמה נעשית
  /// בשכבת ה-UI (file picker), כי היא תלוית-Flutter.
  Future<PluginInstallResult> saveCopy(
    StorePlugin plugin,
    String destPath, {
    String? appVersion,
  }) async {
    final store = await _store();
    final local =
        plugin.localFileFor(plugin.installTarget(appVersion)?.version);
    final strings = AppL10n.strings.pluginsDomain;
    if (local == null || !await store.hasAsset(local.relativePath)) {
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
  String suggestedFileName(StorePlugin plugin, {String? appVersion}) {
    final local =
        plugin.localFileFor(plugin.installTarget(appVersion)?.version) ??
            plugin.anyLocalFile;
    return local?.fileName ?? '${plugin.name}${local?.ext ?? '.otzplugin'}';
  }

  /// מתקין את התוסף באוצריא דרך `otzaria://plugin/install-local` — ישירות
  /// אל ההתקנה ש-[otzariaLaunchPath] מצביע עליה, כשהיא ידועה.
  ///
  /// אם קובץ התוסף חסר מהמראה (למשל הסנכרון דילג עליו) הוא מורד עכשיו —
  /// וזה הצעד היחיד כאן שדורש אינטרנט. כשהקובץ כבר במראה, ההתקנה עובדת
  /// בלי רשת בכלל.
  ///
  /// [appVersion] היא גרסת אוצריא שבמחשב הזה — היא שקובעת **איזה בילד**
  /// מותקן. `null` = לא ידוע, ואז נבחר הבילד החי כמו קודם.
  Future<PluginInstallResult> directInstall(
    StorePlugin plugin, {
    String? appVersion,
  }) async {
    final store = await _store();
    final strings = AppL10n.strings.pluginsDomain;

    final target = plugin.installTarget(appVersion);
    if (target == null) {
      return PluginInstallResult.failure(strings.noCompatibleBuild);
    }

    var local = plugin.localFileFor(target.version);
    if (local == null || !await store.hasAsset(local.relativePath)) {
      local = await _fetchMissingFile(store, plugin, target);
      if (local == null) {
        return PluginInstallResult.failure(strings.pluginFileNotAvailable);
      }
    }

    return PluginDirectInstaller.install(
      store.absolutePath(local.relativePath),
      otzariaLaunchPath: await otzariaLaunchPath?.call(),
    );
  }

  /// מוריד בילד חסר ומעדכן את הקטלוג. מחזיר null אם לא הצליח.
  Future<PluginLocalFile?> _fetchMissingFile(
    PluginMirrorStore store,
    StorePlugin plugin,
    PluginVersionEntry target,
  ) async {
    if (target.downloadUrl.isEmpty) return null;

    try {
      await Directory(store.pluginDir(plugin.id)).create(recursive: true);
      final asset = await _client.downloadAsset(
        target.downloadUrl,
        store.pluginFilePathNoExt(plugin.id, target.version),
        preferredExt: '.otzplugin',
      );

      final file = PluginLocalFile(
        relativePath: store.relativePath(asset.path),
        fileName: asset.originalName ?? '${plugin.name}${asset.ext}',
        ext: asset.ext,
        size: asset.size,
      );
      final updated = plugin.copyWith(
        localFiles: {...plugin.localFiles, target.version: file},
        manifestId:
            plugin.manifestId ?? PluginManifestReader.readId(asset.path),
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
      return file;
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

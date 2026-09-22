import 'dart:convert';
import 'dart:io';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

import '../models/plugin_catalog.dart';
import '../models/store_plugin.dart';
import 'plugin_mirror_store.dart';
import 'plugin_store_client.dart';
import 'store_app_mirror.dart';

/// שלב בדיווח ההתקדמות של הייצוא.
enum StoreAppExportPhase { start, app, plugin, catalog, done }

class StoreAppExportProgress {
  const StoreAppExportProgress({
    required this.phase,
    required this.message,
    this.current,
    this.total,
  });

  final StoreAppExportPhase phase;
  final String message;
  final int? current;
  final int? total;

  /// 0..1 כשידוע היעד, אחרת null (מד לא-קבוע).
  double? get fraction => (current != null && total != null && total! > 0)
      ? current! / total!
      : null;
}

/// מה ייצוא אחד באמת עשה.
class StoreAppExportOutcome {
  const StoreAppExportOutcome({
    required this.destinationDir,
    required this.appPath,
    required this.plugins,
    required this.files,
    required this.bytes,
    this.skipped = const [],
  });

  final String destinationDir;

  /// קובץ ההרצה שנכתב ביעד — ממנו נפתחת התוכנה.
  final String appPath;

  /// כמה תוספים נכנסו ל-`Data\`.
  final int plugins;

  /// כמה קבצים הועתקו (כולל קובץ ההרצה והקטלוג).
  final int files;
  final int bytes;

  /// שמות תוספים שנכס שלהם לא נמצא על הכונן ולכן הושמט. **לא כשל** — תוסף
  /// שקובצו חסר במראה חסר גם בחנות שביעד, וזה בדיוק מה שהיה קורה גם בלי
  /// הייצוא.
  final List<String> skipped;
}

/// אורז את **תוכנת החנות העצמאית** ליעד שהמשתמש בחר: קובץ ההרצה שירד
/// ל-`mirror/store-app/`, ולצידו `Data\` שנבנית מהמראה של התוספים.
///
/// ## למה זו העתקה ולא אריזה מחדש
///
/// תוכנת החנות היא פורט 1:1 של החבילה הזאת (`PluginMirrorStore`,
/// `PluginMirrorSync`, `StorePlugin` — אותם שמות, אותו `toJson`), ולכן
/// `catalog.json` שלה **זהה לשלנו**. ההבדל היחיד הוא איפה הקבצים יושבים:
///
/// ```
/// אצלנו:  <mirror>/plugins/catalog.json  +  <mirror>/plugins/files/<id>/…
/// אצלה:   <dest>/Data/catalog.json       +  <dest>/Data/plugins/<id>/…
/// ```
///
/// הנתיבים בקטלוג יחסיים לתיקייה שמעל, כלומר `files/<id>/…` אצלנו מול
/// `<id>/…` אצלה. לכן כל נכס מועתק ונרשם מחדש יחסית ל-`filesDir`, ורק
/// אחר כך נכתב הקטלוג.
///
/// ⚠️ **הקטלוג נכתב אחרון.** הוא המפתח לכל השאר, וכתיבתו לפני ההעתקה
/// הייתה משאירה — בהעתקה שנקטעה — חנות שמתארת תוספים שאין להם קובץ.
class StoreAppExporter {
  const StoreAppExporter({required this.store, required this.appMirror});

  final PluginMirrorStore store;
  final StoreAppMirror appMirror;

  static const String dataDirName = 'Data';
  static const String _pluginsDirName = 'plugins';

  /// `true` אם ביעד כבר יושבת חנות — קובץ הרצה או `Data\`. הממשק שואל
  /// לפני שהוא דורס.
  static Future<bool> hasExistingStore(String destinationDir) async {
    if (await Directory(p.join(destinationDir, dataDirName)).exists()) {
      return true;
    }
    final dir = Directory(destinationDir);
    if (!await dir.exists()) return false;
    try {
      await for (final entry in dir.list(followLinks: false)) {
        if (entry is File && p.extension(entry.path).toLowerCase() == '.exe') {
          return true;
        }
      }
    } catch (_) {
      // תיקייה שאי אפשר לסרוק — הכתיבה עצמה תיכשל בהודעה ברורה יותר.
    }
    return false;
  }

  /// מעתיק את התוכנה ואת כל מה שיש במראה אל [destinationDir]. **אינו נוגע
  /// ברשת.**
  ///
  /// קובץ קיים ביעד נדרס; מה שאיננו מכירים (`state.json`, `logs\`) נשאר
  /// במקומו, כדי שעדכון של התקנה קיימת לא ימחק את מה שהמשתמש צבר בה.
  Future<StoreAppExportOutcome> exportTo(
    String destinationDir, {
    void Function(StoreAppExportProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final strings = AppL10n.strings.pluginsDomain;
    void report(
      StoreAppExportPhase phase,
      String message, [
      int? current,
      int? total,
    ]) =>
        onProgress?.call(StoreAppExportProgress(
          phase: phase,
          message: message,
          current: current,
          total: total,
        ));

    report(StoreAppExportPhase.start, strings.exportPreparing);

    final mirrored = await appMirror.load();
    if (mirrored == null) {
      throw PluginStoreException(strings.exportAppMissing);
    }

    final catalog = await store.load();
    final dataDir = p.join(destinationDir, dataDirName);
    final pluginsDir = p.join(dataDir, _pluginsDirName);
    await Directory(pluginsDir).create(recursive: true);

    var files = 0;
    var bytes = 0;

    // ── קובץ ההרצה ─────────────────────────────────────────────────────────
    // ראשון, ולא אחרון: הוא הדבר היחיד כאן שאנטי-וירוס או מדיניות ארגונית
    // עשויים לחסום, וכשל אחרי העתקת מאות MB של תוספים הוא כשל יקר.
    report(StoreAppExportPhase.app, strings.exportCopyingApp);
    final appPath = p.join(destinationDir, mirrored.release.assetName);
    await _copyApp(mirrored, appPath);
    files++;
    bytes += mirrored.release.sizeBytes;

    // ── התוספים ────────────────────────────────────────────────────────────
    final exported = <StorePlugin>[];
    final skipped = <String>[];
    final total = catalog.plugins.length;
    var done = 0;

    for (final plugin in catalog.plugins) {
      if (isCancelled?.call() ?? false) {
        throw PluginStoreException(AppL10n.strings.appDomain.downloadCancelled);
      }
      done++;
      report(
        StoreAppExportPhase.plugin,
        strings.exportPlugin(plugin.name, done, total),
        done,
        total,
      );

      var missing = false;

      Future<String?> move(String? relative) async {
        final moved = await _copyAsset(relative, pluginsDir);
        if (moved == null && relative != null && relative.isNotEmpty) {
          missing = true;
          return null;
        }
        if (moved != null) {
          files++;
          bytes += moved.size;
        }
        return moved?.relativePath;
      }

      final imagePath = await move(plugin.imagePath);
      final screenshots = <String>[];
      for (final shot in plugin.screenshotPaths) {
        final moved = await move(shot);
        if (moved != null) screenshots.add(moved);
      }

      final localFiles = <String, PluginLocalFile>{};
      for (final entry in plugin.localFiles.entries) {
        final moved = await _copyAsset(entry.value.relativePath, pluginsDir);
        if (moved == null) {
          missing = true;
          continue;
        }
        files++;
        bytes += moved.size;
        localFiles[entry.key] = PluginLocalFile(
          relativePath: moved.relativePath,
          fileName: entry.value.fileName,
          ext: entry.value.ext,
          size: entry.value.size,
        );
      }

      if (missing) skipped.add(plugin.name);
      exported.add(plugin.copyWith(
        imagePath: imagePath,
        screenshotPaths: screenshots,
        localFiles: localFiles,
      ));
    }

    // ── הקטלוג, אחרון ──────────────────────────────────────────────────────
    report(StoreAppExportPhase.catalog, strings.exportWritingCatalog);
    final rewritten = PluginCatalog(
      lastSync: catalog.lastSync,
      home: catalog.home,
      categories: catalog.categories,
      plugins: exported,
    );
    final catalogPath = p.join(dataDir, PluginMirrorStore.catalogFileName);
    final temp = File('$catalogPath.tmp');
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(rewritten.toJson()),
      flush: true,
    );
    await temp.rename(catalogPath);
    files++;

    // ⚠️ בדיקה שנייה, אחרי הכול: קובץ הרצה לא-חתום שנוחת בתיקיית משתמש
    // נסרק ברגע שנסגר, ואנטי-וירוס עשוי למחוק אותו **אחרי** שההעתקה
    // הצליחה. בלי הבדיקה הזאת הדיאלוג הכריז "החנות הועתקה" על תיקייה שיש
    // בה `Data\` בלבד, ו"הפעלת החנות" לא עשתה דבר.
    await _verifyApp(mirrored, appPath);

    report(StoreAppExportPhase.done, strings.exportDone(exported.length));
    return StoreAppExportOutcome(
      destinationDir: destinationDir,
      appPath: appPath,
      plugins: exported.length,
      files: files,
      bytes: bytes,
      skipped: skipped,
    );
  }

  /// מעתיק את קובץ ההרצה ומוודא מיד שהוא שם ובגודל הנכון. `File.copy`
  /// מדווח הצלחה גם כשמנגנון הגנה החליף את הכתיבה בשקט, ולכן הבדיקה אינה
  /// מיותרת.
  Future<void> _copyApp(MirroredStoreApp mirrored, String appPath) async {
    try {
      await File(mirrored.filePath).copy(appPath);
    } catch (e) {
      throw PluginStoreException(
        AppL10n.strings.pluginsDomain.exportAppCopyFailed('$e'),
      );
    }
    await _verifyApp(mirrored, appPath);
  }

  /// זורק אם קובץ ההרצה אינו ביעד או שגודלו אינו זה שבמראה.
  Future<void> _verifyApp(MirroredStoreApp mirrored, String appPath) async {
    final copied = File(appPath);
    final size = await copied.exists() ? await copied.length() : -1;
    if (size == mirrored.release.sizeBytes) return;
    throw PluginStoreException(
      AppL10n.strings.pluginsDomain.exportAppVanished(appPath),
    );
  }

  /// מעתיק נכס בודד מהמראה אל `Data\plugins\`, ומחזיר את הנתיב שיירשם
  /// בקטלוג — **יחסי ל-`plugins\` ובסגנון POSIX**, בדיוק כמו שהחנות כותבת
  /// אותו בעצמה.
  ///
  /// `null` פירושו "הנכס אינו זמין": נתיב ריק, קובץ שאינו על הדיסק, או
  /// רשומה שמצביעה מחוץ ל-`files/`. האחרון קורה רק בקטלוג פגום או שנערך
  /// ביד, ודילוג עליו עדיף על העתקת קובץ שרירותי מהכונן אל תיקיית היעד.
  Future<_CopiedAsset?> _copyAsset(String? relative, String pluginsDir) async {
    if (relative == null || relative.isEmpty) return null;

    final source = p.normalize(store.absolutePath(relative));
    final within = p.relative(source, from: p.normalize(store.filesDir));
    if (within.startsWith('..') || p.isAbsolute(within)) return null;

    final file = File(source);
    if (!await file.exists()) return null;

    final destination = p.join(pluginsDir, within);
    await Directory(p.dirname(destination)).create(recursive: true);
    await file.copy(destination);

    return _CopiedAsset(
      relativePath: within.replaceAll(r'\', '/'),
      size: await file.length(),
    );
  }
}

class _CopiedAsset {
  const _CopiedAsset({required this.relativePath, required this.size});
  final String relativePath;
  final int size;
}

import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';

import 'models/library_update_check_result.dart';
import 'services/library_db_locator.dart';
import 'services/library_state_store.dart';
import 'services/otzaria_process_guard.dart';
import 'services/zstd_decompressor.dart';

/// נקודת הכניסה היחידה שמודול ה-UI אמור להשתמש בה כדי לעדכן את המסד
/// (ה-DB) של אוצריא — מחווט את כל שרשרת השירותים של
/// `seforim_library_updater` (discovery → planner → downloader →
/// applier/recovery) מול קובץ ה-DB בפועל של המשתמש.
///
/// דוגמת שימוש:
/// ```dart
/// final manager = LibraryManager(dataDir: r'C:\Users\me\AppData\Roaming\OurLauncher');
///
/// final check = await manager.checkForUpdate();
/// if (check.needsManualDbPath) {
///   // הצג בחירת תיקייה למשתמש, ואז:
///   await manager.setCustomDbPath(userChosenDbPath);
///   check = await manager.checkForUpdate();
/// }
///
/// if (check.updateAvailable) {
///   await manager.applyUpdate(
///     check,
///     onStage: (stage) => print(stage),
///     onDownloadProgress: (received, total) => print('$received/$total'),
///   );
/// }
/// ```
class LibraryManager {
  LibraryManager({
    required String dataDir,
    this.otzariaProcessImageName = 'otzaria.exe',
    bool allowPrerelease = true,
  })  : _allowPrerelease = allowPrerelease,
        _stateStore = LibraryStateStore(p.join(dataDir, 'library_state.json')),
        _discovery = LibraryUpdateDiscovery(client: GithubLibraryReleaseClient()),
        _planner = const LibraryUpdatePlanner(),
        _versionReader = const LocalDbVersionReader(),
        _recovery = const LibraryDbRecoveryService(),
        _applier = const PatchApplier(),
        _processGuard = const OtzariaProcessGuard(),
        _downloader = PatchDownloader(decompress: const ZstdDecompressor().call) {
    _locator = LibraryDbLocator(stateStore: _stateStore);
  }

  /// שם קובץ ה-exe (בלבד, לא נתיב) לבדיקת "האם אוצריא רצה" לפני עדכון
  /// DB. ברירת המחדל תואמת את מה ש-[OtzariaExeLocator]/`otzaria_manager`
  /// מוצאים בפועל בהתקנה סטנדרטית.
  final String otzariaProcessImageName;

  /// אם `true` (ברירת מחדל), עדכוני DB עוקבים אחר releases prerelease של
  /// SeforimLibrary גם כן — **לא** אותה החלטה כמו ב-`otzaria_manager`
  /// (שם ההחלטה הייתה "כן, גם prerelease" כי הריפו של אוצריא כמעט ולא
  /// מפרסם יציבים). כאן זו ברירת מחדל סבירה בנפרד, אבל לא אומתה עם
  /// המשתמש במפורש עבור SeforimLibrary — כדאי לוודא בהמשך אם הריפו הזה
  /// כן מפרסם releases יציבים סדירים, ואם כן לשקול להפוך את זה ל-false.
  final bool _allowPrerelease;

  final LibraryStateStore _stateStore;
  late final LibraryDbLocator _locator;
  final LibraryUpdateDiscovery _discovery;
  final LibraryUpdatePlanner _planner;
  final LocalDbVersionReader _versionReader;
  final LibraryDbRecoveryService _recovery;
  final PatchApplier _applier;
  final OtzariaProcessGuard _processGuard;
  final PatchDownloader _downloader;

  Future<void> setCustomDbPath(String dbPath) => _stateStore.saveCustomDbPath(dbPath);

  /// בודק אם יש עדכון זמין. ראו [LibraryUpdateCheckResult.needsManualDbPath]
  /// אם לא נמצא DB לא בנתיב מותאם אישית ולא בברירת המחדל של אוצריא.
  Future<LibraryUpdateCheckResult> checkForUpdate() async {
    final dbPath = await _locator.resolveDbPath();
    if (dbPath == null) {
      return const LibraryUpdateCheckResult(dbPath: null);
    }

    // התאוששות מעדכון שנקטע באמצע, לפני שקוראים גרסה מקומית או פותחים
    // DB בכל דרך אחרת.
    final recovery = await _recovery.recoverIfNeeded(dbPath);
    if (recovery.action == RecoveryAction.blockedMissingBackup) {
      // מסלול דלתא (ה-apply עצמו אטומי): בודקים תקינות בפועל, לא רק
      // מניחים תקלה בגלל שהסימון נשאר.
      if (!_recovery.checkDbHealthAfterCrash(dbPath)) {
        throw StateError(
          '${recovery.detail ?? "עדכון DB שנקטע"} — quick_check נכשל בפועל, '
          'נדרשת התערבות ידנית (שחזור מגיבוי חיצוני).',
        );
      }
      _recovery.clearStaleArtifacts(dbPath);
    }

    final local = _versionReader.read(dbPath);
    final discovery = await _discovery.discover(allowPrerelease: _allowPrerelease);

    final plan = _planner.plan(
      localVersion: local.dbVersion,
      hasLocalVersionMeta: local.hasVersionMeta,
      latestVersion: discovery.latestVersion,
      edges: discovery.edges,
      latestFullDbAsset: discovery.latestFullDbAsset,
      latestReleaseTag: discovery.latestReleaseTag,
    );

    return LibraryUpdateCheckResult(dbPath: dbPath, localVersion: local, plan: plan);
  }

  /// מבצע את תוכנית העדכון שהתקבלה מ-[checkForUpdate]. זורק
  /// [OtzariaIsRunningException] אם אוצריא רצה כרגע — יש לבקש מהמשתמש
  /// לסגור אותה ולנסות שוב (לא מנסים לסגור אוטומטית, לפי ההחלטה איתו).
  Future<void> applyUpdate(
    LibraryUpdateCheckResult check, {
    void Function(String stage)? onStage,
    void Function(int downloaded, int? total)? onDownloadProgress,
  }) async {
    final dbPath = check.dbPath;
    final plan = check.plan;
    if (dbPath == null || plan == null) {
      throw StateError('אין תוכנית עדכון תקפה — יש לקרוא ל-checkForUpdate קודם.');
    }
    if (plan.kind == LibraryUpdatePlanKind.none) return;
    if (plan.kind == LibraryUpdatePlanKind.blocked) {
      throw StateError(plan.reason ?? 'העדכון חסום, וללא DB מלא זמין ל-fallback.');
    }

    if (await _processGuard.isRunning(otzariaProcessImageName)) {
      throw const OtzariaIsRunningException();
    }

    if (plan.kind == LibraryUpdatePlanKind.delta) {
      await _applyDeltaSteps(
        dbPath,
        plan,
        onStage: onStage,
        onDownloadProgress: onDownloadProgress,
      );
    } else {
      await _applyFullDownload(
        dbPath,
        plan,
        onStage: onStage,
        onDownloadProgress: onDownloadProgress,
      );
    }
  }

  Future<void> _applyDeltaSteps(
    String dbPath,
    LibraryUpdatePlan plan, {
    void Function(String stage)? onStage,
    void Function(int downloaded, int? total)? onDownloadProgress,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp('library-patch-');
    try {
      for (final step in plan.deltaSteps) {
        // כרגע manifest.patchFiles הוא תמיד קובץ אחד (ראו התיעוד ב-
        // seforim_library_updater/lib/src/models/delta_manifest.dart) —
        // PatchApplier.apply גם מקבל patchPath יחיד, לא רשימה.
        final patchFile = step.manifest.patchFiles.single;
        final url = step.patchFileUrls[patchFile.file];
        if (url == null) {
          throw StateError('לא נמצא URL הורדה עבור ${patchFile.file}');
        }

        onStage?.call('מוריד עדכון ${step.fromVersion} → ${step.toVersion}');
        final extractedPath = await _downloader.downloadAndExtract(
          patchFile: patchFile,
          downloadUrl: url,
          destDir: tempDir,
          onProgress: onDownloadProgress,
        );

        onStage?.call('מחיל עדכון ${step.fromVersion} → ${step.toVersion}');
        // apply() סינכרוני וכבד (hash + SQL על כל ה-DB) — ב-Isolate נפרד
        // כדי לא לחסום, בדיוק כמו שמתועד ב-README של seforim_library_updater.
        await Isolate.run(
          () => _applier.apply(
            dbPath: dbPath,
            patchPath: extractedPath,
            manifest: step.manifest,
          ),
        );
      }
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  Future<void> _applyFullDownload(
    String dbPath,
    LibraryUpdatePlan plan, {
    void Function(String stage)? onStage,
    void Function(int downloaded, int? total)? onDownloadProgress,
  }) async {
    final asset = plan.fullDbAsset;
    if (asset == null) {
      throw StateError('תוכנית fullDownload בלי asset — מצב לא צפוי.');
    }

    final compressedPath = '$dbPath.download.zst';
    final newDbPath = '$dbPath.new';
    final timestamp = DateTime.now().toIso8601String();

    // createBackup: true — זה מסלול החלפת קובץ, לא אטומי מטבעו (בניגוד
    // ל-delta), אז חובה גיבוי אמיתי לפני שנוגעים בקובץ המקורי.
    await _recovery.beginApply(
      dbPath: dbPath,
      fromVersion: plan.localVersion,
      toVersion: plan.targetVersion ?? plan.localVersion,
      timestamp: timestamp,
      createBackup: true,
    );

    try {
      onStage?.call('מוריד DB מלא (${plan.fullDbReleaseTag})');
      // downloadToFile מוריד את הבייטים הגולמיים (עדיין דחוסים) לדיסק —
      // לא מחלץ בעצמו (ראו PatchDownloader). החילוץ קורה בשלב נפרד למטה.
      await _downloader.downloadToFile(
        url: asset.downloadUrl,
        destPath: compressedPath,
        expectedSize: asset.size,
        onProgress: onDownloadProgress,
      );

      onStage?.call('מחלץ DB מלא');
      // ⚠️ סיכון לא-מאומת: קובץ ה-DB המלא גדול (מוזכר במסמכי הפרויקט
      // כ-~1.1GB דחוס) — חילוץ zstd בזיכרון (ZstdDecompressor.decodeBytes
      // על כל הבייטים בבת אחת) עלול לצרוך RAM רב ולהיות איטי. אם זה
      // מתברר כבעייתי בפועל, יש להחליף לחילוץ streaming (למשל דרך קריאה
      // ל-zstd.exe חיצוני, או binding native), לא בהכרח ל-package:archive
      // כמו שכתוב כרגע.
      final compressedBytes = await File(compressedPath).readAsBytes();
      final decompressed = await const ZstdDecompressor().call(compressedBytes);
      if (decompressed == null) {
        throw StateError('חילוץ ה-DB המלא נכשל.');
      }
      await File(newDbPath).writeAsBytes(decompressed, flush: true);

      onStage?.call('מוודא תקינות DB חדש');
      final newVersion = _versionReader.read(newDbPath);
      if (!newVersion.hasVersionMeta) {
        throw StateError('ה-DB שהורד/חולץ אינו תקין (חסר schema_meta).');
      }

      onStage?.call('מחליף DB');
      _deleteQuietly('$dbPath-wal');
      _deleteQuietly('$dbPath-shm');
      File(dbPath).deleteSync();
      File(newDbPath).renameSync(dbPath);
      _recovery.finishSuccess(dbPath);
    } catch (_) {
      await _recovery.rollback(dbPath);
      rethrow;
    } finally {
      _deleteQuietly(compressedPath);
      _deleteQuietly(newDbPath);
    }
  }

  void _deleteQuietly(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // מתעלמים — ניקוי best-effort בלבד.
    }
  }

  /// סוגר את חיבורי ה-HTTP הפנימיים. יש לקרוא כשמסיימים להשתמש
  /// ב-[LibraryManager] (לא הכרחי בין קריאות בודדות — רק בסגירת האפליקציה).
  void dispose() {
    _discovery.client.dispose();
    _downloader.dispose();
  }
}

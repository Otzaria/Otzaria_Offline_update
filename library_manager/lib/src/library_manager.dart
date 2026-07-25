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
/// **מקור העדכונים** ניתן להחלפה בזמן ריצה בין הענן (GitHub, ברירת מחדל)
/// לבין מראה מקומית (offline) — ראו [useLocalMirror]/[useCloud]. המראה
/// המקומית עצמה נבנית פעם אחת, במחשב עם אינטרנט, דרך [exportOfflineMirror].
///
/// דוגמת שימוש (עדכון רגיל מהענן):
/// ```dart
/// final manager = LibraryManager(dataDir: r'C:\Users\me\AppData\Roaming\OurLauncher');
///
/// final check = await manager.checkForUpdate();
/// if (check.updateAvailable) {
///   await manager.applyUpdate(
///     check,
///     onStage: (stage) => print(stage),
///     onDownloadProgress: (received, total) => print('$received/$total'),
///   );
/// }
/// ```
///
/// דוגמת שימוש (הכנת מראה offline למחשב אחר, ואז עדכון ממנה):
/// ```dart
/// // במחשב עם אינטרנט:
/// await manager.exportOfflineMirror(destDir: r'D:\seforim-mirror');
/// // מעתיקים את D:\seforim-mirror\ ל-USB, פותחים במחשב היעד:
///
/// // במחשב היעד (בלי אינטרנט):
/// await manager.useLocalMirror(r'E:\seforim-mirror'); // E: = כונן ה-USB שם
/// final check = await manager.checkForUpdate(); // קורא מהתיקייה המקומית בלבד
/// ```
class LibraryManager {
  LibraryManager({
    required this.dataDir,
    this.otzariaProcessImageName = 'otzaria.exe',
    bool allowPrerelease = true,
  })  : _allowPrerelease = allowPrerelease,
        _stateStore = LibraryStateStore(p.join(dataDir, 'library_state.json')),
        _planner = const LibraryUpdatePlanner(),
        _versionReader = const LocalDbVersionReader(),
        _recovery = const LibraryDbRecoveryService(),
        _applier = const PatchApplier(),
        _processGuard = const OtzariaProcessGuard(),
        _cloudClient = GithubLibraryReleaseClient(),
        _downloader = PatchDownloader(decompress: const ZstdDecompressor().call) {
    _locator = LibraryDbLocator(stateStore: _stateStore);
  }

  /// תיקיית הנתונים של הלאנצ'ר (state, ונתיב ברירת המחדל להתקנה טרייה של
  /// ה-DB תחת `<dataDir>/library/seforim.db`).
  final String dataDir;

  /// שם קובץ ה-exe (בלבד, לא נתיב) לבדיקת "האם אוצריא רצה" לפני עדכון
  /// DB. ברירת המחדל תואמת את מה ש-[OtzariaExeLocator]/`otzaria_manager`
  /// מוצאים בפועל בהתקנה סטנדרטית.
  final String otzariaProcessImageName;

  /// אם `true` (ברירת מחדל), עדכוני DB עוקבים אחר releases prerelease של
  /// SeforimLibrary גם כן.
  final bool _allowPrerelease;

  final LibraryStateStore _stateStore;
  late final LibraryDbLocator _locator;
  final LibraryUpdatePlanner _planner;
  final LocalDbVersionReader _versionReader;
  final LibraryDbRecoveryService _recovery;
  final PatchApplier _applier;
  final OtzariaProcessGuard _processGuard;
  final PatchDownloader _downloader;

  /// לקוח ה-cloud (GitHub) — נשמר לאורך חיי ה-manager (מחזיק חיבור HTTP
  /// אחד) בין אם מצב ה-cloud פעיל ובין אם לא, כי [exportOfflineMirror]
  /// תמיד צריך אותו גם כשהמשתמש כרגע במצב מראה מקומית.
  final GithubLibraryReleaseClient _cloudClient;

  Future<void> setCustomDbPath(String dbPath) => _stateStore.saveCustomDbPath(dbPath);

  /// עובר לעדכון ממראה מקומית (offline) בתיקייה [mirrorDir] — במקום
  /// מהענן. התיקייה חייבת להיבנות מראש דרך [exportOfflineMirror] (או
  /// שהועתקה מתיקייה כזו, למשל מ-USB). הבחירה נשמרת בין הרצות.
  Future<void> useLocalMirror(String mirrorDir) =>
      _stateStore.saveLocalMirrorPath(mirrorDir);

  /// חוזר לעדכון מהענן (GitHub) — ברירת המחדל.
  Future<void> useCloud() => _stateStore.saveLocalMirrorPath(null);

  /// נתיב המראה המקומית הפעילה כרגע, או `null` אם מצב ה-cloud פעיל.
  Future<String?> currentLocalMirrorPath() => _stateStore.loadLocalMirrorPath();

  /// בונה מראה מקומית מלאה (כל עדכוני ה-DB, כולל היסטוריה) מהענן לתיקייה
  /// [destDir] — כדי להעביר למחשב בלי אינטרנט (USB / תיקייה משותפת). תמיד
  /// פונה ל-GitHub בפועל (דורש אינטרנט), ללא קשר למצב המקור הפעיל כרגע.
  Future<void> exportOfflineMirror({
    required String destDir,
    void Function(String stage)? onStage,
    void Function(int doneAssets, int totalAssets)? onAssetProgress,
    void Function(int downloaded, int? total)? onBytesProgress,
    bool Function()? isCancelled,
  }) async {
    final exporter = LibraryMirrorExporter(client: _cloudClient);
    await exporter.export(
      destDir: destDir,
      allowPrerelease: _allowPrerelease,
      onStage: onStage,
      onAssetProgress: onAssetProgress,
      onBytesProgress: onBytesProgress,
      isCancelled: isCancelled,
    );
  }

  /// מקור ה-releases הפעיל כרגע: מראה מקומית אם המשתמש בחר כזו (ותקינה),
  /// אחרת הענן. נבדק מחדש בכל [checkForUpdate] כדי שמעבר cloud↔mirror
  /// ייכנס לתוקף מיד, בלי לדרוש הפעלה מחדש של האפליקציה.
  Future<LibraryReleaseSource> _resolveSource() async {
    final mirrorPath = await _stateStore.loadLocalMirrorPath();
    if (mirrorPath != null && mirrorPath.isNotEmpty) {
      return LocalMirrorLibraryReleaseClient(mirrorDir: mirrorPath);
    }
    return _cloudClient;
  }

  /// בודק אם יש עדכון זמין.
  ///
  /// אם לא נמצא DB בכלל (לא בנתיב מותאם אישית ולא בברירת המחדל של
  /// אוצריא) — **לא** חוסם ומבקש בחירה ידנית; במקום זה מצביע אוטומטית על
  /// נתיב ברירת מחדל משלו (`<dataDir>/library/seforim.db`) וממשיך לתוכנית
  /// הורדה מלאה, בדיוק כמו שהתקנה ראשונה של אוצריא עצמה עובדת. ראו
  /// [LibraryUpdateCheckResult.isFreshInstall]. בחירה ידנית של קובץ DB
  /// קיים עדיין אפשרית מרצון דרך [setCustomDbPath].
  Future<LibraryUpdateCheckResult> checkForUpdate() async {
    var dbPath = await _locator.resolveDbPath();
    final isFreshInstall = dbPath == null;
    dbPath ??= p.join(dataDir, 'library', LibraryDbLocator.databaseFileName);

    LocalDbVersion local;
    if (isFreshInstall) {
      // אין DB בכלל עדיין — אין מה לקרוא ואין מה לשחזר. localVersion=0 +
      // hasVersionMeta=false גורמים ל-planner לבחור fullDownload, בדיוק
      // כמו DB ישן-מדי-לפאץ' (ראו LibraryUpdatePlanner._fullOrBlocked).
      local = const LocalDbVersion(dbVersion: 0, schemaVersion: null, hasVersionMeta: false);
    } else {
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
      local = _versionReader.read(dbPath);
    }

    final source = await _resolveSource();
    final discoverer = LibraryUpdateDiscovery(client: source);
    final discoveryResult = await discoverer.discover(allowPrerelease: _allowPrerelease);

    final plan = _planner.plan(
      localVersion: local.dbVersion,
      hasLocalVersionMeta: local.hasVersionMeta,
      latestVersion: discoveryResult.latestVersion,
      edges: discoveryResult.edges,
      latestFullDbAsset: discoveryResult.latestFullDbAsset,
      latestReleaseTag: discoveryResult.latestReleaseTag,
    );

    return LibraryUpdateCheckResult(
      dbPath: dbPath,
      localVersion: local,
      plan: plan,
      isFreshInstall: isFreshInstall,
    );
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
        isFreshInstall: check.isFreshInstall,
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
    required bool isFreshInstall,
    void Function(String stage)? onStage,
    void Function(int downloaded, int? total)? onDownloadProgress,
  }) async {
    final asset = plan.fullDbAsset;
    if (asset == null) {
      throw StateError('תוכנית fullDownload בלי asset — מצב לא צפוי.');
    }

    // התקנה טרייה: אין קובץ מקור בכלל עדיין (לא רק "ישן מדי") — צריך
    // ליצור את תיקיית האב, ואסור לנסות לגבות/למחוק קובץ שלא קיים.
    final dbExistsAlready = !isFreshInstall && await File(dbPath).exists();
    if (isFreshInstall) {
      await Directory(p.dirname(dbPath)).create(recursive: true);
    }

    final compressedPath = '$dbPath.download.zst';
    final newDbPath = '$dbPath.new';
    final timestamp = DateTime.now().toIso8601String();

    // createBackup רק אם יש בפועל קובץ קיים לגבות ממנו — בהתקנה טרייה אין
    // מה לגבות, וניסיון גיבוי של קובץ שלא קיים היה נכשל.
    await _recovery.beginApply(
      dbPath: dbPath,
      fromVersion: plan.localVersion,
      toVersion: plan.targetVersion ?? plan.localVersion,
      timestamp: timestamp,
      createBackup: dbExistsAlready,
    );

    try {
      onStage?.call('מוריד DB מלא (${plan.fullDbReleaseTag})');
      // downloadToFile מוריד את הבייטים הגולמיים (עדיין דחוסים) לדיסק —
      // לא מחלץ בעצמו (ראו PatchDownloader). החילוץ קורה בשלב נפרד למטה.
      // אם asset.downloadUrl הוא נתיב מקומי (מצב מראה offline) — מועתק
      // מהדיסק במקום הורדה, שקוף לחלוטין לקוד כאן.
      await _downloader.downloadToFile(
        url: asset.downloadUrl,
        destPath: compressedPath,
        expectedSize: asset.size,
        onProgress: onDownloadProgress,
      );

      onStage?.call('מחלץ DB מלא');
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
      if (dbExistsAlready) File(dbPath).deleteSync();
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
    _cloudClient.dispose();
    _downloader.dispose();
  }
}

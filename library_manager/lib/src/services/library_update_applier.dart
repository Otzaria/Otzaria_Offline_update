import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';

import 'otzaria_process_guard.dart';
import 'zstd_decompressor.dart';

/// שלב עדכון נוכחי — לדיווח ל-UI בלבד, לא נבדק ע"י שום לוגיקה.
enum LibraryApplyStage {
  downloadingPatch,
  applyingPatch,
  downloadingFullDb,
  decompressingFullDb,
  writingFullDb,
  verifying,
  done,
}

/// דיווח התקדמות יחיד. השדות האופציונליים רלוונטיים רק לשלבים מסוימים
/// (למשל [stepIndex]/[stepCount] רק במסלול דלתא, [bytesDownloaded]/
/// [bytesTotal] רק בשלבי הורדה).
class LibraryApplyProgress {
  final LibraryApplyStage stage;
  final int? stepIndex;
  final int? stepCount;
  final int? bytesDownloaded;
  final int? bytesTotal;

  const LibraryApplyProgress({
    required this.stage,
    this.stepIndex,
    this.stepCount,
    this.bytesDownloaded,
    this.bytesTotal,
  });
}

/// נזרק כשההחלה נכשלת מסיבה שאינה כבר מכוסה ע"י חריגים של
/// `seforim_library_updater` עצמו (כתובת חסרה, אי-התאמת גרסה אחרי כתיבה
/// וכו').
class LibraryApplyException implements Exception {
  final String message;
  const LibraryApplyException(this.message);
  @override
  String toString() => 'LibraryApplyException: $message';
}

/// מחיל בפועל [LibraryUpdatePlan] (delta או fullDownload) על ה-DB **החי**.
///
/// זהו בדיוק הרכיב שהוסר בעבר מ-[LibraryManager] בעקבות קריסת
/// `Illegal argument in isolate message: object is unsendable` (ראו
/// README הישן): הסוגר שהועבר ל-`Isolate.run` ניגש לשדה **מופע** (למשל
/// `_applier.apply(...)`), ובכך תפס implicitly את כל `this` — כולל
/// `HttpClient` חי שאינו ניתן לשליחה בין isolates.
///
/// כאן זה נבנה מחדש נכון: כל קריאה ל-`Isolate.run` עוברת דרך פונקציית
/// **top-level** (למטה בקובץ הזה) שמקבלת רק ארגומנטים פרימיטיביים/מבני-דאטה
/// טהורים (records, `String`, `Uint8List`, `DeltaManifest`) — בדיוק כמו
/// שכבר עובד נכון ב-`LibraryDbRecoveryService.cloneOrCopyFile`. אין כאן שום
/// גישה לשדה מופע בתוך סוגר שמועבר ל-Isolate.
class LibraryUpdateApplier {
  LibraryUpdateApplier({
    OtzariaProcessGuard processGuard = const OtzariaProcessGuard(),
    LibraryDbRecoveryService recovery = const LibraryDbRecoveryService(),
    LocalDbVersionReader versionReader = const LocalDbVersionReader(),
  })  : _processGuard = processGuard,
        _recovery = recovery,
        _versionReader = versionReader,
        _downloader = PatchDownloader(decompress: const ZstdDecompressor().call),
        _decompress = const ZstdDecompressor().call;

  final OtzariaProcessGuard _processGuard;
  final LibraryDbRecoveryService _recovery;
  final LocalDbVersionReader _versionReader;
  final PatchDownloader _downloader;
  final Future<Uint8List?> Function(Uint8List) _decompress;

  static const String _otzariaProcessImageName = 'otzaria.exe';

  /// מחיל שרשרת patches דלתאיים ברצף, אחד־אחד, על [dbPath].
  ///
  /// כל שלב אטומי בפני עצמו (transaction יחיד ב-SQLite) — אם שלב N נכשל,
  /// ה-DB נשאר תקין בגרסה שלפני השלב הזה (השלבים 1..N-1 כבר הוחלו והצליחו).
  /// אין גיבוי מלא של הקובץ במסלול הזה — הוא לא נחוץ, ו-DB מלא יכול להיות
  /// גדול מדי לגיבוי חוזר על כל patch.
  Future<void> applyDelta({
    required LibraryUpdatePlan plan,
    required String dbPath,
    void Function(LibraryApplyProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (plan.kind != LibraryUpdatePlanKind.delta) {
      throw const LibraryApplyException('applyDelta נקרא על תוכנית שאינה delta');
    }
    await _guardOtzariaNotRunning();

    final tmpDir = Directory(p.join(p.dirname(dbPath), '.seforim-update-tmp'));
    final steps = plan.deltaSteps;

    for (var i = 0; i < steps.length; i++) {
      _throwIfCancelled(isCancelled);
      final edge = steps[i];
      final manifest = edge.manifest;
      final patchFile = manifest.patchFiles.first;
      final url = edge.patchFileUrls[patchFile.file];
      if (url == null) {
        throw LibraryApplyException('לא נמצא URL להורדת ${patchFile.file}');
      }

      final patchPath = await _downloader.downloadAndExtract(
        patchFile: patchFile,
        downloadUrl: url,
        destDir: tmpDir,
        onProgress: (downloaded, total) => onProgress?.call(
          LibraryApplyProgress(
            stage: LibraryApplyStage.downloadingPatch,
            stepIndex: i + 1,
            stepCount: steps.length,
            bytesDownloaded: downloaded,
            bytesTotal: total,
          ),
        ),
        isCancelled: isCancelled,
      );

      // אין גיבוי (createBackup: false) — ה-apply עצמו אטומי, ראו doc-comment.
      await _recovery.beginApply(
        dbPath: dbPath,
        fromVersion: manifest.fromVersion,
        toVersion: manifest.toVersion,
        timestamp: DateTime.now().toIso8601String(),
        createBackup: false,
      );

      onProgress?.call(LibraryApplyProgress(
        stage: LibraryApplyStage.applyingPatch,
        stepIndex: i + 1,
        stepCount: steps.length,
      ));

      try {
        // חשוב: הקריאה ל-Isolate.run **חייבת** לקרות בתוך מתודה נפרדת
        // (`_isolateApplyPatch`, סטטית), לא כאן inline בתוך הלולאה. הסיבה
        // אינה טריוויאלית: גם אם הסוגר referenced רק dbPath/patchPath/
        // manifest (משתנים מקומיים, לא שדות מופע), ה-compiler של Dart
        // ארוז את כל המשתנים שנתפסים ע"י **כל** הסגורים שמוגדרים באותו
        // בלוק לקסיקלי (כאן: גם הסוגר של `onProgress` בקריאת
        // downloadAndExtract למעלה) לתוך אותו אובייקט Context משותף —
        // ו-Isolate.send מנסה לשלוח את כל ה-Context, כולל שדות שלא
        // בשימוש בפועל ע"י הסוגר הזה עצמו. זה בדיוק מה שגרם לקריסה
        // "object is unsendable" גם אחרי התיקון הקודם: השרשרת בקריסה
        // עברה דרך `onProgress` של הבקר (`LibraryModuleController`), עד
        // לעץ ה-widgets כולו. מתודה נפרדת = frame לקסיקלי נפרד = אין
        // Context משותף עם onProgress.
        await _isolateApplyPatch(dbPath, patchPath, manifest);
        _recovery.finishSuccess(dbPath);
      } catch (_) {
        // apply אטומי: אם זרק, ה-DB כלל לא השתנה. רק מנקים את הסימון.
        _recovery.clearStaleArtifacts(dbPath);
        rethrow;
      } finally {
        _deleteQuietly(patchPath);
      }
    }

    onProgress?.call(const LibraryApplyProgress(stage: LibraryApplyStage.done));
  }

  /// מוריד ומתקין DB מלא — עבור התקנה טרייה (אין DB קיים) או כש-planner
  /// קבע שאין מסלול דלתא בטוח.
  ///
  /// **מגבלה ידועה (MVP):** החילוץ כרגע הוא **בזיכרון** (כל ה-DB, עד
  /// כ-1.1GB לא דחוס, נטען ל-RAM פעמיים — דחוס ואז מחולץ) ולא streaming
  /// כמו ב-onboarding של אוצריא עצמה. עובד, אבל צורך יותר זיכרון משיא
  /// אפשרי. שדרוג ל-streaming extractor הוא צעד המשך מומלץ אם זה מתברר
  /// כבעיה בפועל על מחשבים חלשים.
  Future<void> applyFullDownload({
    required LibraryUpdatePlan plan,
    required String dbPath,
    void Function(LibraryApplyProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (plan.kind != LibraryUpdatePlanKind.fullDownload) {
      throw const LibraryApplyException(
          'applyFullDownload נקרא על תוכנית שאינה fullDownload');
    }
    final asset = plan.fullDbAsset;
    if (asset == null) {
      throw const LibraryApplyException('לא נמצא נכס DB מלא בתוכנית');
    }
    await _guardOtzariaNotRunning();

    final dir = Directory(p.dirname(dbPath));
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final compressedPath = '$dbPath.download.zst';
    await _downloader.downloadToFile(
      url: asset.downloadUrl,
      destPath: compressedPath,
      expectedSize: asset.size,
      expectedSha256: _sha256FromDigest(asset.digest),
      resumeToken: asset.id?.toString(),
      onProgress: (downloaded, total) => onProgress?.call(LibraryApplyProgress(
        stage: LibraryApplyStage.downloadingFullDb,
        bytesDownloaded: downloaded,
        bytesTotal: total,
      )),
      isCancelled: isCancelled,
    );

    _throwIfCancelled(isCancelled);
    onProgress?.call(const LibraryApplyProgress(stage: LibraryApplyStage.decompressingFullDb));

    final compressedBytes = await File(compressedPath).readAsBytes();
    final extracted = await _decompress(compressedBytes);
    if (extracted == null || extracted.isEmpty) {
      _deleteQuietly(compressedPath);
      throw const LibraryApplyException('חילוץ ה-DB המלא נכשל או החזיר ריק');
    }

    final dbAlreadyExists = File(dbPath).existsSync();
    if (dbAlreadyExists) {
      // מסלול החלפת קובץ אינו אטומי כמו patch — כאן כן צריך גיבוי מלא
      // לשחזור אם הכתיבה תיכשל באמצע.
      await _recovery.beginApply(
        dbPath: dbPath,
        fromVersion: plan.localVersion,
        toVersion: plan.targetVersion ?? 0,
        timestamp: DateTime.now().toIso8601String(),
        createBackup: true,
      );
    }

    onProgress?.call(const LibraryApplyProgress(stage: LibraryApplyStage.writingFullDb));
    final newFilePath = '$dbPath.new';
    try {
      // ראו doc-comment ב-`_isolateApplyPatch` למעלה: חייב להיות במתודה
      // סטטית נפרדת, לא Isolate.run inline כאן — כדי לא לחלוק Context
      // לקסיקלי עם `onProgress`.
      await _isolateWriteBytes(newFilePath, extracted);
      _deleteQuietly('$dbPath-wal');
      _deleteQuietly('$dbPath-shm');
      if (File(dbPath).existsSync()) File(dbPath).deleteSync();
      File(newFilePath).renameSync(dbPath);
    } catch (_) {
      _deleteQuietly(newFilePath);
      if (dbAlreadyExists) await _recovery.rollback(dbPath);
      rethrow;
    }

    onProgress?.call(const LibraryApplyProgress(stage: LibraryApplyStage.verifying));
    final resultVersion = _versionReader.read(dbPath);
    if (plan.targetVersion != null && resultVersion.dbVersion != plan.targetVersion) {
      if (dbAlreadyExists) await _recovery.rollback(dbPath);
      throw LibraryApplyException(
        'אחרי כתיבת ה-DB המלא, הגרסה שנקראה (${resultVersion.dbVersion}) '
        'לא תואמת ליעד (${plan.targetVersion}) — בוצע שחזור.',
      );
    }

    if (dbAlreadyExists) _recovery.finishSuccess(dbPath);
    _deleteQuietly(compressedPath);
    onProgress?.call(const LibraryApplyProgress(stage: LibraryApplyStage.done));
  }

  /// עוטף את `Isolate.run` במתודה **סטטית** נפרדת — קריטי, ראו הסבר
  /// ב-doc-comment בנקודת הקריאה ב-[applyDelta]. סטטית = אין `this`
  /// בכלל, ומתודה נפרדת = frame לקסיקלי נפרד שלא חולק Context עם
  /// סגורי `onProgress` של הקוד הקורא.
  static Future<PatchApplyResult> _isolateApplyPatch(
    String dbPath,
    String patchPath,
    DeltaManifest manifest,
  ) {
    return Isolate.run(
      () => _applyPatchInIsolate((dbPath, patchPath, manifest)),
    );
  }

  /// כנ"ל, עבור כתיבת ה-DB המלא המחולץ.
  static Future<void> _isolateWriteBytes(String path, Uint8List bytes) {
    return Isolate.run(() => _writeBytesInIsolate((path, bytes)));
  }

  Future<void> _guardOtzariaNotRunning() async {
    // tasklist הוא פקודת Windows בלבד — בפלטפורמות אחרות (כולל בדיקות
    // אוטומטיות שרצות על Linux/macOS) אין מה לבדוק ופשוט ממשיכים.
    if (!Platform.isWindows) return;
    if (await _processGuard.isRunning(_otzariaProcessImageName)) {
      throw const OtzariaIsRunningException();
    }
  }

  void _throwIfCancelled(bool Function()? isCancelled) {
    if (isCancelled?.call() ?? false) {
      throw const LibraryApplyException('העדכון בוטל');
    }
  }

  String? _sha256FromDigest(String? digest) {
    const prefix = 'sha256:';
    if (digest == null || !digest.startsWith(prefix)) return null;
    return digest.substring(prefix.length);
  }

  void _deleteQuietly(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  /// סוגר את חיבור ה-HTTP הפנימי של המוריד.
  void dispose() => _downloader.dispose();
}

/// פונקציית top-level — לעולם לא יכולה לתפוס `this` בטעות. זה בדיוק ההבדל
/// מהבאג המקורי (ראו doc-comment של [LibraryUpdateApplier]).
PatchApplyResult _applyPatchInIsolate(
  (String, String, DeltaManifest) args,
) {
  const applier = PatchApplier();
  return applier.apply(
    dbPath: args.$1,
    patchPath: args.$2,
    manifest: args.$3,
  );
}

/// פונקציית top-level לכתיבת ה-DB המלא המחולץ — גם היא ללא כל גישה ל-`this`.
/// [args]: `($1: נתיב יעד, $2: bytes לכתיבה)`.
void _writeBytesInIsolate((String, Uint8List) args) {
  File(args.$1).writeAsBytesSync(args.$2, flush: true);
}

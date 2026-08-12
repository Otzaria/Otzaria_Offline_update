import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'otzaria_process_guard.dart';
import 'zstd_decompressor.dart';
import 'zstd_file_decompressor.dart';

/// שלב עדכון נוכחי — לדיווח ל-UI בלבד, לא נבדק ע"י שום לוגיקה.
enum LibraryApplyStage {
  downloadingPatch,
  applyingPatch,
  downloadingFullDb,
  decompressingFullDb,
  writingFullDb,
  verifying,

  /// התקנת הקבצים הנלווים (תלמוד/קטלוג/מילון) — אחרי המסד, כמו באוצריא.
  installingCompanions,
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

  /// תת-השלב הגולמי בתוך ההחלה, כפי ש-`PatchApplier.onStage` מדווח אותו
  /// (`upserts`, `verifyToHash`...). `null` בכל שלב שאינו החלת patch.
  final String? patchStage;

  /// יחס התקדמות 0..1 בתוך אימות ה-hash הארוך; `null` בשאר תת-השלבים.
  final double? verifyProgress;

  /// טקסט מוכן להצגה שהגיע מהשלב עצמו (הקבצים הנלווים מדווחים כך את שם
  /// הפריט שבטיפול). כבר מתורגם — ה-UI מציג אותו כמו שהוא.
  final String? statusText;

  const LibraryApplyProgress({
    required this.stage,
    this.stepIndex,
    this.stepCount,
    this.bytesDownloaded,
    this.bytesTotal,
    this.patchStage,
    this.verifyProgress,
    this.statusText,
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

/// אימות המסד המחולץ לפני שהוא מחליף את החי — `quick_check` וגרסה. מוזרק
/// כדי שבדיקות יוכלו לרוץ על מטען שאינו מסד sqlite אמיתי.
typedef ExtractedDbVerifier = Future<void> Function(
  String newDbPath,
  int? expectedVersion,
);

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
/// שכבר עובד נכון ב-`ZstdFileDecompressor`. אין כאן שום גישה לשדה מופע בתוך
/// סוגר שמועבר ל-Isolate.
///
/// **תוספת חשובה (הבאג שחזר):** לא מספיק שהסוגר עצמו לא ניגש ל-`this` —
/// דארט חולק אובייקט `Context` *אחד* בין כל הסוגרים שנוצרים באותו scope
/// לקסיקלי, לא רק בין הסוגרים שבפועל *משתמשים* במשתנה מסוים. ב-`applyDelta`/
/// `applyFullDownload`, הפרמטר `onProgress` (סוגר שמגיע מהצרכן וסוגר-שרשרת
/// על `LibraryModuleController` כולו — עד לעץ ה-widgets) נקרא **באותו בלוק**
/// שבו נוצר סוגר ה-`Isolate.run`. כתוצאה מכך, גם אם קוד הסוגר של ה-Isolate
/// לא נוגע ב-`onProgress` בכלל, ה-Context המשותף שלו כן מכיל את `onProgress`
/// — וניסיון השליחה ל-isolate נכשל כי הוא "גורר" איתו את כל השרשרת. ראו
/// dart-lang/sdk#52661 ("Closures over-capture, cannot be sent to other
/// isolate"). הפתרון: קריאת `Isolate.run` חייבת להיות בתוך מתודה/פונקציה
/// **נפרדת לגמרי** (לא רק סוגר נפרד), כדי שה-Context שלה לא ישותף בשום צורה
/// עם ה-scope של `applyDelta`/`applyFullDownload` — ראו [_isolateApplyPatch]
/// ואת אותה תבנית ב-`ZstdFileDecompressor`.
class LibraryUpdateApplier {
  LibraryUpdateApplier({
    OtzariaProcessGuard processGuard = const OtzariaProcessGuard(),
    LibraryDbRecoveryService recovery = const LibraryDbRecoveryService(),
    ExtractedDbVerifier? verifyExtractedDb,
  })  : _processGuard = processGuard,
        _recovery = recovery,
        _verifyExtractedDb = verifyExtractedDb ?? _defaultExtractedDbVerifier,
        _downloader =
            PatchDownloader(decompress: const ZstdDecompressor().call),
        _decompress = const ZstdDecompressor().call;

  final OtzariaProcessGuard _processGuard;
  final LibraryDbRecoveryService _recovery;
  final ExtractedDbVerifier _verifyExtractedDb;
  final PatchDownloader _downloader;
  final Future<Uint8List?> Function(Uint8List) _decompress;

  /// שם קובץ ה-hint לסך-הבתים של אימות ה-hash — ראו [applyDelta].
  static const String _verifyHintFileName = 'verify_total_bytes.txt';

  static Future<void> _defaultExtractedDbVerifier(
    String newDbPath,
    int? expectedVersion,
  ) =>
      _isolateVerifyExtractedDb(newDbPath, expectedVersion, AppL10n.language);

  /// הזמן הקצוב לפתיחת חיבור בהורדות של ההחלה — ראו
  /// [PatchDownloader.connectTimeout]. ה-`stallTimeout` נשאר בברירת המחדל
  /// בכוונה: הוא מודד שקט בין צ'אנקים של הורדה של ~1GB, לא זמן תגובה של
  /// בקשת מטא-דאטה.
  set connectTimeout(Duration value) => _downloader.connectTimeout = value;

  /// שמות התהליך שנחשבים "אוצריא פתוחה", לפי הפלטפורמה הנוכחית — ראו
  /// [OtzariaProcessGuard.processNamesFor] (ב-macOS השם בעברית).
  static final List<String> _otzariaProcessNames =
      OtzariaProcessGuard.processNamesFor(Platform.operatingSystem);

  /// מחיל שרשרת patches דלתאיים ברצף, אחד־אחד, על [dbPath].
  ///
  /// כל שלב אטומי בפני עצמו (transaction יחיד ב-SQLite) — אם שלב N נכשל,
  /// ה-DB נשאר תקין בגרסה שלפני השלב הזה (השלבים 1..N-1 כבר הוחלו והצליחו).
  /// אין גיבוי מלא של הקובץ במסלול הזה — הוא לא נחוץ, ו-DB מלא יכול להיות
  /// גדול מדי לגיבוי חוזר על כל patch.
  ///
  /// **אימות ה-hash רץ פעם אחת, בצעד האחרון.** ה-hash הלוגי הוא על תוכן ה-DB
  /// כולו, ולכן התאמה ל-`toContentHash` של הצעד האחרון מוכיחה את **כל**
  /// השרשרת — ואין טעם לקרוא מסד של ~7.4GB פעם לכל צעד (מי שפספס חמש גרסאות
  /// שילם את זה חמש פעמים). שרשרת שנקטעה באמצע משאירה מסד שהוחל נקי אך לא
  /// אומת, ולכן היא מסמנת אותו ב-[LibraryDbRecoveryService.markUnverified];
  /// ההחלה הבאה שמתחילה מאותה גרסה מפעילה `verifyFromHash` ומאמתת אותו לפני
  /// שהיא בונה עליו. כך אין מצב שבו מסד לא-מאומת נשאר כזה בשקט.
  /// מחזיר את מזהי הספרים שתוכנם השתנה — כפי ש-`PatchApplier` מדווח אותם.
  /// ראו [LibraryManager.applyUpdate] למה נעשה בהם.
  ///
  /// [onStepApplied] נקרא אחרי **כל** שלב שהוחל בהצלחה, עם הספרים שהשלב
  /// הזה נגע בהם — כדי שהקורא יוכל לרשום גם שרשרת שנקטעה באמצע.
  Future<Set<int>> applyDelta({
    required LibraryUpdatePlan plan,
    required String dbPath,
    void Function(LibraryApplyProgress progress)? onProgress,
    void Function(Set<int> booksTouched)? onStepApplied,
    bool Function()? isCancelled,
  }) async {
    if (plan.kind != LibraryUpdatePlanKind.delta) {
      throw const LibraryApplyException(
          'applyDelta נקרא על תוכנית שאינה delta');
    }
    await _guardOtzariaNotRunning();

    final tmpDir = Directory(p.join(p.dirname(dbPath), '.seforim-update-tmp'));
    final steps = plan.deltaSteps;

    // סך-הבתים שנכנסו ל-hash בריצה הקודמת — total מדויק למד ההתקדמות. גודל
    // הקובץ (ברירת המחדל בלעדיו) הוא הערכת-יתר של עשרות אחוזים.
    final hintFile = File(p.join(tmpDir.path, _verifyHintFileName));
    var verifyTotalHint = _readIntQuietly(hintFile);
    var lastVerifyDone = 0;
    var lastPatchStage = 'verifyToHash';
    final booksTouched = <int>{};

    // גרסה שנשארה לא-מאומתת משרשרת שנקטעה — ראו doc-comment למעלה.
    final unverifiedVersion = _recovery.unverifiedVersion(dbPath);

    for (var i = 0; i < steps.length; i++) {
      _throwIfCancelled(isCancelled);
      final edge = steps[i];
      final manifest = edge.manifest;
      final patchFile = manifest.patchFiles.first;
      final url = edge.patchFileUrls[patchFile.file];
      if (url == null) {
        throw LibraryApplyException(
          AppL10n.strings.libraryDomain.patchUrlMissing(patchFile.file),
        );
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

      await _recovery.beginApply(
        dbPath: dbPath,
        fromVersion: manifest.fromVersion,
        toVersion: manifest.toVersion,
        timestamp: DateTime.now().toIso8601String(),
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
        final result = await _isolateApplyPatch(
          dbPath: dbPath,
          patchPath: patchPath,
          manifest: manifest,
          language: AppL10n.language,
          // אימות התוצאה רק בצעד האחרון; אימות המקור רק כשהמסד הגיע לגרסתו
          // בשרשרת שנקטעה ולא אומת.
          verifyFromHash: i == 0 && unverifiedVersion == manifest.fromVersion,
          verifyToHash: i == steps.length - 1,
          verifyTotalBytesHint: verifyTotalHint,
          onStage: (patchStage) {
            // נשמר כדי שמד ההתקדמות של ה-hash ידווח את תת-השלב הנכון: מעכשיו
            // ייתכן גם `verifyFromHash`, ולא רק `verifyToHash`.
            lastPatchStage = patchStage;
            onProgress?.call(LibraryApplyProgress(
              stage: LibraryApplyStage.applyingPatch,
              stepIndex: i + 1,
              stepCount: steps.length,
              patchStage: patchStage,
            ));
          },
          onVerifyProgress: (done, total) {
            lastVerifyDone = done;
            onProgress?.call(LibraryApplyProgress(
              stage: LibraryApplyStage.applyingPatch,
              stepIndex: i + 1,
              stepCount: steps.length,
              patchStage: lastPatchStage,
              verifyProgress: total > 0 ? (done / total).clamp(0.0, 1.0) : null,
            ));
          },
        );
        booksTouched.addAll(result.booksTouched);
        onStepApplied?.call(result.booksTouched);
        // הדיווח האחרון הוא הסך המדויק — ה-total לריצות הבאות.
        if (lastVerifyDone > 0) {
          verifyTotalHint = lastVerifyDone;
          _writeIntQuietly(hintFile, lastVerifyDone);
        }
        // `resultHash != null` פירושו שהצעד הזה אומת בפועל.
        if (result.resultHash != null) {
          _recovery.clearUnverified(dbPath);
        } else {
          _recovery.markUnverified(dbPath, manifest.toVersion);
        }
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
    return booksTouched;
  }

  /// מוריד ומתקין DB מלא — עבור התקנה טרייה (אין DB קיים) או כש-planner
  /// קבע שאין מסלול דלתא בטוח.
  ///
  /// ההורדה והחילוץ שניהם **בזרימה**: הקובץ הדחוס יורד ישר לדיסק
  /// ([PatchDownloader.downloadToFile]), ומשם מחולץ קובץ-לקובץ דרך
  /// [ZstdFileDecompressor] — שיא הזיכרון הוא חוצצים בודדים, לא ~1.1GB של DB.
  /// אם ה-streaming אינו זמין בפלטפורמה (אין ספריית zstd לטעינה) נופלים
  /// למסלול הזיכרון הקודם, שנשאר כגיבוי ב-[_decompressInMemoryTo].
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
      throw LibraryApplyException(
        AppL10n.strings.libraryDomain.fullDbAssetMissingFromPlan,
      );
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
    onProgress?.call(const LibraryApplyProgress(
        stage: LibraryApplyStage.decompressingFullDb));

    // מחלצים לקובץ צדדי ורק בסוף מחליפים את ה-DB: כך ה-DB הקיים נשאר שלם
    // עד שהחדש מוכן במלואו, בדיוק כמו במסלול ה-staging של התקנת האפליקציה.
    final newFilePath = '$dbPath.new';
    _deleteQuietly(newFilePath);
    try {
      if (!await ZstdFileDecompressor.decompressFileToFile(
        compressedPath,
        newFilePath,
      )) {
        // אין streaming בפלטפורמה הזו — מסלול הזיכרון, ראו doc-comment.
        await _decompressInMemoryTo(compressedPath, newFilePath);
      }
    } catch (_) {
      _deleteQuietly(newFilePath);
      _deleteQuietly(compressedPath);
      rethrow;
    }
    if (!File(newFilePath).existsSync() ||
        File(newFilePath).lengthSync() == 0) {
      _deleteQuietly(newFilePath);
      _deleteQuietly(compressedPath);
      throw LibraryApplyException(
        AppL10n.strings.libraryDomain.fullDbExtractionFailed,
      );
    }

    // אימות **לפני** ההחלפה, כמו באוצריא: מסד פגום או בגרסה לא נכונה נעצר
    // כאן, בעוד ה-DB החי עדיין שלם — במקום להחליף ואז לשחזר מגיבוי.
    onProgress
        ?.call(const LibraryApplyProgress(stage: LibraryApplyStage.verifying));
    try {
      await _verifyExtractedDb(newFilePath, plan.targetVersion);
    } catch (_) {
      _deleteQuietly(newFilePath);
      _deleteQuietly(compressedPath);
      rethrow;
    }
    _throwIfCancelled(isCancelled);

    final dbAlreadyExists = File(dbPath).existsSync();
    if (dbAlreadyExists) {
      // סימון בלבד — אין גיבוי של המסד, ראו [LibraryDbRecoveryService].
      try {
        await _recovery.beginApply(
          dbPath: dbPath,
          fromVersion: plan.localVersion,
          toVersion: plan.targetVersion ?? 0,
          timestamp: DateTime.now().toIso8601String(),
        );
      } catch (_) {
        // כשל כאן (תיקייה שאינה ניתנת לכתיבה) קרה **אחרי** שהמסד המחולץ כבר
        // על הדיסק — בלי הניקוי הזה נשארים ~1.1GB תלויים על כונן שכבר צר.
        _deleteQuietly(newFilePath);
        _deleteQuietly(compressedPath);
        rethrow;
      }
    }

    // ההורדה והחילוץ ארכו דקות רבות; אוצריא יכלה להיפתח בינתיים. הבדיקה
    // החוזרת עולה כלום, ובלעדיה ב-macOS היינו מוחקים את המסד מתחת לאוצריא
    // רצה (`unlink` על קובץ פתוח מצליח שם).
    await _guardOtzariaNotRunning();

    onProgress?.call(
        const LibraryApplyProgress(stage: LibraryApplyStage.writingFullDb));
    // מפנים את השם בשני שלבים במקום למחוק ואז להחליף: rename הוא מיידי ואינו
    // עולה מקום, וכך אין רגע שבו אין מסד כלל. מחיקה-ואז-rename שנקטע באמצע
    // (נעילה של אנטי-וירוס, הפסקת חשמל) הותירה את המשתמש בלי ספרייה.
    final retiredPath = '$dbPath.old';
    _deleteQuietly(retiredPath);
    var retired = false;
    try {
      if (File(dbPath).existsSync()) {
        File(dbPath).renameSync(retiredPath);
        retired = true;
      }
      File(newFilePath).renameSync(dbPath);
    } catch (_) {
      _deleteQuietly(compressedPath);
      // גלגול אחור: המסד הישן חוזר לשמו, וה-`<db>.new` נשאר לניסיון הבא.
      if (retired && !File(dbPath).existsSync()) {
        try {
          File(retiredPath).renameSync(dbPath);
        } catch (_) {
          // גם הגלגול נכשל — משאירים את שניהם, הם הקבצים התקינים היחידים,
          // ואת הסימון שמעיד שכאן נקטע עדכון.
          rethrow;
        }
      }
      _deleteQuietly(retiredPath);
      if (dbAlreadyExists) _recovery.clearStaleArtifacts(dbPath);
      rethrow;
    }

    // רק עכשיו, כשהמסד החדש במקומו: ה-WAL/SHM שייכים לישן ומחיקתם מוקדם
    // יותר הייתה מאבדת טרנזקציות שכבר בוצעו אם ההחלפה נכשלה.
    _deleteQuietly('$dbPath-wal');
    _deleteQuietly('$dbPath-shm');
    _deleteQuietly(retiredPath);

    if (dbAlreadyExists) _recovery.finishSuccess(dbPath);
    // המסד החדש אומת (`quick_check` + גרסה) והגיע מנכס שה-sha256 שלו נבדק,
    // ולכן סימון "לא מאומת" משרשרת שנקטעה בעבר אינו רלוונטי יותר.
    _recovery.clearUnverified(dbPath);
    _deleteQuietly(compressedPath);
    onProgress?.call(const LibraryApplyProgress(stage: LibraryApplyStage.done));
  }

  /// עוטף את `Isolate.run` במתודה **סטטית** נפרדת — קריטי, ראו הסבר
  /// ב-doc-comment בנקודת הקריאה ב-[applyDelta]. סטטית = אין `this`
  /// בכלל, ומתודה נפרדת = frame לקסיקלי נפרד שלא חולק Context עם
  /// סגורי `onProgress` של הקוד הקורא.
  ///
  /// [language] מועברת במפורש: משתנים סטטיים אינם משותפים בין isolates, ולכן
  /// `AppL10n` בתוך ה-isolate היה חוזר לברירת המחדל והודעות השגיאה משם היו
  /// יוצאות בעברית גם כשהממשק באנגלית.
  ///
  /// דיווח תת-השלבים חוזר דרך [ReceivePort]: ה-callbacks עצמם נשארים כאן
  /// ולא נכנסים ל-scope של ה-`Isolate.run` (ראו ההסבר על ה-Context המשותף).
  static Future<PatchApplyResult> _isolateApplyPatch({
    required String dbPath,
    required String patchPath,
    required DeltaManifest manifest,
    required AppLanguage language,
    required bool verifyFromHash,
    required bool verifyToHash,
    int? verifyTotalBytesHint,
    void Function(String stage)? onStage,
    void Function(int done, int total)? onVerifyProgress,
  }) async {
    final port = ReceivePort();
    final sub = port.listen((msg) {
      // String = שם תת-שלב; record = (bytesHashed, total) של האימות.
      if (msg is String) {
        onStage?.call(msg);
      } else if (msg is (int, int)) {
        onVerifyProgress?.call(msg.$1, msg.$2);
      }
    });
    try {
      return await _runApplyIsolate(
        dbPath: dbPath,
        patchPath: patchPath,
        manifest: manifest,
        language: language,
        verifyFromHash: verifyFromHash,
        verifyToHash: verifyToHash,
        verifyTotalBytesHint: verifyTotalBytesHint,
        sendPort: port.sendPort,
      );
    } finally {
      // ההודעות האחרונות עדיין בתור כש-`Isolate.run` חוזר; בלי המתנה לסבב
      // אירועים אחד הן היו נזרקות עם הביטול, וה-hint לאימות היה יוצא נמוך.
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      port.close();
    }
  }

  /// מתודה נפרדת נוספת: כאן נוצר סוגר ה-`Isolate.run`, ולכן היא מקבלת **רק**
  /// ערכים ניתנים-לשליחה — ה-callbacks של [_isolateApplyPatch] נשארים מחוצה לה.
  static Future<PatchApplyResult> _runApplyIsolate({
    required String dbPath,
    required String patchPath,
    required DeltaManifest manifest,
    required AppLanguage language,
    required bool verifyFromHash,
    required bool verifyToHash,
    required SendPort sendPort,
    int? verifyTotalBytesHint,
  }) {
    return Isolate.run(
      () => _applyPatchInIsolate((
        dbPath,
        patchPath,
        manifest,
        language,
        verifyTotalBytesHint,
        sendPort,
        verifyFromHash,
        verifyToHash,
      )),
    );
  }

  /// מריץ את בדיקת התקינות של המסד המחולץ ב-isolate — `quick_check` על ~5.5GB
  /// חוסם דקות. ראו [_verifyExtractedDb].
  static Future<void> _isolateVerifyExtractedDb(
    String newDbPath,
    int? expectedVersion,
    AppLanguage language,
  ) {
    return Isolate.run(
      () => _verifyExtractedDbInIsolate((newDbPath, expectedVersion, language)),
    );
  }

  /// מסלול הגיבוי לחילוץ, לפלטפורמה שאין בה ספריית zstd לטעינה ישירה: כל
  /// ה-DB עובר דרך ה-RAM. נשמר בכוונה — עדיף חילוץ יקר בזיכרון מכשל מוחלט —
  /// אבל **אינו** המסלול הרגיל, ראו [ZstdFileDecompressor].
  ///
  /// הכתיבה היא `writeAsBytes` אסינכרוני ולא `Isolate.run`: שליחת `Uint8List`
  /// ל-isolate מעתיקה אותו, כלומר עוד ~1.1GB, בעוד ש-`writeAsBytes` כבר מבצע
  /// את ה-I/O מחוץ ל-isolate הראשי.
  Future<void> _decompressInMemoryTo(
    String compressedPath,
    String destPath,
  ) async {
    final extracted =
        await _decompress(await File(compressedPath).readAsBytes());
    if (extracted == null || extracted.isEmpty) {
      throw LibraryApplyException(
        AppL10n.strings.libraryDomain.fullDbExtractionFailed,
      );
    }
    await File(destPath).writeAsBytes(extracted, flush: true);
  }

  Future<void> _guardOtzariaNotRunning() async {
    // הבדיקה עצמה תלויית-פלטפורמה (tasklist/pgrep) ומטופלת בתוך ה-guard;
    // כאן רק מחליטים מה לעשות עם התשובה. שים לב שבלינוקס אין מסלול התקנה
    // של הלאנצ'ר, אבל ה-guard בכל זאת עונה שם — כדי שבדיקות אוטומטיות
    // שרצות על לינוקס יעברו באותו מסלול קוד ולא ב-shortcut.
    if (await _processGuard.isAnyRunning(_otzariaProcessNames)) {
      throw const OtzariaIsRunningException();
    }
  }

  void _throwIfCancelled(bool Function()? isCancelled) {
    if (isCancelled?.call() ?? false) {
      throw LibraryApplyException(
        AppL10n.strings.libraryDomain.updateCancelled,
      );
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

  static int? _readIntQuietly(File file) {
    try {
      if (!file.existsSync()) return null;
      final value = int.tryParse(file.readAsStringSync().trim());
      return (value != null && value > 0) ? value : null;
    } catch (_) {
      return null;
    }
  }

  static void _writeIntQuietly(File file, int value) {
    try {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('$value');
    } catch (_) {}
  }

  /// סוגר את חיבור ה-HTTP הפנימי של המוריד.
  void dispose() => _downloader.dispose();
}

/// פונקציית top-level — לעולם לא יכולה לתפוס `this` בטעות. זה בדיוק ההבדל
/// מהבאג המקורי (ראו doc-comment של [LibraryUpdateApplier]).
///
/// `checkForeignKeys` כבוי, בדיוק כמו ב-`LibraryUpdateRepository` של אוצריא:
/// אימות ה-hash הוא הערובה האמיתית (מקור שונה ⇒ ה-hash לא יתאים וה-transaction
/// יתגלגל אחורה), והוא גם מכסה את כל הטבלאות וה-FK שביניהן. שני דגלי ה-hash
/// נקבעים ע"י הקורא לפי מקום הצעד בשרשרת — ראו [LibraryUpdateApplier.applyDelta].
PatchApplyResult _applyPatchInIsolate(
  (String, String, DeltaManifest, AppLanguage, int?, SendPort, bool, bool) args,
) {
  AppL10n.use(args.$4);
  const applier = PatchApplier();
  return applier.apply(
    dbPath: args.$1,
    patchPath: args.$2,
    manifest: args.$3,
    verifyFromHash: args.$7,
    checkForeignKeys: false,
    verifyToHash: args.$8,
    verifyTotalBytesHint: args.$5,
    onStage: (stage) => args.$6.send(stage),
    onVerifyProgress: (done, total) => args.$6.send((done, total)),
  );
}

/// מוודא שהמסד שחולץ תקין (`quick_check`) ובגרסה הצפויה — **לפני** שהוא
/// מחליף את המסד החי. top-level מאותה סיבה כמו [_applyPatchInIsolate].
void _verifyExtractedDbInIsolate((String, int?, AppLanguage) args) {
  AppL10n.use(args.$3);
  final db = sqlite3.sqlite3.open(args.$1, mode: sqlite3.OpenMode.readOnly);
  try {
    final check = db.select('PRAGMA quick_check');
    final result = check.isEmpty ? '' : check.first.values.first?.toString();
    if (result != 'ok') {
      throw LibraryApplyException(
        AppL10n.strings.libraryDomain.dbIntegrityCheckFailed('$result'),
      );
    }
  } finally {
    db.close();
  }
  final expectedVersion = args.$2;
  if (expectedVersion != null) {
    final local = const LocalDbVersionReader().read(args.$1);
    if (local.dbVersion != expectedVersion) {
      throw LibraryApplyException(
        AppL10n.strings.libraryDomain
            .versionMismatchAfterWrite(local.dbVersion, expectedVersion),
      );
    }
  }
}

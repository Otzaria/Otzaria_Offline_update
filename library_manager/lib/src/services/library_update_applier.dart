import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'library_updater_l10n.dart';
import 'otzaria_process_guard.dart';
import 'zstd_file_decompressor.dart';

/// שלב עדכון נוכחי — לדיווח ל-UI בלבד, לא נבדק ע"י שום לוגיקה.
enum LibraryApplyStage {
  downloadingPatch,
  decompressingPatch,
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
/// (למשל [stepIndex]/[stepCount] רק במסלול דלתא, [bytesDone]/[bytesTotal] רק
/// בשלבים שסופרים בייטים).
class LibraryApplyProgress {
  final LibraryApplyStage stage;
  final int? stepIndex;
  final int? stepCount;

  /// בייטים שהושלמו מתוך [bytesTotal] בשלב הנוכחי: מה שירד בשלבי ההורדה, ומה
  /// שנכתב בחילוץ דלתא או נקרא בחילוץ מלא. `null` בשלבים ללא ספירת בייטים.
  final int? bytesDone;
  final int? bytesTotal;

  /// תת-השלב הגולמי בתוך ההחלה, כפי ש-`PatchApplier.onStage` מדווח אותו
  /// (`upserts`, `verifyToHash`...). `null` בכל שלב שאינו החלת patch.
  final String? patchStage;

  /// **מה** מאומת כרגע, כשמשהו מאומת: `sourceHash` (ה-sha256 של הנכס הדחוס,
  /// רוכב על החילוץ), `dbIntegrity` (`quick_check` על המסד שחולץ) או
  /// `dbVersion`. קיים כי "מוודא תקינות..." לבדו לא אמר למשתמש דבר, והוא
  /// מופיע כמה פעמים בהחלה אחת.
  final String? verifyStage;

  /// יחס התקדמות 0..1 בתוך אימות ה-hash הארוך; `null` בשאר תת-השלבים.
  final double? verifyProgress;

  /// טקסט מוכן להצגה שהגיע מהשלב עצמו (הקבצים הנלווים מדווחים כך את שם
  /// הפריט שבטיפול). כבר מתורגם — ה-UI מציג אותו כמו שהוא.
  final String? statusText;

  const LibraryApplyProgress({
    required this.stage,
    this.stepIndex,
    this.stepCount,
    this.bytesDone,
    this.bytesTotal,
    this.patchStage,
    this.verifyStage,
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
  String toString() => message;
}

/// Preserves the applier's message contract and the downloader's cancellation tag.
class LibraryApplyCancelledException extends LibraryApplyException
    implements PatchDownloadCancelled {
  const LibraryApplyCancelledException(super.message);
}

typedef ZstdFileStreamer =
    Future<bool> Function(
      String sourcePath,
      String destPath, {
      void Function(int bytesRead, int totalBytes)? onProgress,
      void Function(int bytesWritten)? onOutputProgress,
      void Function(String sha256Hex)? onSourceDigest,
      void Function(String sha256Hex, int bytesWritten)? onOutputDigest,
      bool Function()? isCancelled,
      int? maxOutputBytes,
    });

typedef ExtractedDbVerifier =
    Future<void> Function(
      String newDbPath,
      int? expectedVersion, {
      void Function(String stage)? onStage,
    });

/// מחיל בפועל [LibraryUpdatePlan] (delta או fullDownload) על ה-DB **החי**.
///
/// **כל קריאה ל-`Isolate.run` יושבת במתודה נפרדת** ([_runApplyIsolate],
/// [_isolateVerifyExtractedDb]) ומריצה פונקציית top-level שמקבלת רק ערכים
/// ניתנים-לשליחה. שתי קריסות `object is unsendable` נבעו מכאן, והשנייה עדינה:
/// סוגרים באותו בלוק לקסיקלי חולקים `Context` אחד, ולכן די בכך ש-`onProgress`
/// נקרא באותו בלוק כדי שהשליחה תיכשל. אין להחזיר את הקריאה לגוף [applyDelta].
/// הסיפור המלא ב-`library_manager/README.md`, "היסטוריית התיקון".
class LibraryUpdateApplier {
  LibraryUpdateApplier({
    OtzariaProcessGuard processGuard = const OtzariaProcessGuard(),
    OfflineLibraryDbRecoveryService recovery =
        const OfflineLibraryDbRecoveryService(),
    ExtractedDbVerifier? verifyExtractedDb,
    ZstdFileStreamer? streamFile,
    @Deprecated('Use streamFile for bounded extraction')
    Future<Uint8List?> Function(Uint8List compressed)? decompress,
    int maxFullDbBytes = defaultMaxFullDbBytes,
    int? Function(String path)? freeBytesFor,
    bool Function(String path)? isFatVolume,
  }) : _processGuard = processGuard,
       _freeBytesFor = freeBytesFor ?? DiskSpaceProbe.freeBytesFor,
       _isFatVolume = isFatVolume ?? DiskSpaceProbe.isKnownFat,
       _recovery = recovery,
       _verifyExtractedDb = verifyExtractedDb ?? _defaultExtractedDbVerifier,
       _streamFile = streamFile ?? ZstdFileDecompressor.decompressFileToFile,
       _maxFullDbBytes = maxFullDbBytes {
    if (maxFullDbBytes <= 0) {
      throw ArgumentError.value(maxFullDbBytes, 'maxFullDbBytes');
    }
    _downloader = StreamingPatchDownloader(extractor: _extractRemotePatch);
  }

  final OtzariaProcessGuard _processGuard;
  final OfflineLibraryDbRecoveryService _recovery;
  final ExtractedDbVerifier _verifyExtractedDb;
  final ZstdFileStreamer _streamFile;
  final int? Function(String path) _freeBytesFor;
  final bool Function(String path) _isFatVolume;
  late final StreamingPatchDownloader _downloader;
  final int _maxFullDbBytes;

  /// תקרה כוללת גם ל-frames נוספים, כשאין גודל פלט במטא-דאטה של הנכס.
  static const int defaultMaxFullDbBytes = kDefaultMaxExtractedBytes;

  /// שם קובץ ה-hint לסך-הבתים של אימות ה-hash — ראו [applyDelta].
  static const String _verifyHintFileName = 'verify_total_bytes.txt';

  static Future<void> _defaultExtractedDbVerifier(
    String newDbPath,
    int? expectedVersion, {
    void Function(String stage)? onStage,
  }) => _isolateVerifyExtractedDb(
    newDbPath,
    expectedVersion,
    AppL10n.language,
    onStage: onStage,
  );

  /// הזמן הקצוב לפתיחת חיבור בהורדות של ההחלה — ראו
  /// [PatchDownloader.connectTimeout]. ה-`stallTimeout` נשאר בברירת המחדל
  /// בכוונה: הוא מודד שקט בין צ'אנקים של הורדה של ~1GB, לא זמן תגובה של
  /// בקשת מטא-דאטה.
  set connectTimeout(Duration value) => _downloader.connectTimeout = value;

  /// שמות התהליך שנחשבים "אוצריא פתוחה", לפי הפלטפורמה הנוכחית — ראו
  /// [OtzariaProcessGuard.processNamesFor] (ב-macOS השם בעברית).
  static final List<String> _otzariaProcessNames =
      OtzariaProcessGuard.processNamesFor(Platform.operatingSystem);

  Future<Set<int>> applyDelta({
    required LibraryUpdatePlan plan,
    required String dbPath,
    void Function(LibraryApplyProgress progress)? onProgress,
    void Function(Set<int> booksTouched, int toVersion)? onStepApplied,
    bool Function()? isCancelled,
  }) async {
    for (final edge in plan.deltaSteps) {
      for (final source in edge.patchFileUrls.values) {
        if (!PatchDownloader.isRemoteUrl(source)) {
          _assertSourceOutsideWorkFiles(source, dbPath);
        }
      }
    }
    return withFileOperationLock(
      dbPath,
      () => _applyDeltaLocked(
        plan: plan,
        dbPath: dbPath,
        onProgress: onProgress,
        onStepApplied: onStepApplied,
        isCancelled: isCancelled,
      ),
    );
  }

  Future<Set<int>> _applyDeltaLocked({
    required LibraryUpdatePlan plan,
    required String dbPath,
    void Function(LibraryApplyProgress progress)? onProgress,
    void Function(Set<int> booksTouched, int toVersion)? onStepApplied,
    bool Function()? isCancelled,
  }) async {
    if (plan.kind != LibraryUpdatePlanKind.delta) {
      throw StateError('applyDelta נקרא על תוכנית שאינה delta');
    }
    await _guardOtzariaNotRunning();

    final tmpDir = Directory(_recovery.patchTmpDirFor(dbPath));
    final steps = plan.deltaSteps;

    final hintFile = File(p.join(tmpDir.path, _verifyHintFileName));
    var verifyTotalHint = _readIntQuietly(hintFile);
    var lastVerifyDone = 0;
    var lastPatchStage = 'verifyToHash';
    final booksTouched = <int>{};

    final needsSourceVerification = File(
      _recovery.unverifiedMarkerPathFor(dbPath),
    ).existsSync();

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

      if (i > 0) await _guardOtzariaNotRunning();

      _ensureDeltaStepFits(dbPath, url, patchFile);

      final patchPath = await _fetchPatch(
        patchFile: patchFile,
        url: url,
        destDir: tmpDir,
        onProgress: (downloaded, total) => onProgress?.call(
          LibraryApplyProgress(
            stage: LibraryApplyStage.downloadingPatch,
            stepIndex: i + 1,
            stepCount: steps.length,
            bytesDone: downloaded,
            bytesTotal: total,
          ),
        ),
        onExtractionProgress: (written, total) => onProgress?.call(
          LibraryApplyProgress(
            stage: LibraryApplyStage.decompressingPatch,
            stepIndex: i + 1,
            stepCount: steps.length,
            bytesDone: written,
            bytesTotal: total,
          ),
        ),
        isCancelled: isCancelled,
      );

      try {
        _throwIfCancelled(isCancelled);
        await _recovery.beginApply(
          dbPath: dbPath,
          fromVersion: manifest.fromVersion,
          toVersion: manifest.toVersion,
          timestamp: DateTime.now().toIso8601String(),
        );
        _throwIfCancelled(isCancelled);

        onProgress?.call(
          LibraryApplyProgress(
            stage: LibraryApplyStage.applyingPatch,
            stepIndex: i + 1,
            stepCount: steps.length,
          ),
        );

        _throwIfCancelled(isCancelled);
        if (i < steps.length - 1) {
          _recovery.markUnverified(dbPath, manifest.toVersion);
        }
        final result = await _isolateApplyPatch(
          dbPath: dbPath,
          patchPath: patchPath,
          manifest: manifest,
          language: AppL10n.language,
          verifyFromHash: i == 0 && needsSourceVerification,
          verifyToHash: i == steps.length - 1,
          verifyTotalBytesHint: verifyTotalHint,
          onStage: (patchStage) {
            lastPatchStage = patchStage;
            onProgress?.call(
              LibraryApplyProgress(
                stage: LibraryApplyStage.applyingPatch,
                stepIndex: i + 1,
                stepCount: steps.length,
                patchStage: patchStage,
              ),
            );
          },
          onVerifyProgress: (done, total) {
            lastVerifyDone = done;
            onProgress?.call(
              LibraryApplyProgress(
                stage: LibraryApplyStage.applyingPatch,
                stepIndex: i + 1,
                stepCount: steps.length,
                patchStage: lastPatchStage,
                verifyProgress: total > 0
                    ? (done / total).clamp(0.0, 1.0)
                    : null,
              ),
            );
          },
        );
        booksTouched.addAll(result.booksTouched);
        onStepApplied?.call(result.booksTouched, manifest.toVersion);
        if (lastVerifyDone > 0) {
          verifyTotalHint = lastVerifyDone;
          _writeIntQuietly(hintFile, lastVerifyDone);
        }
        if (result.resultHash != null) {
          _recovery.clearUnverified(dbPath);
        }
        _recovery.finishSuccess(dbPath);
      } catch (_) {
        _recovery.clearStaleArtifacts(dbPath);
        rethrow;
      } finally {
        _deleteQuietly(patchPath);
      }
    }

    onProgress?.call(const LibraryApplyProgress(stage: LibraryApplyStage.done));
    return booksTouched;
  }

  Future<String> _fetchPatch({
    required PatchFileEntry patchFile,
    required String url,
    required Directory destDir,
    void Function(int done, int? total)? onProgress,
    void Function(int written, int total)? onExtractionProgress,
    bool Function()? isCancelled,
  }) async {
    if (!PatchDownloader.isRemoteUrl(url)) {
      final extracted = await _extractLocalPatch(
        patchFile: patchFile,
        sourcePath: url,
        destDir: destDir,
        onProgress: onProgress,
        onExtractionProgress: onExtractionProgress,
        isCancelled: isCancelled,
      );
      if (extracted != null) return extracted;
      throw LibraryApplyException(
        AppL10n.strings.libraryDomain.patchNeedsNativeZstd,
      );
    }
    return _downloader.downloadAndExtract(
      patchFile: patchFile,
      downloadUrl: url,
      destDir: destDir,
      onProgress: onProgress,
      onExtractionProgress: onExtractionProgress,
      isCancelled: isCancelled,
    );
  }

  void _assertSourceOutsideWorkFiles(String source, String dbPath) {
    final staged = '$dbPath.download.zst';
    final owned = <String>[
      dbPath,
      '$dbPath.lock',
      '$dbPath.new',
      '$dbPath.old',
      '$dbPath-wal',
      '$dbPath-shm',
      staged,
      '$staged.lock',
      PatchDownloader.resumeSidecarPath(staged),
      '$staged.segments',
      '$staged.segments.tmp',
      _recovery.markerPathFor(dbPath),
      _recovery.unverifiedMarkerPathFor(dbPath),
    ];
    final parent = Directory(p.dirname(staged));
    if (parent.existsSync()) {
      final prefix = '${p.basename(staged)}.seg-';
      owned.addAll(
        parent
            .listSync(followLinks: false)
            .where((entry) => p.basename(entry.path).startsWith(prefix))
            .map((entry) => entry.path),
      );
    }
    for (final target in owned) {
      _assertDistinctSource(source, target);
    }
    final sourceReal = _resolvedPath(source);
    final cacheReal = _resolvedPath(_recovery.patchTmpDirFor(dbPath));
    if (p.equals(sourceReal, cacheReal) || p.isWithin(cacheReal, sourceReal)) {
      throw ArgumentError('Local source must be outside update staging files');
    }
  }

  static void _assertDistinctSource(String source, String target) {
    final sourceReal = _resolvedPath(source);
    final targetReal = _resolvedPath(target);
    if (p.equals(sourceReal, targetReal) ||
        (File(source).existsSync() &&
            File(target).existsSync() &&
            FileSystemEntity.identicalSync(sourceReal, targetReal))) {
      throw ArgumentError('Local source must be distinct from update output');
    }
  }

  static String _resolvedPath(String path) {
    var existing = p.normalize(p.absolute(path));
    final suffix = <String>[];
    while (FileSystemEntity.typeSync(existing) ==
        FileSystemEntityType.notFound) {
      final parent = p.dirname(existing);
      if (parent == existing) break;
      suffix.insert(0, p.basename(existing));
      existing = parent;
    }
    return p.joinAll([File(existing).resolveSymbolicLinksSync(), ...suffix]);
  }

  Future<String?> _extractLocalPatch({
    required PatchFileEntry patchFile,
    required String sourcePath,
    required Directory destDir,
    void Function(int done, int? total)? onProgress,
    void Function(int written, int total)? onExtractionProgress,
    bool Function()? isCancelled,
  }) async {
    final strings = AppL10n.strings.libraryDomain;
    final source = File(sourcePath);
    if (!source.existsSync()) {
      throw PatchDownloadException(strings.localFileNotFound(sourcePath));
    }
    final size = source.lengthSync();
    if (size != patchFile.size) {
      throw PatchDownloadException(
        strings.checksumMismatchDetailed(
          strings.compressedFileSizeLabel,
          '${patchFile.size}',
          '$size',
        ),
      );
    }
    _throwIfCancelled(isCancelled);
    if (!destDir.existsSync()) destDir.createSync(recursive: true);
    final name = patchFile.file;
    final extractedPath = p.join(destDir.path, extractedPatchFileName(name));
    if (name.isEmpty ||
        name.contains('/') ||
        name.contains('\\') ||
        name.contains(':') ||
        !p.isWithin(p.absolute(destDir.path), p.absolute(extractedPath)) ||
        patchFile.size <= 0 ||
        patchFile.uncompressedSize <= 0) {
      throw PatchDownloadException(
        LibraryUpdaterMessages.current.manifestMissingField('file'),
      );
    }
    for (final target in [
      extractedPath,
      '$extractedPath.extracting',
      '$extractedPath.lock',
    ]) {
      _assertDistinctSource(sourcePath, target);
    }
    return withFileOperationLock(
      extractedPath,
      () => _extractLocalPatchLocked(
        patchFile: patchFile,
        sourcePath: sourcePath,
        extractedPath: extractedPath,
        onProgress: onProgress,
        onExtractionProgress: onExtractionProgress,
        isCancelled: isCancelled,
      ),
    );
  }

  Future<String?> _extractLocalPatchLocked({
    required PatchFileEntry patchFile,
    required String sourcePath,
    required String extractedPath,
    void Function(int done, int? total)? onProgress,
    void Function(int written, int total)? onExtractionProgress,
    bool Function()? isCancelled,
  }) async {
    final strings = AppL10n.strings.libraryDomain;
    final partialPath = '$extractedPath.extracting';
    _assertDistinctSource(sourcePath, partialPath);
    _assertDistinctSource(sourcePath, extractedPath);
    _deleteQuietly(partialPath);
    _throwIfCancelled(isCancelled);
    String? sourceDigest;
    String? outputDigest;
    var outputBytes = 0;
    try {
      final streamed = await _streamFile(
        sourcePath,
        partialPath,
        onProgress: onProgress,
        onOutputProgress: (written) =>
            onExtractionProgress?.call(written, patchFile.uncompressedSize),
        onSourceDigest: (hex) => sourceDigest = hex,
        onOutputDigest: (hex, written) {
          outputDigest = hex;
          outputBytes = written;
        },
        isCancelled: isCancelled,
        maxOutputBytes: patchFile.uncompressedSize,
      );
      if (!streamed) {
        _deleteQuietly(partialPath);
        return null;
      }
      _throwIfCancelled(isCancelled);
      if (sourceDigest?.toLowerCase() != patchFile.sha256.toLowerCase()) {
        _forgetMirrorVerification(sourcePath);
        throw PatchDownloadException(strings.localFileHashMismatch(sourcePath));
      }
      final output = File(partialPath);
      if (outputBytes != patchFile.uncompressedSize ||
          !output.existsSync() ||
          output.lengthSync() != outputBytes) {
        throw PatchDownloadException(
          strings.checksumMismatchDetailed(
            strings.extractedFileSizeLabel,
            '${patchFile.uncompressedSize}',
            '$outputBytes',
          ),
        );
      }
      if (outputDigest?.toLowerCase() !=
          patchFile.uncompressedSha256.toLowerCase()) {
        throw PatchDownloadException(
          strings.checksumMismatch(strings.extractedFileHashLabel),
        );
      }
      _throwIfCancelled(isCancelled);
      await output.rename(extractedPath);
      return extractedPath;
    } on ZstdOutputLimitExceeded catch (e) {
      _deleteQuietly(partialPath);
      _throwIfCancelled(isCancelled);
      _forgetMirrorVerification(sourcePath);
      throw PatchDownloadException(e.message);
    } on ZstdStreamException catch (e) {
      // קובץ שנפגם בכונן נופל כאן, לפני השוואת ה-sha256.
      _deleteQuietly(partialPath);
      _throwIfCancelled(isCancelled);
      if (!_isCorruptSource(e)) rethrow;
      _forgetMirrorVerification(sourcePath);
      throw PatchDownloadException(strings.localFileHashMismatch(sourcePath));
    } catch (_) {
      _deleteQuietly(partialPath);
      _throwIfCancelled(isCancelled);
      rethrow;
    }
  }

  Future<FileExtractionResult> _extractRemotePatch(
    String sourcePath,
    String outputPath, {
    required int maxOutputBytes,
    bool Function()? isCancelled,
    void Function(int bytesWritten)? onProgress,
  }) async {
    String? outputDigest;
    int? bytesWritten;
    final bool streamed;
    try {
      streamed = await _streamFile(
        sourcePath,
        outputPath,
        onOutputProgress: onProgress,
        onOutputDigest: (digest, written) {
          outputDigest = digest;
          bytesWritten = written;
        },
        maxOutputBytes: maxOutputBytes,
        isCancelled: isCancelled,
      );
    } on ZstdStreamException catch (error) {
      _throwIfCancelled(isCancelled);
      if (error is ZstdCancelledException) {
        throw const PatchDownloadCancelled();
      }
      if (error is ZstdOutputLimitExceeded || _isCorruptSource(error)) {
        throw PatchDownloadException(error.message);
      }
      rethrow;
    } catch (_) {
      _throwIfCancelled(isCancelled);
      rethrow;
    }
    _throwIfCancelled(isCancelled);
    if (!streamed) {
      throw LibraryApplyException(
        AppL10n.strings.libraryDomain.patchNeedsNativeZstd,
      );
    }
    if (outputDigest == null || bytesWritten == null) {
      throw StateError(
        'Streaming extractor did not report output verification',
      );
    }
    return FileExtractionResult(
      bytesWritten: bytesWritten!,
      sha256: outputDigest!,
    );
  }

  /// מוריד ומתקין DB מלא — עבור התקנה טרייה (אין DB קיים) או כש-planner
  /// קבע שאין מסלול דלתא בטוח.
  ///
  /// ההורדה והחילוץ שניהם **בזרימה**: הקובץ הדחוס יורד ישר לדיסק
  /// ([PatchDownloader.downloadToFile]), ומשם מחולץ קובץ-לקובץ דרך
  /// [ZstdFileDecompressor] — שיא הזיכרון הוא חוצצים בודדים, לא ~1.1GB של DB.
  Future<void> applyFullDownload({
    required LibraryUpdatePlan plan,
    required String dbPath,
    void Function(LibraryApplyProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (plan.kind != LibraryUpdatePlanKind.fullDownload) {
      throw StateError('applyFullDownload נקרא על תוכנית שאינה fullDownload');
    }
    final source = plan.fullDbAsset?.downloadUrl;
    if (source != null && !PatchDownloader.isRemoteUrl(source)) {
      _assertSourceOutsideWorkFiles(source, dbPath);
    }
    _throwIfCancelled(isCancelled);
    final dir = Directory(p.dirname(dbPath));
    try {
      if (!dir.existsSync()) dir.createSync(recursive: true);
    } on FileSystemException catch (error) {
      throw LibraryApplyException(
        AppL10n.strings.libraryDomain.installDirNotWritable(
          dir.path,
          error.osError?.message ?? error.message,
        ),
      );
    }
    return withFileOperationLock(
      dbPath,
      () => _applyFullDownloadLocked(
        plan: plan,
        dbPath: dbPath,
        onProgress: onProgress,
        isCancelled: isCancelled,
      ),
    );
  }

  Future<void> _applyFullDownloadLocked({
    required LibraryUpdatePlan plan,
    required String dbPath,
    void Function(LibraryApplyProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (plan.kind != LibraryUpdatePlanKind.fullDownload) {
      throw StateError('applyFullDownload נקרא על תוכנית שאינה fullDownload');
    }
    final asset = plan.fullDbAsset;
    if (asset == null) {
      throw LibraryApplyException(
        AppL10n.strings.libraryDomain.fullDbAssetMissingFromPlan,
      );
    }
    await _guardOtzariaNotRunning();

    final dir = Directory(p.dirname(dbPath));
    try {
      if (!dir.existsSync()) dir.createSync(recursive: true);
    } on FileSystemException catch (e) {
      // issue #23: חשבון רגיל שאינו יכול ליצור תיקייה תחת C:\Users. השורש
      // תוקן (נתיב פר-מחשב), אבל ההודעה הגולמית לא הפנתה לבורר הידני.
      throw LibraryApplyException(
        AppL10n.strings.libraryDomain.installDirNotWritable(
          dir.path,
          e.osError?.message ?? e.message,
        ),
      );
    }

    final stagedPath = '$dbPath.download.zst';
    final expectedSha256 = _sha256FromDigest(asset.digest);

    // **מראה מקומית = מחלצים ממנה ישירות.** הנכס כבר קובץ על הדיסק (הכונן
    // הנייד), והעתקתו לצד המסד הייתה מוסיפה כתיבה וקריאה של ~1.5GB ודורשת
    // ישן + דחוס + חדש על אותו נפח. ה-sha256 נשמר: הוא מחושב על אותם בתים
    // שנקראים לחילוץ. רק מקור רשת עדיין יורד לקובץ ביניים.
    final isLocalSource = !PatchDownloader.isRemoteUrl(asset.downloadUrl);
    // הנתיב ש**אנחנו** יצרנו, ולכן מותר למחוק. המראה עצמה לעולם לא.
    String? staged;
    void deleteStaged() {
      if (staged case final path?) {
        _deleteQuietly(path);
        _deleteQuietly(PatchDownloader.resumeSidecarPath(path));
      }
    }

    final String compressedPath;
    if (isLocalSource) {
      compressedPath = asset.downloadUrl;
      _throwIfCancelled(isCancelled);
      final source = File(compressedPath);
      if (!source.existsSync()) {
        throw LibraryApplyException(
          AppL10n.strings.libraryDomain.localSourceNotFound(compressedPath),
        );
      }
      final size = source.lengthSync();
      if (size != asset.size) {
        throw LibraryApplyException(
          AppL10n.strings.libraryDomain.localFileSizeMismatch(
            asset.size,
            size,
            compressedPath,
          ),
        );
      }
      // שארית מגרסה שעוד העתיקה את הנכס לכאן — אין לה שימוש יותר.
      _deleteQuietly(stagedPath);
      _deleteQuietly(PatchDownloader.resumeSidecarPath(stagedPath));
      PatchDownloader.deleteSegmentFiles(stagedPath);
    } else {
      compressedPath = stagedPath;
      // הדחוס וה-`.new` יושבים שניהם לצד המסד הקיים, ולכן שיא התפוסה על אותו
      // נפח הוא ישן + דחוס + חדש. בלי הבדיקה הזו הכשל היה `errno = 112`
      // באנגלית באמצע חילוץ של דקות, על נתיב `.new` שהמשתמש אינו מכיר.
      _ensureSpaceFor(dir.path, asset.size + _segmentAssemblyOverhead(asset));
      await _downloader.downloadToFile(
        url: asset.downloadUrl,
        destPath: stagedPath,
        expectedSize: asset.size,
        expectedSha256: expectedSha256,
        resumeToken: asset.id?.toString(),
        onProgress: (downloaded, total) => onProgress?.call(
          LibraryApplyProgress(
            stage: LibraryApplyStage.downloadingFullDb,
            bytesDone: downloaded,
            bytesTotal: total,
          ),
        ),
        isCancelled: isCancelled,
      );
      staged = stagedPath;
    }

    _throwIfCancelled(isCancelled);
    // המקור המקומי מאומת תוך כדי החילוץ; מקור רשת כבר אומת בהורדה.
    final verifiesWhileExtracting = isLocalSource && expectedSha256 != null;
    onProgress?.call(
      LibraryApplyProgress(
        stage: LibraryApplyStage.decompressingFullDb,
        verifyStage: verifiesWhileExtracting ? 'sourceHash' : null,
      ),
    );

    // מחלצים לקובץ צדדי ורק בסוף מחליפים את ה-DB: כך ה-DB הקיים נשאר שלם
    // עד שהחדש מוכן במלואו, בדיוק כמו במסלול ה-staging של התקנת האפליקציה.
    final newFilePath = '$dbPath.new';
    _deleteQuietly(newFilePath);
    final extractedSize = ZstdFileDecompressor.contentSizeOf(compressedPath);
    if (extractedSize != null) {
      _ensureFileFitsVolume(dir.path, extractedSize);
      _ensureSpaceFor(dir.path, extractedSize);
    }
    String? sourceDigest;
    try {
      final streamed = await _streamFile(
        compressedPath,
        newFilePath,
        onProgress: (read, total) => onProgress?.call(
          LibraryApplyProgress(
            stage: LibraryApplyStage.decompressingFullDb,
            verifyStage: verifiesWhileExtracting ? 'sourceHash' : null,
            bytesDone: read,
            bytesTotal: total,
          ),
        ),
        onSourceDigest: verifiesWhileExtracting
            ? (hex) => sourceDigest = hex
            : null,
        isCancelled: isCancelled,
        maxOutputBytes: _maxFullDbBytes,
      );
      _throwIfCancelled(isCancelled);
      if (!streamed) {
        throw LibraryApplyException(
          AppL10n.strings.libraryDomain.fullDbNeedsNativeZstd,
        );
      }
      if (verifiesWhileExtracting &&
          sourceDigest?.toLowerCase() != expectedSha256.toLowerCase()) {
        _forgetMirrorVerification(compressedPath);
        throw PatchDownloadException(
          AppL10n.strings.libraryDomain.localFileHashMismatch(compressedPath),
        );
      }
    } catch (e) {
      _deleteQuietly(newFilePath);
      _throwIfCancelled(isCancelled);
      if (_isCorruptSource(e)) deleteStaged();
      if (_isFileTooLargeError(e)) {
        throw LibraryApplyException(
          AppL10n.strings.libraryDomain.fileTooLargeForVolume(dir.path),
        );
      }
      // קובץ שנפגם בכונן נופל בחילוץ, לפני השוואת ה-sha256.
      if (isLocalSource && _isCorruptSource(e)) {
        _forgetMirrorVerification(compressedPath);
        throw PatchDownloadException(
          AppL10n.strings.libraryDomain.localFileHashMismatch(compressedPath),
        );
      }
      rethrow;
    }
    // הגודל שנכתב בפועל מושווה לזה שכותרת ה-frame הצהירה עליו. libzstd עצמו
    // כבר תופס קלט פגום או קטוע, ולכן זו שכבת הגנה על הקובץ **כפי שהוא על
    // הדיסק**: אנטי-וירוס שקיצר אותו, או מערכת קבצים נשלפת שדיווחה הצלחה.
    // רק `<` נחשב כשל — ארכיון מרובה-frames מפיק יותר מהצהרת ה-frame הראשון.
    final writtenSize = File(newFilePath).existsSync()
        ? File(newFilePath).lengthSync()
        : 0;
    if (writtenSize == 0 ||
        writtenSize > _maxFullDbBytes ||
        (extractedSize != null && writtenSize < extractedSize)) {
      _deleteQuietly(newFilePath);
      throw LibraryApplyException(
        AppL10n.strings.libraryDomain.fullDbExtractionFailed,
      );
    }

    // אימות **לפני** ההחלפה, כמו באוצריא: מסד פגום או בגרסה לא נכונה נעצר
    // כאן, בעוד ה-DB החי עדיין שלם — במקום להחליף ואז לשחזר מגיבוי.
    try {
      onProgress?.call(
        const LibraryApplyProgress(stage: LibraryApplyStage.verifying),
      );
      _throwIfCancelled(isCancelled);
      await _verifyExtractedDb(
        newFilePath,
        plan.targetVersion,
        // `quick_check` על מסד מלא לוקח דקות; המשתמש צריך לדעת מה נבדק.
        onStage: (stage) => onProgress?.call(
          LibraryApplyProgress(
            stage: LibraryApplyStage.verifying,
            verifyStage: stage,
          ),
        ),
      );
    } catch (_) {
      _deleteQuietly(newFilePath);
      rethrow;
    }
    if (isCancelled?.call() ?? false) {
      _deleteQuietly(newFilePath);
    }
    _throwIfCancelled(isCancelled);

    final dbAlreadyExists = File(dbPath).existsSync();
    final markerPreexisted = File(_recovery.markerPathFor(dbPath)).existsSync();
    if (dbAlreadyExists) {
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
        rethrow;
      }
    }

    // ההורדה והחילוץ ארכו דקות רבות; אוצריא יכלה להיפתח בינתיים. הבדיקה
    // החוזרת עולה כלום, ובלעדיה ב-macOS היינו מוחקים את המסד מתחת לאוצריא
    // רצה (`unlink` על קובץ פתוח מצליח שם).
    try {
      _throwIfCancelled(isCancelled);
      await _guardOtzariaNotRunning();
      _throwIfCancelled(isCancelled);
      onProgress?.call(
        const LibraryApplyProgress(stage: LibraryApplyStage.writingFullDb),
      );
      _throwIfCancelled(isCancelled);
    } catch (_) {
      if (dbAlreadyExists && !markerPreexisted) {
        _recovery.clearStaleArtifacts(dbPath);
      }
      _deleteQuietly(newFilePath);
      rethrow;
    }
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
      // גלגול אחור: המסד הישן חוזר לשמו. `<db>.new` נמחק בתחילת הריצה הבאה.
      var rolledBack = false;
      if (retired) {
        // הקובץ שתופס עכשיו את `seforim.db` אינו המסד החדש — ה-rename השני
        // נכשל. אם הוא באורך 0 הוא גם אינו מסד: כך נראה נתיב ש-sqlite פתחה
        // ולא כתבה, וזה בדיוק מה שנוצר כשאוצריא נפתחה בין שני ה-rename.
        // בלי הפינוי הזה `.old` היה נשאר בצד והמשתמש היה נשאר עם מסד ריק.
        if (_isEmptyFile(dbPath)) _deleteQuietly(dbPath);
        if (!File(dbPath).existsSync()) {
          try {
            File(retiredPath).renameSync(dbPath);
            rolledBack = true;
          } catch (_) {
            // גם הגלגול נכשל — משאירים את שניהם, הם הקבצים התקינים היחידים,
            // ואת הסימון שמעיד שכאן נקטע עדכון.
            rethrow;
          }
        }
        // ⚠️ מוחקים את `<db>.old` **רק** אחרי גלגול שהצליח. קודם לכן המחיקה
        // רצה גם בענף שבו הגלגול דולג — והוא ניתן להגעה: rename ראשון מצליח,
        // ואז אוצריא נפתחת, פתיחת `seforim.db` חסר ב-sqlite **יוצרת** קובץ ריק
        // ונועלת אותו (וזה בדיוק מה שמכשיל את ה-rename השני), התנאי
        // `!existsSync()` נופל, והמחיקה השמידה את הספרייה של המשתמש. שני
        // ה-rename קיימים בדיוק כדי שזה לא יקרה.
        if (rolledBack) _deleteQuietly(retiredPath);
      }
      if (dbAlreadyExists && !markerPreexisted && (rolledBack || !retired)) {
        _recovery.clearStaleArtifacts(dbPath);
      }
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
    // ה-sidecar הוא באחריות הצרכן (ראו PatchDownloader.downloadToFile);
    // בלי זה נשאר `seforim.db.download.zst.resume` בתיקיית הספרים לנצח.
    deleteStaged();
    onProgress?.call(const LibraryApplyProgress(stage: LibraryApplyStage.done));
  }

  /// סטטית ונפרדת — אין `this` בכלל, ואין `Context` משותף עם סוגרי
  /// ה-`onProgress` של הקורא (ראו תיעוד [LibraryUpdateApplier]).
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
    AppLanguage language, {
    void Function(String stage)? onStage,
  }) async {
    final port = ReceivePort();
    final sub = port.listen((msg) {
      if (msg is String) onStage?.call(msg);
    });
    try {
      await _runVerifyIsolate(
        newDbPath,
        expectedVersion,
        language,
        port.sendPort,
      );
    } finally {
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      port.close();
    }
  }

  /// מתודה נפרדת — כאן נוצר סוגר ה-`Isolate.run` (ראו תיעוד המחלקה).
  static Future<void> _runVerifyIsolate(
    String newDbPath,
    int? expectedVersion,
    AppLanguage language,
    SendPort sendPort,
  ) {
    return Isolate.run(
      () => _verifyExtractedDbInIsolate((
        newDbPath,
        expectedVersion,
        language,
        sendPort,
      )),
    );
  }

  Future<void> _guardOtzariaNotRunning() async {
    if (await _processGuard.isAnyRunning(_otzariaProcessNames)) {
      throw const OtzariaIsRunningException();
    }
  }

  void _throwIfCancelled(bool Function()? isCancelled) {
    if (isCancelled?.call() ?? false) {
      throw LibraryApplyCancelledException(
        AppL10n.strings.libraryDomain.updateCancelled,
      );
    }
  }

  /// זורק הודעה שאומרת כמה לפנות ואיפה, כשידוע בוודאות שאין מקום ל-[needed]
  /// תחת [dir]. מדידה שנכשלה אינה חוסמת — ראו [DiskSpaceProbe].
  void _ensureSpaceFor(String dir, int needed) {
    final free = _freeBytesFor(dir);
    if (free == null || !DiskSpaceProbe.lacksSpace(free, needed)) return;
    throw LibraryApplyException(
      AppL10n.strings.libraryDomain.notEnoughDiskSpace(
        dir,
        DiskSpaceProbe.formatBytes(needed),
        DiskSpaceProbe.formatBytes(free),
      ),
    );
  }

  /// הורדה בטווחים מחזיקה בזמן הצירוף עותק נוסף של הטווח הגדול ביותר.
  int _segmentAssemblyOverhead(ReleaseAsset asset) {
    final connections = _downloader.maxConnections;
    if (connections < 2 || asset.size < _downloader.segmentThresholdBytes) {
      return 0;
    }
    return (asset.size + connections - 1) ~/ connections;
  }

  void _ensureDeltaStepFits(String dbPath, String url, PatchFileEntry patch) {
    final dir = p.dirname(dbPath);
    final download = PatchDownloader.isRemoteUrl(url) ? patch.size : 0;
    final dbSize = File(dbPath).existsSync() ? File(dbPath).lengthSync() : 0;
    // SQLite may journal every existing page even when the patch is small.
    _ensureSpaceFor(dir, download + dbSize + 2 * patch.uncompressedSize);
    _ensureFileFitsVolume(dir, dbSize + patch.uncompressedSize);
  }

  void _ensureFileFitsVolume(String dir, int fileSize) {
    if (fileSize <= DiskSpaceProbe.fatMaxFileBytes) return;
    if (!_isFatVolume(dir)) return;
    throw LibraryApplyException(
      AppL10n.strings.libraryDomain.fileTooLargeForVolume(dir),
    );
  }

  static bool _isFileTooLargeError(Object error) =>
      error is FileSystemException &&
      error.osError?.errorCode == (Platform.isWindows ? 223 : 27);

  String? _sha256FromDigest(String? digest) {
    const prefix = 'sha256:';
    if (digest == null || !digest.startsWith(prefix)) return null;
    return digest.substring(prefix.length);
  }

  /// נכס במראה שנכשל ב-sha256: בלי סימון האימות שלידו, ההורדה הבאה במחשב
  /// המקוון מאמתת אותו מחדש ומחליפה אותו — אחרת גודל ו-mtime זהים מדלגים עליו.
  void _forgetMirrorVerification(String mirrorPath) =>
      _deleteQuietly(PatchDownloader.resumeSidecarPath(mirrorPath));

  /// כשל zstd שמקורו בתוכן הקובץ — לא תקרת פלט ולא כשל משאבים.
  static bool _isCorruptSource(Object e) =>
      e is ZstdStreamException &&
      e is! ZstdOutputLimitExceeded &&
      e is! ZstdResourceException &&
      e is! ZstdCancelledException;

  void _deleteQuietly(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  /// קובץ שקיים ואורכו 0 — הסימן היחיד שאפשר לסמוך עליו לזיהוי נתיב שנפתח
  /// ולא נכתב. קובץ לא-קיים אינו "ריק": שם אין מה לפנות.
  bool _isEmptyFile(String path) {
    try {
      final file = File(path);
      return file.existsSync() && file.lengthSync() == 0;
    } catch (_) {
      return false;
    }
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
  useLibraryUpdaterL10n();
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
void _verifyExtractedDbInIsolate((String, int?, AppLanguage, SendPort) args) {
  AppL10n.use(args.$3);
  useLibraryUpdaterL10n();
  final stagePort = args.$4;
  // `quick_check` סורק את הקובץ כולו ולוקח דקות על מסד מלא — האמירה מה
  // נבדק היא ההבדל בין "מוודא תקינות..." שנתקע לבין שלב מובן.
  stagePort.send('dbIntegrity');
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
    stagePort.send('dbVersion');
    final local = const LocalDbVersionReader().read(args.$1);
    if (local.dbVersion != expectedVersion) {
      throw LibraryApplyException(
        AppL10n.strings.libraryDomain.versionMismatchAfterWrite(
          local.dbVersion,
          expectedVersion,
        ),
      );
    }
  }
}

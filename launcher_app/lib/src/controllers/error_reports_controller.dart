import 'dart:io';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:library_manager/library_manager.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

import '../services/app_logger.dart';
import 'dispose_guard.dart';

/// תוצאת איסוף: כמה דיווחים הועברו לתיבה, ושגיאה אם הייתה.
typedef ReportCollectOutcome = ({int collected, String? error});

class ErrorReportsController extends ChangeNotifier
    with DisposeGuard, SilentAfterDispose {
  ErrorReportsController({
    required this.outbox,
    required Future<OtzariaReportQueue?> Function() resolveQueue,
    ErrorReportUploader? uploader,
  })  : _resolveQueue = resolveQueue,
        _uploader = uploader ?? ErrorReportUploader();

  factory ErrorReportsController.forDrive({
    required String stateDir,
    String? dataDir,
    String? stateFilesDir,
    required Future<String?> Function() launchPath,
  }) {
    return ErrorReportsController(
      outbox: DirectoryReportOutbox(
        DirectoryReportOutbox.dirIn(stateDir),
        onInvalid: (path, e) =>
            AppLogger.maybeInstance?.warn('דיווח פגום דולג: $path ($e)'),
      ),
      resolveQueue: () async {
        final launch = await launchPath();
        if (launch == null) return null;
        return resolveOtzariaReportQueue(
          launchPath: launch,
          locator: LibraryDbLocator.forLaunch(
            stateDir: stateFilesDir ?? stateDir,
            launchPath: launch,
            dataDir: dataDir ?? stateDir,
          ),
        );
      },
    );
  }

  /// `user_state.db` של ההתקנה הזו, או `null` כשאין מה לגעת בו.
  /// קופסת דיווחים שעוד לא הועברה פירושה שהתור עדיין ב-Hive.
  static Future<OtzariaReportQueue?> resolveOtzariaReportQueue({
    required String launchPath,
    required LibraryDbLocator locator,
  }) async {
    final dataRoot = await locator.otzariaSettingsRoot(launchPath);
    if (dataRoot == null) return null;
    for (final box in [
      'error_reports_queue',
      'app_reports_queue',
      'plugin_reports_queue',
    ]) {
      if (await File(p.join(dataRoot, '$box.hive')).exists()) return null;
    }
    final settings = await locator.settingsReader.read(dataRoot);
    final db = await locateUserStateDb(
      dataRoot: dataRoot,
      databasesPathSetting: settings?.databasesPath,
      libraryPathSetting: settings?.libraryPath,
    );
    return db == null ? null : UserStateReportQueue(db);
  }

  final ReportOutbox outbox;
  final Future<OtzariaReportQueue?> Function() _resolveQueue;
  final ErrorReportUploader _uploader;

  OtzariaReportQueue? _queue;

  /// ההצעה לאסוף — פעם אחת בהרצה, גם כשנענתה "לא עכשיו".
  bool _offered = false;

  int outboxCount = 0;
  bool isCollecting = false;
  bool isUploading = false;
  ReportUploadProgress? progress;
  ReportUploadCancellation? _cancellation;

  int get batchSize => _uploader.batchSize;
  int estimateMinutes(int count) => _uploader.estimateMinutes(count);

  @override
  void dispose() {
    stop();
    _uploader.close();
    super.dispose();
  }

  Future<void> refreshOutbox() async {
    try {
      outboxCount = (await outbox.list()).length;
    } catch (e) {
      AppLogger.maybeInstance?.warn('קריאת תיבת הדיווחים נכשלה: $e');
      outboxCount = 0;
    }
    notifyListeners();
  }

  /// כמה דיווחים ניתנים לשליחה ממתינים באוצריא, אם עוד לא הצענו בהרצה הזו.
  /// 0 = אין מה להציע: אין התקנה, אין מסד, סכמה לא מוכרת או כשל בקריאה.
  Future<int> pendingToOffer() async {
    if (_offered) return 0;
    _offered = true;
    try {
      final queue = _queue = await _resolveQueue();
      if (queue == null) return 0;
      return await queue.countSendable();
    } catch (e) {
      // מסד נעול או פגום — לא סיבה להטריד את המשתמש בעלייה.
      AppLogger.maybeInstance?.warn('קריאת תור הדיווחים של אוצריא נכשלה: $e');
      return 0;
    }
  }

  /// מעביר את הדיווחים לתיבה ומסמן אותם באוצריא כנשלחו. נספרות רק שורות
  /// שהועברו בפועל.
  Future<ReportCollectOutcome> collect() async {
    if (isCollecting) return (collected: 0, error: null);
    isCollecting = true;
    notifyListeners();
    try {
      final queue = _queue ?? await _resolveQueue();
      if (queue == null) return (collected: 0, error: null);
      final result = await queue.collectTo(outbox);
      final error = result.error;
      if (error == null) return result;
      // הפרטים ליומן; במסך — הודעה מתורגמת, בלי טקסט של חריג.
      AppLogger.maybeInstance?.warn('איסוף חלקי: $error');
      return (
        collected: result.collected,
        error: AppL10n.strings.errorReportsDomain.someNotCollected,
      );
    } catch (e) {
      AppLogger.maybeInstance?.error('איסוף הדיווחים נכשל', e);
      return (
        collected: 0,
        error: AppL10n.strings.errorReportsDomain.queueUnreadable,
      );
    } finally {
      isCollecting = false;
      await refreshOutbox();
    }
  }

  Future<ReportUploadResult?> upload() async {
    if (isUploading || isDisposed) return null;
    final cancellation = _cancellation = ReportUploadCancellation();
    isUploading = true;
    progress = null;
    notifyListeners();
    try {
      final result = await _uploader.upload(
        outbox,
        cancellation: cancellation,
        onProgress: (p) {
          progress = p;
          notifyListeners();
        },
      );
      for (final r in result.rejections) {
        AppLogger.maybeInstance?.warn(
          'דיווח ${r.reportId} (${r.bookTitle}) נדחה: ${r.reason}',
        );
      }
      return result;
    } catch (e) {
      AppLogger.maybeInstance?.error('העלאת הדיווחים נכשלה', e);
      return ReportUploadResult(
        total: 0,
        sent: 0,
        rejected: 0,
        remaining: 0,
        error: AppL10n.strings.errorReportsDomain.outboxUnreadable('$e'),
      );
    } finally {
      isUploading = false;
      progress = null;
      _cancellation = null;
      if (!isDisposed) await refreshOutbox();
    }
  }

  /// עוצר מיד, גם באמצע ההמתנה בין מנות.
  void stop() => _cancellation?.cancel();
}

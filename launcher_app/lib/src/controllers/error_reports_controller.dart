import 'dart:async';
import 'dart:io';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:library_manager/library_manager.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart' show OtzariaCapabilities;

import '../services/app_logger.dart';
import 'dispose_guard.dart';

typedef ReportCollectOutcome = ({int collected, String? error});

class ErrorReportsController extends ChangeNotifier
    with DisposeGuard, SilentAfterDispose {
  ErrorReportsController({
    required this.outbox,
    required Future<OtzariaReportQueue?> Function() resolveQueue,
    Future<List<String>> Function()? findUnmigratedLegacy,
    ErrorReportUploader? uploader,
  })  : _resolveQueue = resolveQueue,
        _findUnmigratedLegacy = findUnmigratedLegacy,
        _uploader = uploader ?? ErrorReportUploader();

  factory ErrorReportsController.forDrive({
    required String stateDir,
    String? dataDir,
    String? stateFilesDir,
    required Future<String?> Function() launchPath,
  }) {
    LibraryDbLocator locatorFor(String launch) => LibraryDbLocator.forLaunch(
          stateDir: stateFilesDir ?? stateDir,
          launchPath: launch,
          dataDir: dataDir ?? stateDir,
        );
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
          locator: locatorFor(launch),
        );
      },
      findUnmigratedLegacy: () async {
        final launch = await launchPath();
        if (launch == null) return const [];
        return unmigratedLegacyReports(
          launchPath: launch,
          locator: locatorFor(launch),
        );
      },
    );
  }

  /// `user_state.db` של ההתקנה הזו, או `null` כשאין מה לגעת בו.
  static Future<OtzariaReportQueue?> resolveOtzariaReportQueue({
    required String launchPath,
    required LibraryDbLocator locator,
  }) async {
    final dataRoot = await locator.otzariaSettingsRoot(launchPath);
    if (dataRoot == null) return null;
    final db = await _userStateDb(dataRoot, locator);
    if (db == null) return null;
    final capabilities = await OtzariaCapabilities.read(dataRoot);
    return UserStateReportQueue(
      db,
      reportsQueueFormat: capabilities?.reportsQueueFormat,
    );
  }

  static Future<List<String>> unmigratedLegacyReports({
    required String launchPath,
    required LibraryDbLocator locator,
  }) async {
    final dataRoot = await locator.otzariaSettingsRoot(launchPath);
    if (dataRoot == null) return const [];
    return findUnmigratedReportBoxes(
      dataRoot: dataRoot,
      userStateDb: await _userStateDb(dataRoot, locator),
    );
  }

  static Future<String?> _userStateDb(
    String dataRoot,
    LibraryDbLocator locator,
  ) async {
    final settings = await locator.settingsReader.read(dataRoot);
    return locateUserStateDb(
      dataRoot: dataRoot,
      databasesPathSetting: settings?.databasesPath,
      libraryPathSetting: settings?.libraryPath,
    );
  }

  final ReportOutbox outbox;
  final Future<OtzariaReportQueue?> Function() _resolveQueue;
  final Future<List<String>> Function()? _findUnmigratedLegacy;

  List<String> unmigratedLegacy = const [];
  final ErrorReportUploader _uploader;

  int outboxCount = 0;
  bool isCollecting = false;
  bool isUploading = false;
  ReportUploadProgress? progress;
  ReportUploadCancellation? _cancellation;
  Timer? _automaticUpload;

  void startAutomaticPluginUpload() {
    _automaticUpload?.cancel();
    unawaited(uploadAutomaticPluginReports());
    _automaticUpload = Timer.periodic(const Duration(minutes: 5), (_) {
      unawaited(uploadAutomaticPluginReports());
    });
  }

  Future<String> queuePluginReport({
    required String pluginUid,
    required String pluginName,
    required String pluginVersion,
    required String reportType,
    required String details,
    String? reporterEmail,
  }) async {
    final record = PluginReportRecord(
      reportId: AppReport.generateReportId(),
      pluginUid: pluginUid,
      pluginName: pluginName,
      pluginVersion: pluginVersion,
      reportType: reportType,
      details: details.trim(),
      reporterEmail: reporterEmail?.trim(),
      platform: Platform.operatingSystem,
      createdAt: DateTime.now(),
    );
    await outbox.write(
      'plugin-${record.reportId}',
      OutboxReport.encodeFile(OutboxReport.fileJson(
        reportId: 'plugin-${record.reportId}',
        bookTitle: pluginName,
        createdAt: record.createdAt.toUtc().toIso8601String(),
        endpoint: OutboxReport.pluginReportingEndpoint,
        body: record.toApiPayload(),
        autoUpload: true,
      )),
    );
    await refreshOutbox();
    return 'plugin-${record.reportId}';
  }

  int get batchSize => _uploader.batchSize;
  int estimateMinutes(int count) => _uploader.estimateMinutes(count);

  @override
  void dispose() {
    _automaticUpload?.cancel();
    stop();
    _uploader.close();
    super.dispose();
  }

  Future<void> refreshOutbox() async {
    try {
      outboxCount = await outbox.count();
    } catch (e) {
      AppLogger.maybeInstance?.warn('קריאת תיבת הדיווחים נכשלה: $e');
      outboxCount = 0;
    }
    notifyListeners();
  }

  Future<int> pendingToOffer() async {
    if (isUploading || isCollecting) return 0;
    try {
      unmigratedLegacy = await _findUnmigratedLegacy?.call() ?? const [];
    } catch (e) {
      AppLogger.maybeInstance?.warn('בדיקת תורי Hive ישנים נכשלה: $e');
    }
    if (unmigratedLegacy.isNotEmpty) {
      AppLogger.maybeInstance?.info(
        'תורי דיווחים ישנים שלא הועברו: ${unmigratedLegacy.join(', ')}',
      );
    }
    try {
      final queue = await _resolveQueue();
      if (queue == null) return 0;
      final count = await queue.countSendable();
      return count;
    } catch (e) {
      AppLogger.maybeInstance?.warn('קריאת תור הדיווחים של אוצריא נכשלה: $e');
      return 0;
    }
  }

  Future<ReportCollectOutcome> collect() async {
    if (isCollecting || isUploading) return (collected: 0, error: null);
    isCollecting = true;
    notifyListeners();
    try {
      final queue = await _resolveQueue();
      if (queue == null) return (collected: 0, error: null);
      final result = await queue.collectTo(outbox);
      final error = result.error;
      if (error == null) return result;
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

  Future<ReportUploadResult?> upload() => _upload();

  Future<ReportUploadResult?> uploadAutomaticPluginReports(
      {String? reportId}) async {
    if (isUploading || isCollecting || isDisposed) return null;
    try {
      final pending = await outbox.list();
      if (!pending.any((report) =>
          _isAutomaticPlugin(report) &&
          (reportId == null || report.reportId == reportId))) {
        return null;
      }
    } catch (e) {
      AppLogger.maybeInstance?.warn('קריאת תיבת דיווחי התוספים נכשלה: $e');
      return null;
    }
    return _upload(automaticOnly: true, reportId: reportId);
  }

  static bool _isAutomaticPlugin(OutboxReport report) =>
      report.autoUpload &&
      report.endpoint.toString() == OutboxReport.pluginReportingEndpoint;

  Future<ReportUploadResult?> _upload(
      {bool automaticOnly = false, String? reportId}) async {
    if (isUploading || isCollecting || isDisposed) return null;
    final cancellation = _cancellation = ReportUploadCancellation();
    isUploading = true;
    progress = null;
    notifyListeners();
    try {
      final result = await _uploader.upload(
        outbox,
        cancellation: cancellation,
        where: automaticOnly
            ? (report) =>
                _isAutomaticPlugin(report) &&
                (reportId == null || report.reportId == reportId)
            : null,
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

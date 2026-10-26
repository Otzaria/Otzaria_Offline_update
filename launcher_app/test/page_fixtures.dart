import 'dart:typed_data';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:launcher_app/src/controllers/app_reports_controller.dart';
import 'package:launcher_app/src/controllers/error_reports_controller.dart';
import 'package:launcher_app/src/controllers/launcher_update_controller.dart';
import 'package:launcher_app/src/controllers/library_module_controller.dart';
import 'package:launcher_app/src/controllers/otzaria_module_controller.dart';
import 'package:launcher_app/src/screens/launcher/launcher_update_page.dart';
import 'package:launcher_app/src/screens/library_screen.dart';
import 'package:launcher_app/src/screens/otzaria_advanced_page.dart';
import 'package:launcher_app/src/screens/reports/reports_page.dart';
import 'package:launcher_app/src/self_update/launcher_release.dart';
import 'package:launcher_app/src/settings/app_settings.dart';
import 'package:launcher_app/src/settings/settings_controller.dart';
import 'package:library_manager/library_manager.dart';

/// מצבי דפי התוכנה, הספרייה, הדיווחים ועדכון הכלי — לצילומי הסקירה. כל
/// מצב בונה קונטרולרים אמיתיים ומציב בהם שדות, בלי דיסק ובלי רשת.
typedef PageScenario = Widget Function(String dataDir, SettingsController s);

/// נתיבים עקביים לכל המצבים — כמו במחשב אמיתי, ולא "לא זוהתה התקנה".
const _launchPath =
    r'C:\Users\David\AppData\Local\Programs\otzaria\otzaria.exe';
const _dbPath = r'C:\Users\David\AppData\Roaming\otzaria\books\seforim.db';

OtzariaAdvancedPage _otzaria(
  String dir,
  SettingsController s,
  void Function(OtzariaModuleController c) setup,
) {
  final c = OtzariaModuleController(dataDir: dir);
  setup(c);
  if (c.currentVersion != null) c.launchPath ??= _launchPath;
  return OtzariaAdvancedPage(otzaria: c, settings: s, onReinstall: () {});
}

LibraryScreen _library(
  String dir,
  void Function(LibraryModuleController c) setup, {
  bool running = false,
  bool appInstalled = true,
  bool appInstallable = false,
}) {
  final c = LibraryModuleController(dataDir: dir);
  setup(c);
  if (c.localVersion != null) c.dbPath ??= _dbPath;
  return LibraryScreen(
    library: c,
    otzariaIsRunning: running,
    isDownloading: false,
    onProcessStateChanged: () async => false,
    onCloseOtzaria: () async => true,
    onRequestReindex: () async {},
    onGoToSettings: () {},
    onGrantSemanticConsent: () async {},
    onUpdateHere: () {},
    onInstallFull: () {},
    appInstalled: appInstalled,
    appInstallable: appInstallable,
  );
}

final Map<String, PageScenario> pageScenarios = {
  'otzaria_advanced': (d, s) => _otzaria(d, s, (c) {
        c
          ..status = OtzariaModuleStatus.upToDate
          ..currentVersion = '0.10.4'
          ..latestVersion = '0.10.4'
          ..stableVersion = '0.10.4'
          ..prereleaseVersion = '0.10.5-beta'
          ..hasChannelChoice = true
          ..lastDownloadedAt = DateTime(2026, 10, 18);
      }),
  'otzaria_advanced_notinstalled': (d, s) => _otzaria(d, s, (c) {
        c
          ..status = OtzariaModuleStatus.updateAvailable
          ..latestVersion = '0.10.4';
      }),
  'library_update': (d, s) => _library(d, (c) {
        c
          ..status = LibraryModuleStatus.updateAvailable
          ..localVersion = 27
          ..targetVersion = 31
          ..semanticPending = true
          ..mirroredCompanions = {CompanionAsset.talmud}
          ..lastDownloadedAt = DateTime(2026, 10, 18)
          ..changesNotes = const [
            LibraryChangesNote(releaseTag: 'v31-1', path: 'none.md'),
          ]
          ..changesNotesVersion = 31;
      }),
  'library_uptodate': (d, s) => _library(d, (c) {
        c
          ..status = LibraryModuleStatus.upToDate
          ..localVersion = 31
          ..targetVersion = 31
          ..onlineLatestVersion = 32
          ..onlineCheckedAt = DateTime(2026, 10, 25)
          ..semanticPending = true
          ..semanticConsentGranted = true
          ..mirroredCompanions = {CompanionAsset.talmud};
      }),
  'library_issues': (d, s) => _library(
        d,
        (c) {
          c
            ..status = LibraryModuleStatus.updateAvailable
            ..localVersion = 27
            ..targetVersion = 31
            ..mirroredCompanions = {CompanionAsset.talmud}
            ..unavailableCompanions = {CompanionAsset.dictionary};
        },
        running: true,
      ),
  'library_notfound': (d, s) => _library(d, (c) {
        c.status = LibraryModuleStatus.needsManualPath;
      }),
  'library_fullafterfail': (d, s) => _library(d, (c) {
        c
          ..status = LibraryModuleStatus.error
          ..localVersion = 27
          ..targetVersion = 31
          ..canRetryWithFullDownload = true
          ..lastDownloadedAt = DateTime(2026, 10, 18)
          ..errorMessage = 'העדכון נכשל: קובץ העדכון אינו מתאים לספריית אוצריא';
      }),
  // המצב האישי קודם למצב: ה-setter שלו מריץ בדיקה כשהמצב אינו idle.
  'library_elsewhere': (d, s) => _library(d, (c) {
        c
          ..personalUpdateMode = true
          ..status = LibraryModuleStatus.personalTargetElsewhere
          ..personalFromVersion = 27
          ..localVersion = 25
          ..targetVersion = 31
          ..lastDownloadedAt = DateTime(2026, 10, 18);
      }),
  // "רק המחשב שלי": המחשב הזה ועוד אחד נרשמו — שורה אחת בכרטיס.
  'library_personal': (d, s) => _library(d, (c) {
        c
          ..personalUpdateMode = true
          ..status = LibraryModuleStatus.updateAvailable
          ..localVersion = 145
          ..targetVersion = 147
          ..lastDownloadedAt = DateTime(2026, 10, 18)
          ..registeredMachines = const [
            RegisteredMachine(key: 'a', version: 145, isThisMachine: true),
            RegisteredMachine(key: 'b', version: 146, isThisMachine: false),
          ];
      }),
  // אוצריא לא מותקנת, והתוכנה בכונן — התקנה מלאה, והדף אומר זאת מראש.
  'library_withapp': (d, s) => _library(
        d,
        (c) {
          c
            ..status = LibraryModuleStatus.updateAvailable
            ..isFreshInstall = true
            ..targetVersion = 31
            ..installTargetPath = _dbPath
            ..mirroredCompanions = {CompanionAsset.talmud}
            ..lastDownloadedAt = DateTime(2026, 10, 18);
        },
        appInstalled: false,
        appInstallable: true,
      ),
  'library_needsapp': (d, s) => _library(
        d,
        (c) {
          c
            ..status = LibraryModuleStatus.updateAvailable
            ..isFreshInstall = true
            ..targetVersion = 31
            ..installTargetPath = _dbPath
            ..mirroredCompanions = {CompanionAsset.talmud}
            ..lastDownloadedAt = DateTime(2026, 10, 18);
        },
        appInstalled: false,
      ),
  'library_updating': (d, s) => _library(d, (c) {
        c
          ..status = LibraryModuleStatus.updating
          ..localVersion = 27
          ..targetVersion = 31
          ..stageText = 'מעדכן את הספרייה (3/7)...'
          ..applyProgress = 0.42;
      }),
  'reports_collect': (d, s) =>
      _reports(d, toCollect: 3, waiting: 9, connection: false, own: true),
  // מקוון, ויש גם מה לאסוף — השליחה של מה שבכונן באותו כרטיס.
  'reports_collect_online': (d, s) =>
      _reports(d, toCollect: 3, waiting: 9, connection: true, own: true),
  'reports_online': (d, s) =>
      _reports(d, waiting: 12, connection: true, legacy: true, own: true),
  'reports_offline': (d, s) =>
      _reports(d, waiting: 9, connection: false, own: true),
  'reports_readonly': (d, s) =>
      _reports(d, toCollect: 3, waiting: 9, readOnly: true, own: true),
  'reports_busy': (d, s) => _reports(
        d,
        toCollect: 3,
        waiting: 9,
        connection: true,
        own: true,
        busy: true,
      ),
  'reports_sending': (d, s) => _reports(
        d,
        waiting: 12,
        connection: true,
        own: true,
        progress: const ReportUploadProgress(
          total: 12,
          done: 7,
          waitRemaining: Duration(seconds: 40),
        ),
      ),
  'reports_nothing': (d, s) => _reports(d, own: true),
  'reports_nothing_empty': (d, s) => _reports(d, own: true, ownEmpty: true),
  'self_online': (d, s) => _self(d, (c) => c.onlineRelease = _releaseNotes),
  'self_idle': (d, s) => _self(d, (c) => c.status = LauncherUpdateStatus.idle),
  'self_ready': (d, s) => _self(d, (c) {
        c
          ..status = LauncherUpdateStatus.readyToInstall
          ..downloadedVersion = '99.1.2'
          ..canInstall = true;
      }),
  'self_downloading': (d, s) => _self(d, (c) {
        c
          ..onlineRelease = _release
          ..status = LauncherUpdateStatus.downloading
          ..downloadReceived = 38
          ..downloadTotal = 100;
      }),
  'self_error': (d, s) => _self(d, (c) {
        c
          ..onlineRelease = _release
          ..status = LauncherUpdateStatus.error
          ..errorMessage = 'הורדת הגרסה החדשה נכשלה: סטטוס 503';
      }),
  'self_manual': (d, s) => _self(d, (c) {
        c
          ..status = LauncherUpdateStatus.readyToInstall
          ..downloadedVersion = '99.1.2'
          ..canInstall = false;
      }),
  'self_admin': (d, s) => _self(d, (c) {
        c
          ..status = LauncherUpdateStatus.readyToInstall
          ..downloadedVersion = '99.1.2'
          ..canInstall = true
          ..needsElevation = true
          ..errorMessage = 'Access is denied';
      }),
  'self_uptodate': (d, s) =>
      _self(d, (c) => c.status = LauncherUpdateStatus.upToDate),
};

/// מצבים שמצולמים גם עם "מתקדם" פתוח.
const advancedScenarios = {
  'library_update',
  'library_fullafterfail',
  'library_withapp',
};

const _release = LauncherRelease(
  tagName: 'v99.1.2',
  name: 'v99.1.2',
  assetName: 'OtzariaUpdates.exe',
  downloadUrl: 'https://example.invalid/OtzariaUpdates.exe',
  sizeBytes: 38 * 1024 * 1024,
  changelog: null,
);

const _releaseNotes = LauncherRelease(
  tagName: 'v99.1.2',
  name: 'v99.1.2',
  assetName: 'OtzariaUpdates.exe',
  downloadUrl: 'https://example.invalid/OtzariaUpdates.exe',
  sizeBytes: 38 * 1024 * 1024,
  changelog: '## 99.1.2\n'
      '- ההורדה ממשיכה מהמקום שבו נעצרה\n'
      '- דף הדיווחים מראה גם את הדיווחים על הכלי',
);

LauncherUpdatePage _self(
  String dir,
  void Function(LauncherUpdateController c) setup,
) {
  final c = LauncherUpdateController(dataDir: dir)
    ..status = LauncherUpdateStatus.upToDate;
  setup(c);
  return LauncherUpdatePage(
    controller: c,
    onDownload: () {},
    onInstall: () {},
    onOpenFolder: () {},
    onRestartElevated: () {},
  );
}

ReportsPage _reports(
  String dir, {
  int toCollect = 0,
  int waiting = 0,
  bool? connection,
  bool readOnly = false,
  bool legacy = false,
  bool own = false,
  bool ownEmpty = false,
  bool busy = false,
  ReportUploadProgress? progress,
}) {
  final errors = ErrorReportsController(
    outbox: _NoOutbox(),
    resolveQueue: () async => null,
  )..outboxCount = waiting;
  if (progress != null) {
    errors
      ..isUploading = true
      ..progress = progress;
  }
  return ReportsPage(
    errorReports: errors,
    connection: connection,
    isUploadingAll: progress != null,
    busy: busy,
    reportsToCollect: toCollect,
    onCollect: () {},
    onUpload: () async {},
    readOnly: readOnly,
    legacyNotice: legacy,
    onDismissLegacy: () {},
    appReports: own ? _appReports(empty: ownEmpty) : null,
  );
}

AppReportsController _appReports({bool empty = false}) {
  final service = _ShotService();
  if (!empty) _fillShotService(service);
  return AppReportsController(
    service: service,
    collector: _NoCollector(),
    settings: _ShotSettings(),
    logsDirectory: '',
    redactor: AppReportRedactor(environment: const {}),
    appVersion: '3.2.0',
    host: 'PC',
    isProcessAlive: (_) => false,
  );
}

void _fillShotService(_ShotService service) {
  service
    ..pending.addAll([
      _report('p1', 'ההורדה נעצרת ב-40%', DateTime(2026, 10, 21)),
      _report('p2', 'הכלי נסגר בפתיחת דף התוספים', DateTime(2026, 10, 19)),
    ])
    ..history.add(
      _report('s1', 'הספרייה לא עודכנה', DateTime(2026, 10, 1)).copyWith(
        sentAt: DateTime(2026, 10, 1),
        issueNumber: 812,
        issueUrl: 'https://github.com/Otzaria/Otzaria_Offline_update/'
            'issues/812',
      ),
    );
}

AppReport _report(String id, String title, DateTime at) => AppReport(
      reportId: id,
      type: AppReportType.bug,
      trigger: AppReportTrigger.manual,
      title: title,
      description: '',
      reporterEmail: 'a@b.co',
      appVersion: '3.2.0',
      platform: 'windows',
      createdAt: at,
    );

class _ShotService extends AppReportService {
  _ShotService()
      : super(
          directory: '',
          client: MockClient((_) async => http.Response('', 500)),
        );

  final List<AppReport> pending = [];
  final List<AppReport> history = [];

  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Future<List<AppReport>> getPendingReports() async => List.of(pending);
  @override
  Future<int> getPendingReportsCount() async => pending.length;
  @override
  Future<List<AppReport>> getSentReports() async => List.of(history);
  @override
  Future<int> getSentReportsTotal() async => history.length;
  @override
  void startAutomaticFlush() {}
}

class _ShotSettings extends SettingsController {
  _ShotSettings() : super(dataDir: '');

  @override
  AppSettings get settings => const AppSettings();
}

class _NoCollector implements AppReportAttachmentsCollector {
  @override
  Future<AppReportAttachments> collect() async =>
      const AppReportAttachments(diagnostics: {}, errorLog: '');
}

class _NoOutbox implements ReportOutbox {
  @override
  Future<int> count() async => 0;
  @override
  Future<void> discard(String reportId) async {}
  @override
  Future<List<OutboxReport>> list() async => const [];
  @override
  Future<void> remove(OutboxReport report) async {}
  @override
  Future<Uint8List> requestBody(OutboxReport report) async => Uint8List(0);
  @override
  Future<void> write(String reportId, Uint8List fileBytes) async {}
}

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:error_reports_manager/error_reports_manager.dart'
    show CrashReportOutcome;
import 'package:flutter/widgets.dart';
import 'package:library_manager/library_manager.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;
import 'package:plugins_manager/plugins_manager.dart'
    show PluginsManager, StorePlugin;
import 'package:seforim_library_updater/seforim_library_updater.dart'
    show DiskSpaceProbe;

import '../app_report/launcher_crash_session.dart';
import '../controllers/app_reports_controller.dart';
import '../controllers/auto_install_flow.dart';
import '../controllers/custom_apps_controller.dart';
import '../controllers/download_plan.dart';
import '../controllers/error_reports_controller.dart';
import '../controllers/faq_controller.dart';
import '../controllers/launcher_update_controller.dart';
import '../controllers/launcher_update_flow.dart';
import '../controllers/library_module_controller.dart';
import '../controllers/mirror_download_flow.dart';
import '../controllers/otzaria_module_controller.dart';
import '../controllers/plugins_module_controller.dart';
import '../controllers/search_feedback_controller.dart';
import '../controllers/shell_module_ports.dart';
import '../flows/update_here_flow.dart';
import '../services/app_logger.dart';
import '../services/app_paths.dart';
import '../services/byte_size.dart';
import '../services/elevation.dart';
import '../services/file_reveal.dart';
import '../services/mirror_junk_sweeper.dart';
import '../services/notices_seen_store.dart';
import '../services/report_offer_coordinator.dart';
import '../services/search_feedback_auto_sync.dart';
import '../services/sleep_inhibitor.dart';
import '../settings/app_settings.dart';
import '../settings/safer_mode.dart';
import '../settings/settings_controller.dart';
import '../widgets/ui_snack.dart';
import 'download_failure.dart';
import 'home_guidance.dart' show FoundNothing, GuidanceItem;
import 'home_guidance_session.dart' show onlineState;
import 'session_prompts.dart';
import 'shell_tasks.dart';

/// המצב והזרימות של הרצה אחת: המודולים, הבדיקות, ההורדה והדגלים שחוסמים
/// יציאה. כל מה שדורש `BuildContext` עובר דרך [prompts].
class AppSession extends ChangeNotifier {
  AppSession({
    required this.dataDir,
    required this.stateDir,
    required this.settings,
    required this.prompts,
    this.readOnly = false,
    this.driveFull = false,
    this.runningLocator = const RunningOtzariaLocator(),
    NoticesSeenStore? noticesStore,
    this.appReports,
    SleepInhibitor? sleepInhibitor,
    @visibleForTesting
    OtzariaLauncher otzariaLauncher = const OtzariaLauncher(),
    SearchFeedbackController? searchFeedback,
    ErrorReportsController? errorReports,
    @visibleForTesting OtzariaManager? otzariaManager,
    @visibleForTesting LibraryManager? libraryManager,
    @visibleForTesting PluginsManager? pluginsManager,
  })  : _noticesStore = noticesStore,
        _injectedSleepInhibitor = sleepInhibitor {
    final s = settings.settings;

    _otzaria = OtzariaModuleController(
      dataDir: dataDir,
      stateDir: stateFilesDir,
      preferPrerelease: s.preferAppPrerelease,
      runningLocator: runningLocator,
      launcher: otzariaLauncher,
      manager: otzariaManager,
      pendingLaunchUri: () async =>
          _library.hasPendingReindex ? OtzariaDeepLinks.libraryReindex : null,
      onLaunchUriDelivered: () => _library.markReindexRequestDelivered(),
      isLibraryApplying: () => _library.isApplying,
    )..addListener(_onChange);
    _library = LibraryModuleController(
      dataDir: dataDir,
      stateDir: stateFilesDir,
      otzariaLaunchPath: () async => _otzaria.launchPath,
      otzariaAppVersion: () async => _otzaria.currentVersion,
      mirroredReadableDbSchema: () => _otzaria.mirroredReadableDbSchema(),
      mirroredOtzariaUpdate: () async =>
          _otzaria.status == OtzariaModuleStatus.updateAvailable
              ? _otzaria.latestVersion
              : null,
      instanceLock: const OtzariaInstanceLock(),
      manager: libraryManager,
    )..addListener(_onChange);
    _plugins = PluginsModuleController(
      mirrorRootDir: p.join(dataDir, 'mirror'),
      stateDir: stateFilesDir,
      otzariaLaunchPath: () async => _otzaria.launchPath,
      locatePluginsDb: PluginsModuleController.locateOtzariaPluginsDb,
      mirroredAppVersions: () async => [
        if (_otzaria.stableVersion != null) _otzaria.stableVersion!,
        if (_otzaria.prereleaseVersion != null) _otzaria.prereleaseVersion!,
      ],
      installedAppVersion: () async =>
          _otzaria.currentVersion ?? _otzaria.latestVersion,
      ensureAppVersionsKnown: _otzaria.ensureChecked,
      manager: pluginsManager,
    )..addListener(_onChange);
    _installDone = _plugins.installCompletions.listen((name) {
      if (isActive) {
        UiSnack.showSuccess(AppL10n.strings.plugins.installDoneSnack(name));
      }
    });
    _installRejected = _plugins.installRejections.listen((entry) {
      if (!isActive) return;
      final t = AppL10n.strings.plugins;
      if (entry.report.cancelled) {
        UiSnack.show(t.installCancelledSnack(entry.name));
      } else {
        UiSnack.showError(
          t.installRejectedSnack(entry.name, entry.report.message),
        );
      }
    });
    _customApps = CustomAppsController(
      mirrorRootDir: p.join(dataDir, 'mirror'),
      stateDir: stateFilesDir,
      trustFilePath: _customAppsTrustFile(),
    )..addListener(_onChange);
    _launcherUpdate = LauncherUpdateController(dataDir: dataDir)
      ..addListener(_onChange);
    _faq = FaqController(dataDir: stateDir);
    _errorReports = (errorReports ??
        ErrorReportsController.forDrive(
          stateDir: stateDir,
          dataDir: dataDir,
          stateFilesDir: stateFilesDir,
          launchPath: () async => _otzaria.launchPath,
        ))
      ..addListener(_onReportsChange);
    _searchFeedback = (searchFeedback ??
        SearchFeedbackController.forDrive(
          dataDir: dataDir,
          stateDir: stateDir,
          stateFilesDir: stateFilesDir,
          launchPath: () async => _otzaria.launchPath,
          runningLocator: runningLocator,
        ))
      ..addListener(_onReportsChange);
  }

  /// התיקייה שלצד התוכנה — המראה, כלומר המקור שממנו קוראים ומתקינים.
  final String dataDir;

  /// לאן נכתבים לוג, הגדרות ומצב — ראו [AppPaths.stateDir].
  final String stateDir;

  String get stateFilesDir => p.join(stateDir, AppPaths.logsDirName);

  final bool readOnly;
  final bool driveFull;
  final SettingsController settings;
  final SessionPrompts prompts;
  final RunningOtzariaLocator runningLocator;

  /// `null` בבדיקות: הוא מפעיל טיימר שליחה ופונה לרשת.
  final AppReportsController? appReports;

  final NoticesSeenStore? _noticesStore;
  final SleepInhibitor? _injectedSleepInhibitor;

  late final SleepInhibitor _sleepInhibitor =
      _injectedSleepInhibitor ?? SleepInhibitor();
  late final OtzariaModuleController _otzaria;
  late final LibraryModuleController _library;
  late final PluginsModuleController _plugins;
  late final StreamSubscription<String> _installDone;
  late final StreamSubscription<Object?> _installRejected;
  late final CustomAppsController _customApps;
  late final LauncherUpdateController _launcherUpdate;
  late final FaqController _faq;
  late final ErrorReportsController _errorReports;
  late final SearchFeedbackController _searchFeedback;

  late final NoticesSeenStore _notices =
      _noticesStore ?? NoticesSeenStore(stateFilesDir);

  /// אימות אחד מלווה את כל ההרצה — ראו `SaferModeGate`.
  late final SaferModeGate saferMode = SaferModeGate(settings);

  OtzariaModuleController get otzaria => _otzaria;
  LibraryModuleController get library => _library;
  PluginsModuleController get plugins => _plugins;
  CustomAppsController get customApps => _customApps;
  LauncherUpdateController get launcherUpdate => _launcherUpdate;
  FaqController get faq => _faq;
  ErrorReportsController get errorReports => _errorReports;
  SearchFeedbackController get searchFeedback => _searchFeedback;
  NoticesSeenStore get notices => _notices;

  /// מסכי המשימה (הורדה, עדכון כאן) — המסגרת מציגה אותם בשכבה מעל הגוף.
  final ShellTasks tasks = ShellTasks();

  bool _disposed = false;
  bool get isActive => !_disposed;

  Future<void> _errorReportsIntro = Future<void>.value();
  Future<void>? _semanticAnswerLoad;

  /// `null` — עוד לא נקרא; עד אז הבית שקט, בלי "עדכון" שמהבהב בעלייה.
  bool? _semanticConsentAnswered;
  bool _reportsIntroPending = false;
  bool _autoInstallSkipped = false;
  int _errorReportsToCollect = 0;
  DateTime? _checkedAt;

  /// "מה התחדש" כבר מוצג בדף הכלי, ולכן אישור ההתקנה לא חוזר עליו.
  bool _whatsNewAlreadyShown = false;

  bool _elevationPending = false;
  bool _elevationDismissed = false;
  bool _legacyReportsNotice = false;
  bool _isCheckingOnline = false;
  bool _checkingNow = false;
  bool _markingPluginsVisited = false;
  bool _uploadingReports = false;
  bool _reportsStopRequested = false;

  bool get isCheckingOnline => _isCheckingOnline;

  /// "הורדה" שלא מצאה מה להביא — הבית אומר זאת במקום מסך משימה. נמחק בבדיקה,
  /// בהורדה הבאה ובשינוי הגדרות.
  FoundNothing? get foundNothing => _foundNothing;
  FoundNothing? _foundNothing;
  AppSettings? _appliedSettings;

  /// "לשאול כל פעם" ויש חיפוש חכם להוריד — שורה משנית בבית ובדף הספרייה.
  bool get onlineSemanticOffer =>
      !readOnly &&
      settings.settings.downloadsLibrary &&
      _library.onlineSemanticOffer;

  /// המקום הפנוי בכונן, ליד רשימת ההורדה בבית. נמדד אחרי בדיקה ברשת ואחרי
  /// הורדה; `null` עד אז או כשהמדידה נכשלה.
  int? get driveFreeBytes => _driveFreeBytes;
  int? _driveFreeBytes;

  /// ב-isolate: ב-macOS המדידה מריצה `df`, ותהליך חוסם את ה-UI (§5.9).
  Future<void> _measureDriveFree() async {
    int? free;
    Object? failure;
    try {
      free = await _freeBytesInIsolate(dataDir);
    } catch (e) {
      failure = e;
    }
    if (!isActive) return;
    if (failure != null) {
      AppLogger.instance.info('מדידת המקום הפנוי בכונן לא הצליחה: $failure');
    }
    _update(() => _driveFreeBytes = free);
  }

  // סטטית: סגור בתוך מתודה async היה לוכד את ה-Future שלה, שאינו נשלח ל-isolate.
  static Future<int?> _freeBytesInIsolate(String dir) =>
      Isolate.run(() => DiskSpaceProbe.freeBytesFor(dir));

  /// בדיקה רצה — "בדוק עכשיו", הבדיקה שבעלייה, או בדיקה ברשת.
  bool get isCheckingNow => _checkingNow || _isCheckingOnline;

  /// משימה ארוכה חוסמת את "בדוק עכשיו" — אותו תנאי לקישור, לכפתור ולפעולה.
  bool get checkNowBlocked => longTaskRunning;

  /// תורי דיווחים ישנים שלא הועברו — הסבר בבית עד "הבנתי".
  bool get showsLegacyReportsNotice => _legacyReportsNotice;

  /// ההסבר החד-פעמי על הדיווחים: הודעה בבית עד "הבנתי".
  bool get showsReportsIntro => _reportsIntroPending;

  /// ההתקנה האוטומטית דילגה כי אוצריא הייתה פתוחה — הודעה קבועה בבית.
  bool get autoInstallSkipped => _autoInstallSkipped;

  /// כמה דיווחים ממתינים באוצריא לאיסוף — המונה של אריח הדיווחים.
  int get reportsToCollect => _errorReportsToCollect;
  int get errorReportsToCollect => _errorReportsToCollect;

  /// הבדיקה האחרונה, מקומית או ברשת — "נבדק ב-" בתחתית הבית.
  DateTime? get lastCheckedAt => [
        _checkedAt,
        _otzaria.onlineCheckedAt,
        _library.onlineCheckedAt,
        _plugins.onlineCheckedAt,
      ].whereType<DateTime>().fold<DateTime?>(
            null,
            (latest, at) => latest == null || at.isAfter(latest) ? at : latest,
          );
  bool get uploadingReports => _uploadingReports;

  /// נגזר מהקונטרולר ולא מועתק: העתק נשאר תקוע על "פתוחה" אחרי שנסגרה.
  bool get otzariaIsRunning => _otzariaIsRunning;
  bool get _otzariaIsRunning => _otzaria.isRunning;

  static const Duration _runningPollInterval = Duration(seconds: 3);
  static const Duration _runningWatchSlice = Duration(minutes: 1);
  Timer? _runningPoll;
  Future<void>? _runningWatch;

  late final OtzariaModulePort _otzariaPort = OtzariaModulePort(
    _otzaria,
    onInstalled: _refreshAfterAppInstall,
  );

  Future<void> _refreshAfterAppInstall() async {
    if (!isActive) return;
    await Future.wait([
      _library.checkForUpdate(fresh: true),
      _plugins.refreshInstalled(),
    ]);
  }

  late final LibraryModulePort _libraryPort = LibraryModulePort(_library);
  late final PluginsModulePort _pluginsPort = PluginsModulePort(_plugins);

  late final MirrorDownloadFlow _downloads = MirrorDownloadFlow(
    app: _otzariaPort,
    library: _libraryPort,
    plugins: _pluginsPort,
    host: _SessionDownloadHost(this),
  );

  late final UpdateHereFlow _updateHere = UpdateHereFlow(
    app: _otzariaPort,
    library: _libraryPort,
    plugins: _pluginsPort,
    host: _SessionUpdateHost(this),
  );

  late final LauncherUpdateFlow _launcherFlow = LauncherUpdateFlow(
    launcher: LauncherUpdatePort(_launcherUpdate),
    downloads: _downloads,
    host: _SessionLauncherHost(this),
  );

  late final AutoInstallFlow _autoInstall = AutoInstallFlow(
    library: _libraryPort,
    app: _otzariaPort,
    isOtzariaRunning: refreshProcessState,
    isDownloading: () => _downloads.isDownloading,
    exitPending: () => exitPending,
    isActive: () => isActive,
  );

  late final ReportOfferCoordinator _offers = ReportOfferCoordinator(
    isTaskRunning: () =>
        exitWouldInterrupt || _downloads.isPreparing || tasks.isRunning,
    isActive: () => isActive,
    prepare: _prepareOffer,
    runDialog: prompts.runDialog,
    perform: recountReportsToCollect,
    onResume: () {
      if (!readOnly) _feedbackSync.resume();
    },
  );

  late final SearchFeedbackAutoSync _feedbackSync = SearchFeedbackAutoSync(
    run: _syncSearchFeedback,
    isBusy: () => _offers.busy,
  );
  final Completer<void> _firstFrame = Completer<void>();

  bool get isDownloading => _downloads.isDownloading;
  bool get isCancellingDownload => _downloads.isCancelling;

  /// מה יורד עכשיו — למסך ההתקדמות.
  MirrorComponent? get currentDownload => _downloads.currentComponent;

  /// מה שכל רכיב צפוי להוריד לפי הבדיקה ברשת; רכיב שגודלו לא ידוע חסר.
  Map<MirrorComponent, int> get expectedDownloadBytes {
    final plan = _downloads.activePlan;
    if (plan == null) return const {};
    final s = settings.settings;
    final app = _otzaria.onlineDownloadBytes;
    final plugins = [
      if (plan.runsPlugins(s)) _plugins.onlineStatus?.pendingBytes,
      if (plan.runsStoreApp(s)) _plugins.storeAppOnline?.sizeBytes,
    ];
    final pluginBytes = plugins.contains(null)
        ? 0
        : plugins.fold<int>(0, (sum, bytes) => sum + bytes!);
    return {
      if (app != null && plan.runsApp(s)) MirrorComponent.app: app,
      if (pluginBytes > 0) MirrorComponent.plugins: pluginBytes,
    };
  }

  /// העבודה שבעלייה. נפרד מהבנאי כדי שבדיקות יוכלו לבנות סשן בלי להריץ אותה.
  void start() {
    LauncherCrashSession.closeGuard = confirmClose;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _firstFrame.complete();
      // The scene is submitted before post-frame callbacks finish.
      scheduleMicrotask(() {
        if (isActive) _startAfterFrame();
      });
    });
  }

  void _startAfterFrame() {
    final s = settings.settings;
    unawaited(_faq.load());
    // ספירה בלבד — גם בכונן מוגן, כדי שהבית יאמר שיש בו דיווחים.
    unawaited(_errorReports.refreshOutbox());
    if (!readOnly) _errorReports.startAutomaticPluginUpload();
    _errorReportsIntro = _loadReportsIntro();
    unawaited(loadSemanticConsentAnswer());
    settings.addListener(_onChange);
    _applySettings(s);

    unawaited(_plugins.load());
    unawaited(_customApps.load());
    if (s.autoCheckUpdates) {
      _startupLocal.complete(_asCheck(checkAll).catchError((_) {}));
    } else {
      unawaited(refreshProcessState());
      unawaited(_launcherFlow.checkMirror());
      final local = _asCheck(() async {
        await _otzaria.ensureChecked();
        _markChecked();
      });
      _startupLocal.complete(local.catchError((_) {}));
      unawaited(local.then((_) {
        _requestFeedbackSync();
        return _offers.request();
      }));
    }
    var crashCheck = Future<void>.value();
    if (appReports case final reports?) {
      reports.stateProvider = _reportState;
      crashCheck = _startReports(reports);
    }
    final online = s.autoCheckUpdates ? checkOnline() : Future<void>.value();
    _startupOnlineDone = false;
    _startupOnline = online.catchError((_) {}).whenComplete(() {
      if (isActive) _update(() => _startupOnlineDone = true);
    });
    unawaited(_askPersonalScopeAfter(crashCheck));
    unawaited(
      Future.wait([_startupLocal.future, _startupOnline])
          .then((_) => registerPendingMachine()),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _sleepInhibitor.dispose();
    if (LauncherCrashSession.closeGuard == confirmClose) {
      LauncherCrashSession.closeGuard = null;
    }
    _runningPoll?.cancel();
    _offers.dispose();
    _feedbackSync.dispose();
    unawaited(_installDone.cancel());
    unawaited(_installRejected.cancel());
    settings.removeListener(_onChange);
    _otzaria.removeListener(_onChange);
    _library.removeListener(_onChange);
    _plugins.removeListener(_onChange);
    _customApps.removeListener(_onChange);
    _launcherUpdate.removeListener(_onChange);
    _errorReports.removeListener(_onReportsChange);
    _searchFeedback.removeListener(_onReportsChange);
    _otzaria.dispose();
    _library.dispose();
    _plugins.dispose();
    _customApps.dispose();
    _launcherUpdate.dispose();
    _errorReports.dispose();
    _searchFeedback.dispose();
    _faq.dispose();
    tasks.dispose();
    super.dispose();
  }

  void _update(VoidCallback change) {
    change();
    if (isActive) notifyListeners();
  }

  void _onChange() {
    if (!isActive) return;
    _syncSleepInhibition();
    _offers.onRunningState(running: _otzariaIsRunning);
    if (!readOnly) _feedbackSync.onRunningState(running: _otzariaIsRunning);
    _offers.resume();
    _applySettings(settings.settings);
    _syncRunningPoll();
    notifyListeners();
  }

  void _onReportsChange() {
    if (!isActive) return;
    _syncSleepInhibition();
    _offers.resume();
  }

  /// תוספים חדשים בכונן שהבית עוד לא הזכיר — פס בבית עד הכניסה לחנות.
  List<StorePlugin> get newPluginsForHome =>
      _plugins.status == PluginsModuleStatus.ready
          ? _plugins.newPluginsForHome
          : const [];

  /// הכניסה לחנות: התוספים החדשים נרשמים כמוזכרים, פעם אחת במחשב.
  Future<void> markPluginsVisited() async {
    final fresh = newPluginsForHome;
    if (fresh.isEmpty || _markingPluginsVisited) return;
    _markingPluginsVisited = true;
    try {
      await _plugins.markHomeNotified(fresh);
    } finally {
      _markingPluginsVisited = false;
    }
    if (isActive) notifyListeners();
  }

  Future<void> _loadReportsIntro() async {
    final seen = await _notices.hasSeen(NoticesSeenStore.errorReportsIntro);
    if (!seen && isActive) _update(() => _reportsIntroPending = true);
  }

  /// נקרא פעם אחת (בעלייה, או בלחיצה הראשונה כשהעלייה לא רצה).
  Future<void> loadSemanticConsentAnswer() => _semanticAnswerLoad ??= () async {
        final answered =
            await _notices.hasSeen(NoticesSeenStore.semanticConsentAnswered);
        if (isActive) {
          _update(() => _semanticConsentAnswered ??= answered);
        }
      }();

  /// הסכמה חסרה שעוד לא נענתה בחלון שלפני העדכון — אחרי תשובה הבית שקט,
  /// וההפעלה נשארת בהגדרות ובדף הספרייה.
  bool get semanticConsentUnanswered =>
      _library.semanticConsentRequired && _semanticConsentAnswered == false;

  Future<void> _recordSemanticConsentAnswer() async {
    await loadSemanticConsentAnswer();
    _update(() => _semanticConsentAnswered = true);
    await _notices.markSeen(NoticesSeenStore.semanticConsentAnswered);
  }

  /// "הבנתי" בהודעה — נרשם רק עכשיו, ולא כשהיא הופיעה.
  Future<void> dismissReportsIntro() async {
    if (!_reportsIntroPending) return;
    _update(() => _reportsIntroPending = false);
    await _notices.markSeen(NoticesSeenStore.errorReportsIntro);
  }

  /// סופר מה ממתין באוצריא לאיסוף, בלי לאסוף. אוצריא פתוחה נועלת את התור.
  Future<void> recountReportsToCollect() async {
    if (readOnly || !isActive) return;
    if (await refreshProcessState()) return;
    final reports = await _errorReports.pendingToOffer();
    final legacy = _errorReports.unmigratedLegacy.isNotEmpty &&
        !await _notices.hasSeen(NoticesSeenStore.legacyReportsNotice);
    if (!isActive) return;
    _update(() {
      _errorReportsToCollect = reports;
      _legacyReportsNotice = legacy;
    });
  }

  Future<void> dismissLegacyReportsNotice() async {
    if (!_legacyReportsNotice) return;
    _update(() => _legacyReportsNotice = false);
    await _notices.markSeen(NoticesSeenStore.legacyReportsNotice);
  }

  void _markChecked() {
    if (isActive) _update(() => _checkedAt = DateTime.now());
  }

  /// מצב המודולים לאבחון הדיווח — בלי נתיבים ושמות קבצים של המשתמש.
  Map<String, dynamic> _reportState() {
    final s = settings.settings;
    return {
      'readOnly': readOnly,
      'otzaria': _otzaria.status.name,
      'otzariaVersion': _otzaria.currentVersion,
      'otzariaRunning': _otzariaIsRunning,
      'library': _library.status.name,
      'plugins': _plugins.status.name,
      'pluginDetails': _plugins.diagnostics,
      'customApps': _customApps.hasApps,
      'launcherUpdateReady': _launcherUpdate.hasUpdateReady,
      'autoCheckUpdates': s.autoCheckUpdates,
      'autoInstall': s.autoInstall,
      'personalUpdateMode': s.personalUpdateMode,
      'crashReportMode': s.crashReportMode.wireName,
      'language': s.language.name,
    };
  }

  Future<void> _startReports(AppReportsController reports) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!isActive) return;
    reports.startBackground();
    final outcome = await reports.runCrashCheck(
      showPrompt: (candidate) async {
        final shown = await prompts.showCrashPrompt(reports, candidate);
        return shown ?? false;
      },
    );
    if (outcome == CrashReportOutcome.sentAutomatically && isActive) {
      UiSnack.show(AppL10n.strings.appReports.crashAutoSentSnack);
    }
  }

  /// המחשב הזה נרשם בהרצה הזו בלי לחיצה על "רישום" — הערה שקטה בבית.
  bool get preparedForThisMachine => _preparedHere;
  bool _preparedHere = false;

  /// הבדיקות של העלייה: המקומית (הבית כבר במצבו, גם מסך הפתיחה), והמקוונת —
  /// שקובעת אם זה המחשב המחובר.
  final Completer<void> _startupLocal = Completer<void>();
  Future<void> _startupOnline = Future<void>.value();

  /// הבדיקה המקוונת של העלייה הסתיימה (או לא רצה כלל) — עד אז `null` אינו
  /// "לא ידוע", אלא "עוד לא".
  bool _startupOnlineDone = true;

  /// השאלה נשאלת פעם אחת לכונן (ההגדרה נוסעת איתו). כונן מוגן אינו יכול
  /// לשמור תשובה, ובמצב נעול אסור לשנות הגדרות — בשניהם לא שואלים.
  bool get shouldAskPersonalScope =>
      !readOnly && !settings.settings.personalModeAsked && !saferMode.isLocked;

  /// אחרי שאלת הקריסה ואחרי שהבית התייצב (מסך הפתיחה כבר מוצג), באותו תור
  /// דיאלוגים. סגירה בלי תשובה אינה נשמרת, ולכן השאלה חוזרת בהפעלה הבאה.
  Future<void> _askPersonalScopeAfter(Future<void> crashCheck) async {
    try {
      await crashCheck;
    } catch (_) {}
    await _firstFrame.future;
    await _startupLocal.future;
    if (!isActive || !shouldAskPersonalScope) return;
    final answer = await prompts.runDialog(prompts.askPersonalScope);
    if (answer == null || !isActive || !shouldAskPersonalScope) return;
    await choosePersonalScope(personal: answer, fromQuestion: true);
  }

  /// בדיקה ברשת רצה ונכשלה. בלי בדיקה (`null`) לא ידוע — ולא רושמים.
  bool get _provenOffline => onlineState(this) == false;

  /// התשובה לשאלה וגם הבחירה בהגדרות. "רק המחשב שלי" רושם מיד רק מחשב שהוכח
  /// לא מחובר ואוצריא מותקנת בו; אחרת נדלק הדגל לרישום במחשב כזה.
  Future<void> choosePersonalScope({
    required bool personal,
    bool fromQuestion = false,
  }) async {
    // בהגדרות האזהרה כבר נשאלה לפני הבחירה.
    if (personal && fromQuestion && await _library.mirrorHoldsFullDb()) {
      final approved = await prompts.runDialog(prompts.confirmPersonalMode);
      if (approved != true || !isActive) return;
    }
    await _startupOnline;
    if (!isActive) return;
    var registered = false;
    if (personal && !readOnly && _provenOffline) {
      if (_otzaria.currentVersion == null) await _otzaria.ensureChecked();
      if (!isActive) return;
      registered = _otzaria.currentVersion != null &&
          await _library.capturePersonalVersion();
    }
    if (!isActive) return;
    final pending =
        personal && !registered && await _library.hasNoRegisteredMachine();
    await settings.update(
      settings.settings.copyWith(
        personalUpdateMode: personal,
        personalModeAsked: true,
        personalAutoRegisterPending: pending,
      ),
    );
    if (registered && isActive) _update(() => _preparedHere = true);
  }

  /// אירוע של העלייה, לא של הבדיקה (§5.4): לפי הדגל שבכונן, פעם אחת, נרשם
  /// המחשב הראשון שאוצריא מותקנת בו ושהבדיקה ברשת בו נכשלה.
  @visibleForTesting
  Future<void> registerPendingMachine() async {
    final s = settings.settings;
    if (!isActive || readOnly) return;
    if (!s.personalUpdateMode || !s.personalAutoRegisterPending) return;
    if (!_provenOffline || _otzaria.currentVersion == null) return;
    if (!await _library.hasNoRegisteredMachine()) {
      await _clearAutoRegister();
      return;
    }
    if (!await _library.capturePersonalVersion() || !isActive) return;
    await _clearAutoRegister();
    _update(() => _preparedHere = true);
  }

  Future<void> _clearAutoRegister() async {
    if (!isActive || !settings.settings.personalAutoRegisterPending) return;
    await settings.update(
      settings.settings.copyWith(personalAutoRegisterPending: false),
    );
  }

  /// הבית מסביר שהבחירה ממתינה למחשב שאוצריא מותקנת בו.
  bool get personalRegistrationPending =>
      settings.settings.personalUpdateMode &&
      settings.settings.personalAutoRegisterPending &&
      _library.registeredMachines.isEmpty;

  /// כאן אוצריא מותקנת ולא ידוע אם המחשב מחובר (לא רצה בדיקה ברשת): רישום
  /// אוטומטי לא יקרה, ולכן הבית מציע את הכפתור במקום הבטחה.
  bool get personalPendingNeedsClick =>
      personalRegistrationPending &&
      !readOnly &&
      _startupOnlineDone &&
      !isCheckingOnline &&
      onlineState(this) == null &&
      _otzaria.currentVersion != null;

  /// "הסרה" בהגדרות. גם מבטלת רישום אוטומטי שממתין — כדי שהסרת המחשב
  /// האחרון לא תרשום מחשב מחדש בהפעלה הבאה.
  Future<void> forgetRegisteredMachine(String machineKey) async {
    await _clearAutoRegister();
    await _library.forgetMachine(machineKey);
  }

  /// אחרי "רישום המחשב הזה" (לחיצה מפורשת): הרישום האוטומטי כבר לא נחוץ.
  Future<void> afterManualRegistration() async {
    if (!await _library.hasNoRegisteredMachine()) await _clearAutoRegister();
  }

  bool get _needsElevation =>
      _library.needsElevation ||
      _otzaria.needsElevation ||
      _launcherUpdate.needsElevation;

  /// [restartElevated] יפעל עכשיו: רק ב-Windows, כשיש כשל הרשאות, ולא
  /// בזמן פעולה שיציאה קוטעת.
  bool get canRestartElevated =>
      Platform.isWindows &&
      _needsElevation &&
      !_elevationPending &&
      !exitWouldInterrupt;

  /// הפס "הפעלה מחדש כמנהל" בבית. "לא עכשיו" מסתיר אותו עד סוף ההרצה.
  bool get offersElevation => canRestartElevated && !_elevationDismissed;

  void dismissElevation() => _update(() => _elevationDismissed = true);

  Future<void> restartElevated() async {
    if (!Platform.isWindows || !_needsElevation || _elevationPending) return;
    final t = AppL10n.strings.elevation;
    await _searchFeedback.stopAndWait();
    if (!isActive) return;
    if (exitWouldInterrupt) {
      UiSnack.show(t.busyNotice);
      return;
    }

    _update(() => _elevationPending = true);
    final Object? failure;
    try {
      failure = await Elevation.restartElevated();
    } finally {
      if (isActive) {
        _update(() => _elevationPending = false);
        _offers.resume();
      }
    }
    if (failure != null && failure != Elevation.cancelled) {
      UiSnack.showError(t.restartFailedSnack('$failure'));
    }
  }

  void _syncRunningPoll() {
    if (_otzariaIsRunning) _runningWatch ??= _watchUntilClosed();
  }

  Future<void> _watchUntilClosed() async {
    try {
      while (isActive && _otzariaIsRunning) {
        final exited = await runningLocator.waitForExit(_runningWatchSlice);
        if (!isActive) return;
        if (exited == null) {
          final elapsed = Completer<void>();
          _runningPoll = Timer(_runningPollInterval, elapsed.complete);
          await elapsed.future;
          if (!isActive) return;
        }
        await _otzaria.refreshRunningState();
      }
    } finally {
      _runningWatch = null;
    }
  }

  /// הצבת ערך idempotent — ה-setter מתעלם מאותו ערך, ולכן אין בדיקה חוזרת.
  void _applySettings(AppSettings s) {
    // נקרא בכל שינוי בסשן; רק הגדרות חדשות מבטלות את "אין חדש".
    if (_appliedSettings != null && !identical(s, _appliedSettings)) {
      _foundNothing = null;
    }
    _appliedSettings = s;
    _otzaria.preferPrerelease = s.preferAppPrerelease;
    if (s.personalUpdateMode && !_library.personalUpdateMode) {
      _library.personalUpdateMode = true;
      unawaited(_library.refreshRegisteredMachines());
    } else {
      _library.personalUpdateMode = s.personalUpdateMode;
    }
    _library.semanticPreference = s.semanticDownload;
  }

  /// בדיקת תהליך טרייה מיד לפני פעולה שאוצריא הפתוחה חוסמת. `force`: אינה
  /// מסתפקת בתשובה של בדיקה שכבר הייתה באוויר.
  Future<bool> refreshProcessState() =>
      _otzaria.refreshRunningState(force: true);

  Future<bool> closeOtzaria() => _offers.holdFor(() async {
        final closed = await _otzaria.closeRunning();
        if (isActive) _syncRunningPoll();
        return closed;
      });

  bool _blockedByReadOnly() {
    if (!readOnly) return false;
    final t = AppL10n.strings.readOnlyDrive;
    UiSnack.show(
      driveFull ? t.downloadsDisabledSnackDriveFull : t.downloadsDisabledSnack,
    );
    return true;
  }

  Future<void> checkAll() async {
    await _launcherFlow.checkMirror();
    if (!isActive) return;

    await _otzaria.checkForUpdate();
    if (!isActive) return;
    unawaited(_plugins.refreshInstalled());

    await _library.checkForUpdate();
    if (!isActive) return;
    await _autoInstallIfEnabled();
    if (!isActive) return;
    _markChecked();
    _requestFeedbackSync();
    await _offers.request();
  }

  Future<bool> _prepareOffer() async {
    await WidgetsBinding.instance.endOfFrame;
    await _errorReportsIntro;
    return isActive && _otzaria.launchPath != null;
  }

  Future<Duration?> _syncSearchFeedback() async {
    await _firstFrame.future;
    if (!isActive) return null;
    if (exitPending) return SearchFeedbackController.minRetry;
    return _searchFeedback.synchronize();
  }

  void _requestFeedbackSync() {
    if (!readOnly && isActive) unawaited(_feedbackSync.request());
  }

  Future<void> grantSemanticConsent() async {
    if (await refreshProcessState()) {
      UiSnack.showError(AppL10n.strings.home.otzariaOpenSnack);
      return;
    }
    if (!isActive) return;
    final agreed = await prompts.confirmSemanticConsent();
    if (!agreed || !isActive) return;
    await _writeSemanticConsent();
  }

  /// מחזיר מה לומר כשלא נכתבה ([snack] — גם כהודעה צפה). מפתח שהשרת חסם
  /// אינו נפתח בהסכמה חדשה, ולכן גם הוא תשובה: לא שואלים עליו שוב.
  Future<String?> _writeSemanticConsent({bool snack = true}) async {
    final t = AppL10n.strings.libraryDomain;
    String? problem;
    try {
      switch (await _searchFeedback.grantConsent()) {
        case ConsentWrite.failed:
          problem = t.semanticConsentNotSaved;
        case ConsentWrite.blocked:
          problem = t.semanticConsentBlocked;
          await _recordSemanticConsentAnswer();
        case ConsentWrite.granted:
          _requestFeedbackSync();
          await _recordSemanticConsentAnswer();
          await _library.checkForUpdate(fresh: true);
      }
    } catch (error, stack) {
      AppLogger.instance.error('כתיבת ההסכמה לחיפוש החכם נכשלה', error, stack);
      problem = t.semanticConsentNotSaved;
    }
    if (problem != null && snack) UiSnack.showError(problem);
    return problem;
  }

  Future<void> uploadReports() => _offers.guardedUpload(
        blocked: () => _blockedByReadOnly() || !isActive,
        run: (onActive) => prompts.uploadReports(
          isCancelled: () => _reportsStopRequested,
          onActiveChanged: onActive,
          onUploadingChanged: (uploading) {
            if (!isActive) return;
            if (uploading) _reportsStopRequested = false;
            _update(() => _uploadingReports = uploading);
            _syncSleepInhibition();
            _offers.resume();
          },
        ),
      );

  void stopReports() => _reportsStopRequested = true;

  Future<void> checkOnline() async {
    if (readOnly || _isCheckingOnline) return;
    _update(() {
      _isCheckingOnline = true;
      _foundNothing = null;
    });
    await _launcherFlow.checkMirror();
    if (!isActive) return;
    await Future.wait([
      _otzaria.checkOnline(),
      _library.checkOnline(),
      _plugins.checkOnline(),
      _launcherUpdate.checkOnline(),
    ]);
    if (!isActive) return;
    _update(() => _isCheckingOnline = false);
    _markChecked();
    unawaited(_measureDriveFree());
  }

  /// "הורדה והפעלה מחדש" בדף הכלי: מה חדש כבר מוצג בדף, ולכן אישור
  /// ההתקנה שאחרי ההורדה אינו חוזר עליו.
  Future<void> downloadLauncherUpdate() =>
      _fromLauncherPage(_launcherFlow.download);

  bool get longTaskRunning =>
      _downloads.isDownloading ||
      _library.isApplying ||
      _library.status == LibraryModuleStatus.updating ||
      _otzaria.status == OtzariaModuleStatus.installing ||
      _customApps.isBusy ||
      _customApps.isLearning ||
      _customApps.isDownloadingAll ||
      _plugins.isExporting ||
      _plugins.isSyncing ||
      _plugins.isUpdatingAll ||
      exitPending;

  bool get pluginSyncBlockedElsewhere =>
      _downloads.isDownloading ||
      _library.isApplying ||
      _library.status == LibraryModuleStatus.updating ||
      _otzaria.status == OtzariaModuleStatus.installing ||
      _customApps.isBusy;

  bool get exitPending => _elevationPending || _launcherUpdate.isInstalling;

  void _syncSleepInhibition() => _sleepInhibitor.setActive(
        exitWouldInterrupt ||
            _searchFeedback.isCollecting ||
            _searchFeedback.isUploading ||
            _launcherUpdate.isDownloading ||
            _library.downloadStatus == MirrorDownloadStatus.downloading ||
            _otzaria.downloadStatus == OtzariaDownloadStatus.downloading ||
            _plugins.isAwaitingInstall,
      );

  bool get exitWouldInterrupt =>
      longTaskRunning ||
      _errorReports.isCollecting ||
      _errorReports.isUploading ||
      _uploadingReports;

  Future<void> installLauncherUpdate() =>
      _fromLauncherPage(_launcherFlow.install);

  Future<void> _fromLauncherPage(Future<void> Function() action) async {
    if (!isActive) return;
    _whatsNewAlreadyShown = true;
    try {
      await action();
    } finally {
      _whatsNewAlreadyShown = false;
    }
  }

  Future<bool> _confirmLauncherInstall(String version) =>
      prompts.confirmLauncherInstall(
        version,
        whatsNew:
            _whatsNewAlreadyShown ? null : _launcherUpdate.downloadedWhatsNew,
      );

  Future<void> _autoInstallIfEnabled() async {
    final skippedWhileRunning = await _autoInstall.run(
      enabled: settings.settings.autoInstall,
    );
    if (isActive) _update(() => _autoInstallSkipped = skippedWhileRunning);
  }

  @visibleForTesting
  Map<MirrorComponent, List<String>> get downloadMirrorDirs => {
        MirrorComponent.app: [_otzaria.mirrorDir],
        MirrorComponent.library: [
          _library.mirrorDir,
          _library.companionsMirrorDir,
          _library.semanticMirrorDir,
        ],
        MirrorComponent.plugins: _plugins.mirrorDirs,
      };

  Future<void> cancelDownload() async {
    if (!_downloads.isDownloading || _downloads.isCancelling || !isActive) {
      return;
    }
    final approved = await prompts.confirmCancelDownload();
    if (!approved || !isActive || !_downloads.isDownloading) return;
    _downloads.requestCancel();
  }

  /// [LauncherCrashSession.closeGuard]: שואל רק בזמן פעולה ארוכה, ומבטל
  /// הורדה (עם שחזור המראה) לפני שהחלון נסגר.
  Future<bool> confirmClose() async {
    // הסגירה מסתיימת ב-`exit`, ושום dispose לא ירוץ אחריה.
    await _faq.flush().timeout(const Duration(seconds: 1), onTimeout: () {});
    // גם במסירת התוספים, שאינה longTask; בשאלות (סגירת אוצריא, משתמש אחר) עוד לא רץ דבר.
    final updatingHere = switch (tasks.current) {
      UpdateHereTask(phase: UpdateHereTaskPhase.running) => true,
      _ => false,
    };
    if (!isActive || !(longTaskRunning || updatingHere)) return true;
    final approved = await prompts.confirmClose(
      downloading: _downloads.isDownloading,
    );
    if (!approved) return false;
    if (!isActive) return true;
    await _downloads.cancelAndWait();
    return true;
  }

  /// "מתכונן" נפתח מיד, גם מ"נסה שוב"; זרימה שחזרה בלי להתחיל סוגרת אותו.
  /// [forceSemantic] — ראו [MirrorDownloadFlow.downloadAll].
  Future<void> downloadAll({bool forceSemantic = false}) async {
    if (_blockedByReadOnly() || tasks.isRunning) return;
    if (!settings.settings.hasSyncSelection) {
      prompts.notifyNoSyncSelection();
      return;
    }
    if (longTaskRunning || _launcherUpdate.isDownloading) {
      UiSnack.show(AppL10n.strings.guide.downloadBusySnack);
      return;
    }
    final request = ++_downloadRequest;
    if (_foundNothing != null) _update(() => _foundNothing = null);
    tasks.prepareDownload();
    await _downloads.downloadAll(forceSemantic: forceSemantic);
    if (isActive) unawaited(_measureDriveFree());
    // בקשה שבוטלה לא סוגרת את המסך של בקשה חדשה שנפתחה אחריה.
    if (isActive && request == _downloadRequest) tasks.abandonDownload();
  }

  int _downloadRequest = 0;

  /// "נסה שוב" בהערה על קבצים שלא ירדו. הספרייה רצה בשבילם ממילא (ההוכחה
  /// סופרת אותם), וההורדה מחשבת מחדש מה נכשל.
  Future<void> retryFailedDownloads() =>
      downloadAll(forceSemantic: _library.semanticDownloadFailed);

  /// "ביטול" ב"מתכונן להורדה": המסך נסגר, והזרימה עוצרת אחרי הבדיקה ברשת.
  void abandonPreparingDownload() {
    _downloads.abandonPreparing();
    tasks.abandonDownload();
  }

  /// "עדכון כאן". מ"אוצריא — מתקדם" [reinstallApp] — אותה גרסה שוב; מדף
  /// הספרייה [fullLibrary] — הספרייה המלאה במקום עדכון שנכשל.
  Future<void> updateHere(
    List<GuidanceItem> items, {
    bool reinstallApp = false,
    bool fullLibrary = false,
  }) async {
    if (tasks.isRunning || exitPending || !isActive) return;
    await _updateHere.run(
      items,
      reinstallApp: reinstallApp,
      fullLibrary: fullLibrary,
    );
  }

  /// הכפתור שבהודעה בבית: אותו חלון ואותה זרימה כמו "עדכון המחשב הזה".
  /// בלי אוצריא אין לאן לכתוב — וזרימה בלעדיה הייתה מריצה את מתקין התוכנה.
  Future<void> answerSemanticConsent() async {
    if (tasks.isRunning || exitPending || !isActive) return;
    if (_otzaria.currentVersion == null) return;
    if (await _updateHere.run(const [GuidanceItem.library]) || !isActive) {
      return;
    }
    await grantSemanticConsent();
  }

  Future<void> retryUpdateHere() async {
    if (tasks.isRunning || exitPending || !isActive) return;
    if (await _updateHere.retry() || !isActive) return;
    tasks.dismiss();
    UiSnack.show(AppL10n.strings.task.retryNothingSnack);
  }

  void stopWaitingForSetup() => _updateHere.stopWaiting();

  /// "פתיחת אוצריא". הכשל נאמר מיד: הבית מציג את `errorMessage` רק כשהבדיקה
  /// עצמה נכשלה, ובלי זה הלחיצה נראתה כאילו לא קרתה.
  Future<void> launchOtzaria() async {
    final error = await _otzaria.launch();
    if (error != null && isActive) {
      UiSnack.showError(error.split('\n').first);
    }
  }

  Future<bool> _refreshStaleOnlineChecks(AppSettings s) async {
    final stale = StaleOnlineChecks.of(
      s,
      app: OnlineCheckStamp(
        checkedAt: _otzaria.onlineCheckedAt,
        error: _otzaria.onlineCheckError,
      ),
      library: OnlineCheckStamp(
        checkedAt: _library.onlineCheckedAt,
        error: _library.onlineCheckError,
      ),
      catalog: OnlineCheckStamp(
        checkedAt: _plugins.onlineCheckedAt,
        error: _plugins.onlineCheckError,
      ),
      storeApp: OnlineCheckStamp(
        checkedAt: _plugins.storeAppCheckedAt,
        error: _plugins.storeAppCheckError,
      ),
    );
    if (!stale.any) return false;
    final ownsCheckingFlag = !_isCheckingOnline;
    if (ownsCheckingFlag) _update(() => _isCheckingOnline = true);
    try {
      await Future.wait([
        if (stale.app) _otzaria.checkOnline(),
        if (stale.library) _library.checkOnline(),
        if (stale.plugins) _plugins.checkOnline(),
      ]);
    } finally {
      if (ownsCheckingFlag && isActive) {
        _update(() => _isCheckingOnline = false);
      }
    }
    return true;
  }

  Future<DownloadRollback> _captureDownloadRollback() =>
      CancelledDownloadRollback.capture(
        otzaria: _otzaria,
        library: _library,
        plugins: _plugins,
        mirrorDirs: downloadMirrorDirs,
      );

  void _rebuild() {
    if (!isActive) return;
    _syncSleepInhibition();
    notifyListeners();
    _offers.resume();
  }

  Future<void> _sweepMirrorJunk() async {
    final freed = await MirrorJunkSweeper(dataDir: dataDir).sweep();
    if (freed > 0) {
      AppLogger.instance.info('ניקוי המראה פינה ${formatBytes(freed)}');
    }
  }

  /// מציע ומוסר לאוצריא את בקשת עדכון אינדקס החיפוש. הסימון נמחק רק אחרי
  /// מסירה מוצלחת — סירוב או כשל משאירים אותו, וההצעה תחזור.
  Future<void> requestLibraryReindex() async {
    if (!_library.hasPendingReindex || !isActive) return;

    final approved = await prompts.confirmLibraryReindex();
    if (!approved) return;
    await deliverLibraryReindex();
  }

  /// מוסר את הבקשה בלי לשאול — הלחיצה במסך הסיום היא האישור.
  Future<void> deliverLibraryReindex() async {
    if (!_library.hasPendingReindex || !isActive) return;
    final t = AppL10n.strings.libraryScreen;
    if (await _otzaria.requestLibraryReindex()) {
      await _library.markReindexRequestDelivered();
      UiSnack.showSuccess(t.reindexRequestedSnack);
      return;
    }
    UiSnack.showError(t.reindexFailedSnack(_otzaria.errorMessage ?? ''));
  }

  Future<void> openLogFolder() async {
    final logger = AppLogger.instance;
    if (await FileReveal.revealDirectory(logger.logDir)) return;
    UiSnack.show(AppL10n.strings.shell.logPathFallback(logger.filePath));
  }

  /// אישורי התוכנות הנוספות נשמרים במחשב, לעולם לא על הכונן.
  static String? _customAppsTrustFile() {
    final dir = AppPaths.machineStateDir(
      Platform.environment,
      isWindows: Platform.isWindows,
      isMacOS: Platform.isMacOS,
    );
    return dir == null ? null : p.join(dir, 'custom_apps_trust.json');
  }

  /// "בדוק עכשיו" ו"בדוק שוב" בבית: הכונן והמחשב, ואז האתר. בכונן מוגן —
  /// רק הבדיקה המקומית. `checkAll` כולל את ההתקנה האוטומטית, אם היא דלוקה.
  Future<void> checkNow() async {
    if (checkNowBlocked || isCheckingNow || !isActive) return;
    await _asCheck(() async {
      await checkAll();
      if (!isActive || readOnly) return;
      _library.forgetDownloadFailures();
      await checkOnline();
    });
    // "בדוק עכשיו" שנכשל ברשת מוכיח מחשב לא מחובר — גם כשהבדיקה בעלייה כבויה.
    await registerPendingMachine();
  }

  Future<void> _asCheck(Future<void> Function() check) async {
    _update(() => _checkingNow = true);
    try {
      await check();
    } finally {
      if (isActive) _update(() => _checkingNow = false);
    }
  }

  /// Ctrl+R/F5: קורא מחדש מה מותקן ומה יש על הכונן, בלי ההצעות של העלייה.
  Future<void> refreshFromKeyboard() async {
    // לא `longTaskRunning` עצמו: `isBlocked` של ההורדה נשען עליו, והיה
    // עוצר את ההורדה של המשימה עצמה.
    if (longTaskRunning || tasks.isRunning) return;
    await _launcherFlow.checkMirror();
    if (!isActive) return;
    await _otzaria.checkForUpdate();
    if (!isActive) return;
    unawaited(_plugins.refreshInstalled());
    await _library.checkForUpdate();
    _markChecked();
  }
}

class _SessionDownloadHost implements MirrorDownloadHost {
  _SessionDownloadHost(this._session);

  final AppSession _session;

  @override
  bool get isActive => _session.isActive;

  @override
  bool get isBlocked =>
      _session.longTaskRunning || _session._launcherUpdate.isDownloading;

  @override
  bool get launcherDownloading => _session._launcherUpdate.isDownloading;

  @override
  AppSettings get settings => _session.settings.settings;

  @override
  Future<bool> refreshStaleOnlineChecks(AppSettings s) =>
      _session._refreshStaleOnlineChecks(s);

  @override
  Future<SemanticSearchAnswer?> confirmSemanticSearch() async {
    final answer = await _session.tasks.askBeforeDownload();
    if (answer != null && answer.remember && _session.isActive) {
      final settings = _session.settings;
      unawaited(settings.update(
        settings.settings.copyWith(
          semanticDownload: answer.download
              ? SemanticDownloadPreference.always
              : SemanticDownloadPreference.never,
        ),
      ));
    }
    return answer;
  }

  @override
  Future<DownloadRollback> captureRollback() =>
      _session._captureDownloadRollback();

  @override
  Future<void> sweepMirror() => _session._sweepMirrorJunk();

  @override
  void stateChanged() {
    final flow = _session._downloads;
    if (flow.isDownloading) {
      _session.tasks.downloadRunning(
        flow.activeComponents,
        expectedBytes: _session.expectedDownloadBytes,
      );
    }
    _session._rebuild();
  }

  @override
  void downloadSnapshotFailed(Object error) {
    AppLogger.instance.info('mirror snapshot failed: $error');
    _session.tasks.downloadFailed(
      DownloadFailure(DownloadFailureKind.snapshot, details: '$error'),
    );
  }

  @override
  void downloadCancelled({
    Object? revertError,
    List<MirrorComponent> kept = const [],
  }) {
    if (revertError != null) {
      AppLogger.instance
          .info('revert after cancelled download failed: $revertError');
    }
    _session.tasks.downloadCancelled(
      revertFailed: revertError != null,
      kept: kept,
    );
  }

  @override
  void downloadEnded() {}

  @override
  void downloadFoundNothing({required bool rechecked}) =>
      _session._update(() => _session._foundNothing =
          rechecked ? FoundNothing.rechecked : FoundNothing.earlierCheck);

  @override
  void downloadCrashed(
    Object error,
    StackTrace stackTrace, {
    bool abandoned = false,
  }) {
    AppLogger.instance.error('ההורדה נעצרה בחריג', error, stackTrace);
    final task = _session.tasks.current;
    if (abandoned ||
        task is! DownloadTask ||
        task.isFinished ||
        task.phase == DownloadTaskPhase.question) {
      return;
    }
    _session.tasks.downloadFailed(
      DownloadFailure(DownloadFailureKind.other, details: '$error'),
    );
  }

  @override
  void downloadFinished({
    required List<MirrorComponent> failed,
    required List<MirrorComponent> skipped,
  }) {
    final s = _session;
    final task = s.tasks.current;
    final libraryRan = task is DownloadTask &&
        task.components.contains(MirrorComponent.library) &&
        !skipped.contains(MirrorComponent.library);
    final notes = libraryRan ? s._library.downloadNotes : const <String>[];
    if (failed.isEmpty) {
      s.tasks.downloadDone(skipped: skipped, notes: notes);
    } else if (failed.length == 1 &&
        failed.single == MirrorComponent.library &&
        s._library.downloadNeedsOtzariaInstaller) {
      s.tasks.downloadFailed(DownloadFailure(
        DownloadFailureKind.libraryInstaller,
        components: failed,
      ));
    } else {
      s.tasks.downloadFailed(
          classifyDownloadFailure(
            failed: failed,
            errors: {
              MirrorComponent.app: s._otzaria.downloadError,
              MirrorComponent.library: s._library.downloadError,
              MirrorComponent.plugins:
                  s._plugins.errorMessage ?? s._plugins.shabbatNotice,
            },
            causes: {
              MirrorComponent.app: s._otzaria.downloadCause,
              MirrorComponent.library: s._library.downloadCause,
              MirrorComponent.plugins:
                  s._plugins.syncCause ?? s._plugins.storeAppCause,
            },
            shabbat: s._plugins.shabbatNotice != null,
          ),
          notes: notes);
    }
  }
}

class _SessionUpdateHost implements UpdateHereHost {
  _SessionUpdateHost(this._session);

  final AppSession _session;

  @override
  bool get isActive => _session.isActive;

  @override
  ShellTasks get tasks => _session.tasks;

  @override
  Future<bool> isOtzariaRunning() => _session.refreshProcessState();

  @override
  Future<bool> closeOtzaria() => _session.closeOtzaria();

  @override
  void closeFailed() =>
      UiSnack.showError(AppL10n.strings.common.closeOtzariaFailedSnack);

  @override
  Future<bool> semanticConsentUnanswered() async {
    await _session.loadSemanticConsentAnswer();
    return _session.semanticConsentUnanswered;
  }

  @override
  Future<bool?> askSemanticConsent() =>
      _session.prompts.askSemanticConsentBeforeUpdate();

  @override
  Future<void> declineSemanticConsent() =>
      _session._recordSemanticConsentAnswer();

  @override
  Future<String?> grantSemanticConsent() =>
      _session._writeSemanticConsent(snack: false);
}

class _SessionLauncherHost implements LauncherUpdateHost {
  _SessionLauncherHost(this._session);

  final AppSession _session;

  @override
  bool get isActive => _session.isActive;

  @override
  bool get isReadOnly => _session.readOnly;

  @override
  bool blockedByReadOnly() => _session._blockedByReadOnly();

  @override
  bool get wouldInterrupt => _session.exitWouldInterrupt;

  @override
  Future<void> settleBackgroundWork() => _session._searchFeedback.stopAndWait();

  @override
  Future<bool> confirmInstall(String version) =>
      _session._confirmLauncherInstall(version);

  @override
  void notify(LauncherUpdateNotice notice, {String? detail}) =>
      _session.prompts.notifyLauncherUpdate(notice, detail ?? '');
}

import 'dart:async';
import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:library_manager/library_manager.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;

import '../app_report/launcher_crash_session.dart';
import '../controllers/app_reports_controller.dart';
import '../controllers/auto_install_flow.dart';
import '../controllers/custom_apps_controller.dart';
import '../controllers/download_plan.dart';
import '../controllers/download_summary.dart';
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
import '../services/app_logger.dart';
import '../services/app_paths.dart';
import '../services/byte_size.dart';
import '../services/dialog_queue.dart';
import '../services/elevation.dart';
import '../services/file_reveal.dart';
import '../services/mirror_junk_sweeper.dart';
import '../services/notices_seen_store.dart';
import '../services/report_offer_coordinator.dart';
import '../settings/app_settings.dart';
import '../settings/safer_mode.dart';
import '../settings/settings_controller.dart';
import '../theme/theme_exports.dart';
import '../widgets/widgets_exports.dart';
import 'app_report/crash_prompt_dialog.dart';
import 'custom_apps/custom_apps_screen.dart';
import 'error_reports_flow.dart';
import 'faq/faq_floating_button.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'otzaria_screen.dart';
import 'plugins/plugins_screen.dart';
import 'reports_upload_flow.dart';
import 'search_feedback_flow.dart';
import 'settings_screen.dart';

/// המסך הפעיל בסרגל הניווט. "תוכנה" קודם ל"ספרייה" — ראו [_NavRail].
///
/// [customApps] הוא היחיד שאינו תמיד בסרגל: הוא מופיע רק אחרי שהמשתמש
/// הוסיף תוכנה משלו. מי שלא עושה זאת רואה בדיוק את הסרגל שהיה כאן קודם.
enum LauncherScreen { home, otzaria, library, plugins, customApps, settings }

/// מסגרת האפליקציה: שורת כותרת מותאמת למעלה, סרגל ניווט קבוע בצד, וחמשת
/// המסכים. שלושתם נצבעים באותו רקע לוח — בלי תפר ביניהם.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.dataDir,
    required this.settings,
    String? stateDir,
    this.readOnly = false,
    this.driveFull = false,
    this.runningLocator = const RunningOtzariaLocator(),
    this.showWindowButtons,
    this.noticesStore,
    this.appReports,
  }) : _stateDir = stateDir;

  /// התיקייה שלצד התוכנה — המראה, כלומר המקור שממנו קוראים ומתקינים.
  final String dataDir;

  final String? _stateDir;

  /// לאן נכתבים לוג, הגדרות ומצב. זהה ל-[dataDir] בהרצה רגילה — ראו
  /// [AppPaths.stateDir].
  String get stateDir => _stateDir ?? dataDir;

  /// קובצי המצב יושבים בתיקיית הלוגים — ראו [AppPaths.stateFilesDir].
  String get stateFilesDir => p.join(stateDir, AppPaths.logsDirName);

  final bool readOnly;
  final bool driveFull;

  final SettingsController settings;

  /// בדיקת "אוצריא פתוחה?" — מוזרקת כדי שבדיקות widget לא יריצו בדיקה
  /// אמיתית ב-isolate, שמשאירה טיימר תלוי ומפילה את הבדיקה.
  final RunningOtzariaLocator runningLocator;

  /// ראו [AppTitleBar.showWindowButtons] — מוזרק `false` בבדיקות widget.
  final bool? showWindowButtons;

  /// "אילו הודעות הוצגו". מוזרק בבדיקות: קריאת דיסק אמיתית אינה מסתיימת
  /// בתוך ה-fake-async, ובלי זה הודעה יכולה לצוץ באמצע בדיקה שאינה שלה.
  final NoticesSeenStore? noticesStore;

  /// הדיווחים של הלאנצ'ר על עצמו — נוצר ב-`main`, ו-`null` בבדיקות: הוא
  /// מפעיל טיימר שליחה ופונה לרשת.
  final AppReportsController? appReports;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final OtzariaModuleController _otzaria;
  late final LibraryModuleController _library;
  late final PluginsModuleController _plugins;

  /// "התוסף הותקן בהצלחה" — נשלח מהקונטרולר כשהסריקה זיהתה שאוצריא סיימה.
  late final StreamSubscription<String> _installDone;
  late final StreamSubscription<Object?> _installRejected;

  /// תוכנות שהמשתמש הוסיף בעצמו. אינו מודול כמו השלושה: הוא לא נבדק
  /// ב-[checkAll], אין לו הורדה מהרשת, והוא נעלם לגמרי כשאין בו כלום.
  late final CustomAppsController _customApps;

  /// עדכון הלאנצ'ר **עצמו** — נפרד משלושת המודולים: הוא לא מתקין כלום במחשב,
  /// אלא מחליף את קובץ ההרצה שלנו ומפעיל אותו מחדש.
  late final LauncherUpdateController _launcherUpdate;

  /// ההתאמות שהמשתמש עשה להדרכת השאלות הנפוצות. אינו מודול: אין לו בדיקה,
  /// אין לו הורדה, והוא נטען פעם אחת בעלייה.
  late final FaqController _faq;

  /// דיווחי טעויות של אוצריא: איסוף לכונן בעלייה, והעלאה מכרטיס ההורדות.
  late final ErrorReportsController _errorReports;
  late final SearchFeedbackController _searchFeedback;

  late final NoticesSeenStore _notices =
      widget.noticesStore ?? NoticesSeenStore(widget.stateFilesDir);

  Future<void> _errorReportsIntro = Future<void>.value();

  /// ההצעה להוריד גרסה חדשה של הלאנצ'ר מוצגת **פעם אחת בהרצה**. הבדיקה הקלה
  /// יכולה לרוץ עוד פעמים (כפתור "בדיקת עדכונים"), ודיאלוג שקופץ בכל אחת מהן
  /// היה נדנוד.
  bool _askedAboutLauncherUpdate = false;

  /// "מה התחדש" כבר הוצג בדיאלוג ההצעה, ולכן דיאלוג ההתקנה שבא מיד אחריו
  /// לא חוזר עליו. נכבה בסוף הרצף, כדי שהתקנה ידנית מאוחרת תציג אותו.
  bool _whatsNewAlreadyShown = false;

  /// ההצעה להפעיל מחדש כמנהל — גם היא פעם אחת בהרצה, ראו
  /// [_maybeOfferElevation].
  bool _offeredElevation = false;

  bool _elevationPending = false;

  LauncherScreen _screen = LauncherScreen.home;

  /// שומר הסף של מצב הסייפר. חי לאורך ההרצה, ולכן אימות אחד מלווה גם את
  /// ההגדרות וגם את עריכת ההדרכה — ראו `SaferModeGate`.
  late final SaferModeGate _saferMode = SaferModeGate(widget.settings);

  /// **נגזר** מהקונטרולר ולא מועתק לשדה: העתק נשאר תקוע על "פתוחה" עד
  /// להפעלה מחדש של הלאנצ'ר, גם אחרי שאוצריא נסגרה ובדיקה חדשה כבר ידעה זאת.
  bool get _otzariaIsRunning => _otzaria.isRunning;

  static const Duration _runningPollInterval = Duration(seconds: 3);
  static const Duration _runningWatchSlice = Duration(minutes: 1);
  Timer? _runningPoll;
  Future<void>? _runningWatch;

  /// המסכים שנבנו בפועל. ה-[IndexedStack] בונה את *כל* ילדיו, ולכן בעבר גם
  /// חנות התוספים (רשת כרטיסים עם תמונה לכל תוסף) נבנתה ופענחה את כל
  /// התמונות עוד לפני שהמשתמש נכנס אליה — עלות ישירה בזמן העלייה וב-RAM.
  /// כאן כל מסך נבנה בכניסה הראשונה אליו, ומאותו רגע נשאר בעץ עם המצב שלו.
  final Set<LauncherScreen> _builtScreens = {LauncherScreen.home};

  bool _announcedPlugins = false;

  bool _isCheckingOnline = false;

  late final OtzariaModulePort _otzariaPort = OtzariaModulePort(_otzaria);
  late final LibraryModulePort _libraryPort = LibraryModulePort(_library);

  late final MirrorDownloadFlow _downloads = MirrorDownloadFlow(
    app: _otzariaPort,
    library: _libraryPort,
    plugins: PluginsModulePort(_plugins),
    host: _ShellDownloadHost(this),
  );

  late final LauncherUpdateFlow _launcherFlow = LauncherUpdateFlow(
    launcher: LauncherUpdatePort(_launcherUpdate),
    downloads: _downloads,
    host: _ShellLauncherHost(this),
  );

  late final AutoInstallFlow _autoInstall = AutoInstallFlow(
    library: _libraryPort,
    app: _otzariaPort,
    isOtzariaRunning: refreshProcessState,
    isDownloading: () => _downloads.isDownloading,
    exitPending: () => _exitPending,
    isActive: () => mounted,
  );

  late final ReportOfferCoordinator _offers = ReportOfferCoordinator(
    isTaskRunning: () => _exitWouldInterrupt || _downloads.isPreparing,
    isActive: () => mounted,
    prepare: _prepareOffer,
    runDialog: _dialogs.run,
    perform: _performOffer,
  );

  bool _uploadingReports = false;
  bool _reportsStopRequested = false;

  late final DialogQueue _dialogs = DialogQueue(
    isActive: () => mounted,
    isBlocked: () =>
        _exitPending || !(ModalRoute.of(context)?.isCurrent ?? true),
  );

  @override
  void initState() {
    super.initState();
    final s = widget.settings.settings;

    _otzaria = OtzariaModuleController(
      dataDir: widget.dataDir,
      stateDir: widget.stateFilesDir,
      preferPrerelease: s.preferAppPrerelease,
      runningLocator: widget.runningLocator,
      pendingLaunchUri: () async =>
          _library.hasPendingReindex ? OtzariaDeepLinks.libraryReindex : null,
      onLaunchUriDelivered: () => _library.markReindexRequestDelivered(),
      isLibraryApplying: () => _library.isApplying,
    )..addListener(_onChange);
    _library = LibraryModuleController(
      dataDir: widget.dataDir,
      stateDir: widget.stateFilesDir,
      otzariaLaunchPath: () async => _otzaria.launchPath,
      otzariaAppVersion: () async => _otzaria.currentVersion,
      mirroredOtzariaUpdate: () async =>
          _otzaria.status == OtzariaModuleStatus.updateAvailable
              ? _otzaria.latestVersion
              : null,
      instanceLock: const OtzariaInstanceLock(),
    )..addListener(_onChange);
    _plugins = PluginsModuleController(
      mirrorRootDir: p.join(widget.dataDir, 'mirror'),
      stateDir: widget.stateFilesDir,
      otzariaLaunchPath: () async => _otzaria.launchPath,
      locatePluginsDb: PluginsModuleController.locateOtzariaPluginsDb,
      mirroredAppVersions: () async => [
        if (_otzaria.stableVersion != null) _otzaria.stableVersion!,
        if (_otzaria.prereleaseVersion != null) _otzaria.prereleaseVersion!,
      ],
      installedAppVersion: () async =>
          _otzaria.currentVersion ?? _otzaria.latestVersion,
      ensureAppVersionsKnown: _otzaria.ensureChecked,
    )..addListener(_onChange);
    _installDone = _plugins.installCompletions.listen((name) {
      if (mounted) {
        UiSnack.showSuccess(AppL10n.strings.plugins.installDoneSnack(name));
      }
    });
    _installRejected = _plugins.installRejections.listen((entry) {
      if (!mounted) return;
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
      mirrorRootDir: p.join(widget.dataDir, 'mirror'),
      stateDir: widget.stateFilesDir,
      trustFilePath: _customAppsTrustFile(),
    )..addListener(_onChange);
    _launcherUpdate = LauncherUpdateController(dataDir: widget.dataDir)
      ..addListener(_onChange);
    _faq = FaqController(dataDir: widget.stateDir);
    unawaited(_faq.load());
    _errorReports = ErrorReportsController.forDrive(
      stateDir: widget.stateDir,
      dataDir: widget.dataDir,
      stateFilesDir: widget.stateFilesDir,
      launchPath: () async => _otzaria.launchPath,
    )..addListener(_onReportsChange);
    _searchFeedback = SearchFeedbackController.forDrive(
      dataDir: widget.dataDir,
      stateDir: widget.stateDir,
      stateFilesDir: widget.stateFilesDir,
      launchPath: () async => _otzaria.launchPath,
      runningLocator: widget.runningLocator,
    )..addListener(_onReportsChange);
    if (!widget.readOnly) unawaited(_searchFeedback.refreshOutbox());
    if (!widget.readOnly) unawaited(_errorReports.refreshOutbox());
    _errorReportsIntro = _showErrorReportsIntro();
    widget.settings.addListener(_onChange);
    _applySettings(s);

    unawaited(_plugins.load());
    unawaited(_customApps.load());
    if (s.autoCheckUpdates) {
      unawaited(checkAll());
    } else {
      unawaited(refreshProcessState());
      unawaited(_launcherFlow.checkMirror());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_otzaria.ensureChecked().then((_) => _offers.request()));
      });
    }
    if (widget.appReports case final reports?) {
      reports.stateProvider = _reportState;
      unawaited(_startReports(reports));
    }
    if (s.autoCheckUpdates) {
      unawaited(checkOnline());
    }
    LauncherCrashSession.closeGuard = _confirmClose;
  }

  @override
  void dispose() {
    if (LauncherCrashSession.closeGuard == _confirmClose) {
      LauncherCrashSession.closeGuard = null;
    }
    _dialogs.dispose();
    _runningPoll?.cancel();
    _offers.dispose();
    unawaited(_installDone.cancel());
    unawaited(_installRejected.cancel());
    widget.settings.removeListener(_onChange);
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
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    _offers.onRunningState(running: _otzariaIsRunning);
    _offers.resume();
    _applySettings(widget.settings.settings);
    _syncRunningPoll();
    setState(() {});
    unawaited(_maybeOfferElevation());
    unawaited(_maybeAnnouncePlugins());
  }

  void _onReportsChange() {
    if (!mounted) return;
    _offers.resume();
    unawaited(_maybeOfferElevation());
  }

  Future<void> _maybeAnnouncePlugins() async {
    if (_announcedPlugins || _plugins.status != PluginsModuleStatus.ready) {
      return;
    }
    _announcedPlugins = true;

    final fresh = _plugins.newPluginsForHome;
    final hasUpdates = _plugins.updatablePlugins.isNotEmpty;
    if (fresh.isEmpty && !hasUpdates) return;

    await WidgetsBinding.instance.endOfFrame;
    await _dialogs.run(() async {
      final t = context.strings.plugins;
      final message = hasUpdates && fresh.isNotEmpty
          ? t.homeNoticeUpdatesAndNew
          : hasUpdates
              ? t.homeNoticeUpdates
              : fresh.length == 1
                  ? t.homeNoticeNewOne
                  : t.homeNoticeNewMany(fresh.length);

      unawaited(_plugins.markHomeNotified(fresh));
      final open = await showTwoActionsDialog(
        context: context,
        title: t.homeNoticeTitle,
        content: message,
        cancelText: context.strings.common.close,
        confirmText: t.homeNoticeOpenButton,
      );
      if (open && mounted) await _goTo(LauncherScreen.plugins);
    });
  }

  Future<void> _showErrorReportsIntro() async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await _dialogs.run(
      () => showErrorReportsIntroOnce(
        context,
        _notices,
        readOnly: widget.readOnly,
        driveFull: widget.driveFull,
      ),
    );
  }

  /// מצב המודולים לאבחון הדיווח — בלי נתיבים ושמות קבצים של המשתמש.
  Map<String, dynamic> _reportState() {
    final s = widget.settings.settings;
    return {
      'readOnly': widget.readOnly,
      'otzaria': _otzaria.status.name,
      'otzariaRunning': _otzariaIsRunning,
      'library': _library.status.name,
      'plugins': _plugins.status.name,
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
    if (!mounted) return;
    reports.startBackground();
    await reports.runCrashCheck(
      showPrompt: (candidate) async {
        final shown = await _dialogs.run(
          () async {
            await showCrashPromptDialog(
              context,
              reports: reports,
              candidate: candidate,
              saferMode: _saferMode,
            );
            return true;
          },
          forever: true,
        );
        return shown ?? false;
      },
    );
  }

  Future<void> _maybeOfferElevation() async {
    if (_offeredElevation || !Platform.isWindows) return;
    if (!_library.needsElevation &&
        !_otzaria.needsElevation &&
        !_launcherUpdate.needsElevation) {
      return;
    }
    if (_exitWouldInterrupt) return;
    _offeredElevation = true;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    final t = AppL10n.strings.elevation;
    final approved = await _dialogs.run(
      () => showTwoActionsDialog(
        context: context,
        title: t.dialogTitle,
        content: t.dialogContent,
        cancelText: t.dialogCancel,
        confirmText: t.dialogConfirm,
      ),
    );
    if (approved == null) _offeredElevation = false;
    if (approved != true || !mounted) return;
    if (_exitWouldInterrupt) {
      _offeredElevation = false;
      UiSnack.show(t.busyNotice);
      return;
    }

    setState(() => _elevationPending = true);
    final Object? failure;
    try {
      failure = await Elevation.restartElevated();
    } finally {
      if (mounted) {
        setState(() => _elevationPending = false);
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
      while (mounted && _otzariaIsRunning) {
        final exited =
            await widget.runningLocator.waitForExit(_runningWatchSlice);
        if (!mounted) return;
        if (exited == null) {
          final elapsed = Completer<void>();
          _runningPoll = Timer(_runningPollInterval, elapsed.complete);
          await elapsed.future;
          if (!mounted) return;
        }
        await _otzaria.refreshRunningState();
      }
    } finally {
      _runningWatch = null;
    }
  }

  /// מזליג הגדרות שהקונטרולרים צריכים. הכול idempotent (הצבת ערך), ולכן אין
  /// צורך לעקוב אחרי שינוי בפועל.
  void _applySettings(AppSettings s) {
    // ה-setter מתעלם מהצבה חוזרת של אותו ערך, ולכן זה לא מריץ בדיקה בכל
    // שינוי הגדרה אחר.
    _otzaria.preferPrerelease = s.preferAppPrerelease;
    _library.personalUpdateMode = s.personalUpdateMode;
  }

  /// בדיקת תהליך עצמאית — לרענון יזום מהמסך, ובעיקר **מיד לפני** פעולה
  /// שאוצריא הפתוחה חוסמת. מחזירה את התוצאה הטרייה, כי `otzariaIsRunning`
  /// של המסכים הוא הערך שנלכד בבנייה — זה שבגללו נחסמו מלכתחילה.
  ///
  /// `force`: זו נקודת ההכרעה לפני פעולה חוסמת, ולכן אינה מסתפקת בתשובה של
  /// בדיקה שכבר הייתה באוויר. הרענון המחזורי, לעומת זאת, כן מצטרף.
  Future<bool> refreshProcessState() =>
      _otzaria.refreshRunningState(force: true);

  Future<bool> closeOtzaria() => _offers.holdFor(() async {
        final closed = await _otzaria.closeRunning();
        if (mounted) _syncRunningPoll();
        return closed;
      });

  bool _blockedByReadOnly() {
    if (!widget.readOnly) return false;
    final t = AppL10n.strings.readOnlyDrive;
    UiSnack.show(
      widget.driveFull
          ? t.downloadsDisabledSnackDriveFull
          : t.downloadsDisabledSnack,
    );
    return true;
  }

  Future<void> checkAll() async {
    await _launcherFlow.checkMirror();
    if (!mounted) return;

    await _otzaria.checkForUpdate();
    if (!mounted) return;
    unawaited(_plugins.refreshInstalled());

    await _library.checkForUpdate();
    if (!mounted) return;
    await _autoInstallIfEnabled();
    if (!mounted) return;
    await _offers.request();
  }

  Future<bool> _prepareOffer() async {
    await WidgetsBinding.instance.endOfFrame;
    await _errorReportsIntro;
    return mounted && _otzaria.launchPath != null;
  }

  Future<void> _performOffer() async {
    await offerErrorReportCollection(
      context,
      _errorReports,
      readOnly: widget.readOnly,
      isOtzariaRunning: refreshProcessState,
      notices: _notices,
    );
    if (!mounted) return;
    await offerSearchFeedbackCollection(
      context,
      _searchFeedback,
      readOnly: widget.readOnly,
    );
  }

  Future<void> _grantSemanticConsent() async {
    if (await refreshProcessState()) {
      UiSnack.showError(AppL10n.strings.home.otzariaOpenSnack);
      return;
    }
    if (!mounted) return;
    final t = context.strings.libraryDomain;
    final agreed = await showTwoActionsDialog(
      context: context,
      title: t.semanticConsentTitle,
      content: t.semanticConsentText,
      confirmText: t.semanticConsentConfirm,
    );
    if (!agreed || !mounted) return;
    try {
      if (!await _searchFeedback.grantConsent()) {
        UiSnack.showError(t.semanticConsentRequired);
        return;
      }
      await _library.checkForUpdate();
    } catch (error, stack) {
      AppLogger.instance.error('כתיבת ההסכמה לחיפוש החכם נכשלה', error, stack);
      UiSnack.showError(t.semanticFeedbackFailed);
    }
  }

  Future<void> _uploadReports() => _offers.guardedUpload(
        blocked: () => _blockedByReadOnly() || !mounted,
        run: (onActive) => uploadAllReports(
          context,
          errorReports: _errorReports,
          searchFeedback: _searchFeedback,
          isCancelled: () => _reportsStopRequested,
          onActiveChanged: onActive,
          onUploadingChanged: (uploading) {
            if (!mounted) return;
            if (uploading) _reportsStopRequested = false;
            setState(() => _uploadingReports = uploading);
            _offers.resume();
          },
        ),
      );

  Future<void> checkOnline() async {
    if (widget.readOnly || _isCheckingOnline) return;
    setState(() => _isCheckingOnline = true);
    await _launcherFlow.checkMirror();
    if (!mounted) return;
    await Future.wait([
      _otzaria.checkOnline(),
      _library.checkOnline(),
      _plugins.checkOnline(),
      _launcherUpdate.checkOnline(),
    ]);
    if (!mounted) return;
    setState(() => _isCheckingOnline = false);
    await _promptLauncherUpdate();
  }

  Future<void> _promptLauncherUpdate() async {
    if (!mounted || widget.readOnly) return;
    final c = _launcherUpdate;
    final release = c.onlineRelease;
    if (release == null || !c.hasOnlineUpdate) return;
    if (_askedAboutLauncherUpdate || c.isDownloading) return;
    _askedAboutLauncherUpdate = true;

    final t = context.strings.launcherUpdate;
    final whatsNew = c.onlineWhatsNew;
    final approved = await _dialogs.run(
      () => showTwoActionsDialog(
        context: context,
        title: t.availableDialogTitle,
        content: '${t.availableDialogContent(release.version)}\n\n'
            '${t.availableDialogDetail(formatBytes(release.sizeBytes))}',
        customContent: whatsNew == null
            ? null
            : WhatsNewSection(heading: t.whatsNewHeading, markdown: whatsNew),
        cancelText: t.availableDialogCancel,
        confirmText: t.availableDialogConfirm,
      ),
    );
    if (approved == null) _askedAboutLauncherUpdate = false;
    if (approved != true || !mounted) return;
    _whatsNewAlreadyShown = whatsNew != null;
    try {
      await downloadLauncherUpdate();
    } finally {
      _whatsNewAlreadyShown = false;
    }
  }

  Future<void> downloadLauncherUpdate() => _launcherFlow.download();

  bool get _longTaskRunning =>
      _downloads.isDownloading ||
      _library.isApplying ||
      _library.status == LibraryModuleStatus.updating ||
      _otzaria.status == OtzariaModuleStatus.installing ||
      _customApps.isBusy ||
      _customApps.isLearning ||
      _customApps.isDownloadingAll ||
      _plugins.isExporting ||
      _plugins.isSyncing ||
      _exitPending;

  bool get _pluginSyncBlockedElsewhere =>
      _downloads.isDownloading ||
      _library.isApplying ||
      _library.status == LibraryModuleStatus.updating ||
      _otzaria.status == OtzariaModuleStatus.installing ||
      _customApps.isBusy;

  bool get _exitPending => _elevationPending || _launcherUpdate.isInstalling;

  bool get _exitWouldInterrupt =>
      _longTaskRunning ||
      _errorReports.isCollecting ||
      _errorReports.isUploading ||
      _searchFeedback.isCollecting ||
      _searchFeedback.isUploading ||
      _uploadingReports;

  Future<void> installLauncherUpdate() => _launcherFlow.install();

  Future<bool> _confirmLauncherInstall(String version) {
    final t = context.strings.launcherUpdate;
    final whatsNew =
        _whatsNewAlreadyShown ? null : _launcherUpdate.downloadedWhatsNew;
    return showTwoActionsDialog(
      context: context,
      title: t.readyDialogTitle,
      content: t.readyDialogContent(version),
      customContent: whatsNew == null
          ? null
          : WhatsNewSection(heading: t.whatsNewHeading, markdown: whatsNew),
      confirmText: t.readyDialogConfirm,
    );
  }

  void _notifyLauncherUpdate(LauncherUpdateNotice notice, String detail) {
    final t = AppL10n.strings.launcherUpdate;
    switch (notice) {
      case LauncherUpdateNotice.downloaded:
        UiSnack.showSuccess(t.downloadedSnack(detail));
      case LauncherUpdateNotice.busy:
        UiSnack.show(t.busyNotice);
      case LauncherUpdateNotice.installing:
        UiSnack.show(t.installingSnack);
      case LauncherUpdateNotice.installFailed:
        UiSnack.showError(detail);
      case LauncherUpdateNotice.manualRestart:
        UiSnack.show(t.manualRestartNotice);
    }
  }

  Future<void> _autoInstallIfEnabled() async {
    final skippedWhileRunning = await _autoInstall.run(
      enabled: widget.settings.settings.autoInstall,
    );
    if (!skippedWhileRunning || !mounted) return;
    final t = context.strings.home;
    await showSingleActionDialog(
      context: context,
      title: t.autoInstallSkippedTitle,
      content: t.autoInstallSkippedContent,
    );
  }

  @visibleForTesting
  List<String> get downloadMirrorDirs => [
        _library.mirrorDir,
        _library.companionsMirrorDir,
        _library.semanticMirrorDir,
        _otzaria.mirrorDir,
        ..._plugins.mirrorDirs,
      ];

  Future<void> cancelDownload() async {
    if (!_downloads.isDownloading || _downloads.isCancelling || !mounted) {
      return;
    }

    final t = context.strings.home;
    final approved = await showWarningDialog(
      context: context,
      title: t.cancelDownloadDialogTitle,
      content: t.cancelDownloadPrompt,
      cancelText: t.cancelDownloadKeepGoing,
      confirmText: t.cancelDownloadButton,
    );
    if (!approved || !mounted || !_downloads.isDownloading) return;
    _downloads.requestCancel();
  }

  Future<bool> _confirmClose() async {
    if (!mounted || !_longTaskRunning) return true;
    final t = context.strings.shell;
    final downloading = _downloads.isDownloading;
    final approved = await showWarningDialog(
      context: context,
      title: t.closeWhileBusyTitle,
      content: downloading
          ? t.closeWhileDownloadingPrompt
          : t.closeWhileInstallingPrompt,
      cancelText: t.closeWhileBusyKeepGoing,
      confirmText: downloading
          ? t.closeWhileDownloadingConfirm
          : t.closeWhileInstallingConfirm,
    );
    if (!approved) return false;
    if (!mounted) return true;
    await _downloads.cancelAndWait();
    return true;
  }

  Future<void> downloadAll() async {
    if (_blockedByReadOnly()) return;
    await _downloads.downloadAll();
  }

  Future<void> _refreshStaleOnlineChecks(AppSettings s) async {
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
    if (!stale.any) return;
    final ownsCheckingFlag = !_isCheckingOnline;
    if (ownsCheckingFlag) setState(() => _isCheckingOnline = true);
    try {
      await Future.wait([
        if (stale.app) _otzaria.checkOnline(),
        if (stale.library) _library.checkOnline(),
        if (stale.plugins) _plugins.checkOnline(),
      ]);
    } finally {
      if (ownsCheckingFlag && mounted) {
        setState(() => _isCheckingOnline = false);
      }
    }
  }

  Future<bool> _confirmSemanticSearch() => showTwoActionsDialog(
        context: context,
        title: context.strings.libraryDomain.companionSemanticName,
        content: context.strings.libraryDomain.semanticDownloadPrompt,
        confirmText: context.strings.home.downloadNowButton,
      );

  Future<DownloadRollback> _captureDownloadRollback() =>
      CancelledDownloadRollback.capture(
        otzaria: _otzaria,
        library: _library,
        plugins: _plugins,
        mirrorDirs: downloadMirrorDirs,
      );

  void _rebuild() {
    if (!mounted) return;
    setState(() {});
    _offers.resume();
  }

  void _reportDownload({
    required List<MirrorComponent> failed,
    required List<MirrorComponent> skipped,
  }) {
    final t = context.strings;
    String label(MirrorComponent component) => switch (component) {
          MirrorComponent.app => t.home.appTileTitle,
          MirrorComponent.library => t.home.libraryTileTitle,
          MirrorComponent.plugins => t.shell.navPlugins,
        };
    final failedLabels = [for (final c in failed) label(c)];
    final skippedLabels = [for (final c in skipped) label(c)];

    switch (summarizeDownload(failed: failedLabels, skipped: skippedLabels)) {
      case DownloadSummary.failed:
        UiSnack.show(t.home.downloadFailedSnack(failedLabels.join(', ')));
      case DownloadSummary.skipped:
        UiSnack.show(t.home.downloadSkippedSnack(skippedLabels.join(', ')));
      case DownloadSummary.done:
        UiSnack.showSuccess(t.home.downloadDoneSnack);
    }
  }

  Future<void> _sweepMirrorJunk() async {
    final freed = await MirrorJunkSweeper(dataDir: widget.dataDir).sweep();
    if (freed > 0) {
      AppLogger.instance.info('ניקוי המראה פינה ${formatBytes(freed)}');
    }
  }

  /// מציע ומוסר לאוצריא את בקשת עדכון אינדקס החיפוש — הפעולה היזומה, כשלא
  /// מחכים להפעלה הבאה של אוצריא. הדיאלוג יושב כאן ולא במסכים, כי גם מסך
  /// הבית וגם מסך הספרייה מציעים אותה מיד אחרי עדכון מסד.
  ///
  /// הסימון נמחק רק אחרי מסירה מוצלחת: סירוב או כשל משאירים אותו, וההצעה
  /// תחזור.
  Future<void> requestLibraryReindex() async {
    if (!_library.hasPendingReindex || !mounted) return;

    final t = context.strings.libraryScreen;
    final approved = await showTwoActionsDialog(
      context: context,
      title: t.reindexDialogTitle,
      content: t.reindexDialogContent,
      confirmText: t.reindexDialogConfirm,
    );
    if (!approved) return;

    if (await _otzaria.requestLibraryReindex()) {
      await _library.markReindexRequestDelivered();
      UiSnack.showSuccess(t.reindexRequestedSnack);
      return;
    }
    UiSnack.showError(t.reindexFailedSnack(_otzaria.errorMessage ?? ''));
  }

  Future<void> _openLogFolder() async {
    final logger = AppLogger.instance;
    if (await FileReveal.revealDirectory(logger.logDir)) return;
    UiSnack.show(AppL10n.strings.shell.logPathFallback(logger.filePath));
  }

  /// ניווט למסך. הכניסה להגדרות עוברת בשומר הסף של מצב הסייפר — כאן ולא
  /// בתוך המסך עצמו: ה-[IndexedStack] משאיר כל מסך שנבנה בעץ עד הסגירה,
  /// ולכן שער שיושב בתוך המסך היה נפתח פעם אחת ונשאר פתוח.
  Future<void> _goTo(LauncherScreen screen) async {
    if (screen == LauncherScreen.settings && _saferMode.isLocked) {
      final unlocked = await showSaferModePasswordDialog(
        context,
        storedPassword: widget.settings.settings.saferModePassword,
        hint: context.strings.saferMode.verifySettingsHint,
      );
      if (!unlocked || !mounted) return;
      _saferMode.unlock();
    }
    setState(() {
      _screen = screen;
      _builtScreens.add(screen);
    });
  }

  Widget _screenWidget(LauncherScreen screen) => switch (screen) {
        LauncherScreen.home => HomeScreen(
            otzaria: _otzaria,
            library: _library,
            plugins: _plugins,
            launcherUpdate: _launcherUpdate,
            settings: widget.settings,
            otzariaIsRunning: _otzariaIsRunning,
            isDownloading: _downloads.isDownloading,
            isCancellingDownload: _downloads.isCancelling,
            isCheckingOnline: _isCheckingOnline,
            longTaskRunning: _longTaskRunning,
            onProcessStateChanged: refreshProcessState,
            onCloseOtzaria: closeOtzaria,
            onCheckOnline: checkOnline,
            onDownloadAll: downloadAll,
            onCancelDownload: cancelDownload,
            onDownloadLauncherUpdate: downloadLauncherUpdate,
            onInstallLauncherUpdate: installLauncherUpdate,
            onRequestReindex: requestLibraryReindex,
            onGoToOtzaria: () => _goTo(LauncherScreen.otzaria),
            onGoToLibrary: () => _goTo(LauncherScreen.library),
            readOnly: widget.readOnly,
            driveFull: widget.driveFull,
            errorReports: _errorReports,
            searchFeedback: _searchFeedback,
            isUploadingReports: _uploadingReports,
            onUploadReports: _uploadReports,
            onStopReports: () => _reportsStopRequested = true,
          ),
        LauncherScreen.otzaria => OtzariaScreen(
            otzaria: _otzaria,
            settings: widget.settings,
            otzariaIsRunning: _otzariaIsRunning,
            onCloseOtzaria: closeOtzaria,
            onInstallAdopted: _plugins.refreshInstalled,
            saferMode: _saferMode,
          ),
        LauncherScreen.customApps => CustomAppsScreen(
            controller: _customApps,
            readOnly: widget.readOnly,
          ),
        LauncherScreen.library => LibraryScreen(
            library: _library,
            otzariaIsRunning: _otzariaIsRunning,
            isDownloading: _downloads.isDownloading,
            onProcessStateChanged: refreshProcessState,
            onCloseOtzaria: closeOtzaria,
            onRequestReindex: requestLibraryReindex,
            onGoToSettings: () => _goTo(LauncherScreen.settings),
            onGrantSemanticConsent: _grantSemanticConsent,
          ),
        LauncherScreen.plugins => PluginsScreen(
            controller: _plugins,
            onRequestFocus: () => _goTo(LauncherScreen.plugins),
            readOnly: widget.readOnly,
            driveFull: widget.driveFull,
            busyElsewhere: _pluginSyncBlockedElsewhere,
          ),
        LauncherScreen.settings => SettingsScreen(
            controller: widget.settings,
            onOpenLog: _openLogFolder,
            launcherVersion: _launcherUpdate.currentVersion,
            saferMode: _saferMode,
            customApps: _customApps,
            readOnly: widget.readOnly,
            driveFull: widget.driveFull,
            appReports: widget.appReports,
          ),
      };

  /// אישורי התוכנות הנוספות נשמרים במחשב, לעולם לא על הכונן.
  static String? _customAppsTrustFile() {
    final dir = AppPaths.machineStateDir(
      Platform.environment,
      isWindows: Platform.isWindows,
      isMacOS: Platform.isMacOS,
    );
    return dir == null ? null : p.join(dir, 'custom_apps_trust.json');
  }

  /// Ctrl+R/F5: קורא מחדש מה מותקן ומה יש על הכונן, בלי ההצעות של העלייה.
  /// לא פועל בזמן משימה ארוכה.
  Future<void> _refreshFromKeyboard() async {
    if (_longTaskRunning) return;
    await _launcherFlow.checkMirror();
    if (!mounted) return;
    await _otzaria.checkForUpdate();
    if (!mounted) return;
    unawaited(_plugins.refreshInstalled());
    await _library.checkForUpdate();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): () =>
            unawaited(_refreshFromKeyboard()),
        const SingleActivator(LogicalKeyboardKey.f5): () =>
            unawaited(_refreshFromKeyboard()),
      },
      child: Focus(autofocus: true, child: _scaffold(context)),
    );
  }

  Widget _scaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: AppSurfaces.panelBackground(context),
      // שורת הכותרת נפרסת על כל הרוחב — מעל סרגל הניווט ולא לצידו — כך שגרירת
      // החלון אפשרית לכל רוחב החלון (כמו באוצריא).
      body: Column(
        children: [
          AppTitleBar(
            screenTitle: _screenLabel(context, _screen),
            showWindowButtons: widget.showWindowButtons,
          ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                AbsorbPointer(
                  absorbing: _exitPending,
                  child: ExcludeFocus(
                    excluding: _exitPending,
                    child: _shellRow(context),
                  ),
                ),
                if (widget.settings.settings.showFaqButton)
                  PositionedDirectional(
                    end: AppTokens.spaceMD,
                    bottom: AppTokens.spaceMD,
                    // `Offstage` ולא בנייה מותנית: הכפתור מוצג בדף הבית בלבד,
                    // אבל ה-state שלו חייב לשרוד ניווט — אחרת ההבהוב והבועה
                    // החד-פעמיים היו חוזרים בכל חזרה לדף הבית.
                    child: Offstage(
                      offstage: _screen != LauncherScreen.home,
                      child: FaqFloatingButton(
                        faq: _faq,
                        saferMode: _saferMode,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _shellRow(BuildContext context) => Row(
        children: [
          _NavRail(
            current: _screen,
            onSelect: _goTo,
            showCustomApps: _customApps.hasApps,
          ),
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: AppSurfaces.shellDivider(context),
          ),
          Expanded(
            child: IndexedStack(
              index: _screen.index,
              children: [
                for (final screen in LauncherScreen.values)
                  _builtScreens.contains(screen)
                      ? TickerMode(
                          enabled: screen == _screen,
                          child: _screenWidget(screen),
                        )
                      : const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      );
}

class _ShellDownloadHost implements MirrorDownloadHost {
  _ShellDownloadHost(this._shell);

  final _AppShellState _shell;

  @override
  bool get isActive => _shell.mounted;

  @override
  bool get isBlocked =>
      _shell._longTaskRunning || _shell._launcherUpdate.isDownloading;

  @override
  bool get launcherDownloading => _shell._launcherUpdate.isDownloading;

  @override
  AppSettings get settings => _shell.widget.settings.settings;

  @override
  Future<void> refreshStaleOnlineChecks(AppSettings s) =>
      _shell._refreshStaleOnlineChecks(s);

  @override
  Future<bool> confirmSemanticSearch() => _shell._confirmSemanticSearch();

  @override
  Future<DownloadRollback> captureRollback() =>
      _shell._captureDownloadRollback();

  @override
  Future<void> sweepMirror() => _shell._sweepMirrorJunk();

  @override
  void stateChanged() => _shell._rebuild();

  @override
  void downloadSnapshotFailed(Object error) {
    AppLogger.instance.info('mirror snapshot failed: $error');
    UiSnack.show(AppL10n.strings.home.downloadSnapshotFailedSnack);
  }

  @override
  void downloadCancelled({Object? revertError}) {
    if (revertError != null) {
      AppLogger.instance
          .info('revert after cancelled download failed: $revertError');
    }
    unawaited(_shell._maybeOfferElevation());
    UiSnack.show(
      revertError == null
          ? AppL10n.strings.home.downloadCancelledSnack
          : AppL10n.strings.home.downloadCancelRevertFailedSnack,
    );
  }

  @override
  void downloadEnded() => unawaited(_shell._maybeOfferElevation());

  @override
  void downloadFinished({
    required List<MirrorComponent> failed,
    required List<MirrorComponent> skipped,
  }) =>
      _shell._reportDownload(failed: failed, skipped: skipped);
}

class _ShellLauncherHost implements LauncherUpdateHost {
  _ShellLauncherHost(this._shell);

  final _AppShellState _shell;

  @override
  bool get isActive => _shell.mounted;

  @override
  bool get isReadOnly => _shell.widget.readOnly;

  @override
  bool blockedByReadOnly() => _shell._blockedByReadOnly();

  @override
  bool get wouldInterrupt => _shell._exitWouldInterrupt;

  @override
  Future<bool> confirmInstall(String version) =>
      _shell._confirmLauncherInstall(version);

  @override
  void notify(LauncherUpdateNotice notice, {String? detail}) =>
      _shell._notifyLauncherUpdate(notice, detail ?? '');
}

// ── סרגל הניווט ───────────────────────────────────────────────────────────────

/// שם המסך — אותה תווית בסרגל הניווט ובשורת הכותרת, כך שהשניים מדברים באותה
/// שפה. מקור אחד בכוונה: שני העתקים נטו להיפרד.
String _screenLabel(BuildContext context, LauncherScreen screen) {
  final s = context.strings.shell;
  return switch (screen) {
    LauncherScreen.home => s.navHome,
    LauncherScreen.otzaria => s.navApp,
    LauncherScreen.library => s.navLibrary,
    LauncherScreen.plugins => s.navPlugins,
    LauncherScreen.customApps => s.navCustomApps,
    LauncherScreen.settings => s.navSettings,
  };
}

class _NavRail extends StatelessWidget {
  final LauncherScreen current;
  final ValueChanged<LauncherScreen> onSelect;

  /// מוסיף את "תוכנות נוספות" לסרגל. מוצג רק כשיש בפועל תוכנה כזו —
  /// הכניסה הראשונה היא מההגדרות.
  final bool showCustomApps;

  const _NavRail({
    required this.current,
    required this.onSelect,
    required this.showCustomApps,
  });

  /// הסמל הרגיל והמלא לכל מסך. הפריטים עצמם נגזרים מ-[LauncherScreen.values]
  /// ולא נכתבים אחד-אחד, כך שמסך חדש אינו יכול להישאר בלי פריט בסרגל — הוא
  /// ייפול כאן על סמל חסר במקום להיעלם בשקט.
  static const Map<LauncherScreen, (IconData, IconData)> _icons = {
    LauncherScreen.home: (
      FluentIcons.home_24_regular,
      FluentIcons.home_24_filled,
    ),
    LauncherScreen.otzaria: (
      FluentIcons.desktop_24_regular,
      FluentIcons.desktop_24_filled,
    ),
    LauncherScreen.library: (
      FluentIcons.library_24_regular,
      FluentIcons.library_24_filled,
    ),
    LauncherScreen.plugins: (
      FluentIcons.puzzle_piece_24_regular,
      FluentIcons.puzzle_piece_24_filled,
    ),
    LauncherScreen.customApps: (
      FluentIcons.box_24_regular,
      FluentIcons.box_24_filled,
    ),
    LauncherScreen.settings: (
      FluentIcons.settings_24_regular,
      FluentIcons.settings_24_filled,
    ),
  };

  @override
  Widget build(BuildContext context) {
    NavRailItem item(LauncherScreen screen) {
      final (icon, iconFilled) = _icons[screen]!;
      return NavRailItem(
        icon: icon,
        iconFilled: iconFilled,
        label: _screenLabel(context, screen),
        isSelected: current == screen,
        onTap: () => onSelect(screen),
      );
    }

    return Container(
      width: NavRailItem.width,
      color: AppSurfaces.navRailBackground(context),
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSM),
      child: Column(
        children: [
          // ההגדרות נדחקות לתחתית; כל השאר בסדר ההכרזה של ה-enum.
          for (final screen in LauncherScreen.values)
            if (screen != LauncherScreen.settings &&
                (screen != LauncherScreen.customApps || showCustomApps))
              item(screen),
          const Spacer(),
          item(LauncherScreen.settings),
        ],
      ),
    );
  }
}

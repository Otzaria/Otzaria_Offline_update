import 'dart:async';
import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;

import '../app_report/launcher_crash_session.dart';
import '../controllers/app_reports_controller.dart';
import '../controllers/cancelled_download_refresh.dart';
import '../controllers/custom_apps_controller.dart';
import '../controllers/download_summary.dart';
import '../controllers/error_reports_controller.dart';
import '../controllers/faq_controller.dart';
import '../controllers/launcher_update_controller.dart';
import '../controllers/library_module_controller.dart';
import '../controllers/online_check.dart';
import '../controllers/otzaria_module_controller.dart';
import '../controllers/plugins_module_controller.dart';
import '../controllers/search_feedback_controller.dart';
import '../services/app_logger.dart';
import '../services/app_paths.dart';
import '../services/byte_size.dart';
import '../services/elevation.dart';
import '../services/file_reveal.dart';
import '../services/mirror_download_undo.dart';
import '../services/mirror_junk_sweeper.dart';
import '../services/notices_seen_store.dart';
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

  /// בדיקת "אוצריא פתוחה?" — מוזרקת כדי שבדיקות widget לא יריצו `tasklist`
  /// אמיתי: תהליך חיצוני משאיר טיימר תלוי ומפיל את הבדיקה.
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

  /// אילו הודעות חד-פעמיות כבר הוצגו במחשב הזה. נכתב ל-`stateDir`, ולכן
  /// עובד גם בכונן לקריאה בלבד.
  late final NoticesSeenStore _notices =
      widget.noticesStore ?? NoticesSeenStore(widget.stateFilesDir);

  /// ההסבר על דיווחי הטעויות רץ לפני ההצעה לאסוף — [_offerErrorReports]
  /// ממתין לו, כדי שהמשתמש יבין קודם מה זה ואחר כך יישאל.
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

  /// כל עוד אוצריא פתוחה בודקים שוב מדי [_runningPollInterval], כדי שסגירה
  /// שלה תזוהה מעצמה. כשהיא סגורה אין טיימר בכלל — פתיחה מחדש נתפסת
  /// בבדיקה שרצה לפני כל פעולה חוסמת (ראו [refreshProcessState]).
  static const Duration _runningPollInterval = Duration(seconds: 3);
  Timer? _runningPoll;

  /// המסכים שנבנו בפועל. ה-[IndexedStack] בונה את *כל* ילדיו, ולכן בעבר גם
  /// חנות התוספים (רשת כרטיסים עם תמונה לכל תוסף) נבנתה ופענחה את כל
  /// התמונות עוד לפני שהמשתמש נכנס אליה — עלות ישירה בזמן העלייה וב-RAM.
  /// כאן כל מסך נבנה בכניסה הראשונה אליו, ומאותו רגע נשאר בעץ עם המצב שלו.
  final Set<LauncherScreen> _builtScreens = {LauncherScreen.home};

  /// הורדה אחת בכל רגע — [downloadAll] מריץ את הרכיבים בטור.
  bool _isDownloading = false;

  /// בקשת ביטול להורדה שרצה. נקראת דרך `isCancelled` בכל שכבות ההורדה, ולכן
  /// נכנסת לתוקף באמצע נכס ולא רק בין רכיב לרכיב — ראו [cancelDownload].
  bool _cancelDownload = false;

  /// חלון "יש עדכונים / תוספים חדשים" נבדק פעם אחת בהרצה — ראו
  /// [_maybeAnnouncePlugins].
  bool _announcedPlugins = false;

  /// הבדיקה הקלה ("יש עדכון ברשת?") — נפרדת לגמרי מ-[_isDownloading].
  bool _isCheckingOnline = false;

  /// הבדיקה שלפני ההורדה ב-[downloadAll], לפני ש-[_isDownloading] נדלק.
  bool _isPreparingDownload = false;

  Future<void>? _downloadRun;
  Future<void>? _mirrorSweep;
  Future<void>? _launcherMirrorCheck;

  @override
  void initState() {
    super.initState();
    final s = widget.settings.settings;

    _otzaria = OtzariaModuleController(
      dataDir: widget.dataDir,
      stateDir: widget.stateFilesDir,
      // ההורדה מביאה תמיד את שתי הגרסאות; זו רק הבחירה איזו מהן מותקנת.
      preferPrerelease: s.preferAppPrerelease,
      runningLocator: widget.runningLocator,
      // עדכון מסד שנעשה כאן משאיר את אינדקס החיפוש של אוצריא על התוכן הישן.
      // הבקשה לתקן זאת נוסעת עם ההפעלה הרגילה של אוצריא, ונמחקת רק אחרי
      // שנמסרה בפועל — ראו [requestLibraryReindex].
      pendingLaunchUri: () async =>
          _library.hasPendingReindex ? OtzariaDeepLinks.libraryReindex : null,
      onLaunchUriDelivered: () => _library.markReindexRequestDelivered(),
    )..addListener(_onChange);
    _library = LibraryModuleController(
      dataDir: widget.dataDir,
      stateDir: widget.stateFilesDir,
      // נתיב ההתקנה של אוצריא מזהה התקנה ניידת/ספרייה מצורפת, ששם המסד לא
      // יושב ב-`%APPDATA%`. `null` לפני הבדיקה הראשונה — ראו [checkAll].
      otzariaLaunchPath: () async => _otzaria.launchPath,
    )..addListener(_onChange);
    _plugins = PluginsModuleController(
      // כל המראות יושבות תחת אותו שורש שלצד התוכנה, כך שהכול נוסע יחד.
      mirrorRootDir: p.join(widget.dataDir, 'mirror'),
      // "אילו תוספים כבר נראו" הוא נתון של המחשב הזה, ולכן בתיקיית הכתיבה.
      stateDir: widget.stateFilesDir,
      // אותו נתיב התקנה שמודול הספרייה מקבל: התקנה ניידת מחזיקה גם את
      // התוספים לידה, ואליה גם נמסרת ההתקנה הישירה של תוסף.
      otzariaLaunchPath: () async => _otzaria.launchPath,
      locatePluginsDb: PluginsModuleController.locateOtzariaPluginsDb,
      // ההורדה מביאה בילד תוסף לכל גרסת אוצריא שהכונן נושא — שתיהן, בדיוק
      // כמו מראת התוכנה עצמה. נקרא **בזמן** הסנכרון, שרץ אחרי הורדת
      // התוכנה, ולכן משקף גם גרסה שזה עתה ירדה.
      mirroredAppVersions: () async => [
        if (_otzaria.stableVersion != null) _otzaria.stableVersion!,
        if (_otzaria.prereleaseVersion != null) _otzaria.prereleaseVersion!,
      ],
      // ומה שמותקן כאן בפועל הוא שקובע איזה בילד מוצג ומותקן. כשאין
      // התקנה — הגרסה שעומדת להיות מותקנת מהכונן.
      installedAppVersion: () async =>
          _otzaria.currentVersion ?? _otzaria.latestVersion,
      // ההצצה ברשת יוצאת בעלייה **במקביל** לבדיקה המקומית, ושתי הקריאות
      // שמעליי עונות ממנה. בלי ההמתנה הזו הן החזירו ריק, וההצצה שאלה על
      // הבילד החי של כל תוסף במקום על התואם.
      ensureAppVersionsKnown: _otzaria.ensureChecked,
    )..addListener(_onChange);
    // כאן ולא במסך החנות: ההתקנה נגמרת בחלון של אוצריא, והמשתמש עשוי
    // לחזור בינתיים לכל מסך אחר — ההודעה צריכה למצוא אותו גם שם.
    _installDone = _plugins.installCompletions.listen((name) {
      if (mounted) {
        UiSnack.showSuccess(AppL10n.strings.plugins.installDoneSnack(name));
      }
    });
    _customApps = CustomAppsController(
      mirrorRootDir: p.join(widget.dataDir, 'mirror'),
      // תיקיית הכתיבה, כי "על מה כבר הודענו" הוא נתון של המחשב הזה.
      stateDir: widget.stateFilesDir,
    )..addListener(_onChange);
    _launcherUpdate = LauncherUpdateController(dataDir: widget.dataDir)
      ..addListener(_onChange);
    // בלי `addListener`: הדיאלוג עצמו מאזין לו, והמסגרת אינה מציגה ממנו כלום.
    _faq = FaqController(dataDir: widget.stateDir);
    unawaited(_faq.load());
    _errorReports = ErrorReportsController.forDrive(
      stateDir: widget.stateDir,
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
    // קריאת דיסק בלבד, ובדרך כלל של תיקייה שאינה קיימת — זולה.
    unawaited(_customApps.load());
    // בדיקה מקומית בלבד — קוראת מהתיקייה שלצד התוכנה ולא נוגעת ברשת.
    // הורדה תמיד יזומה בלחיצה.
    if (s.autoCheckUpdates) {
      // `checkAll` כבר מרענן את מצב התהליך בעצמו — קריאה נפרדת כאן הייתה
      // מריצה `tasklist` פעמיים בעלייה.
      unawaited(checkAll());
    } else {
      unawaited(refreshProcessState());
      unawaited(_checkLauncherMirror());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_otzaria.ensureChecked().then((_) => _offerErrorReports()));
      });
    }
    if (widget.appReports case final reports?) {
      reports.stateProvider = _reportState;
      unawaited(_startReports(reports));
    }
    // בדיקה קלה ברשת (מטא-דאטה בלבד) — פעם אחת בהפעלה, לא טיימר מחזורי.
    // כשל (אין רשת) נבלע בתוך הקונטרולרים ולא מוצג כשגיאה.
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
    _pauseTimer?.cancel();
    if (_pauseDone case final done? when !done.isCompleted) done.complete();
    _runningPoll?.cancel();
    unawaited(_installDone.cancel());
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
    _applySettings(widget.settings.settings);
    _syncRunningPoll();
    setState(() {});
    unawaited(_maybeOfferElevation());
    unawaited(_maybeAnnouncePlugins());
  }

  void _onReportsChange() {
    if (mounted) unawaited(_maybeOfferElevation());
  }

  /// "יש עדכונים / יש תוספים חדשים" — חלון אחד בעלייה, כמו התראת הרקע של
  /// החנות הרשמית. **פעם אחת בהרצה**, ורק כשהקטלוג המקומי נטען: הבדיקה
  /// קוראת מהמראה ולא מהרשת. תוסף חדש מוזכר כאן פעם אחת במחשב הזה.
  Future<void> _maybeAnnouncePlugins() async {
    if (_announcedPlugins || _plugins.status != PluginsModuleStatus.ready) {
      return;
    }
    _announcedPlugins = true;

    final fresh = _plugins.newPluginsForHome;
    final hasUpdates = _plugins.updatablePlugins.isNotEmpty;
    if (fresh.isEmpty && !hasUpdates) return;

    // אחרי הפריים, ובלי לעלות מעל דיאלוג אחר שכבר פתוח (עדכון לאנצ'ר,
    // הצעת דיווחים). מוותרים אחרי דקה — ההודעה לא נרשמה, ותחזור בהרצה הבאה.
    await WidgetsBinding.instance.endOfFrame;
    await _withDialogSlot(() async {
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

  Future<bool> _waitUntilNoDialog({bool forever = false}) async {
    var waits = 0;
    while (mounted &&
        (_exitPending || !(ModalRoute.of(context)?.isCurrent ?? true))) {
      if (!forever && ++waits > 120) return false;
      await _pause(const Duration(milliseconds: 500));
    }
    return mounted;
  }

  Timer? _pauseTimer;
  Completer<void>? _pauseDone;

  /// השהיה שאפשר לבטל: ב-`dispose` הטיימר נעצר וההמתנה מתעוררת, כך שלולאת
  /// ההמתנה אינה נשארת תלויה אחרי שהמסגרת נסגרה.
  Future<void> _pause(Duration duration) {
    final done = _pauseDone = Completer<void>();
    _pauseTimer = Timer(duration, () {
      if (!done.isCompleted) done.complete();
    });
    return done.future;
  }

  /// סוף התור של הדיאלוגים שמופיעים מעצמם בעלייה.
  Future<void> _dialogTail = Future<void>.value();

  /// מריץ [body] — שמציג דיאלוג — כשאין אחר פתוח, וגם כשאין עוד אחד שממתין
  /// באותו רגע: הבדיקה וההצגה בתור אחד, כך ששני דיאלוגים לא יעלו יחד. מחזיר
  /// `null` כשלא ניתן היה להציג (ההודעה לא נרשמה ותחזור בהרצה הבאה).
  Future<T?> _withDialogSlot<T>(
    Future<T> Function() body, {
    bool forever = false,
  }) async {
    final previous = _dialogTail;
    final done = Completer<void>();
    _dialogTail = done.future;
    try {
      await previous;
      if (!await _waitUntilNoDialog(forever: forever)) return null;
      return await body();
    } finally {
      done.complete();
    }
  }

  Future<void> _showErrorReportsIntro() async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await _withDialogSlot(
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

  /// הדיווחים של הלאנצ'ר — הכול אחרי הפריים הראשון (§5.9): קריאת התור
  /// ושליחתו, וזיהוי הקריסה של ההפעלה הקודמת. ההצעה לא עולה מעל דיאלוג אחר.
  Future<void> _startReports(AppReportsController reports) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    // חריג מכוון ל"רשת רק בלחיצה" (AGENTS §1): תור הדיווחים נשלח לבד.
    reports.startBackground();
    await reports.runCrashCheck(
      showPrompt: (candidate) async {
        final shown = await _withDialogSlot(
          () async {
            await showCrashPromptDialog(
              context,
              reports: reports,
              candidate: candidate,
              saferMode: _saferMode,
            );
            return true;
          },
          // הנעילה כבר נדרסה: מי שוויתר כאן מאבד את הקריסה לצמיתות.
          forever: true,
        );
        return shown ?? false;
      },
    );
  }

  Future<void> _maybeOfferElevation() async {
    if (_offeredElevation || !Platform.isWindows) return;
    if (!_library.needsElevation && !_otzaria.needsElevation) return;
    if (_exitWouldInterrupt) return;
    _offeredElevation = true;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    final t = AppL10n.strings.elevation;
    final approved = await _withDialogSlot(
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
      if (mounted) setState(() => _elevationPending = false);
    }
    if (failure != null) {
      UiSnack.showError(t.restartFailedSnack('$failure'));
    }
  }

  /// מדליק/מכבה את הרענון המחזורי לפי מצב התהליך שהתקבל כרגע.
  void _syncRunningPoll() {
    if (_otzariaIsRunning) {
      _runningPoll ??= Timer.periodic(
        _runningPollInterval,
        (_) => unawaited(_otzaria.refreshRunningState()),
      );
    } else {
      _runningPoll?.cancel();
      _runningPoll = null;
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

  /// מבקש מאוצריא הפתוחה להיסגר — הכפתור שלצד האזהרה, בכל מסך שמציג אותה.
  /// מחזיר אם היא אכן נסגרה; ההודעה על כישלון היא של הכפתור עצמו.
  ///
  /// הרענון המחזורי מסונכרן אחריו במפורש: הוא נדלק לפי מצב התהליך, וסגירה
  /// שהצליחה אמורה לכבות אותו מיד ולא רק בפעימה הבאה.
  Future<bool> closeOtzaria() async {
    final closed = await _otzaria.closeRunning();
    if (mounted) _syncRunningPoll();
    return closed;
  }

  bool _blockedByReadOnly() {
    if (!widget.readOnly) return false;
    final t = AppL10n.strings.readOnlyDrive;
    UiSnack.show(widget.driveFull
        ? t.downloadsDisabledSnackDriveFull
        : t.downloadsDisabledSnack);
    return true;
  }

  Future<void> checkAll() async {
    await _checkLauncherMirror();
    if (!mounted) return;

    await _otzaria.checkForUpdate();
    if (!mounted) return;
    unawaited(_plugins.refreshInstalled());

    await _library.checkForUpdate();
    if (!mounted) return;
    await _autoInstallIfEnabled();
    if (!mounted) return;
    await _offerErrorReports();
  }

  Future<void> _checkLauncherMirror() {
    if (widget.readOnly ||
        _launcherUpdate.isDownloading ||
        _launcherUpdate.isInstalling) {
      return Future.value();
    }
    return _launcherMirrorCheck ??= _launcherUpdate
        .checkForUpdate()
        .whenComplete(() => _launcherMirrorCheck = null);
  }

  /// "נמצאו דיווחים שלא נשלחו — לאסוף?". אוצריא פתוחה נבדקת בזרימה עצמה,
  /// לפני ההצעה ואחרי האישור: המאגר שלה עלול להיות נעול.
  Future<void> _offerErrorReports() async {
    // גם מ-`checkAll` שהתחיל ב-`initState`: הדיאלוג והקריאה מהמסד — אחרי פריים.
    await WidgetsBinding.instance.endOfFrame;
    // ההסבר קודם להצעה: מי שנשאל "לאסוף?" צריך לדעת קודם על מה מדובר.
    await _errorReportsIntro;
    if (!mounted || _otzaria.launchPath == null) return;
    // בתור הדיאלוגים: ההצעה לא עולה מעל דיאלוג אחר, והיא לא נצרכת אם לא הוצגה.
    await _withDialogSlot(() async {
      await offerErrorReportCollection(
        context,
        _errorReports,
        readOnly: widget.readOnly,
        isOtzariaRunning: refreshProcessState,
      );
      if (!mounted) return;
      await offerSearchFeedbackCollection(
        context,
        _searchFeedback,
        readOnly: widget.readOnly,
      );
    });
  }

  Future<void> _uploadSearchFeedback() async {
    if (_blockedByReadOnly() || !mounted) return;
    await uploadSearchFeedback(context, _searchFeedback);
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

  /// העלאת הדיווחים שעל הכונן — הפעולה היחידה שלהם שפונה לרשת.
  Future<void> _uploadErrorReports() async {
    if (_blockedByReadOnly() || !mounted) return;
    await uploadErrorReports(context, _errorReports);
  }

  Future<void> checkOnline() async {
    if (widget.readOnly || _isCheckingOnline) return;
    setState(() => _isCheckingOnline = true);
    await _checkLauncherMirror();
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

  /// "גירסה X זמינה, להוריד עכשיו?" — פעם אחת בהרצה, ורק כשהבדיקה הקלה מצאה
  /// ברשת גרסה חדשה מזו שכבר יושבת בתיקייה.
  Future<void> _promptLauncherUpdate() async {
    if (!mounted || widget.readOnly) return;
    final c = _launcherUpdate;
    final release = c.onlineRelease;
    if (release == null || !c.hasOnlineUpdate) return;
    if (_askedAboutLauncherUpdate || c.isDownloading) return;
    _askedAboutLauncherUpdate = true;

    final t = context.strings.launcherUpdate;
    final whatsNew = c.onlineWhatsNew;
    final approved = await _withDialogSlot(
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

  Future<void> downloadLauncherUpdate() async {
    if (_blockedByReadOnly()) return;
    if (_mirrorSweep case final sweep?) await sweep;
    if (_launcherMirrorCheck case final check?) await check;
    if (!mounted ||
        _isPreparingDownload ||
        _isDownloading ||
        _launcherUpdate.isDownloading) {
      return;
    }

    final downloaded = await _launcherUpdate.download();
    if (!downloaded || !mounted || !_launcherUpdate.hasUpdateReady) return;

    UiSnack.showSuccess(
      AppL10n.strings.launcherUpdate
          .downloadedSnack('${_launcherUpdate.downloadedVersion}'),
    );
    await installLauncherUpdate();
  }

  bool get _longTaskRunning =>
      _isDownloading ||
      _library.isApplying ||
      _library.status == LibraryModuleStatus.updating ||
      _otzaria.status == OtzariaModuleStatus.installing ||
      _customApps.isBusy ||
      _customApps.isLearning ||
      _customApps.isDownloadingAll ||
      _plugins.isExporting ||
      _exitPending;

  bool get _exitPending => _elevationPending || _launcherUpdate.isInstalling;

  bool get _exitWouldInterrupt =>
      _longTaskRunning ||
      _errorReports.isCollecting ||
      _errorReports.isUploading ||
      _searchFeedback.isCollecting ||
      _searchFeedback.isUploading;

  Future<void> installLauncherUpdate() async {
    if (_blockedByReadOnly()) return;
    if (!mounted) return;
    if (_exitWouldInterrupt) {
      UiSnack.show(AppL10n.strings.launcherUpdate.busyNotice);
      return;
    }
    final version = _launcherUpdate.downloadedVersion;
    if (version == null || !_launcherUpdate.canInstall) return;

    final t = context.strings.launcherUpdate;
    final whatsNew =
        _whatsNewAlreadyShown ? null : _launcherUpdate.downloadedWhatsNew;
    final approved = await showTwoActionsDialog(
      context: context,
      title: t.readyDialogTitle,
      content: t.readyDialogContent(version),
      customContent: whatsNew == null
          ? null
          : WhatsNewSection(heading: t.whatsNewHeading, markdown: whatsNew),
      confirmText: t.readyDialogConfirm,
    );
    if (!approved || !mounted) return;
    if (_exitWouldInterrupt) {
      UiSnack.show(AppL10n.strings.launcherUpdate.busyNotice);
      return;
    }

    UiSnack.show(AppL10n.strings.launcherUpdate.installingSnack);
    final restarted = await _launcherUpdate.install();
    if (restarted || !mounted) return;

    final error = _launcherUpdate.errorMessage;
    if (error != null) {
      UiSnack.showError(error);
      return;
    }
    UiSnack.show(AppL10n.strings.launcherUpdate.manualRestartNotice);
  }

  Future<void> _autoInstallIfEnabled() async {
    final s = widget.settings.settings;

    var skippedWhileRunning = false;

    if (s.autoInstall &&
        !_isDownloading &&
        !_library.isFreshInstall &&
        _library.status == LibraryModuleStatus.updateAvailable) {
      if (await refreshProcessState()) {
        skippedWhileRunning = true;
      } else if (!_exitPending) {
        await _library.update();
        if (!mounted) return;
      }
    }

    if (s.autoInstall &&
        _otzaria.currentVersion != null &&
        _otzaria.status == OtzariaModuleStatus.updateAvailable) {
      if (await refreshProcessState()) {
        skippedWhileRunning = true;
      } else if (!_exitPending) {
        await _otzaria.install(useWizard: false);
      }
    }

    if (!skippedWhileRunning || !mounted) return;
    final t = context.strings.home;
    await showSingleActionDialog(
      context: context,
      title: t.autoInstallSkippedTitle,
      content: t.autoInstallSkippedContent,
    );
  }

  /// התיקיות ש-[downloadAll] ממלא, ולכן אלה שביטול מנקה. `mirror/apps`
  /// (תוכנות שהמשתמש הוסיף) ו-`mirror/launcher` אינן כאן בכוונה: אף הורדה
  /// מכאן אינה נוגעת בהן.
  List<String> get _downloadMirrorDirs => [
        _library.mirrorDir,
        _library.companionsMirrorDir,
        _library.semanticMirrorDir,
        _otzaria.mirrorDir,
        p.join(widget.dataDir, 'mirror', 'plugins'),
        p.join(widget.dataDir, 'mirror', 'store-app'),
      ];

  /// מבקש מהמשתמש אישור ואז מסמן ביטול להורדה שרצה. הדגל בלבד — ההורדה
  /// עצמה יוצאת מהלולאות שלה, ו-[downloadAll] הוא שמנקה אחריה.
  Future<void> cancelDownload() async {
    if (!_isDownloading || _cancelDownload || !mounted) return;

    final t = context.strings.home;
    final approved = await showWarningDialog(
      context: context,
      title: t.cancelDownloadDialogTitle,
      content: t.cancelDownloadPrompt,
      cancelText: t.cancelDownloadKeepGoing,
      confirmText: t.cancelDownloadButton,
    );
    // ההורדה יכולה להסתיים בזמן שהדיאלוג פתוח — ואז אין מה לבטל, ובעיקר אין
    // מה למחוק: היא הצליחה.
    if (!approved || !mounted || !_isDownloading) return;
    setState(() => _cancelDownload = true);
  }

  Future<bool> _confirmClose() async {
    if (!mounted || !_longTaskRunning) return true;
    final t = context.strings.shell;
    final downloading = _isDownloading;
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
    if (_downloadRun case final run? when _isDownloading) {
      setState(() => _cancelDownload = true);
      await run;
    }
    return true;
  }

  Future<void> downloadAll() async {
    if (_blockedByReadOnly()) return;
    if (_isPreparingDownload) return;
    _isPreparingDownload = true;
    final run = _downloadRun = _downloadAll();
    try {
      await run;
    } finally {
      _isPreparingDownload = false;
      _downloadRun = null;
    }
  }

  Future<void> _downloadAll() async {
    if (_mirrorSweep case final sweep?) {
      await sweep;
      if (!mounted) return;
    }
    final s = widget.settings.settings;
    if (!s.hasSyncSelection ||
        _longTaskRunning ||
        _launcherUpdate.isDownloading) {
      return;
    }

    // רכיב שהבדיקה אמרה עליו "אין חדש" לא מורץ בכלל: ההורדה שלו אורכת
    // דקות ומציגה מד התקדמות, ולא הייתה מביאה כלום. הכפתור עצמו מופיע רק
    // כשמשהו כן התחדש — ולכן זה תמיד "הורד את מה שהתחדש", לא "הורד הכול".
    //
    // חריג אחד: על הכונן יושבת עדיין חבילת FULL מגרסה ישנה. מודול התוכנה
    // הוא זה שמוחק אותה, ובלי החריג "אין גרסה חדשה" היה מדלג עליו — ו-2GB
    // היו נשארים שם לנצח.
    final skipApp = s.syncApp &&
        !_otzaria.hasStaleFullPackage &&
        provenUpToDateOnline(
          checkedAt: _otzaria.onlineCheckedAt,
          error: _otzaria.onlineCheckError,
          hasUpdate: _otzaria.hasOnlineUpdate,
        );
    // בלי בדיקה שהצליחה "כבר בכונן" אינו ידוע, והשאלה הייתה קופצת על מה שכבר
    // שם. בדיקה אחת קלה לפניה; כשל שלה משאיר את השאלה, כמו קודם.
    if (s.downloadsLibrary &&
        (_library.onlineCheckedAt == null ||
            _library.onlineCheckError != null)) {
      await _library.checkOnline();
      if (!mounted) return;
    }
    // ב"עדכון אישי" היעד נגזר מהגרסה שנרשמה ולא מהחדשה שברשת, ולכן
    // "אין חדש ברשת" אינו אומר שאין מה להוריד.
    final includeSemanticSearch = s.downloadsLibrary &&
        _library.shouldOfferSemanticDownload &&
        await showTwoActionsDialog(
          context: context,
          title: context.strings.libraryDomain.companionSemanticName,
          content: context.strings.libraryDomain.semanticDownloadPrompt,
          confirmText: context.strings.home.downloadNowButton,
        );
    if (!mounted || _longTaskRunning || _launcherUpdate.isDownloading) return;
    final skipLibrary = !includeSemanticSearch &&
        s.downloadsLibrary &&
        !_library.personalUpdateMode &&
        provenUpToDateOnline(
          checkedAt: _library.onlineCheckedAt,
          error: _library.onlineLibraryProofError,
          hasUpdate: _library.hasOnlineLibraryUpdate,
        );
    final skipPlugins = s.syncPlugins &&
        provenUpToDateOnline(
          checkedAt: _plugins.onlineCheckedAt,
          error: _plugins.onlineCheckError,
          hasUpdate: _plugins.hasCatalogOnlineUpdate,
        );
    // נפרד מהקטלוג: הוא מגיע מגיטהאב ולא מ-otzaria.org, ובדיקה שנכשלה
    // באחד מהם אינה אומרת דבר על השני.
    final skipStoreApp = s.syncPlugins &&
        provenUpToDateOnline(
          checkedAt: _plugins.storeAppCheckedAt,
          error: _plugins.storeAppCheckError,
          hasUpdate: _plugins.hasStoreAppOnlineUpdate,
        );

    setState(() {
      _isDownloading = true;
      _cancelDownload = false;
    });

    final before = OnlineAnswersBeforeDownload.capture(
      library: _library,
      plugins: _plugins,
    );
    final undo = await MirrorDownloadUndo.capture(_downloadMirrorDirs);
    bool cancelled() => _cancelDownload;

    // הבדיקה בין רכיב לרכיב: ביטול באמצע הספרייה לא אמור להתחיל את התוספים.
    if (s.syncApp && !skipApp) await _otzaria.download(isCancelled: cancelled);
    if (!cancelled() && s.downloadsLibrary && !skipLibrary) {
      await _library.download(
        includeSemanticSearch: includeSemanticSearch,
        isCancelled: cancelled,
      );
    }
    if (!cancelled() && s.syncPlugins && !skipPlugins) {
      await _plugins.sync(isCancelled: cancelled);
    }
    // גם כשדילגנו על התוספים — לתוכנת החנות בדיקה משלה. `syncStoreApp`
    // מוריד רק את מה שהבדיקה הקלה כבר מצאה, ולכן דילוג כאן פירושו שאין
    // שום פנייה לגיטהאב.
    if (!cancelled() && s.syncPlugins && !skipStoreApp) {
      await _plugins.syncStoreApp();
    }

    if (cancelled()) {
      await undo.revert();
      await refreshAfterCancelledDownload(
        otzaria: _otzaria,
        library: _library,
        plugins: _plugins,
        before: before,
      );
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _cancelDownload = false;
      });
      unawaited(_maybeOfferElevation());
      UiSnack.show(AppL10n.strings.home.downloadCancelledSnack);
      return;
    }
    if (!mounted) return;

    setState(() => _isDownloading = false);
    unawaited(_maybeOfferElevation());

    final t = context.strings;
    final skipped = [
      if (skipApp) t.home.appTileTitle,
      if (skipLibrary) t.home.libraryTileTitle,
      if (skipPlugins) t.shell.navPlugins,
    ];

    final failed = [
      if (s.syncApp && !skipApp && _otzaria.downloadError != null)
        t.home.appTileTitle,
      if (s.downloadsLibrary && !skipLibrary && _library.downloadError != null)
        t.home.libraryTileTitle,
      if (s.syncPlugins && !skipPlugins && _plugins.lastSyncFailed)
        t.shell.navPlugins,
    ];

    if (failed.isEmpty &&
        !_library.downloadNeedsRetry &&
        !_launcherUpdate.isDownloading) {
      _mirrorSweep = _sweepMirrorJunk();
    }

    // הודעה אחת בסוף, לפי [summarizeDownload] — ראו שם למה לא שתיים.
    switch (summarizeDownload(failed: failed, skipped: skipped)) {
      case DownloadSummary.failed:
        UiSnack.show(t.home.downloadFailedSnack(failed.join(', ')));
      case DownloadSummary.skipped:
        UiSnack.show(t.home.downloadSkippedSnack(skipped.join(', ')));
      case DownloadSummary.done:
        UiSnack.showSuccess(t.home.downloadDoneSnack);
    }
  }

  Future<void> _sweepMirrorJunk() async {
    try {
      final freed = await MirrorJunkSweeper(dataDir: widget.dataDir).sweep();
      if (freed > 0) {
        AppLogger.instance.info('ניקוי המראה פינה ${formatBytes(freed)}');
      }
    } finally {
      _mirrorSweep = null;
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
            isDownloading: _isDownloading,
            isCancellingDownload: _cancelDownload,
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
            onUploadErrorReports: _uploadErrorReports,
            searchFeedback: _searchFeedback,
            onUploadSearchFeedback: _uploadSearchFeedback,
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
            isDownloading: _isDownloading,
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

  @override
  Widget build(BuildContext context) {
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
                      child:
                          FaqFloatingButton(faq: _faq, saferMode: _saferMode),
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

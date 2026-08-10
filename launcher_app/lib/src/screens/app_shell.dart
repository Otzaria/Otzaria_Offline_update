import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;

import '../controllers/library_module_controller.dart';
import '../controllers/otzaria_module_controller.dart';
import '../controllers/plugins_module_controller.dart';
import '../services/app_logger.dart';
import '../services/file_reveal.dart';
import '../settings/app_settings.dart';
import '../settings/settings_controller.dart';
import '../theme/theme_exports.dart';
import '../widgets/widgets_exports.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'otzaria_screen.dart';
import 'plugins/plugins_screen.dart';
import 'settings_screen.dart';

/// המסך הפעיל בסרגל הניווט. "תוכנה" קודם ל"ספרייה" — ראו [_NavRail].
enum LauncherScreen { home, otzaria, library, plugins, settings }

/// מסגרת האפליקציה: שורת כותרת מותאמת למעלה, סרגל ניווט קבוע בצד, וחמשת
/// המסכים. שלושתם נצבעים באותו רקע לוח — בלי תפר ביניהם.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.dataDir,
    required this.settings,
    this.runningLocator = const RunningOtzariaLocator(),
    this.showWindowButtons,
  });

  final String dataDir;
  final SettingsController settings;

  /// בדיקת "אוצריא פתוחה?" — מוזרקת כדי שבדיקות widget לא יריצו `tasklist`
  /// אמיתי: תהליך חיצוני משאיר טיימר תלוי ומפיל את הבדיקה.
  final RunningOtzariaLocator runningLocator;

  /// ראו [AppTitleBar.showWindowButtons] — מוזרק `false` בבדיקות widget.
  final bool? showWindowButtons;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final OtzariaModuleController _otzaria;
  late final LibraryModuleController _library;
  late final PluginsModuleController _plugins;

  LauncherScreen _screen = LauncherScreen.home;

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

  /// הבדיקה הקלה ("יש עדכון ברשת?") — נפרדת לגמרי מ-[_isDownloading].
  bool _isCheckingOnline = false;

  @override
  void initState() {
    super.initState();
    final s = widget.settings.settings;

    _otzaria = OtzariaModuleController(
      dataDir: widget.dataDir,
      // ההורדה מביאה תמיד את שתי הגרסאות; זו רק הבחירה איזו מהן מותקנת.
      preferPrerelease: s.preferAppPrerelease,
      runningLocator: widget.runningLocator,
    )..addListener(_onChange);
    _library = LibraryModuleController(
      dataDir: widget.dataDir,
      // נתיב ההתקנה של אוצריא מזהה התקנה ניידת/ספרייה מצורפת, ששם המסד לא
      // יושב ב-`%APPDATA%`. `null` לפני הבדיקה הראשונה — ראו [checkAll].
      otzariaLaunchPath: () async => _otzaria.launchPath,
    )..addListener(_onChange);
    _plugins = PluginsModuleController(
      // כל המראות יושבות תחת אותו שורש שלצד התוכנה, כך שהכול נוסע יחד.
      mirrorRootDir: p.join(widget.dataDir, 'mirror'),
    )..addListener(_onChange);
    widget.settings.addListener(_onChange);
    _applySettings(s);

    unawaited(_plugins.load());
    // בדיקה מקומית בלבד — קוראת מהתיקייה שלצד התוכנה ולא נוגעת ברשת.
    // הורדה תמיד יזומה בלחיצה.
    if (s.autoMetadataCheck) {
      // `checkAll` כבר מרענן את מצב התהליך בעצמו — קריאה נפרדת כאן הייתה
      // מריצה `tasklist` פעמיים בעלייה.
      unawaited(checkAll());
    } else {
      unawaited(refreshProcessState());
    }
    // בדיקה קלה ברשת (מטא-דאטה בלבד) — פעם אחת בהפעלה, לא טיימר מחזורי.
    // כשל (אין רשת) נבלע בתוך הקונטרולרים ולא מוצג כשגיאה.
    if (s.autoCheckOnlineUpdates) {
      unawaited(checkOnline());
    }
  }

  @override
  void dispose() {
    _runningPoll?.cancel();
    widget.settings.removeListener(_onChange);
    _otzaria.removeListener(_onChange);
    _library.removeListener(_onChange);
    _plugins.removeListener(_onChange);
    _otzaria.dispose();
    _library.dispose();
    _plugins.dispose();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    _applySettings(widget.settings.settings);
    _syncRunningPoll();
    setState(() {});
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
  }

  /// בדיקת תהליך עצמאית — לרענון יזום מהמסך, ובעיקר **מיד לפני** פעולה
  /// שאוצריא הפתוחה חוסמת. מחזירה את התוצאה הטרייה, כי `otzariaIsRunning`
  /// של המסכים הוא הערך שנלכד בבנייה — זה שבגללו נחסמו מלכתחילה.
  ///
  /// `force`: זו נקודת ההכרעה לפני פעולה חוסמת, ולכן אינה מסתפקת בתשובה של
  /// בדיקה שכבר הייתה באוויר. הרענון המחזורי, לעומת זאת, כן מצטרף.
  Future<bool> refreshProcessState() =>
      _otzaria.refreshRunningState(force: true);

  /// בודק גרסאות בשני המודולים **מהתיקייה המקומית בלבד**. לא נוגע ברשת,
  /// לא מוריד ולא מתקין דבר.
  Future<void> checkAll() async {
    // בטור ולא במקביל: בדיקת הספרייה משתמשת בנתיב ההתקנה של אוצריא כדי לאתר
    // את המסד (התקנה ניידת/ספרייה מצורפת), והוא ידוע רק אחרי הבדיקה שלה.
    // מצב התהליך מתעדכן בתוכה, ו-[_otzariaIsRunning] נגזר ממנו.
    await _otzaria.checkForUpdate();
    if (!mounted) return;

    await _library.checkForUpdate();
    if (!mounted) return;
    await _autoInstallIfEnabled();
  }

  /// בדיקה קלה ברשת ("יש עדכון חדש?") לשני הרכיבים — מטא-דאטה בלבד, בלי
  /// הורדת installer/מסד. כשל (אין רשת) נבלע בתוך הקונטרולרים עצמם.
  Future<void> checkOnline() async {
    if (_isCheckingOnline) return;
    setState(() => _isCheckingOnline = true);
    await Future.wait([_otzaria.checkOnline(), _library.checkOnline()]);
    if (!mounted) return;
    setState(() => _isCheckingOnline = false);
  }

  /// מתקין מהתיקייה המקומית בלי לשאול — אך ורק למי שהדליק זאת במפורש
  /// בהגדרות (ראו `SettingsScreen._confirmAutoInstall`). לא מוריד דבר.
  Future<void> _autoInstallIfEnabled() async {
    final s = widget.settings.settings;

    if (s.autoInstallApp &&
        _otzaria.status == OtzariaModuleStatus.updateAvailable) {
      await _otzaria.install();
      if (!mounted) return;
    }

    // עדכון מסד כותב לקובץ שאוצריא נועלת — מדלגים בשקט כשהיא פתוחה, במקום
    // להיכשל ברקע על משהו שהמשתמש לא ביקש עכשיו.
    if (s.autoInstallLibrary &&
        !_otzariaIsRunning &&
        _library.status == LibraryModuleStatus.updateAvailable) {
      await _library.update();
    }
  }

  /// מוריד מהרשת אל התיקייה שלצד התוכנה — רק את הרכיבים שסומנו בהגדרות.
  /// זו הפעולה היחידה בכל האפליקציה שדורשת אינטרנט.
  ///
  /// הרכיבים מורדים בזה אחר זה ולא במקביל, כי הם חולקים את אותו רוחב פס
  /// והמסד לבדו הוא ~1GB; במקביל זה רק היה מאט את כולם ומבלבל את התצוגה.
  Future<void> downloadAll() async {
    final s = widget.settings.settings;
    if (!s.hasSyncSelection || _isDownloading) return;

    setState(() => _isDownloading = true);

    if (s.syncApp) await _otzaria.download();
    if (s.syncLibrary) await _library.download();
    if (s.syncPlugins) await _plugins.sync();
    if (!mounted) return;

    setState(() => _isDownloading = false);
  }

  Future<void> _openLogFolder() async {
    final logger = AppLogger.instance;
    if (await FileReveal.revealDirectory(logger.logDir)) return;
    UiSnack.show(AppL10n.strings.shell.logPathFallback(logger.filePath));
  }

  void _goTo(LauncherScreen screen) {
    setState(() {
      _screen = screen;
      _builtScreens.add(screen);
    });
  }

  /// שם המסך הפתוח, כפי שהוא מוצג בשורת הכותרת — אותן תוויות בדיוק כמו
  /// בסרגל הניווט, כך שהשורה והסרגל מדברים באותה שפה.
  String _screenTitle(BuildContext context, LauncherScreen screen) {
    final s = context.strings.shell;
    return switch (screen) {
      LauncherScreen.home => s.navHome,
      LauncherScreen.otzaria => s.navApp,
      LauncherScreen.library => s.navLibrary,
      LauncherScreen.plugins => s.navPlugins,
      LauncherScreen.settings => s.navSettings,
    };
  }

  Widget _screenWidget(LauncherScreen screen) => switch (screen) {
        LauncherScreen.home => HomeScreen(
            otzaria: _otzaria,
            library: _library,
            plugins: _plugins,
            settings: widget.settings,
            otzariaIsRunning: _otzariaIsRunning,
            isDownloading: _isDownloading,
            isCheckingOnline: _isCheckingOnline,
            onProcessStateChanged: refreshProcessState,
            onCheckOnline: checkOnline,
            onDownloadAll: downloadAll,
            onGoToOtzaria: () => _goTo(LauncherScreen.otzaria),
            onGoToLibrary: () => _goTo(LauncherScreen.library),
          ),
        LauncherScreen.otzaria => OtzariaScreen(
            otzaria: _otzaria,
            settings: widget.settings,
            otzariaIsRunning: _otzariaIsRunning,
          ),
        LauncherScreen.library => LibraryScreen(
            library: _library,
            otzariaIsRunning: _otzariaIsRunning,
            isDownloading: _isDownloading,
            onProcessStateChanged: refreshProcessState,
          ),
        LauncherScreen.plugins => PluginsScreen(
            controller: _plugins,
            onRequestFocus: () => _goTo(LauncherScreen.plugins),
          ),
        LauncherScreen.settings => SettingsScreen(
            controller: widget.settings,
            onOpenLog: _openLogFolder,
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
            screenTitle: _screenTitle(context, _screen),
            showWindowButtons: widget.showWindowButtons,
          ),
          Expanded(
            child: Row(
              children: [
                _NavRail(
                  current: _screen,
                  onSelect: _goTo,
                ),
                // הסרגל והתוכן חולקים רקע — הקו הזה הוא ההפרדה היחידה ביניהם.
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
                            ? _screenWidget(screen)
                            : const SizedBox.shrink(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── סרגל הניווט ───────────────────────────────────────────────────────────────

class _NavRail extends StatelessWidget {
  final LauncherScreen current;
  final ValueChanged<LauncherScreen> onSelect;

  const _NavRail({required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final s = context.strings.shell;

    return Container(
      width: NavRailItem.width,
      color: AppSurfaces.navRailBackground(context),
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSM),
      child: Column(
        children: [
          NavRailItem(
            icon: FluentIcons.home_24_regular,
            iconFilled: FluentIcons.home_24_filled,
            label: s.navHome,
            isSelected: current == LauncherScreen.home,
            onTap: () => onSelect(LauncherScreen.home),
          ),
          NavRailItem(
            icon: FluentIcons.desktop_24_regular,
            iconFilled: FluentIcons.desktop_24_filled,
            label: s.navApp,
            isSelected: current == LauncherScreen.otzaria,
            onTap: () => onSelect(LauncherScreen.otzaria),
          ),
          NavRailItem(
            icon: FluentIcons.library_24_regular,
            iconFilled: FluentIcons.library_24_filled,
            label: s.navLibrary,
            isSelected: current == LauncherScreen.library,
            onTap: () => onSelect(LauncherScreen.library),
          ),
          NavRailItem(
            icon: FluentIcons.puzzle_piece_24_regular,
            iconFilled: FluentIcons.puzzle_piece_24_filled,
            label: s.navPlugins,
            isSelected: current == LauncherScreen.plugins,
            onTap: () => onSelect(LauncherScreen.plugins),
          ),
          const Spacer(),
          NavRailItem(
            icon: FluentIcons.settings_24_regular,
            iconFilled: FluentIcons.settings_24_filled,
            label: s.navSettings,
            isSelected: current == LauncherScreen.settings,
            onTap: () => onSelect(LauncherScreen.settings),
          ),
        ],
      ),
    );
  }
}

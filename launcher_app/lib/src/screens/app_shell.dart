import 'dart:async';
import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:library_manager/library_manager.dart';
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

/// מצב הרשת כפי שהוא נגזר מההורדה האחרונה שנוסתה. הבדיקה עצמה כבר לא
/// נוגעת ברשת (היא קוראת מהתיקייה המקומית), ולכן זו הערכה שמתעדכנת רק
/// כשבאמת ניסינו להוריד.
enum NetworkState { unknown, checking, online, offline }

/// המסך הפעיל בסרגל הניווט. "תוכנה" קודם ל"ספרייה" — ראו [_NavRail].
enum LauncherScreen { home, otzaria, library, plugins, settings }

/// מסגרת האפליקציה: סרגל ניווט קבוע בצד, סרגל מצב עליון, וחמשת המסכים.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.dataDir,
    required this.settings,
  });

  final String dataDir;
  final SettingsController settings;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final OtzariaModuleController _otzaria;
  late final LibraryModuleController _library;
  late final PluginsModuleController _plugins;

  LauncherScreen _screen = LauncherScreen.home;
  NetworkState _network = NetworkState.unknown;
  bool _otzariaIsRunning = false;
  DateTime? _lastCheckedAt;

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
      // הריפו של אוצריא מפרסם כמעט רק pre-release — בערוץ "יציב בלבד"
      // ייתכן שלא תימצא גרסה כלל, ולכן זה קבוע ולא הגדרה למשתמש.
      allowPrerelease: true,
    )..addListener(_onChange);
    _library = LibraryModuleController(
      dataDir: widget.dataDir,
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
      unawaited(_refreshProcessState());
    }
    // בדיקה קלה ברשת (מטא-דאטה בלבד) — פעם אחת בהפעלה, לא טיימר מחזורי.
    // כשל (אין רשת) נבלע בתוך הקונטרולרים ולא מוצג כשגיאה.
    if (s.autoCheckOnlineUpdates) {
      unawaited(checkOnline());
    }
  }

  @override
  void dispose() {
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
    setState(() {});
  }

  /// מזליג הגדרות שהקונטרולרים צריכים. הכול idempotent (הצבת ערך), ולכן אין
  /// צורך לעקוב אחרי שינוי בפועל.
  void _applySettings(AppSettings s) {
    _library.keepSafetyBackup = s.backupsToKeep > 0;
    final timeout = Duration(seconds: s.networkTimeoutSeconds);
    _otzaria.networkTimeout = timeout;
    _library.networkTimeout = timeout;
    _plugins.networkTimeout = timeout;
  }

  Future<void> _refreshProcessState() async {
    const guard = OtzariaProcessGuard();
    final running = await guard.isAnyRunning(
      OtzariaProcessGuard.processNamesFor(Platform.operatingSystem),
    );
    if (!mounted) return;
    setState(() => _otzariaIsRunning = running);
  }

  /// בודק גרסאות בשני המודולים **מהתיקייה המקומית בלבד**. לא נוגע ברשת,
  /// לא מוריד ולא מתקין דבר.
  Future<void> checkAll() async {
    await Future.wait([_otzaria.checkForUpdate(), _library.checkForUpdate()]);
    await _refreshProcessState();
    if (!mounted) return;
    setState(() => _lastCheckedAt = DateTime.now());
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

    setState(() {
      _isDownloading = true;
      _network = NetworkState.checking;
    });

    if (s.syncApp) await _otzaria.download();
    if (s.syncLibrary) await _library.download();
    if (s.syncPlugins) await _plugins.sync();
    if (!mounted) return;

    // "לא מחובר" רק אם *כל* מה שנבחר נכשל — כשל בודד הוא בעיה נקודתית
    // ברכיב, לא עדות לכך שאין רשת.
    final attempted = <bool>[
      if (s.syncApp) _otzaria.downloadStatus == OtzariaDownloadStatus.done,
      if (s.syncLibrary) _library.downloadStatus == MirrorDownloadStatus.done,
      if (s.syncPlugins) _plugins.status != PluginsModuleStatus.error,
    ];
    setState(() {
      _isDownloading = false;
      _network =
          attempted.contains(true) ? NetworkState.online : NetworkState.offline;
    });
  }

  Future<void> _openLogFolder() async {
    final logger = AppLogger.instance;
    if (await FileReveal.revealDirectory(logger.logDir)) return;
    UiSnack.show('נתיב יומן הפעילות: ${logger.filePath}');
  }

  void _goTo(LauncherScreen screen) {
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
            settings: widget.settings,
            otzariaIsRunning: _otzariaIsRunning,
            isDownloading: _isDownloading,
            isCheckingOnline: _isCheckingOnline,
            onCheckOnline: checkOnline,
            onDownloadAll: downloadAll,
            onGoToOtzaria: () => _goTo(LauncherScreen.otzaria),
            onGoToLibrary: () => _goTo(LauncherScreen.library),
          ),
        LauncherScreen.otzaria => OtzariaScreen(
            otzaria: _otzaria,
            otzariaIsRunning: _otzariaIsRunning,
          ),
        LauncherScreen.library => LibraryScreen(
            library: _library,
            otzariaIsRunning: _otzariaIsRunning,
            isDownloading: _isDownloading,
            onProcessStateChanged: _refreshProcessState,
          ),
        LauncherScreen.plugins => PluginsScreen(controller: _plugins),
        LauncherScreen.settings => SettingsScreen(
            controller: widget.settings,
            onOpenLog: _openLogFolder,
          ),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppSurfaces.panelBackground(context),
      body: Row(
        children: [
          _NavRail(
            current: _screen,
            onSelect: _goTo,
          ),
          Expanded(
            child: Column(
              children: [
                _TopBar(
                  network: _network,
                  dataDir: widget.dataDir,
                  otzariaIsRunning: _otzariaIsRunning,
                  lastCheckedAt: _lastCheckedAt,
                  onOpenLog: _openLogFolder,
                  onRecheck: checkAll,
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
    return Container(
      width: NavRailItem.width,
      color: AppSurfaces.navRailBackground(context),
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSM),
      child: Column(
        children: [
          NavRailItem(
            icon: FluentIcons.home_24_regular,
            iconFilled: FluentIcons.home_24_filled,
            label: 'דף הבית',
            isSelected: current == LauncherScreen.home,
            onTap: () => onSelect(LauncherScreen.home),
          ),
          NavRailItem(
            icon: FluentIcons.desktop_24_regular,
            iconFilled: FluentIcons.desktop_24_filled,
            label: 'תוכנה',
            isSelected: current == LauncherScreen.otzaria,
            onTap: () => onSelect(LauncherScreen.otzaria),
          ),
          NavRailItem(
            icon: FluentIcons.library_24_regular,
            iconFilled: FluentIcons.library_24_filled,
            label: 'ספרייה',
            isSelected: current == LauncherScreen.library,
            onTap: () => onSelect(LauncherScreen.library),
          ),
          NavRailItem(
            icon: FluentIcons.puzzle_piece_24_regular,
            iconFilled: FluentIcons.puzzle_piece_24_filled,
            label: 'תוספים',
            isSelected: current == LauncherScreen.plugins,
            onTap: () => onSelect(LauncherScreen.plugins),
          ),
          const Spacer(),
          NavRailItem(
            icon: FluentIcons.settings_24_regular,
            iconFilled: FluentIcons.settings_24_filled,
            label: 'הגדרות',
            isSelected: current == LauncherScreen.settings,
            onTap: () => onSelect(LauncherScreen.settings),
          ),
        ],
      ),
    );
  }
}

// ── סרגל המצב העליון ──────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final NetworkState network;
  final String dataDir;
  final bool otzariaIsRunning;
  final DateTime? lastCheckedAt;
  final VoidCallback onOpenLog;
  final VoidCallback onRecheck;

  const _TopBar({
    required this.network,
    required this.dataDir,
    required this.otzariaIsRunning,
    required this.lastCheckedAt,
    required this.onOpenLog,
    required this.onRecheck,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      color: AppSurfaces.topBarBackground(context),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceMD,
        vertical: AppTokens.spaceSM,
      ),
      child: Row(
        children: [
          Text(
            'אוצריא — מנהל עדכונים',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: AppTokens.spaceMD),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _Pill(
                    icon: switch (network) {
                      NetworkState.online => FluentIcons.cloud_24_regular,
                      NetworkState.offline => FluentIcons.cloud_off_24_regular,
                      NetworkState.checking =>
                        FluentIcons.arrow_sync_24_regular,
                      NetworkState.unknown =>
                        FluentIcons.question_circle_24_regular,
                    },
                    label: switch (network) {
                      NetworkState.online => 'מחובר',
                      NetworkState.offline => 'לא מחובר',
                      NetworkState.checking => 'מוריד...',
                      NetworkState.unknown => 'הרשת לא נדרשה',
                    },
                  ),
                  const SizedBox(width: AppTokens.spaceSM),
                  // מקור העדכונים תמיד זהה — התיקייה שלצד התוכנה. אין מה
                  // להחליף, ולכן מוצג הנתיב עצמו ולא בחירה.
                  _Pill(
                    icon: FluentIcons.folder_24_regular,
                    label: 'העדכונים נקראים מהתיקייה שלצד התוכנה',
                    tooltip: dataDir,
                  ),
                  if (otzariaIsRunning) ...[
                    const SizedBox(width: AppTokens.spaceSM),
                    const StatusChip(
                      kind: StatusKind.needsAction,
                      label: 'אוצריא פתוחה — עדכון מסד חסום',
                    ),
                  ],
                  if (lastCheckedAt != null) ...[
                    const SizedBox(width: AppTokens.spaceSM),
                    Text(
                      'נבדק ב-${_formatTime(lastCheckedAt!)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SecondaryIconButton(
            icon: FluentIcons.arrow_sync_24_regular,
            tooltip: 'בדיקה מחדש',
            onPressed: onRecheck,
          ),
          const SizedBox(width: AppTokens.spaceSM),
          SecondaryIconButton(
            icon: FluentIcons.document_bullet_list_24_regular,
            tooltip: 'פתיחת יומן הפעילות',
            onPressed: onOpenLog,
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime time) {
    final t = time.toLocal();
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? tooltip;

  const _Pill({required this.icon, required this.label, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppSurfaces.topBarPill(cs),
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: AppTokens.fontMD,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    if (tooltip == null || tooltip!.isEmpty) return pill;
    return Tooltip(message: tooltip!, child: pill);
  }
}

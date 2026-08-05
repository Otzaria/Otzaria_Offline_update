import 'dart:async';
import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:library_manager/library_manager.dart';

import '../controllers/library_module_controller.dart';
import '../controllers/otzaria_module_controller.dart';
import '../services/app_logger.dart';
import '../services/file_reveal.dart';
import '../settings/settings_controller.dart';
import '../theme/theme_exports.dart';
import '../widgets/widgets_exports.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'plugins_screen.dart';
import 'settings_screen.dart';

/// מצב הרשת כפי שהוא נגזר מהבדיקה האחרונה. עד שייבנה
/// `NetworkStatusService` (תכנון §11.2) זו הערכה בלבד — הצלחה/כשל של
/// בדיקת המטא־דאטה, ולא בדיקת זמינות מקורות בפני עצמה.
enum NetworkState { unknown, checking, online, offline }

/// מקור העדכונים הפעיל.
enum UpdateSource { network, localMirror }

/// המסך הפעיל בסרגל הניווט.
enum LauncherScreen { home, library, plugins, settings }

/// מסגרת האפליקציה: סרגל ניווט קבוע בצד, סרגל מצב עליון, וארבעת המסכים.
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

  LauncherScreen _screen = LauncherScreen.home;
  NetworkState _network = NetworkState.unknown;
  bool _otzariaIsRunning = false;
  DateTime? _lastCheckedAt;

  @override
  void initState() {
    super.initState();
    _otzaria = OtzariaModuleController(dataDir: widget.dataDir)
      ..addListener(_onChange);
    _library = LibraryModuleController(dataDir: widget.dataDir)
      ..addListener(_onChange);
    widget.settings.addListener(_onChange);

    unawaited(_refreshProcessState());
    // בדיקת מטא־דאטה קלה בלבד, ורק אם המשתמש לא כיבה אותה. אין כאן שום
    // הורדה או התקנה — אלו תמיד יזומות (תכנון §2.2).
    if (widget.settings.settings.autoMetadataCheck) {
      unawaited(checkAll());
    }
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onChange);
    _otzaria.removeListener(_onChange);
    _library.removeListener(_onChange);
    _otzaria.dispose();
    _library.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshProcessState() async {
    const guard = OtzariaProcessGuard();
    final running = await guard.isAnyRunning(
      OtzariaProcessGuard.processNamesFor(Platform.operatingSystem),
    );
    if (!mounted) return;
    setState(() => _otzariaIsRunning = running);
  }

  /// בודק גרסאות בשני המודולים. לא מוריד ולא מתקין דבר.
  Future<void> checkAll() async {
    if (widget.settings.settings.offlineOnly) {
      setState(() => _network = NetworkState.offline);
    } else {
      setState(() => _network = NetworkState.checking);
    }

    await Future.wait([_otzaria.checkForUpdate(), _library.checkForUpdate()]);
    await _refreshProcessState();
    if (!mounted) return;

    final failed = _otzaria.status == OtzariaModuleStatus.error &&
        _library.status == LibraryModuleStatus.error;
    setState(() {
      _network = failed ? NetworkState.offline : NetworkState.online;
      _lastCheckedAt = DateTime.now();
    });
  }

  UpdateSource get _source => _library.activeMirrorPath != null
      ? UpdateSource.localMirror
      : UpdateSource.network;

  Future<void> _openLogFolder() async {
    final logger = AppLogger.instance;
    if (await FileReveal.revealDirectory(logger.logDir)) return;
    UiSnack.show('נתיב יומן הפעילות: ${logger.filePath}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppSurfaces.panelBackground(context),
      body: Row(
        children: [
          _NavRail(
            current: _screen,
            onSelect: (screen) => setState(() => _screen = screen),
          ),
          Expanded(
            child: Column(
              children: [
                _TopBar(
                  network: _network,
                  source: _source,
                  mirrorPath: _library.activeMirrorPath,
                  otzariaIsRunning: _otzariaIsRunning,
                  lastCheckedAt: _lastCheckedAt,
                  onOpenLog: _openLogFolder,
                  onRecheck: checkAll,
                ),
                Expanded(
                  child: IndexedStack(
                    index: _screen.index,
                    children: [
                      HomeScreen(
                        otzaria: _otzaria,
                        library: _library,
                        settings: widget.settings,
                        network: _network,
                        otzariaIsRunning: _otzariaIsRunning,
                        onRecheck: checkAll,
                        onGoToLibrary: () =>
                            setState(() => _screen = LauncherScreen.library),
                        onGoToPlugins: () =>
                            setState(() => _screen = LauncherScreen.plugins),
                      ),
                      LibraryScreen(
                        library: _library,
                        otzariaIsRunning: _otzariaIsRunning,
                        onProcessStateChanged: _refreshProcessState,
                      ),
                      const PluginsScreen(),
                      SettingsScreen(
                        controller: widget.settings,
                        onOpenLog: _openLogFolder,
                      ),
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
  final UpdateSource source;
  final String? mirrorPath;
  final bool otzariaIsRunning;
  final DateTime? lastCheckedAt;
  final VoidCallback onOpenLog;
  final VoidCallback onRecheck;

  const _TopBar({
    required this.network,
    required this.source,
    required this.mirrorPath,
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
                      NetworkState.checking => 'בודק...',
                      NetworkState.unknown => 'מצב רשת לא נבדק',
                    },
                  ),
                  const SizedBox(width: AppTokens.spaceSM),
                  _Pill(
                    icon: source == UpdateSource.localMirror
                        ? FluentIcons.usb_stick_24_regular
                        : FluentIcons.cloud_arrow_down_24_regular,
                    label: source == UpdateSource.localMirror
                        ? 'מקור: תיקייה מקומית / USB'
                        : 'מקור: אינטרנט',
                    tooltip: mirrorPath,
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

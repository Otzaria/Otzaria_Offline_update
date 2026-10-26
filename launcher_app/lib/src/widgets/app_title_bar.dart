// AppTitleBar — שורת הכותרת של החלון (מסגרת המערכת מוסתרת ב-main.dart).

import 'dart:async';
import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/app_strings_scope.dart';
import '../theme/theme_exports.dart';
import 'focus_ring.dart';

/// גובה השורה.
const double kAppTitleBarHeight = AppTokens.titleBarHeight;

/// הרוחב שנשמר בפינה **השמאלית הפיזית** ב-macOS לשלושת הכפתורים העגולים של
/// המערכת, שמצוירים מעל החלון.
const double _kMacTrafficLightsWidth = 78;

/// הכלי בשורת הכותרת שהדף שלו פתוח עכשיו — מסומן ברקע tonal.
enum TitleBarTool { help, settings }

/// ל-`MaterialApp.builder`, סביב ה-Navigator: [AppTitleBar] מצויר ב-Overlay
/// הזה, מעל כל המסלולים — כך שהשכבה של דו-שיח אינה מכסה אותו.
class TitleBarHost extends StatelessWidget {
  const TitleBarHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Overlay.wrap(child: child);
}

/// לוגו ושם, כלי עזרה והגדרות וכפתורי החלון; כל השאר גורר. מצויר ב-Overlay של
/// [TitleBarHost], ובזמן דו-שיח הכלים מושבתים וכפתורי החלון פעילים.
class AppTitleBar extends StatefulWidget {
  const AppTitleBar({
    super.key,
    this.onHelp,
    this.onSettings,
    this.activeTool,
    this.toolsEnabled = true,
    this.showTitle = true,
    this.showWindowButtons,
    this.isMacOS,
  });

  /// בלי שניהם אין כלים — מסכי העצירה.
  final VoidCallback? onHelp;
  final VoidCallback? onSettings;
  final TitleBarTool? activeTool;

  /// `false` בזמן שהיציאה ממתינה — הכלים נשארים במקומם אך אינם מגיבים.
  final bool toolsEnabled;

  /// מסכי העצירה מציגים את הלוגו בלבד.
  final bool showTitle;

  /// כפתורי מזעור/הגדלה/סגירה בסגנון Windows. `null` = לפי הפלטפורמה;
  /// בבדיקות widget מוזרק `false`.
  final bool? showWindowButtons;

  /// `null` = לפי הפלטפורמה. מוזרק בבדיקות.
  final bool? isMacOS;

  @override
  State<AppTitleBar> createState() => _AppTitleBarState();
}

class _AppTitleBarState extends State<AppTitleBar> with WindowListener {
  final OverlayPortalController _portal = OverlayPortalController();

  /// במסך מלא של macOS הכפתורים העגולים נעלמים, ואיתם הצורך במקום להם.
  bool _fullScreen = false;

  bool get _isMacOS => widget.isMacOS ?? Platform.isMacOS;

  /// ב-macOS המערכת מציירת את הכפתורים שלה (`windowButtonVisibility`).
  bool get _showWindowButtons =>
      !_isMacOS &&
      (widget.showWindowButtons ?? (Platform.isWindows || Platform.isLinux));

  @override
  void initState() {
    super.initState();
    _portal.show();
    if (_isMacOS) windowManager.addListener(this);
  }

  @override
  void dispose() {
    if (_isMacOS) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowEnterFullScreen() => setState(() => _fullScreen = true);

  @override
  void onWindowLeaveFullScreen() => setState(() => _fullScreen = false);

  @override
  Widget build(BuildContext context) => SizedBox(
        height: kAppTitleBarHeight,
        child: OverlayPortal(
          controller: _portal,
          overlayLocation: OverlayChildLocation.rootOverlay,
          overlayChildBuilder: (context) => Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: double.infinity,
              height: kAppTitleBarHeight,
              child: _bar(context),
            ),
          ),
          child: const SizedBox.expand(),
        ),
      );

  Widget _bar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = context.strings.shell;
    final onHelp = widget.onHelp;
    final onSettings = widget.onSettings;
    final toolsEnabled =
        widget.toolsEnabled && (ModalRoute.isCurrentOf(context) ?? true);

    return Container(
      // הקו לכל הרוחב, גם מתחת לכפתורי החלון — כמו במוקאפ.
      foregroundDecoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppSurfaces.shellDivider(context)),
        ),
      ),
      color: AppSurfaces.topBarBackground(context),
      // `EdgeInsets.only(left:)` ולא `EdgeInsetsDirectional`: הכפתורים של
      // macOS יושבים בפינה השמאלית הפיזית גם כשהממשק בעברית.
      padding: _isMacOS && !_fullScreen
          ? const EdgeInsets.only(left: _kMacTrafficLightsWidth)
          : EdgeInsets.zero,
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: DragToMoveArea(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(start: 12),
                      child: Row(
                        children: [
                          Image.asset(
                            'assets/images/otzaria_logo.png',
                            width: 16,
                            height: 16,
                            filterQuality: FilterQuality.medium,
                            semanticLabel: s.otzariaLogoLabel,
                          ),
                          const SizedBox(width: 8),
                          if (widget.showTitle)
                            Flexible(
                              child: Text(
                                s.appTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.meta.copyWith(
                                  color: cs.onSurface,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (onHelp != null || onSettings != null) ...[
                  _ToolsGate(
                    enabled: toolsEnabled,
                    child: Row(
                      children: [
                        if (onHelp != null)
                          _ToolButton(
                            icon: FluentIcons.question_circle_20_regular,
                            tooltip: s.helpTooltip,
                            active: widget.activeTool == TitleBarTool.help,
                            enabled: toolsEnabled,
                            onPressed: onHelp,
                          ),
                        if (onHelp != null && onSettings != null)
                          const _DragGap(width: 2),
                        if (onSettings != null)
                          _ToolButton(
                            icon: FluentIcons.settings_20_regular,
                            tooltip: s.settingsTooltip,
                            active: widget.activeTool == TitleBarTool.settings,
                            enabled: toolsEnabled,
                            onPressed: onSettings,
                          ),
                      ],
                    ),
                  ),
                  const _DragGap(width: 8),
                ],
              ],
            ),
          ),
          if (_showWindowButtons) const WindowCaptionButtons(),
        ],
      ),
    );
  }
}

/// רווח בין הכלים שגם הוא גורר את החלון. לא `DragToMoveArea` סביב הכלים
/// עצמם: הלחיצה הכפולה שלו מעכבת כל לחיצה בודדת על כלי.
class _DragGap extends StatelessWidget {
  const _DragGap({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) => DragToMoveArea(
        child: SizedBox(width: width, height: kAppTitleBarHeight),
      );
}

class _ToolsGate extends StatelessWidget {
  const _ToolsGate({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) => AbsorbPointer(
        absorbing: !enabled,
        child: ExcludeFocus(excluding: !enabled, child: child),
      );
}

/// כלי בשורת הכותרת: 36×28, רדיוס 6.
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final bool enabled;
  final VoidCallback onPressed;

  static const BorderRadius _radius = BorderRadius.all(Radius.circular(6));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        enabled: enabled,
        selected: active,
        label: tooltip,
        onTap: enabled ? onPressed : null,
        excludeSemantics: true,
        child: FocusRing(
          borderRadius: _radius,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onPressed,
              borderRadius: _radius,
              // הכלי הפעיל נשאר שטוח גם בריחוף (`.tb-tool.on`).
              overlayColor: active
                  ? const WidgetStatePropertyAll(Colors.transparent)
                  : AppSurfaces.stateLayer(cs.primary),
              child: Ink(
                width: 36,
                height: 28,
                decoration: BoxDecoration(
                  color: active ? cs.secondaryContainer : null,
                  borderRadius: _radius,
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: active ? cs.onSecondaryContainer : cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _Caption { minimize, maximize, close }

/// שלושת כפתורי החלון, 46×36 כל אחד, מצוירים כמו ב-Windows 11. הסגירה עוברת
/// ב-`windowManager.close`, ולכן ב-`closeGuard` של `LauncherCrashSession`.
class WindowCaptionButtons extends StatefulWidget {
  const WindowCaptionButtons({super.key});

  @override
  State<WindowCaptionButtons> createState() => _WindowCaptionButtonsState();
}

class _WindowCaptionButtonsState extends State<WindowCaptionButtons>
    with WindowListener {
  /// נשאל מהחלון: ה-runner פותח אותו מוגדל כשהוא אינו נכנס בשטח העבודה.
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(_syncMaximized());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _syncMaximized() async {
    final maximized = await windowManager.isMaximized();
    if (mounted && maximized != _maximized) {
      setState(() => _maximized = maximized);
    }
  }

  Future<void> _toggleMaximized() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
    await _syncMaximized();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  void onWindowRestore() => unawaited(_syncMaximized());

  @override
  Widget build(BuildContext context) {
    final s = context.strings.shell;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CaptionButton(
          kind: _Caption.minimize,
          label: s.windowMinimize,
          onPressed: () => unawaited(windowManager.minimize()),
        ),
        _CaptionButton(
          kind: _Caption.maximize,
          maximized: _maximized,
          label: _maximized ? s.windowRestore : s.windowMaximize,
          onPressed: () => unawaited(_toggleMaximized()),
        ),
        _CaptionButton(
          kind: _Caption.close,
          label: s.windowClose,
          onPressed: () => unawaited(windowManager.close()),
        ),
      ],
    );
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.kind,
    required this.label,
    required this.onPressed,
    this.maximized = false,
  });

  final _Caption kind;
  final String label;
  final VoidCallback onPressed;
  final bool maximized;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final isClose = widget.kind == _Caption.close;
    final background = !_hovered
        ? null
        : isClose
            ? palette.closeHover
            : palette.captionHover;
    final glyph =
        _hovered && isClose ? palette.closeGlyph : palette.captionGlyph;

    return Semantics(
      button: true,
      label: widget.label,
      onTap: widget.onPressed,
      excludeSemantics: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Container(
            width: AppTokens.captionButtonWidth,
            height: kAppTitleBarHeight,
            color: background,
            alignment: Alignment.center,
            child: CustomPaint(
              size: const Size(10, 10),
              painter: _GlyphPainter(widget.kind, widget.maximized, glyph),
            ),
          ),
        ),
      ),
    );
  }
}

/// הסמלים של המוקאפ: קו, מלבן מעוגל (או שניים בשחזור) ו-X, בעובי 1.
class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.kind, this.maximized, this.color);

  final _Caption kind;
  final bool maximized;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    switch (kind) {
      case _Caption.minimize:
        canvas.drawLine(const Offset(0, 5.5), const Offset(10, 5.5), paint);
      case _Caption.maximize when maximized:
        canvas.drawRRect(
          RRect.fromLTRBR(0.5, 2.5, 7.5, 9.5, const Radius.circular(1.5)),
          paint,
        );
        canvas.drawPath(
          Path()
            ..moveTo(2.5, 2.5)
            ..lineTo(2.5, 1.5)
            ..arcToPoint(const Offset(3.5, 0.5),
                radius: const Radius.circular(1))
            ..lineTo(8.5, 0.5)
            ..arcToPoint(const Offset(9.5, 1.5),
                radius: const Radius.circular(1))
            ..lineTo(9.5, 6.5)
            ..arcToPoint(const Offset(8.5, 7.5),
                radius: const Radius.circular(1))
            ..lineTo(7.5, 7.5),
          paint,
        );
      case _Caption.maximize:
        canvas.drawRRect(
          RRect.fromLTRBR(0.5, 0.5, 9.5, 9.5, const Radius.circular(1.5)),
          paint,
        );
      case _Caption.close:
        canvas.drawLine(const Offset(0.5, 0.5), const Offset(9.5, 9.5), paint);
        canvas.drawLine(const Offset(9.5, 0.5), const Offset(0.5, 9.5), paint);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.kind != kind || old.maximized != maximized || old.color != color;
}

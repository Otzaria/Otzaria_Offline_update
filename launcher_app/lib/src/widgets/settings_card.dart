// כרטיס הגדרות ושורות ההגדרה — פורט מאוצריא
// (`otzaria/lib/settings/widgets/settings_card.dart`), בגרסה מצומצמת:
// ללא אנכורי חיפוש, dropdown ותפריטי נתיב.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme_exports.dart';
import 'app_card.dart';
import 'custom_switch.dart';
import 'rtl_icon.dart';
import 'segmented_control.dart';

// ── SettingsCard ──────────────────────────────────────────────────────────────

/// כרטיס הגדרות מעוצב בסגנון M3 — כותרת מעל הכרטיס, שורות בתוכו.
class SettingsCard extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final List<Widget> children;

  const SettingsCard({
    super.key,
    this.title,
    this.subtitle,
    required this.children,
  });

  /// סגנון כותרת הכרטיס — מקור אמת יחיד.
  static TextStyle? titleStyleOf(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.bold,
      color: theme.colorScheme.primary,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (title == null || title!.isEmpty) {
      return AppCard.section(children: children);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.only(
            right: 16,
            left: 16,
            top: 24,
            bottom: 12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title!, style: titleStyleOf(context)),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        AppCard.section(children: children),
      ],
    );
  }
}

// ── Helpers לטיפוגרפיה אחידה ──────────────────────────────────────────────────

Widget _settingTitle(String text) => Text(
      text,
      style: AppTextStyles.settingTitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

Widget _settingSubtitle(String text, {Color? color, bool ltr = false}) => Text(
      text,
      style: color != null
          ? AppTextStyles.settingSubtitle.copyWith(color: color)
          : AppTextStyles.settingSubtitle,
      textDirection: ltr ? TextDirection.ltr : null,
      textAlign: ltr ? TextAlign.end : null,
    );

Widget? _buildSettingIcon(IconData? icon, IconData? rtlIcon, Color? iconColor) {
  if (rtlIcon != null) return RtlIcon(rtlIcon, color: iconColor);
  if (icon != null) return Icon(icon, color: iconColor);
  return null;
}

// ── SettingsActionTile ────────────────────────────────────────────────────────

/// שורת הגדרה רספונסיבית — מקור האמת לפריסה, מרווחים וסגנון של כל השורות.
///
/// - מסך רחב: [ListTile] עם ה-actions ב-trailing.
/// - מסך צר / טקסט שגולש: כותרת למעלה, actions מתחתיה.
class SettingsActionTile extends StatelessWidget {
  final IconData? icon;
  final IconData? rtlIcon;
  final Color? iconColor;
  final Widget title;
  final Widget? subtitle;
  final List<Widget> actions;
  final VoidCallback? onTap;
  final FocusNode? focusNode;
  final bool enabled;
  final bool responsiveActions;
  final Widget? leading;

  /// טקסט גולמי לבדיקת גלישה עם TextPainter — מאוכלס רק ב-.text()/.path()
  final String? _rawTitle;

  const SettingsActionTile({
    super.key,
    this.icon,
    this.rtlIcon,
    this.iconColor,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.onTap,
    this.focusNode,
    this.enabled = true,
    this.responsiveActions = true,
    this.leading,
  })  : _rawTitle = null,
        assert(
          icon == null || rtlIcon == null,
          'העבר icon או rtlIcon — לא שניהם יחד',
        );

  SettingsActionTile.text({
    super.key,
    this.icon,
    this.rtlIcon,
    this.iconColor,
    required String title,
    String? subtitle,
    bool subtitleLtr = false,
    Color? subtitleColor,
    this.actions = const [],
    this.onTap,
    this.focusNode,
    this.enabled = true,
    this.responsiveActions = true,
    this.leading,
  })  : assert(
          icon == null || rtlIcon == null,
          'העבר icon או rtlIcon — לא שניהם יחד',
        ),
        _rawTitle = title,
        title = _settingTitle(title),
        subtitle = subtitle != null
            ? _settingSubtitle(subtitle, color: subtitleColor, ltr: subtitleLtr)
            : null;

  /// שורת נתיב קובץ — מאכפת LTR ומוסיפה סימני U+200E אחרי מפרידים.
  SettingsActionTile.path({
    super.key,
    this.icon,
    this.rtlIcon,
    this.iconColor,
    required String title,
    required String? path,
    required String placeholder,
    this.actions = const [],
    this.onTap,
    this.focusNode,
    this.enabled = true,
    this.responsiveActions = true,
    this.leading,
  })  : assert(
          icon == null || rtlIcon == null,
          'העבר icon או rtlIcon — לא שניהם יחד',
        ),
        _rawTitle = title,
        title = _settingTitle(title),
        subtitle = _settingSubtitle(
          (path != null && path.isNotEmpty) ? _formatPath(path) : placeholder,
          ltr: path != null && path.isNotEmpty,
        );

  /// שורת on/off עם [CustomSwitch]; לחיצה על כל השורה, Enter ו-Space מחליפים.
  static Widget switchTile({
    Key? key,
    IconData? icon,
    IconData? rtlIcon,
    required String title,
    String? subtitle,
    required bool value,
    ValueChanged<bool>? onChanged,
    bool enabled = true,
  }) =>
      _SwitchTile(
        key: key,
        icon: icon,
        rtlIcon: rtlIcon,
        title: title,
        subtitle: subtitle,
        value: value,
        onChanged: onChanged,
        enabled: enabled,
      );

  /// שורה עם [AppSegmentedControl] — 2–4 אפשרויות מוציאות זו את זו.
  static Widget segmentedTile<T>({
    Key? key,
    IconData? icon,
    IconData? rtlIcon,
    required String title,
    String? subtitle,
    required List<SegmentOption<T>> options,
    required T currentValue,
    required ValueChanged<T> onChanged,
  }) =>
      _SegmentedTile<T>(
        key: key,
        icon: icon,
        rtlIcon: rtlIcon,
        title: title,
        subtitle: subtitle,
        options: options,
        currentValue: currentValue,
        onChanged: onChanged,
      );

  // ── Internals ──────────────────────────────────────────────────────────────

  static final RegExp _pathSeparatorRegExp = RegExp(r'[/\\]');

  static String _formatPath(String path) =>
      path.replaceAllMapped(_pathSeparatorRegExp, (m) => '${m[0]!}‎');

  Widget? _buildIcon() =>
      leading ?? _buildSettingIcon(icon, rtlIcon, iconColor);

  Widget? _buildTrailing() {
    if (actions.isEmpty) return null;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: actions,
    );
  }

  Widget _buildListTile() => ListTile(
        focusNode: focusNode,
        enabled: enabled,
        onTap: onTap,
        // ה-hover צריך להופיע על כפתורי הפעולה בלבד, לא על השורה כולה.
        hoverColor: actions.isNotEmpty ? Colors.transparent : null,
        leading: _buildIcon(),
        title: title,
        subtitle: subtitle,
        trailing: _buildTrailing(),
      );

  // אומדן שמרני לרוחב ה-actions, כדי להטות לפריסה האנכית ולא לדחוס את הטקסט.
  bool _wouldTextOverflow(double containerWidth, TextDirection textDirection) {
    if (_rawTitle == null) return false;
    const iconAreaWidth = 56.0;
    const hPadding = 32.0;
    final actionsEst = actions.length * 170.0;
    final textWidth = containerWidth - iconAreaWidth - hPadding - actionsEst;
    if (textWidth <= 80) return true;

    final titlePainter = TextPainter(
      text: TextSpan(text: _rawTitle, style: AppTextStyles.settingTitle),
      textDirection: textDirection,
      maxLines: 1,
    )..layout(maxWidth: textWidth);
    return titlePainter.didExceedMaxLines;
  }

  Widget _buildColumnLayout() {
    final iconWidget = _buildIcon();
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (iconWidget != null) ...[
                iconWidget,
                const SizedBox(width: 16),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    title,
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      subtitle!,
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: actions,
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: enabled ? onTap : null,
      focusNode: focusNode,
      child: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!responsiveActions) return _buildListTile();
    return LayoutBuilder(
      builder: (context, constraints) =>
          _wouldTextOverflow(constraints.maxWidth, Directionality.of(context))
              ? _buildColumnLayout()
              : _buildListTile(),
    );
  }
}

// ── _SwitchTile ───────────────────────────────────────────────────────────────

class _SwitchTile extends StatefulWidget {
  final IconData? icon;
  final IconData? rtlIcon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  const _SwitchTile({
    super.key,
    this.icon,
    this.rtlIcon,
    required this.title,
    this.subtitle,
    required this.value,
    this.onChanged,
    this.enabled = true,
  });

  @override
  State<_SwitchTile> createState() => _SwitchTileState();
}

class _SwitchTileState extends State<_SwitchTile> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'switch_tile');
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _toggle() {
    if (!widget.enabled || widget.onChanged == null) return;
    widget.onChanged!(!widget.value);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_focusNode.canRequestFocus) _focusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final canToggle = widget.enabled && widget.onChanged != null;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space) {
          _toggle();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: SettingsActionTile.text(
        icon: widget.icon,
        rtlIcon: widget.rtlIcon,
        title: widget.title,
        subtitle: widget.subtitle,
        enabled: widget.enabled,
        focusNode: _focusNode,
        responsiveActions: false,
        onTap: canToggle ? _toggle : null,
        actions: [
          ExcludeFocus(
            child: CustomSwitch(
              value: widget.value,
              onChanged: canToggle ? (_) => _toggle() : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ── _SegmentedTile ────────────────────────────────────────────────────────────

const _kSegBaseNoIcon = 60.0;
const _kSegBaseWithIcon = 80.0;
const _kSegCharWidth = 8.0;
const _kSegGroupPadding = 24.0;
const _kSegMinWidth = 180.0;
const _kSegMaxWidth = 400.0;

double _segGroupWidth(List<SegmentOption<dynamic>> options) {
  final hasIcons = options.any((o) => o.icon != null || o.rtlIcon != null);
  final maxLen =
      options.map((o) => o.label.length).reduce((a, b) => a > b ? a : b);
  final btnW = (hasIcons ? _kSegBaseWithIcon : _kSegBaseNoIcon) +
      maxLen * _kSegCharWidth;
  return (btnW * options.length + _kSegGroupPadding)
      .clamp(_kSegMinWidth, _kSegMaxWidth);
}

class _SegmentedTile<T> extends StatelessWidget {
  final IconData? icon;
  final IconData? rtlIcon;
  final String title;
  final String? subtitle;
  final List<SegmentOption<T>> options;
  final T currentValue;
  final ValueChanged<T> onChanged;

  const _SegmentedTile({
    super.key,
    this.icon,
    this.rtlIcon,
    required this.title,
    this.subtitle,
    required this.options,
    required this.currentValue,
    required this.onChanged,
  });

  /// [subtitle], אם סופק, גובר על תת-הכותרת של האפשרות הנבחרת.
  String? get _resolvedSubtitle {
    if (subtitle != null) return subtitle;
    for (final o in options) {
      if (o.value == currentValue) return o.subtitle;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < LayoutBreakpoints.compact;
        final control = AppSegmentedControl<T>(
          options: options,
          currentValue: currentValue,
          onChanged: onChanged,
          expandToFillWidth: isNarrow,
          height: 40,
        );

        if (!isNarrow) {
          return SettingsActionTile.text(
            icon: icon,
            rtlIcon: rtlIcon,
            title: title,
            subtitle: _resolvedSubtitle,
            actions: [
              SizedBox(width: _segGroupWidth(options), child: control),
            ],
          );
        }

        // מסך צר: כותרת ב-ListTile, הפקד מתחתיה ברוחב מלא
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: _buildSettingIcon(icon, rtlIcon, null),
              title: _settingTitle(title),
              subtitle: _resolvedSubtitle != null
                  ? _settingSubtitle(_resolvedSubtitle!)
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
              child: control,
            ),
          ],
        );
      },
    );
  }
}

// כרטיס הגדרות ושורות ההגדרה — פורט מאוצריא
// (`otzaria/lib/settings/widgets/settings_card.dart`), בגרסה מצומצמת:
// ללא אנכורי חיפוש, dropdown ותפריטי נתיב.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme_exports.dart';
import 'app_card.dart';
import 'app_dropdown_field.dart';
import 'custom_switch.dart';
import 'rtl_icon.dart';
import 'segmented_control.dart';

// ── SettingsCard ──────────────────────────────────────────────────────────────

/// כרטיס הגדרות מעוצב בסגנון M3 — כותרת מעל הכרטיס, שורות בתוכו.
class SettingsCard extends StatelessWidget {
  final String? title;
  final String? subtitle;

  /// הסבר שמוצג בריחוף על סימן שאלה שליד הכותרת — לכרטיס שההסבר שלו נכון
  /// אך אינו צריך לתפוס שורה קבועה על המסך.
  final String? hint;
  final List<Widget> children;

  /// כפתורי הפעולה של הכרטיס. מוצגים **מתחת** למשטח הכרטיס ולא כשורה בתוכו,
  /// כדי שלא יישבו בפס לבן משל עצמם.
  final List<Widget> actions;

  const SettingsCard({
    super.key,
    this.title,
    this.subtitle,
    this.hint,
    required this.children,
    this.actions = const [],
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
    final hasHeader = title != null && title!.isNotEmpty;
    if (!hasHeader && actions.isEmpty) {
      return AppCard.section(children: children);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasHeader)
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
                Row(
                  children: [
                    Flexible(child: Text(title!, style: titleStyleOf(context))),
                    if (hint != null) ...[
                      const SizedBox(width: AppTokens.spaceXS),
                      _HintIcon(hint!),
                    ],
                  ],
                ),
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
        if (actions.isNotEmpty)
          CardActionsRow(
            // רק מלמעלה: הכפתורים מיושרים לקצה הכרטיס שמעליהם, והמרווח
            // לכרטיס הבא מגיע ממילא מריפוד הכותרת שלו.
            padding: const EdgeInsets.only(top: AppTokens.spaceMD),
            actions: actions,
          ),
      ],
    );
  }
}

/// שורת כפתורי הפעולה של כרטיס.
///
/// ברירת המחדל היא ריפוד מלא — לשורה שיושבת *בתוך* משטח הכרטיס.
/// [SettingsCard.actions] מציב אותה מתחתיו, על רקע הלוח, עם ריפוד משלו.
class CardActionsRow extends StatelessWidget {
  final List<Widget> actions;
  final EdgeInsetsGeometry padding;

  const CardActionsRow({
    super.key,
    required this.actions,
    this.padding = const EdgeInsets.all(AppTokens.spaceMD),
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Wrap(
          spacing: AppTokens.spaceSM,
          runSpacing: AppTokens.spaceSM,
          children: actions,
        ),
      );
}

/// סימן השאלה שלצד כותרת הכרטיס. גם לחיצה פותחת אותו, כי במסך מגע אין ריחוף.
class _HintIcon extends StatelessWidget {
  const _HintIcon(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: message,
        triggerMode: TooltipTriggerMode.tap,
        child: Icon(
          FluentIcons.question_circle_24_regular,
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
}

// ── Helpers לטיפוגרפיה אחידה ──────────────────────────────────────────────────

Widget _settingTitle(String text, {String? hint}) {
  final label = Text(
    text,
    style: AppTextStyles.settingTitle,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
  if (hint == null) return label;

  // ההסבר הארוך יושב בסימן שאלה ולא בשורה נוספת מתחת לכותרת.
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Flexible(child: label),
      const SizedBox(width: AppTokens.spaceXS),
      _HintIcon(hint),
    ],
  );
}

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
    String? hint,
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
        title = _settingTitle(title, hint: hint),
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
    String? hint,
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
        hint: hint,
        value: value,
        onChanged: onChanged,
        enabled: enabled,
      );

  /// שורה עם [AppDropdownField]. [subtitle] — כשלא סופק, נלקח מתת-הכותרת של
  /// האפשרות הנבחרת.
  static Widget dropdownTile<T>({
    Key? key,
    IconData? icon,
    IconData? rtlIcon,
    required String title,
    String? subtitle,
    required List<AppMenuEntry<T>> entries,
    required T currentValue,
    required ValueChanged<T> onSelected,
    double? width,
  }) =>
      _DropdownTile<T>(
        key: key,
        icon: icon,
        rtlIcon: rtlIcon,
        title: title,
        subtitle: subtitle,
        entries: entries,
        currentValue: currentValue,
        onSelected: onSelected,
        width: width,
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
    double? width,
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
        width: width,
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
  final String? hint;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  const _SwitchTile({
    super.key,
    this.icon,
    this.rtlIcon,
    required this.title,
    this.subtitle,
    this.hint,
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
        hint: widget.hint,
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

// ── _DropdownTile ─────────────────────────────────────────────────────────────

/// רוחב התיבה לפי התווית הארוכה ברשימה — לא רוחב קבוע: תיבה של שלוש שפות
/// אינה צריכה להיות ברוחב של פקד סגמנטד.
double _dropdownWidth(List<AppMenuEntry<dynamic>> entries) {
  final maxLen =
      entries.map((e) => e.label.length).reduce((a, b) => a > b ? a : b);
  // ריפוד + סמל החץ + רוחב תו ממוצע.
  return (56 + maxLen * 9.0).clamp(120.0, 400.0);
}

class _DropdownTile<T> extends StatelessWidget {
  final IconData? icon;
  final IconData? rtlIcon;
  final String title;
  final String? subtitle;
  final List<AppMenuEntry<T>> entries;
  final T currentValue;
  final ValueChanged<T> onSelected;
  final double? width;

  const _DropdownTile({
    super.key,
    this.icon,
    this.rtlIcon,
    required this.title,
    this.subtitle,
    required this.entries,
    required this.currentValue,
    required this.onSelected,
    this.width,
  });

  String? get _resolvedSubtitle {
    if (subtitle != null) return subtitle;
    for (final e in entries) {
      if (e.value == currentValue) return e.subtitle;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final field = AppDropdownField<T>(
      value: currentValue,
      entries: entries,
      onSelected: onSelected,
      height: _kSegBoxHeight,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= LayoutBreakpoints.compact) {
          return SettingsActionTile.text(
            icon: icon,
            rtlIcon: rtlIcon,
            title: title,
            subtitle: _resolvedSubtitle,
            actions: [
              SizedBox(
                width: width ?? _dropdownWidth(entries),
                height: _kSegBoxHeight,
                child: field,
              ),
            ],
          );
        }

        // מסך צר: כותרת ב-ListTile, הפקד מתחתיה ברוחב מלא — כמו בשורת הסגמנטד.
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
              child: SizedBox(height: _kSegBoxHeight, child: field),
            ),
          ],
        );
      },
    );
  }
}

// ── _SegmentedTile ────────────────────────────────────────────────────────────

/// גובה תיבת הפקד — נכפה גם על הכפתורים שבתוכה. כשהתיבה הייתה נמוכה מהם
/// הם גלשו מטה, והתווית נראתה יושבת מתחת למרכז.
const _kSegBoxHeight = 32.0;

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

  /// עוקף את הרוחב המחושב מ-[_segGroupWidth] — לשורות שצריכות להשתוות
  /// ברוחב לשורה אחרת בכרטיס, בלי קשר לאורך התוויות שלהן.
  final double? width;

  const _SegmentedTile({
    super.key,
    this.icon,
    this.rtlIcon,
    required this.title,
    this.subtitle,
    required this.options,
    required this.currentValue,
    required this.onChanged,
    this.width,
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
          height: _kSegBoxHeight,
        );

        if (!isNarrow) {
          return SettingsActionTile.text(
            icon: icon,
            rtlIcon: rtlIcon,
            title: title,
            subtitle: _resolvedSubtitle,
            actions: [
              // התיבה כאן והגובה שנכפה על הכפתורים חייבים להיות זהים: תווית
              // ארוכה מותחת את SegmentedButton, ופער בין השניים מזיז את
              // התוכן ביחס לתיבה במקום למרכז אותו.
              SizedBox(
                width: width ?? _segGroupWidth(options),
                height: _kSegBoxHeight,
                child: control,
              ),
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

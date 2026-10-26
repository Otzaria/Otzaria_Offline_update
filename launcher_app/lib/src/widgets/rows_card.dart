import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../theme/theme_exports.dart';
import 'app_card.dart';
import 'custom_switch.dart';
import 'focus_ring.dart';
import 'rtl_icon.dart';

/// כרטיס של שורות (`.rows`) — [AppCard.section] בשם של המוקאפ.
class RowsCard extends StatelessWidget {
  const RowsCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => AppCard.section(children: children);
}

/// שורה (`.row`): ריפוד 12/16, רווח 14, גובה לפחות 56. עם [onTap] היא לחיצה
/// ומסתיימת בחץ.
class AppRow extends StatelessWidget {
  const AppRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.label,
    this.below,
    this.dense = false,
    this.titleDirection,
    this.alignTop = false,
  });

  /// אריח הסמל והקצה בראש השורה ולא במרכזה — לשורה שיש מתחתיה פקדים.
  final bool alignTop;

  /// שורת סיכום בחלון צר: 44 במקום 56.
  final bool dense;

  final String title;

  /// [TextDirection.ltr] לכותרת שהיא מספר גרסה, נתיב וכדומה.
  final TextDirection? titleDirection;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// שורת סיכום: תווית קטנה מעל ערך 16 במקום כותרת 14/600.
  final String? label;

  /// מתחת לפירוט — למשל נתיב ([PathText]).
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null)
          Text(label!,
              style: AppTextStyles.meta.copyWith(
                color: cs.onSurfaceVariant,
              )),
        Text(
          title,
          textDirection: titleDirection,
          style:
              (label != null ? AppTextStyles.rowValue : AppTextStyles.rowTitle)
                  .copyWith(color: cs.onSurface),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: AppTextStyles.rowSub.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
        if (below != null) ...[const SizedBox(height: 4), below!],
      ],
    );
    final row = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: dense ? 44 : AppTokens.rowMinHeight,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: dense ? 4 : 12),
        child: Row(
          crossAxisAlignment:
              alignTop ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 14)],
            Expanded(child: text),
            if (trailing != null) ...[const SizedBox(width: 14), trailing!],
            if (onTap != null) ...[
              const SizedBox(width: 14),
              RtlIcon(
                FluentIcons.chevron_right_20_regular,
                size: 20,
                color: cs.outline,
              ),
            ],
          ],
        ),
      ),
    );
    if (onTap == null) return row;
    // הכרטיס חותך את השורה, ולכן הטבעת בפנים.
    return FocusRing(
      borderRadius: BorderRadius.zero,
      offset: -3,
      child: InkWell(
        onTap: onTap,
        overlayColor: AppSurfaces.stateLayer(cs.primary),
        child: row,
      ),
    );
  }
}

/// שורה עם מתג (`.row` + `.sw`): כל השורה לחיצה, וגם Enter ו-Space. בלי
/// [onChanged] היא מושבתת, והפירוט אומר למה.
class AppSwitchRow extends StatelessWidget {
  const AppSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.leading,
    this.below,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? below;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final onChanged = this.onChanged;
    final toggle = onChanged == null ? null : () => onChanged(!value);
    return Semantics(
      toggled: value,
      enabled: onChanged != null,
      child: FocusRing(
        borderRadius: BorderRadius.zero,
        offset: -3,
        child: InkWell(
          onTap: toggle,
          overlayColor: AppSurfaces.stateLayer(cs.primary),
          child: AppRow(
            title: title,
            subtitle: subtitle,
            leading: leading,
            below: below,
            trailing: ExcludeFocus(
              child: CustomSwitch(
                value: value,
                onChanged: toggle == null ? null : (_) => toggle(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

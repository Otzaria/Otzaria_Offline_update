// תפריט נפתח בסגנון אוצריא (`otzaria/lib/widgets/misc/app_dropdown_field.dart`),
// בגרסה מצומצמת: בלי חיפוש, בלי צ'יפים ובלי תת-תפריטים — רק בחירה מרשימה.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../theme/theme_exports.dart';
import 'rtl_icon.dart';

/// אפשרות יחידה בתפריט נפתח.
class AppMenuEntry<T> {
  final T value;
  final String label;
  final IconData? icon;

  /// תת-כותרת המשויכת לאפשרות — מוצגת בשורת ההגדרה כשלא סופקה שם אחרת.
  final String? subtitle;

  const AppMenuEntry({
    required this.value,
    required this.label,
    this.icon,
    this.subtitle,
  });
}

/// כפתור טונאלי שפותח תפריט בחירה — החלופה לפקד סגמנטד כשיש הרבה אפשרויות
/// או כשהתוויות ארוכות.
class AppDropdownField<T> extends StatelessWidget {
  const AppDropdownField({
    super.key,
    required this.value,
    required this.entries,
    required this.onSelected,
    this.height,
  });

  final T value;
  final List<AppMenuEntry<T>> entries;
  final ValueChanged<T> onSelected;

  /// גובה כפוי לכפתור — כדי שיישב באותו גודל כמו פקדי הסגמנטד שלצדו.
  final double? height;

  AppMenuEntry<T>? get _selected {
    for (final entry in entries) {
      if (entry.value == value) return entry;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;

    return MenuAnchor(
      // התפריט נפתח מתחת לכפתור ובאותו רוחב, כמו בבורר של אוצריא.
      style: const MenuStyle(alignment: AlignmentDirectional.bottomStart),
      menuChildren: [
        for (final entry in entries)
          MenuItemButton(
            leadingIcon: entry.value == value
                ? const Icon(FluentIcons.checkmark_24_regular, size: 18)
                : const SizedBox(width: 18),
            onPressed: () => onSelected(entry.value),
            child: Text(entry.label),
          ),
      ],
      builder: (context, controller, _) => FilledButton.tonal(
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        style: FilledButton.styleFrom(
          minimumSize: Size(0, height ?? 40),
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppTokens.spaceMD,
            0,
            AppTokens.spaceSM,
            0,
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Row(
          children: [
            if (selected?.icon != null) ...[
              RtlIcon(selected!.icon!, size: 18),
              const SizedBox(width: AppTokens.spaceSM),
            ],
            Expanded(
              child: Text(
                selected?.label ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppTokens.spaceSM),
            const Icon(FluentIcons.chevron_down_24_regular, size: 18),
          ],
        ),
      ),
    );
  }
}

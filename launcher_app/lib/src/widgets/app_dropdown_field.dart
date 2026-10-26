// תפריט נפתח (`.dd` במוקאפ): שדה לבן עם מסגרת outline, בלי חיפוש ובלי
// תת-תפריטים — רק בחירה מרשימה.

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

/// שדה שפותח תפריט בחירה — החלופה לפקד סגמנטד כשיש הרבה אפשרויות או
/// כשהתוויות ארוכות.
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
    final cs = Theme.of(context).colorScheme;

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
      builder: (context, controller, _) => OutlinedButton(
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        // ריחוף מכהה את המסגרת בלבד, בלי רקע (`.dd:hover`).
        style: OutlinedButton.styleFrom(
          minimumSize: Size(150, height ?? AppTokens.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          backgroundColor: cs.surfaceContainerLowest,
          foregroundColor: cs.onSurface,
          overlayColor: Colors.transparent,
          textStyle: AppTextStyles.body,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ).copyWith(
          side: AppSurfaces.focusRingSide(
            cs.primary,
            WidgetStateProperty.resolveWith(
              (states) => BorderSide(
                color: states.contains(WidgetState.hovered)
                    ? cs.onSurface
                    : cs.outline,
              ),
            ),
          ),
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
            const SizedBox(width: 12),
            const Icon(FluentIcons.chevron_down_24_regular, size: 16),
          ],
        ),
      ),
    );
  }
}

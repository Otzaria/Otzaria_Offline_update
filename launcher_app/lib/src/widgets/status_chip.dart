import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../theme/theme_exports.dart';

/// סוגי חיווי המצב של רכיב. לכל אחד סמל **וגם** טקסט — לא צבע בלבד.
enum StatusKind {
  ok,
  updateAvailable,
  working,
  needsAction,
  error,
  unknown,

  /// נעול (כונן מוגן, נקבע לפי מחשב אחר) — אין מה לעשות כאן.
  locked,
}

/// שבב מצב: גלולה בגובה 24, סמל 14 וטקסט 12/600 (`.chip` במוקאפ).
class StatusChip extends StatelessWidget {
  final StatusKind kind;
  final String label;

  /// גובר על סמל ברירת המחדל של [kind] — למשל הורדה או שליחה בשבב אריח.
  final IconData? icon;

  const StatusChip({
    super.key,
    required this.kind,
    required this.label,
    this.icon,
  });

  IconData get _icon =>
      icon ??
      switch (kind) {
        StatusKind.ok => FluentIcons.checkmark_16_filled,
        StatusKind.updateAvailable => FluentIcons.arrow_sync_16_regular,
        StatusKind.working => FluentIcons.arrow_sync_16_regular,
        StatusKind.needsAction => FluentIcons.info_16_regular,
        StatusKind.error => FluentIcons.error_circle_16_regular,
        StatusKind.unknown => FluentIcons.question_circle_16_regular,
        StatusKind.locked => FluentIcons.lock_closed_16_regular,
      };

  /// רקע, טקסט, סמל, ומסגרת (רק לשבב הניטרלי).
  (Color, Color, Color, Color?) _colors(ColorScheme cs) => switch (kind) {
        StatusKind.ok => (
            cs.surfaceContainerHigh,
            cs.onSurfaceVariant,
            cs.primary,
            null,
          ),
        StatusKind.updateAvailable || StatusKind.working => (
            cs.secondaryContainer,
            cs.onSecondaryContainer,
            cs.onSecondaryContainer,
            null,
          ),
        StatusKind.needsAction || StatusKind.unknown => (
            Colors.transparent,
            cs.onSurfaceVariant,
            cs.onSurfaceVariant,
            cs.outlineVariant,
          ),
        StatusKind.error => (
            cs.errorContainer,
            cs.onErrorContainer,
            cs.onErrorContainer,
            null,
          ),
        StatusKind.locked => (
            cs.surfaceContainerHighest,
            cs.onSurfaceVariant,
            cs.onSurfaceVariant,
            null,
          ),
      };

  @override
  Widget build(BuildContext context) {
    final (background, foreground, iconColor, border) =
        _colors(Theme.of(context).colorScheme);

    return Container(
      constraints: const BoxConstraints(minHeight: AppTokens.chipHeight),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppTokens.pill,
        border: border == null ? null : Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          kind == StatusKind.working
              ? SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: iconColor,
                  ),
                )
              : Icon(_icon, size: 14, color: iconColor),
          const SizedBox(width: 5),
          // Flexible: השבב יושב גם בעמודה צרה, ותווית ארוכה מתקצרת.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.chip.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

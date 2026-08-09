import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../l10n/app_strings_scope.dart';
import '../theme/theme_exports.dart';
import 'action_buttons.dart';
import 'settings_card.dart';
import 'status_chip.dart';

/// שורת "מצב" בתוך [SettingsCard] — כותרת + [StatusChip].
class InfoStatusRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final StatusKind kind;
  final String label;

  const InfoStatusRow({
    super.key,
    required this.icon,
    required this.title,
    required this.kind,
    required this.label,
  });

  @override
  Widget build(BuildContext context) => SettingsActionTile.text(
        icon: icon,
        title: title,
        responsiveActions: false,
        actions: [StatusChip(kind: kind, label: label)],
      );
}

/// שורת שגיאה — הודעה בשפת הממשק, וכפתור "נסה שוב" כשיש מה לנסות.
/// פרטים טכניים נשארים ביומן הפעילות (תכנון §14).
class InfoErrorRow extends StatelessWidget {
  final String message;
  final Future<void> Function()? onRetry;

  const InfoErrorRow({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final common = context.strings.common;
    return SettingsActionTile.text(
      icon: FluentIcons.error_circle_24_regular,
      iconColor: cs.error,
      title: common.error,
      subtitle: message,
      subtitleColor: cs.error,
      actions: [
        if (onRetry != null)
          ActionButton.neutral(
            text: common.retry,
            icon: FluentIcons.arrow_sync_24_regular,
            onPressed: () => onRetry!(),
          ),
      ],
    );
  }
}

/// שורת התקדמות — טקסט שלב, אחוזים ומד. [progress] של null = מד לא־קבוע
/// (ואז אין אחוז להציג). [detail] הוא פירוט אופציונלי מתחת למד, למשל כמה
/// כבר ירד מתוך כמה — בהורדה ארוכה זה מה שמראה שהיא בכלל מתקדמת.
class InfoProgressRow extends StatelessWidget {
  final String stage;
  final double? progress;
  final String? detail;

  const InfoProgressRow({
    super.key,
    required this.stage,
    this.progress,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = progress?.clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceMD,
        vertical: AppTokens.spaceSM,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(stage, style: theme.textTheme.bodySmall),
              ),
              if (value != null) ...[
                const SizedBox(width: AppTokens.spaceSM),
                Text(
                  '${(value * 100).round()}%',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppTokens.spaceXS),
          LinearProgressIndicator(value: value, minHeight: 6),
          if (detail != null) ...[
            const SizedBox(height: AppTokens.spaceXS),
            Text(
              detail!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// שורת כפתורי הפעולה בתחתית כרטיס.
class CardActionsRow extends StatelessWidget {
  final List<Widget> actions;

  const CardActionsRow({super.key, required this.actions});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(AppTokens.spaceMD),
        child: Wrap(
          spacing: AppTokens.spaceSM,
          runSpacing: AppTokens.spaceSM,
          children: actions,
        ),
      );
}

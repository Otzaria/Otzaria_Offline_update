import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../l10n/app_strings_scope.dart';
import '../theme/theme_exports.dart';
import 'action_buttons.dart';
import 'app_dialogs.dart';
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
///
/// הודעה רב-שורתית (למשל כישלון התקנה, שגורר איתו את סוף לוג ה-Inno) מוצגת
/// בשורתה הראשונה בלבד, והשאר נפתח בדיאלוג: ארבעים שורות בתוך שורת כרטיס
/// דוחפות את כל מה שמתחתיהן ואינן נקראות ממילא.
class InfoErrorRow extends StatelessWidget {
  final String message;
  final Future<void> Function()? onRetry;

  const InfoErrorRow({super.key, required this.message, this.onRetry});

  /// השורה הראשונה היא הכותרת, וכל מה שאחריה — הפירוט (`null` כשאין כזה).
  (String, String?) get _headlineAndDetails {
    final breakAt = message.indexOf('\n');
    if (breakAt < 0) return (message, null);
    final details = message.substring(breakAt + 1).trim();
    return (message.substring(0, breakAt), details.isEmpty ? null : details);
  }

  Future<void> _showDetails(BuildContext context) {
    final common = context.strings.common;
    return showSingleActionDialog(
      context: context,
      title: common.errorDetailsTitle,
      content: message,
      confirmText: common.close,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final common = context.strings.common;
    final (headline, details) = _headlineAndDetails;

    return SettingsActionTile.text(
      icon: FluentIcons.error_circle_24_regular,
      iconColor: cs.error,
      title: common.error,
      subtitle: headline,
      subtitleColor: cs.error,
      actions: [
        if (details != null)
          ActionButton.ghost(
            text: common.errorDetailsButton,
            icon: FluentIcons.document_bullet_list_24_regular,
            onPressed: () => _showDetails(context),
          ),
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

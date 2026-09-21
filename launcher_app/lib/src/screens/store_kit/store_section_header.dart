import 'package:flutter/material.dart';

import '../../theme/theme_exports.dart';
import 'store_visuals.dart';

/// כותרת סעיף בחנות — "קו + עינית" מעל כותרת גדולה, תיאור אופציונלי,
/// ופעולה בקצה השורה. הפורמט של כל הסעיפים באתר התוספים.
class StoreSectionHeader extends StatelessWidget {
  const StoreSectionHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.description = '',
    this.footnote,
    this.action,
  });

  final String title;
  final String? eyebrow;
  final String description;
  final String? footnote;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (eyebrow != null) ...[
                StoreSectionEyebrow(eyebrow!),
                const SizedBox(height: AppTokens.spaceXS),
              ],
              Text(
                title,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: AppTokens.spaceXS),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (footnote != null) ...[
                const SizedBox(height: AppTokens.spaceXS),
                Text(
                  footnote!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (action != null) ...[
          const SizedBox(width: AppTokens.spaceMD),
          action!,
        ],
      ],
    );
  }
}

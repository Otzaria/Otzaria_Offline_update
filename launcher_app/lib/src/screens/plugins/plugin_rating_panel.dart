import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:plugins_manager/plugins_manager.dart';

import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import 'plugin_visuals.dart';

/// תוכן סעיף "דירוג המשתמשים" בעמוד התוסף — הממוצע, הכוכבים, מספר
/// המדרגים והפילוח לפי ציון, באותה צורה שהאתר מציג אותם.
///
/// **תצוגה בלבד.** הדירוג עצמו נעשה באתר ודורש חשבון; המראה רק נושאת את
/// המספרים אל המחשב הלא-מקוון, ואין כאן דרך לדרג.
class PluginRatingSummary extends StatelessWidget {
  const PluginRatingSummary({super.key, required this.plugin});

  final StorePlugin plugin;

  /// מעל הרוחב הזה הממוצע והפילוח יושבים זה לצד זה, כמו `md:` שבאתר.
  static const double _twoColumnWidth = 520;

  /// רוחב תיבת הממוצע בפריסה הרחבה — 220px, כמו באתר.
  static const double _averageWidth = 220;

  @override
  Widget build(BuildContext context) {
    final average = _averageBox(context);
    // בלי דירוגים אין מה לפלח — נשארת רק ההודעה "עדיין לא דורג".
    if (plugin.ratingCount <= 0) return average;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _twoColumnWidth) {
          return Column(
            children: [
              average,
              const SizedBox(height: AppTokens.spaceMD),
              _breakdown(context),
            ],
          );
        }
        return Row(
          children: [
            SizedBox(width: _averageWidth, child: average),
            const SizedBox(width: AppTokens.spaceLG),
            Expanded(child: _breakdown(context)),
          ],
        );
      },
    );
  }

  Widget _averageBox(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.strings.plugins;
    final rated = plugin.ratingCount > 0;

    return Container(
      padding: const EdgeInsets.all(AppTokens.spaceMD),
      decoration: BoxDecoration(
        color: AppSurfaces.panelSection(context),
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (rated) ...[
            Text(
              formatRating(plugin.ratingAvg),
              style: theme.textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppTokens.spaceXS),
          ],
          PluginRatingStars(value: rated ? plugin.ratingAvg : 0, size: 22),
          const SizedBox(height: AppTokens.spaceXS),
          Text(
            rated ? t.ratingCountLabel(plugin.ratingCount) : t.ratingEmpty,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (plugin.ratingVerifiedCount > 0) ...[
            const SizedBox(height: AppTokens.spaceSM),
            Tooltip(
              message: t.ratingVerifiedTooltip,
              child: StatusChip(
                kind: StatusKind.ok,
                label: t.ratingVerifiedLabel(plugin.ratingVerifiedCount),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _breakdown(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var score = 5; score >= 1; score--) ...[
          if (score < 5) const SizedBox(height: AppTokens.spaceSM),
          _BreakdownRow(
            score: score,
            count: _countFor(score),
            total: plugin.ratingCount,
          ),
        ],
      ],
    );
  }

  /// פילוח קצר (קטלוג פגום) נקרא כאפס ולא מפיל את השורה.
  int _countFor(int score) => score <= plugin.ratingBreakdown.length
      ? plugin.ratingBreakdown[score - 1]
      : 0;
}

/// שורת פילוח אחת: הציון, מד היחס מתוך כלל המדרגים, ומספר המדרגים שנתנו
/// אותו.
class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.score,
    required this.count,
    required this.total,
  });

  final int score;
  final int count;
  final int total;

  /// רוחב מזערי לתווית ולמונה, כדי שכל המדים יתחילו ויסתיימו באותו מקום.
  static const BoxConstraints _endWidth = BoxConstraints(minWidth: 30);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Row(
      children: [
        ConstrainedBox(
          constraints: _endWidth,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$score', style: style),
              const SizedBox(width: 2),
              const Icon(
                FluentIcons.star_16_filled,
                size: 13,
                color: AppColors.ratingStar,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppTokens.spaceSM),
        Expanded(
          child: ClipRRect(
            borderRadius: AppTokens.borderRadiusAll,
            child: Container(
              height: 10,
              color: theme.colorScheme.surfaceContainerHighest,
              child: FractionallySizedBox(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: total <= 0 ? 0 : count / total,
                child: const ColoredBox(color: AppColors.ratingStar),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppTokens.spaceSM),
        ConstrainedBox(
          constraints: _endWidth,
          child: Text('$count', style: style),
        ),
      ],
    );
  }
}

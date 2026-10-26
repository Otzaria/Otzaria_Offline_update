import 'package:flutter/material.dart';
import 'package:plugins_manager/plugins_manager.dart';

import '../../services/timestamps.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import 'plugin_visuals.dart';

/// "דירוג המשתמשים" בדף התוסף — תצוגה בלבד: הדירוג נעשה באתר, והכונן
/// רק נושא את המספרים.
class PluginRatingSummary extends StatelessWidget {
  const PluginRatingSummary({super.key, required this.plugin, this.asOf});

  final StorePlugin plugin;

  /// מתי המספרים ירדו לכונן.
  final DateTime? asOf;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = context.strings.plugins;
    final rated = plugin.ratingCount > 0;
    final meta = AppTextStyles.meta.copyWith(color: cs.onSurfaceVariant);

    final average = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          rated ? formatRating(plugin.ratingAvg) : '—',
          style: AppTextStyles.percent.copyWith(color: cs.onSurface),
        ),
        const SizedBox(height: 4),
        PluginRatingStars(value: rated ? plugin.ratingAvg : 0),
        const SizedBox(height: 4),
        Text(
          rated ? t.ratingCountLabel(plugin.ratingCount) : t.ratingEmpty,
          textAlign: TextAlign.center,
          style: meta,
        ),
        if (plugin.ratingVerifiedCount > 0) ...[
          const SizedBox(height: 8),
          Tooltip(
            message: t.ratingVerifiedTooltip,
            child: StatusChip(
              kind: StatusKind.ok,
              label: t.ratingVerifiedLabel(plugin.ratingVerifiedCount),
            ),
          ),
        ],
      ],
    );

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!rated)
            Center(child: average)
          else
            Row(
              children: [
                average,
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    children: [
                      for (var score = 5; score >= 1; score--)
                        _BreakdownRow(
                          score: score,
                          count: _countFor(score),
                          total: plugin.ratingCount,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(height: 10),
          Text(
            asOf == null
                ? t.ratingSourceNote
                : t.ratingAsOfNote(formatStoreLocalDate(asOf!)),
            style: meta,
          ),
        ],
      ),
    );
  }

  /// פילוח קצר (קטלוג פגום) נקרא כאפס ולא מפיל את השורה.
  int _countFor(int score) => score <= plugin.ratingBreakdown.length
      ? plugin.ratingBreakdown[score - 1]
      : 0;
}

/// שורת פילוח (`.rbar`): הציון, פס 6 בצבע הדירוג, ומספר המדרגים.
class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.score,
    required this.count,
    required this.total,
  });

  final int score;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = AppTextStyles.meta.copyWith(color: cs.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 14, child: Text('$score', style: style)),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: AppTokens.pill,
              child: Container(
                height: 6,
                color: cs.surfaceContainerHighest,
                child: FractionallySizedBox(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: total <= 0 ? 0 : count / total,
                  child: ColoredBox(color: AppPalette.of(context).rating),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 28, child: Text('$count', style: style)),
        ],
      ),
    );
  }
}

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:plugins_manager/plugins_manager.dart';

import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import '../store_kit/store_visuals.dart';

/// רכיבי התצוגה הקטנים **של התוספים בלבד** — דירוג, סטטוס וחיווי התקנה.
///
/// מה שמשותף לשני מסכי החנות (גלולה, תגית, תמונה, עינית ורוחב הפענוח)
/// יושב ב-`screens/store_kit/store_visuals.dart`. ראו launcher_app/README.md.

/// תווית סטטוס התוסף כפי שהאתר מדווח אותו (`stable`/`beta`/`experimental`).
/// המפתחות מגיעים מה-API ואינם מתורגמים — רק התוויות שמוצגות.
String pluginStatusLabel(String status) {
  final t = AppL10n.strings.plugins;
  return switch (status) {
    'stable' => t.statusStable,
    'beta' => t.statusBeta,
    'experimental' => t.statusExperimental,
    _ => t.statusUnknown,
  };
}

/// הממוצע כפי שהאתר מציג אותו — ספרה אחת אחרי הנקודה, תמיד.
String formatRating(double value) => value.toStringAsFixed(1);

/// חמישה כוכבים עם מילוי חלקי לפי [value] — הפורט של `StarRating` שבאתר:
/// שכבת כוכבים מעומעמת, ומעליה שכבה כתומה שנחתכת ל-`value/5` מהרוחב.
///
/// **תצוגה בלבד.** את הדירוג עצמו נותנים באתר (דורש חשבון), ואין כאן
/// שום דרך לדרג — גם לא במחשב מקוון.
class PluginRatingStars extends StatelessWidget {
  const PluginRatingStars({super.key, required this.value, this.size = 13});

  final double value;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final clamped = value.clamp(0.0, 5.0);

    return Semantics(
      label: AppL10n.strings.plugins.ratingStarsLabel(formatRating(clamped)),
      child: Stack(
        alignment: AlignmentDirectional.centerStart,
        children: [
          _stars(cs.onSurfaceVariant.withValues(alpha: .3)),
          // Align עם widthFactor הוא מה שחותך כאן — ב-RTL ה-start הוא
          // הצד הימני, ולכן המילוי מתחיל מאותו כוכב כמו באתר.
          ClipRect(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: clamped / 5,
              child: _stars(AppColors.ratingStar),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stars(Color color) {
    final icon =
        size < 20 ? FluentIcons.star_16_filled : FluentIcons.star_24_filled;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++) Icon(icon, size: size, color: color),
      ],
    );
  }
}

/// גלולת הדירוג — כוכבים, הממוצע ומספר המדרגים בסוגריים, כמו בכרטיס
/// שבאתר. מי שקורא לה אחראי להסתיר אותה כשאין דירוגים כלל.
class PluginRatingBadge extends StatelessWidget {
  const PluginRatingBadge({super.key, required this.plugin});

  final StorePlugin plugin;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.plugins;

    return Tooltip(
      message: t.ratingTooltip(plugin.ratingCount),
      child: StoreBadge(
        label:
            t.ratingBadge(formatRating(plugin.ratingAvg), plugin.ratingCount),
        leading: PluginRatingStars(value: plugin.ratingAvg),
      ),
    );
  }
}

/// חיווי המצב מול ההתקנה בפועל. `StatusChip` נותן סמל **וגם** טקסט —
/// חובה לפי מערכת העיצוב, ולא צבע בלבד.
class PluginInstallChip extends StatelessWidget {
  const PluginInstallChip({
    super.key,
    required this.status,
    this.installedVersion,
    this.compact = false,
  });

  final PluginInstallStatus status;
  final String? installedVersion;

  /// בלי הגרסה המותקנת בסוגריים. בכרטיס שברשת אין לשבב מקום להתארך —
  /// `StatusChip` אינו מקצר את עצמו והוא היה גולש מהכרטיס. הפירוט המלא
  /// מוצג בעמוד התוסף.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.plugins;

    return switch (status) {
      PluginInstallStatus.upToDate => StatusChip(
          kind: StatusKind.ok,
          label: t.installChipInstalled,
        ),
      PluginInstallStatus.updateAvailable => StatusChip(
          kind: StatusKind.updateAvailable,
          label: installedVersion == null || compact
              ? t.installChipUpdateAvailable
              : t.installChipUpdateFrom(installedVersion!),
        ),
      // זה כן צריך שבב: בלעדיו התוסף נראה זמין, וההתקנה הייתה נכשלת
      // בלי הסבר — או גרוע מכך, מתקינה משהו שלא עולה.
      PluginInstallStatus.incompatible => StatusChip(
          kind: StatusKind.needsAction,
          label: t.installChipIncompatible,
        ),
      // "לא מותקן" ו-"טרם נבדק" אינם צריכים שבב — היעדר השבב הוא המצב
      // הרגיל בחנות, וכל תוסף שהיה מקבל אותו רק היה מוסיף רעש.
      PluginInstallStatus.notInstalled ||
      PluginInstallStatus.unknown =>
        const SizedBox.shrink(),
    };
  }
}

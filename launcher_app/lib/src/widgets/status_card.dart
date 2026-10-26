import 'package:flutter/material.dart';

import '../theme/theme_exports.dart';
import 'rtl_icon.dart';

/// תא בשורת הגרסאות של [StatusCard] (`.vers > div`): תווית, ערך ומטא.
class StatusValue {
  const StatusValue({
    required this.label,
    required this.value,
    this.meta,
    this.ltr = false,
  });

  final String label;
  final String value;
  final String? meta;

  /// גרסה — נכתבת משמאל לימין גם בממשק עברי.
  final bool ltr;
}

/// כרטיס מצב (`.status-card`): אריח 48, שם 18/600 ושבב, שורת גרסאות בשני
/// תאים, תוספות (התקדמות, הודעה) ושורת פעולות — ראשית בהתחלה, משנית בקצה.
class StatusCard extends StatelessWidget {
  const StatusCard({
    super.key,
    required this.title,
    this.icon,
    this.logo,
    this.quiet = false,
    this.chip,
    this.subtitle,
    this.values = const [],
    this.extra = const [],
    this.actions = const [],
    this.endActions = const [],
  }) : assert(icon != null || logo != null);

  final String title;
  final IconData? icon;

  /// במקום [icon] — הלוגו של אוצריא.
  final Widget? logo;

  /// אריח שקט — "לא נמצא" ולא מצב רגיל.
  final bool quiet;
  final Widget? chip;
  final String? subtitle;
  final List<StatusValue> values;

  /// מתחת לגרסאות, בריפוד של הכרטיס.
  final List<Widget> extra;
  final List<Widget> actions;
  final List<Widget> endActions;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final divider = AppSurfaces.cardRowDivider(context);
    final (tileBg, tileFg) = quiet
        ? (cs.surfaceContainerHigh, cs.onSurfaceVariant)
        : (cs.secondaryContainer, cs.onSecondaryContainer);

    final top = Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tileBg,
              borderRadius: AppTokens.borderRadiusAll,
            ),
            child: logo ?? RtlIcon(icon!, size: 26, color: tileFg),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTextStyles.dialogTitle.copyWith(
                    color: cs.onSurface,
                  ),
                ),
                if (chip != null) ...[const SizedBox(height: 6), chip!],
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: AppTextStyles.rowSub.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    Widget line() => ColoredBox(
          color: divider,
          child: const SizedBox(height: 2, width: double.infinity),
        );

    // Material ולא Container: שורות בתוך הכרטיס (שגיאה, התקדמות) צריכות אותו.
    return Material(
      color: AppSurfaces.card(context),
      borderRadius: AppTokens.borderRadiusAll,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          top,
          if (values.isNotEmpty) ...[
            line(),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, value) in values.indexed) ...[
                    if (i > 0)
                      ColoredBox(
                        color: divider,
                        child: const SizedBox(width: 2),
                      ),
                    Expanded(child: _ValueCell(value)),
                  ],
                ],
              ),
            ),
            if (extra.isNotEmpty) const SizedBox(height: 16),
          ],
          for (final item in extra)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: item,
            ),
          if (actions.isNotEmpty || endActions.isNotEmpty) ...[
            line(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: actions,
                    ),
                  ),
                  if (endActions.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: endActions,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ValueCell extends StatelessWidget {
  const _ValueCell(this.value);

  final StatusValue value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final meta = AppTextStyles.meta.copyWith(color: cs.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value.label, style: meta),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                value.value,
                textDirection: value.ltr ? TextDirection.ltr : null,
                style: AppTextStyles.rowValue.copyWith(color: cs.onSurface),
              ),
              if (value.meta != null) Text(' · ${value.meta}', style: meta),
            ],
          ),
        ],
      ),
    );
  }
}

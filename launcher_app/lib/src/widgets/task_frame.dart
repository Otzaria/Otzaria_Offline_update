import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../theme/theme_exports.dart';
import 'icon_tile.dart';

/// מסגרת מסך משימה (`.task`): עמודה ממורכזת ברוחב 460 (או 560), ותחתית של
/// 68 עם קו עליון — "חזרה" בקצה ההתחלה והפעולה בקצה הסוף.
class TaskFrame extends StatelessWidget {
  const TaskFrame({
    super.key,
    required this.child,
    this.start,
    this.end,
    this.center = false,
    this.wide = false,
    this.endMinWidth = 160,
  });

  final Widget child;

  /// 160 לפעולה הראשית; 120 לכפתור משני כמו "ביטול" (`.task-foot .btn-tonal`).
  final double endMinWidth;
  final Widget? start;
  final Widget? end;

  /// מרכז אנכי — מסכי שאלה קצרים.
  final bool center;
  final bool wide;

  /// חלון צר (`.win.narrow`) — אותו סף כמו בבית (`HomePage.narrowWidth`).
  static const double narrowWidth = 800;

  /// חלון נמוך: ריווח, תג ושורות שלב קטנים יותר גם ברוחב מלא.
  static const double shortHeight = 700;

  /// פריסה קומפקטית (`.win.narrow`): חלון צר או נמוך.
  static bool isCompact(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width <= narrowWidth || size.height < shortHeight;
  }

  static EdgeInsets mainPadding(BuildContext context) => isCompact(context)
      ? const EdgeInsets.fromLTRB(24, 20, 24, 16)
      : const EdgeInsets.fromLTRB(24, 32, 24, 24);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final padding = mainPadding(context);
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: padding,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: center
                      ? (constraints.maxHeight - padding.vertical)
                          .clamp(0, double.infinity)
                      : 0,
                ),
                child: Align(
                  alignment: center ? Alignment.center : Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: wide ? 560 : 460),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (start != null || end != null)
          Container(
            height: AppTokens.taskFooterHeight,
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: cs.outlineVariant)),
            ),
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 768),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    if (start != null)
                      ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 120),
                        child: start,
                      ),
                    const Spacer(),
                    if (end != null)
                      ConstrainedBox(
                        constraints: BoxConstraints(minWidth: endMinWidth),
                        child: end,
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

enum StageState { done, current, waiting }

/// שורת שלב במסך משימה (`.stage-row`): אריח, שם, פירוט, וסימן מצב — ✓,
/// טבעת מסתובבת או עיגול ריק; [mark] מחליף אותו (מנעול כשממתינים למשתמש).
class StageRow extends StatelessWidget {
  const StageRow({
    super.key,
    this.icon,
    this.tileChild,
    required this.title,
    required this.state,
    this.detail,
    this.extra,
    this.mark,
    this.compact = false,
  });

  final IconData? icon;

  /// במקום [icon] — לוגו אוצריא בשורת התוכנה.
  final Widget? tileChild;
  final Widget? mark;

  /// מתחת לפירוט: פס דק, קישור או רשימת מסירות.
  final Widget? extra;
  final String title;
  final String? detail;
  final StageState state;

  /// חלון נמוך: 48 במקום 60.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final waiting = state == StageState.waiting;
    final mark = this.mark ??
        switch (state) {
          StageState.done => Icon(
              FluentIcons.checkmark_circle_24_filled,
              size: 22,
              color: cs.primary,
            ),
          StageState.current => SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: cs.primary,
                backgroundColor: cs.secondaryContainer,
              ),
            ),
          StageState.waiting => Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: cs.outline, width: 2),
              ),
            ),
        };
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: compact ? 48 : 60),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: compact ? 8 : 12,
        ),
        child: Row(
          children: [
            IconTile(
              icon: icon,
              size: IconTileSize.sm,
              tone: waiting ? IconTileTone.quiet : IconTileTone.tonal,
              child: tileChild,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: waiting
                        ? AppTextStyles.body.copyWith(
                            color: cs.onSurfaceVariant,
                          )
                        : AppTextStyles.rowTitle.copyWith(
                            color: cs.onSurface,
                          ),
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      detail!,
                      style: AppTextStyles.meta.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (extra != null) extra!,
                ],
              ),
            ),
            const SizedBox(width: 14),
            SizedBox(width: 22, child: Center(heightFactor: 1, child: mark)),
          ],
        ),
      ),
    );
  }
}

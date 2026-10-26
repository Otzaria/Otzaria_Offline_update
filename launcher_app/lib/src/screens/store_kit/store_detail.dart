import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import 'store_screenshot_lightbox.dart';
import 'store_visuals.dart';

/// מתחת לרוחב התוכן הזה דף הפרטים בעמודה אחת, ותאי הנתונים המשניים נעלמים
/// (`@container body (max-width: 800px)` פחות ריפוד הדף).
const double kStoreDetailNarrowWidth = 752;

/// ראש דף הפרטים (`.dhero`): סמל 96, שם 24/600, מטא, תקציר, פעולות והערה.
class StoreDetailHero extends StatelessWidget {
  const StoreDetailHero({
    super.key,
    required this.icon,
    required this.title,
    this.meta,
    this.summary,
    this.actions = const [],
    this.note,
    this.below,
  });

  final Widget icon;
  final String title;
  final Widget? meta;
  final String? summary;
  final List<Widget> actions;
  final String? note;

  /// מתחת לפעולות — שורת התקדמות.
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        icon,
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTextStyles.heroTitle.copyWith(color: cs.onSurface),
              ),
              if (meta != null) ...[const SizedBox(height: 4), meta!],
              if (summary != null && summary!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  summary!,
                  style: AppTextStyles.body.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
              if (actions.isNotEmpty || note != null) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ...actions,
                    if (note != null)
                      Text(
                        note!,
                        style: AppTextStyles.small.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ],
              if (below != null) ...[const SizedBox(height: 12), below!],
            ],
          ),
        ),
      ],
    );
  }
}

/// תא ברצועת הנתונים: תווית, ערך עם סמל, ושורת הסבר.
class StoreFact {
  const StoreFact({
    required this.label,
    required this.value,
    this.icon,
    this.caption,
    this.wideOnly = false,
    this.ltr = false,
  });

  final String label;
  final String value;
  final IconData? icon;
  final String? caption;

  /// בחלון צר התא נעלם, כמו `.wideonly`.
  final bool wideOnly;

  /// ערך שהוא מספר גרסה או גודל.
  final bool ltr;
}

/// רצועת נתוני המפתח (`.facts`): כרטיס אחד, תאים שווים וקו ביניהם.
class StoreFacts extends StatelessWidget {
  const StoreFacts({super.key, required this.facts});

  final List<StoreFact> facts;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < kStoreDetailNarrowWidth;
        final shown = [
          for (final fact in facts)
            if (!narrow || !fact.wideOnly) fact,
        ];
        return Container(
          decoration: BoxDecoration(
            color: AppSurfaces.card(context),
            borderRadius: AppTokens.borderRadiusAll,
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, fact) in shown.indexed) ...[
                  if (i > 0)
                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: cs.outlineVariant,
                    ),
                  Expanded(child: _FactCell(fact: fact)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FactCell extends StatelessWidget {
  const _FactCell({required this.fact});

  final StoreFact fact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = AppTextStyles.meta.copyWith(color: cs.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            fact.label,
            textAlign: TextAlign.center,
            style: muted.copyWith(fontWeight: AppTextStyles.semibold),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (fact.icon != null) ...[
                RtlIcon(fact.icon!, size: 16, color: cs.primary),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(
                  fact.value,
                  textDirection: fact.ltr ? TextDirection.ltr : null,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.cardTitle.copyWith(color: cs.onSurface),
                ),
              ),
            ],
          ),
          if (fact.caption != null) ...[
            const SizedBox(height: 2),
            Text(fact.caption!, textAlign: TextAlign.center, style: muted),
          ],
        ],
      ),
    );
  }
}

/// שתי עמודות של דף הפרטים (`.dcols` 1.25fr / 1fr), ועמודה אחת בחלון צר.
class StoreDetailColumns extends StatelessWidget {
  const StoreDetailColumns({
    super.key,
    required this.start,
    required this.end,
  });

  final List<Widget> start;
  final List<Widget> end;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        Widget column(List<Widget> children) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            );
        if (constraints.maxWidth < kStoreDetailNarrowWidth) {
          return column([...start, ...end]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 5, child: column(start)),
            const SizedBox(width: 24),
            Expanded(flex: 4, child: column(end)),
          ],
        );
      },
    );
  }
}

/// שורת מידע (`.info .row`): תווית משנית והערך 14/600 בקצה.
class StoreInfoEntry {
  const StoreInfoEntry({
    required this.label,
    required this.value,
    this.ltr = false,
    this.mono = false,
    this.trailing,
  });

  final String label;
  final String value;

  /// [ltr] — גרסה; [mono] — כתובת או נתיב, בתיבת `PathText`.
  final bool ltr;
  final bool mono;

  /// כפתורים קטנים אחרי הערך (העתקה, פתיחה).
  final List<Widget>? trailing;
}

class StoreInfoRows extends StatelessWidget {
  const StoreInfoRows({super.key, required this.entries});

  final List<StoreInfoEntry> entries;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppCard.section(
      children: [
        for (final entry in entries)
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 46),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    entry.label,
                    style: AppTextStyles.small.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: entry.mono
                          ? PathText(entry.value)
                          : Text(
                              entry.value,
                              textAlign: TextAlign.end,
                              textDirection:
                                  entry.ltr ? TextDirection.ltr : null,
                              style: AppTextStyles.rowTitle.copyWith(
                                color: cs.onSurface,
                              ),
                            ),
                    ),
                  ),
                  if (entry.trailing != null) ...[
                    const SizedBox(width: 4),
                    ...entry.trailing!,
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// צילומי המסך (`.shot`): צילום גדול ביחס 16:10 עם כפתור הגדלה, ונקודות
/// למעבר ביניהם. לחיצה פותחת את התצוגה המוגדלת.
class StoreScreenshots extends StatefulWidget {
  const StoreScreenshots({super.key, required this.paths});

  final List<String> paths;

  @override
  State<StoreScreenshots> createState() => _StoreScreenshotsState();
}

class _StoreScreenshotsState extends State<StoreScreenshots> {
  int _index = 0;

  @override
  void didUpdateWidget(StoreScreenshots oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_index >= widget.paths.length) _index = 0;
  }

  void _open() => showStoreScreenshots(
        context,
        paths: widget.paths,
        initialIndex: _index,
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = context.strings.plugins;
    final paths = widget.paths;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          label: t.screenshotZoom,
          child: FocusRing(
            child: Material(
              color: cs.surfaceContainer,
              shape: RoundedRectangleBorder(
                borderRadius: AppTokens.borderRadiusAll,
                side: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: .7),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _open,
                mouseCursor: SystemMouseCursors.zoomIn,
                child: AspectRatio(
                  aspectRatio: 16 / 10,
                  child: LayoutBuilder(
                    builder: (context, constraints) => Stack(
                      children: [
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Image.file(
                              File(paths[_index]),
                              fit: BoxFit.contain,
                              cacheWidth: decodeWidthFor(
                                context,
                                constraints.maxWidth,
                              ),
                              errorBuilder: (context, _, __) => Center(
                                child: Icon(
                                  FluentIcons.image_off_24_regular,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                        PositionedDirectional(
                          bottom: 10,
                          end: 10,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: cs.surface,
                              borderRadius: AppTokens.borderRadiusAll,
                            ),
                            child: Icon(
                              FluentIcons.zoom_in_20_regular,
                              size: 18,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (paths.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < paths.length; i++)
                _Dot(
                  current: i == _index,
                  label: t.screenshotNumber(i + 1, paths.length),
                  onTap: () => setState(() => _index = i),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.current, required this.label, required this.onTap});

  final bool current;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppTokens.borderRadiusAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          child: AnimatedContainer(
            duration: AppTokens.animFast,
            width: current ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: current ? cs.primary : cs.outlineVariant,
              borderRadius: const BorderRadius.all(Radius.circular(3)),
            ),
          ),
        ),
      ),
    );
  }
}

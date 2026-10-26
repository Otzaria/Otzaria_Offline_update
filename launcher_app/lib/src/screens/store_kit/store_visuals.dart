import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../services/store_search.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';

/// רכיבי התצוגה הקטנים של שני מסכי החנות (תוספים ותוכנות נוספות) — לפי
/// חנות התוספים שבאתר ובמידות המוקאפ. אינם מיוצאים ל-`widgets/`.

/// רוחב הפענוח ל-`Image.file`: בלי `cacheWidth` כל תמונה מפוענחת בגודל
/// המקור (מאות MB ברשת); העיגול ל-64 חוסך פענוח בכל שינוי גודל.
int? decodeWidthFor(BuildContext context, double logicalWidth) {
  if (!logicalWidth.isFinite || logicalWidth <= 0) return null;
  final physical = logicalWidth * MediaQuery.devicePixelRatioOf(context);
  return (physical / _decodeStep).ceil() * _decodeStep;
}

const int _decodeStep = 64;

/// סמל הפריט (`.picon`): ריבוע ברדיוס 8 על surfaceContainer עם קו דק. התמונה
/// נכנסת שלמה (`contain`); בלעדיה — [placeholderIcon], או הלוגו כשאין.
class StoreIcon extends StatelessWidget {
  const StoreIcon({
    super.key,
    required this.imagePath,
    this.size = 64,
    this.placeholderIcon,
  });

  final String? imagePath;
  final double size;

  /// `null` — לוגו אוצריא, כמו באתר לתוסף בלי תמונה.
  final IconData? placeholderIcon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final path = imagePath;
    final inner = size * 0.78;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: AppTokens.borderRadiusAll,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .7)),
      ),
      child: path == null || path.isEmpty
          ? _placeholder(context)
          : ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(6)),
              child: Image.file(
                File(path),
                width: inner,
                height: inner,
                fit: BoxFit.contain,
                cacheWidth: decodeWidthFor(context, inner),
                errorBuilder: (context, _, __) => _placeholder(context),
              ),
            ),
    );
  }

  Widget _placeholder(BuildContext context) {
    final icon = placeholderIcon;
    if (icon == null) {
      return Opacity(
        opacity: .8,
        child: Image.asset(
          'assets/images/otzaria_logo.png',
          width: size / 2,
          height: size / 2,
          cacheWidth: decodeWidthFor(context, size / 2),
        ),
      );
    }
    return RtlIcon(
      icon,
      size: size / 2,
      color: Theme.of(context).colorScheme.primary,
    );
  }
}

/// טקסט שמילות החיפוש בו מודגשות ברקע secondaryContainer (`mark`).
class StoreHighlightText extends StatelessWidget {
  const StoreHighlightText(
    this.text, {
    super.key,
    required this.query,
    this.style,
    this.maxLines,
  });

  final String text;
  final String query;
  final TextStyle? style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final range = storeMatchRange(text, query);
    final overflow = maxLines == null ? null : TextOverflow.ellipsis;
    if (range == null) {
      return Text(text, style: style, maxLines: maxLines, overflow: overflow);
    }
    final mark = TextStyle(
      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
    );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: text.substring(0, range.start)),
          TextSpan(
            text: text.substring(range.start, range.end),
            style: mark,
          ),
          TextSpan(text: text.substring(range.end)),
        ],
      ),
      style: style,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

/// שורת מטא (`.pmeta`): פריטים ברווח 10, בשורה אחת — מה שלא נכנס נחתך.
class StoreMetaLine extends StatelessWidget {
  const StoreMetaLine({super.key, required this.items});

  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.textScalerOf(context).scale(24);
    return SizedBox(
      height: height,
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        clipBehavior: Clip.hardEdge,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: items,
      ),
    );
  }
}

/// פריט בשורת המטא: סמל 14 וטקסט 13.
class StoreMetaItem extends StatelessWidget {
  const StoreMetaItem(
    this.text, {
    super.key,
    this.icon,
    this.iconColor,
    this.ltr = false,
  });

  final String text;
  final IconData? icon;
  final Color? iconColor;

  /// מספר גרסה, גודל — LTR.
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: MediaQuery.textScalerOf(context).scale(24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: iconColor ?? cs.onSurfaceVariant),
            const SizedBox(width: 3),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: ltr ? TextDirection.ltr : null,
              style: AppTextStyles.small.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// שבב ניטרלי בשורת המטא ("ניסיוני", "דורש אינטרנט", "חדש").
class StoreMetaChip extends StatelessWidget {
  const StoreMetaChip(this.label, {super.key, this.icon, this.tonal = false});

  final String label;
  final IconData? icon;

  /// שבב בולט (secondaryContainer) — "חדש".
  final bool tonal;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final foreground = tonal ? cs.onSecondaryContainer : cs.onSurfaceVariant;
    return Container(
      height: AppTokens.chipHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: tonal ? cs.secondaryContainer : null,
        borderRadius: AppTokens.pill,
        border: tonal ? null : Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 5),
          ],
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

/// מצב במקום כפתור (`.state`): סמל 18 ב-primary וטקסט 13/600, בגובה כפתור.
class StoreStateLabel extends StatelessWidget {
  const StoreStateLabel({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTokens.buttonHeight),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        // בעמודת הפעולה של שורה — ממורכז; בתחתית כרטיס — בתחילת השורה.
        mainAxisAlignment: StoreCardLayout.isTile(context)
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
        children: [
          RtlIcon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.buttonSm.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// הצורה של הכרטיס שמעל — "כרטיס" (פעולה בתחתית) או "שורה" (בעמודה בצד).
class StoreCardLayout extends InheritedWidget {
  const StoreCardLayout({super.key, required this.tile, required super.child});

  final bool tile;

  static bool isTile(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StoreCardLayout>()?.tile ??
      false;

  @override
  bool updateShouldNotify(StoreCardLayout oldWidget) => tile != oldWidget.tile;
}

/// הערה קטנה מתחת לפעולה (`.pnote`).
class StoreNote extends StatelessWidget {
  const StoreNote(this.text, {super.key, this.center = false});

  final String text;
  final bool center;

  @override
  Widget build(BuildContext context) => Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: center ? TextAlign.center : null,
        style: AppTextStyles.meta.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
}

/// שבב קטגוריה (`.cat`): גלולה 36, ומונה בסוגריים.
class StoreCategoryChip extends StatelessWidget {
  const StoreCategoryChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final palette = AppPalette.of(context);
    final foreground = selected ? cs.onSecondaryContainer : cs.onSurfaceVariant;
    const shape = StadiumBorder();
    return Semantics(
      button: true,
      selected: selected,
      child: FocusRing(
        borderRadius: AppTokens.pill,
        child: Material(
          color: selected ? cs.secondaryContainer : Colors.transparent,
          shape: shape.copyWith(
            side: BorderSide(
              color: selected ? cs.primary : cs.outlineVariant,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            hoverColor: selected ? null : palette.cardSelected,
            overlayColor: selected ? AppSurfaces.stateLayer(cs.primary) : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 36),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: AppTextStyles.buttonSm.copyWith(color: foreground),
                    ),
                    if (count != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '($count)',
                        style: AppTextStyles.meta.copyWith(color: foreground),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// שבב סינון (`.fchip`): 32, רדיוס 8, מסגרת outline; הנבחר tonal עם ✓.
/// נעול — מנעול במקום ✓, ב-60% ובלי לחיצה (`.fchip:disabled`).
class StoreFilterChip extends StatelessWidget {
  const StoreFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.locked = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final foreground = selected ? cs.onSecondaryContainer : cs.onSurface;
    final chip = Semantics(
      button: true,
      selected: selected,
      enabled: !locked,
      child: FocusRing(
        child: Material(
          color: selected ? cs.secondaryContainer : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: AppTokens.borderRadiusAll,
            side: BorderSide(
              color: selected ? cs.secondaryContainer : cs.outline,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: locked ? null : onTap,
            overlayColor: AppSurfaces.stateLayer(cs.primary),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 32),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (selected || locked) ...[
                      Icon(
                        locked
                            ? FluentIcons.lock_closed_16_regular
                            : FluentIcons.checkmark_16_regular,
                        size: 16,
                        color: foreground,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      label,
                      style: AppTextStyles.small.copyWith(color: foreground),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return locked ? Opacity(opacity: 0.6, child: chip) : chip;
  }
}

/// תגית (`.tag`): גלולה 28 עם קו דק. עם [onTap] היא מסננת; [tonal] — הקטגוריה.
class StoreTagPill extends StatelessWidget {
  const StoreTagPill({
    super.key,
    required this.label,
    this.onTap,
    this.tonal = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool tonal;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pill = Material(
      color: tonal ? cs.secondaryContainer : Colors.transparent,
      shape: StadiumBorder(
        side: tonal ? BorderSide.none : BorderSide(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        mouseCursor:
            onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
        overlayColor: AppSurfaces.stateLayer(cs.primary),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: AppTextStyles.small.copyWith(
                color: tonal ? cs.onSecondaryContainer : cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
    return onTap == null
        ? pill
        : FocusRing(borderRadius: AppTokens.pill, child: pill);
  }
}

/// כותרת סעיף בדף פרטים (`.h2`): 16/600, ואחריה קו שנמוג ונקודת זהב.
class StoreSectionTitle extends StatelessWidget {
  const StoreSectionTitle(this.text, {super.key, this.first = false});

  final String text;

  /// הסעיף הראשון בעמודה — בלי הרווח העליון.
  final bool first;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final palette = AppPalette.of(context);
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : 22, bottom: 10),
      child: Row(
        children: [
          Text(text,
              style: AppTextStyles.cardTitle.copyWith(color: cs.onSurface)),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 7,
              child: CustomPaint(
                painter: _OrnamentPainter(
                  line: cs.outlineVariant,
                  dot: palette.glow,
                  rtl: Directionality.of(context) == TextDirection.rtl,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// נקודה צמודה לכותרת, וקו שנמוג ממנה והלאה — כמו `.h2::after` במוקאפ.
class _OrnamentPainter extends CustomPainter {
  const _OrnamentPainter({
    required this.line,
    required this.dot,
    required this.rtl,
  });

  final Color line;
  final Color dot;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final near = rtl ? size.width : 0.0;
    final far = rtl ? 0.0 : size.width;
    final paint = Paint()
      ..strokeWidth = 1
      ..shader = LinearGradient(
        colors: [line, line.withValues(alpha: 0)],
      ).createShader(
        Rect.fromPoints(Offset(near, y), Offset(far, y + 1)),
      );
    canvas.drawLine(Offset(near, y), Offset(far, y), paint);
    canvas.drawCircle(
      Offset(rtl ? size.width - 4 : 4, y),
      3.5,
      Paint()..color = dot,
    );
  }

  @override
  bool shouldRepaint(_OrnamentPainter old) =>
      old.line != line || old.dot != dot || old.rtl != rtl;
}

/// ראש העמוד (`.pagehead`): כותרת 20/600, הסבר, ופעולה בקצה.
class StorePageHead extends StatelessWidget {
  const StorePageHead({
    super.key,
    required this.title,
    this.description,
    this.actions = const [],
  });

  final String title;
  final String? description;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 260, maxWidth: 640),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.pageTitle.copyWith(color: cs.onSurface),
                ),
                if (description != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    description!,
                    style: AppTextStyles.body.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty)
            Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ),
    );
  }
}

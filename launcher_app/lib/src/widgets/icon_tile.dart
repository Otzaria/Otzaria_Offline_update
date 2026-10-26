import 'package:flutter/material.dart';

import '../theme/theme_exports.dart';
import 'rtl_icon.dart';

enum IconTileSize { sm, md, lg }

/// הגוון של אריח הסמל: tonal, שקט (לשורות הגדרה ושלב ממתין) או שגיאה.
enum IconTileTone { tonal, quiet, error }

/// אריח סמל מרובע ברדיוס 8 (`.tile`): 32/40/56, סמל 18/24/28. ב-40 שקט או
/// שגיאה הסמל 22, כמו אריח ההודעה; [glyphSize] גובר על שניהם.
class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    this.icon,
    this.child,
    this.size = IconTileSize.md,
    this.tone = IconTileTone.tonal,
    this.glyphSize,
  }) : assert(icon != null || child != null);

  final IconData? icon;

  /// במקום [icon] — למשל לוגו.
  final Widget? child;
  final IconTileSize size;
  final IconTileTone tone;
  final double? glyphSize;

  static double extentOf(IconTileSize size) => switch (size) {
        IconTileSize.sm => 32,
        IconTileSize.md => 40,
        IconTileSize.lg => 56,
      };

  static double glyphOf(
    IconTileSize size, [
    IconTileTone tone = IconTileTone.tonal,
  ]) =>
      switch (size) {
        IconTileSize.sm => 18,
        IconTileSize.md => tone == IconTileTone.tonal ? 24 : 22,
        IconTileSize.lg => 28,
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (background, foreground) = switch (tone) {
      IconTileTone.tonal => (cs.secondaryContainer, cs.onSecondaryContainer),
      IconTileTone.quiet => (cs.surfaceContainerHigh, cs.onSurfaceVariant),
      IconTileTone.error => (cs.errorContainer, cs.onErrorContainer),
    };
    final extent = extentOf(size);
    return Container(
      width: extent,
      height: extent,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: child ??
          RtlIcon(
            icon!,
            size: glyphSize ?? glyphOf(size, tone),
            color: foreground,
          ),
    );
  }
}

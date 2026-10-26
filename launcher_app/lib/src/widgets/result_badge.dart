import 'package:flutter/material.dart';

import '../theme/theme_exports.dart';
import 'task_frame.dart';

enum ResultBadgeKind { ok, error, calm }

/// תג תוצאה (`.badge`): טבעת 72 בצבע התג ב-11%, ודיסק 64 עם סמל 32.
class ResultBadge extends StatelessWidget {
  const ResultBadge({super.key, required this.kind, required this.icon});

  final ResultBadgeKind kind;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (ring, disc, glyph) = switch (kind) {
      ResultBadgeKind.ok => (
          AppSurfaces.badgeRing(cs.primary),
          cs.primary,
          cs.onPrimary,
        ),
      ResultBadgeKind.error => (
          AppSurfaces.badgeRing(cs.error),
          cs.error,
          cs.onError,
        ),
      ResultBadgeKind.calm => (
          AppSurfaces.calmBadgeRing(cs),
          cs.secondaryContainer,
          cs.onSecondaryContainer,
        ),
    };
    // חלון צר: 56/48 (`.win.narrow .badge`).
    final narrow = TaskFrame.isCompact(context);
    return Container(
      width: narrow ? 56 : 72,
      height: narrow ? 56 : 72,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: ring),
      child: Container(
        width: narrow ? 48 : 64,
        height: narrow ? 48 : 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: disc,
          border: kind == ResultBadgeKind.calm
              ? Border.all(color: cs.onSurfaceVariant, width: 2)
              : null,
        ),
        child: Icon(icon, size: narrow ? 26 : 32, color: glyph),
      ),
    );
  }
}

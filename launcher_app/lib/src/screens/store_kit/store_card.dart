import 'package:flutter/material.dart';

import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import 'store_grid.dart';
import 'store_visuals.dart';

/// כרטיס בחנות (`.pcard`), לחיץ כולו. רחב — שורה; צר — כרטיס. הגובה
/// קבוע ונקבע ברשת.
class StoreItemCard extends StatefulWidget {
  const StoreItemCard({
    super.key,
    required this.icon,
    required this.title,
    required this.meta,
    required this.description,
    required this.onTap,
    this.action,
    this.note,
    this.semanticLabel,
  });

  final Widget icon;
  final String title;
  final Widget meta;
  final String description;
  final VoidCallback onTap;
  final Widget? action;
  final String? note;

  final String? semanticLabel;

  @override
  State<StoreItemCard> createState() => _StoreItemCardState();
}

/// מילות החיפוש שמודגשות בכרטיסים שמתחתיו.
class StoreQueryScope extends InheritedWidget {
  const StoreQueryScope({super.key, required this.query, required super.child});

  final String query;

  static String of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StoreQueryScope>()?.query ??
      '';

  @override
  bool updateShouldNotify(StoreQueryScope oldWidget) =>
      query != oldWidget.query;
}

class _StoreItemCardState extends State<StoreItemCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final query = StoreQueryScope.of(context);
    final textScaler = MediaQuery.textScalerOf(context);

    Widget head({required bool tile}) {
      final name = StoreHighlightText(
        widget.title,
        query: query,
        maxLines: tile ? 2 : 1,
        style: AppTextStyles.cardTitle.copyWith(
          color: _hovered ? cs.primary : cs.onSurface,
        ),
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // בשורה הגובה קבוע לשורת שם אחת — השם המלא בריחוף.
          if (tile) name else Tooltip(message: widget.title, child: name),
          const SizedBox(height: 4),
          widget.meta,
        ],
      );
    }

    final descStyle = AppTextStyles.small.copyWith(height: 1.55);
    final description = SizedBox(
      height: textScaler.scale(13 * 1.55 * 2),
      child: StoreHighlightText(
        widget.description,
        query: query,
        maxLines: 2,
        style: descStyle.copyWith(color: cs.onSurfaceVariant),
      ),
    );

    return Semantics(
      button: true,
      label: widget.semanticLabel ?? widget.title,
      child: FocusRing(
        child: Material(
          color: _hovered ? AppSurfaces.cardSelected(context) : cs.surface,
          borderRadius: AppTokens.borderRadiusAll,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            onHover: (value) => setState(() => _hovered = value),
            hoverColor: Colors.transparent,
            overlayColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.pressed)
                  ? cs.primary.withValues(alpha: AppSurfaces.pressedAlpha)
                  : Colors.transparent,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // ברשת הגובה קבוע, והוא שמכריע — כך הצורה תמיד תואמת לו.
                  final tile = storeTileCardExtent(textScaler.scale(1));
                  final row = constraints.maxHeight.isFinite
                      ? constraints.maxHeight + 32 < tile - 0.5
                      : constraints.maxWidth + 32 >= kStoreRowCardWidth;
                  return row
                      ? _row(head(tile: false), description)
                      : _tile(head(tile: true), description);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget? get _note =>
      widget.note == null ? null : StoreNote(widget.note!, center: true);

  Widget _row(Widget head, Widget description) {
    final note = _note;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        widget.icon,
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [head, const SizedBox(height: 6), description],
          ),
        ),
        if (widget.action != null || note != null) ...[
          const SizedBox(width: 16),
          SizedBox(
            width: 168,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.action != null) widget.action!,
                if (note != null) ...[const SizedBox(height: 6), note],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _tile(Widget head, Widget description) {
    final note = widget.note;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            widget.icon,
            const SizedBox(width: 16),
            Expanded(child: head),
          ],
        ),
        const SizedBox(height: 12),
        description,
        const Spacer(),
        Row(
          children: [
            if (widget.action != null)
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 160),
                  child: StoreCardLayout(tile: true, child: widget.action!),
                ),
              ),
            if (note != null) ...[
              const SizedBox(width: 10),
              Expanded(child: StoreNote(note)),
            ],
          ],
        ),
      ],
    );
  }
}

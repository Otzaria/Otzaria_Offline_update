import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../theme/theme_exports.dart';
import 'focus_ring.dart';
import 'icon_tile.dart';

/// מקטע "מתקדם" מקופל (`.adv`): כותרת עם סיכום, וחץ שמתהפך כשפתוח.
class AdvancedSection extends StatefulWidget {
  const AdvancedSection({
    super.key,
    required this.title,
    required this.child,
    this.summary,
    this.initiallyOpen = false,
    this.icon = FluentIcons.wrench_20_regular,
  });

  final String title;
  final String? summary;
  final Widget child;
  final bool initiallyOpen;
  final IconData icon;

  @override
  State<AdvancedSection> createState() => _AdvancedSectionState();
}

class _AdvancedSectionState extends State<AdvancedSection> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            expanded: _open,
            child: FocusRing(
              // הכותרת יושבת גם בדף בלי Scaffold (בדיקות, דף בתוך דף).
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: () => setState(() => _open = !_open),
                  borderRadius: AppTokens.borderRadiusAll,
                  overlayColor: AppSurfaces.stateLayer(cs.primary),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                    child: Row(
                      children: [
                        IconTile(
                          icon: widget.icon,
                          size: IconTileSize.sm,
                          tone: IconTileTone.quiet,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.title,
                                style: AppTextStyles.rowTitle.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              if (widget.summary != null)
                                Text(
                                  widget.summary!,
                                  style: AppTextStyles.meta.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        AnimatedRotation(
                          turns: _open ? 0.5 : 0,
                          duration: AppTokens.animFast,
                          child: Icon(
                            FluentIcons.chevron_down_20_regular,
                            size: 20,
                            color: cs.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: widget.child,
            ),
        ],
      ),
    );
  }
}

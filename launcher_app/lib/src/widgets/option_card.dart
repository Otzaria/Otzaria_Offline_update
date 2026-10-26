import 'package:flutter/material.dart';

import '../theme/theme_exports.dart';
import 'focus_ring.dart';
import 'icon_tile.dart';

/// כרטיס אפשרות גדול (`.opt`): רדיו, אריח סמל, כותרת 16, תיאור 13 ושורת
/// גודל 12. כל הכרטיס לחיץ, והנבחר בצבע cardSelected.
class OptionCard extends StatelessWidget {
  const OptionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.selected,
    required this.onSelected,
    this.description,
    this.sizeLine,
  });

  final IconData icon;
  final String title;
  final String? description;
  final String? sizeLine;
  final bool selected;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      child: FocusRing(
        child: Material(
          color: selected
              ? AppSurfaces.cardSelected(context)
              : AppSurfaces.card(context),
          borderRadius: AppTokens.borderRadiusAll,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onSelected,
            overlayColor: AppSurfaces.stateLayer(cs.primary),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 68),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                child: Row(
                  children: [
                    _Radio(selected: selected),
                    const SizedBox(width: 14),
                    IconTile(icon: icon),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: AppTextStyles.rowValue.copyWith(
                              color: cs.onSurface,
                            ),
                          ),
                          if (description != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              description!,
                              style: AppTextStyles.rowSub.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                          if (sizeLine != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              sizeLine!,
                              style: AppTextStyles.meta.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
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

/// רדיו 20: טבעת 2 ונקודה 10.
class _Radio extends StatelessWidget {
  const _Radio({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = selected ? cs.primary : cs.onSurfaceVariant;
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
      ),
      child: selected
          ? Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.primary,
              ),
            )
          : null,
    );
  }
}

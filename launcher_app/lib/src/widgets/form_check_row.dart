import 'package:flutter/material.dart';

import '../theme/theme_exports.dart';

/// סימון "כן/לא" בשורה (`.checkrow`).
class FormCheckRow extends StatelessWidget {
  const FormCheckRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.help,
  });

  final String label;
  final String? help;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceMD),
      // מסך משימה אינו יושב על Material, ו-InkWell דורש אחד.
      child: Material(
        type: MaterialType.transparency,
        child: Semantics(
          checked: value,
          child: InkWell(
            onTap: () => onChanged(!value),
            borderRadius: AppTokens.borderRadiusAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: value,
                      onChanged: (next) => onChanged(next ?? false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: AppTextStyles.body.copyWith(
                            color: cs.onSurface,
                          ),
                        ),
                        if (help != null)
                          Text(
                            help!,
                            style: AppTextStyles.meta.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

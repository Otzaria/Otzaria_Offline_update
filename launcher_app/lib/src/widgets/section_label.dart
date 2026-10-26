import 'package:flutter/material.dart';

import '../theme/theme_exports.dart';

/// כותרת מקטע מעל כרטיס (`.sec-label`): 13/600, ופעולה אופציונלית בקצה.
class SectionLabel extends StatelessWidget {
  const SectionLabel(
    this.text, {
    super.key,
    this.trailing,
    this.first = false,
  });

  final String text;
  final Widget? trailing;

  /// המקטע הראשון בדף — בלי הרווח העליון.
  final bool first;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : 28, bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.sectionLabel.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

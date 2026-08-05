import 'package:flutter/material.dart';

import '../theme/theme_exports.dart';

/// גוף מסך אחיד: כותרת, הסבר קצר ורשימת כרטיסים — ברוחב תוכן מוגבל
/// וממורכז, כדי שהכרטיסים לא יתמשכו לרוחב מסך שלם (תכנון §14).
class ScreenBody extends StatelessWidget {
  final String title;
  final String? description;
  final List<Widget> children;

  const ScreenBody({
    super.key,
    required this.title,
    this.description,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: LayoutConstraints.panelContentMaxWidth,
        ),
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceLG,
            vertical: AppTokens.spaceMD,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(
                right: AppTokens.spaceMD,
                left: AppTokens.spaceMD,
                top: AppTokens.spaceSM,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.headlineSmall),
                  if (description != null) ...[
                    const SizedBox(height: AppTokens.spaceXS),
                    Text(
                      description!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            ...children,
            const SizedBox(height: AppTokens.spaceXL),
          ],
        ),
      ),
    );
  }
}

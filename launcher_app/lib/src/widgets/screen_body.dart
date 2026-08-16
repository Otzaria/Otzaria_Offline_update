import 'package:flutter/material.dart';

import '../theme/theme_exports.dart';

/// גוף מסך אחיד: כותרת ורשימת כרטיסים — ברוחב תוכן מוגבל וממורכז, כדי
/// שהכרטיסים לא יתמשכו לרוחב מסך שלם (תכנון §14). אין כאן פסקת הסבר:
/// ההסברים עברו לסימני שאלה שליד הכותרות שהם באמת נוגעות להן.
class ScreenBody extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const ScreenBody({
    super.key,
    required this.title,
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
              child: Text(title, style: theme.textTheme.headlineSmall),
            ),
            ...children,
            const SizedBox(height: AppTokens.spaceXL),
          ],
        ),
      ),
    );
  }
}

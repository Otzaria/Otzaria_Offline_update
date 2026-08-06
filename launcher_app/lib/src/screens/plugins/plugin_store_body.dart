import 'package:flutter/material.dart';

import '../../theme/theme_exports.dart';

/// גוף מסך החנות — **רוחב מלא**, בשונה מ-`ScreenBody` של שאר המסכים
/// שמגביל את התוכן ל-860px וממרכז אותו.
///
/// למה שונה: החנות היא רשת כרטיסים עם תמונות, ולא רשימת שורות הגדרה.
/// הגבלת רוחב הייתה מצמצמת אותה לשתי עמודות גם על מסך רחב, בעוד שהחנות
/// המקורית פורסת כמה שיותר עמודות לרוחב.
class PluginStoreBody extends StatelessWidget {
  const PluginStoreBody({super.key, required this.children, this.header});

  /// שורה קבועה בראש המסך שאינה נגללת (סנכרון ומועד הסנכרון האחרון).
  final Widget? header;
  final List<Widget> children;

  /// המרווח האופקי מקצה המסך — זהה לשני צדי התוכן.
  static const double horizontalPadding = AppTokens.spaceLG;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (header != null) header!,
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: AppTokens.spaceMD,
            ),
            children: [
              ...children,
              const SizedBox(height: AppTokens.spaceXL),
            ],
          ),
        ),
      ],
    );
  }
}

/// תווית שדה קטנה מעל פקד — כמו ה-`label` בחנות המקורית.
class PluginFieldLabel extends StatelessWidget {
  const PluginFieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppTokens.fontSM,
          fontWeight: FontWeight.bold,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

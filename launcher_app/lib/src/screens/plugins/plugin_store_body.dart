import 'package:flutter/material.dart';

import '../../theme/theme_exports.dart';

/// גוף מסך החנות — **רוחב מלא**, בשונה מ-`ScreenBody` של שאר המסכים
/// שמגביל את התוכן ל-860px וממרכז אותו.
///
/// למה שונה: החנות היא רשת כרטיסים עם תמונות, ולא רשימת שורות הגדרה.
/// הגבלת רוחב הייתה מצמצמת אותה לשתי עמודות גם על מסך רחב, בעוד שהחנות
/// המקורית פורסת כמה שיותר עמודות לרוחב.
///
/// **התוכן נמסר כ-slivers בלבד.** כל התוכן הגליל של החנות הוא רשתות
/// כרטיסים עם תמונות, ולכן הוא חייב להיבנות מדורג. `SliverList` עם רשימת
/// ילדים קבועה בונה את כולם מיד — מה שמחזיר בדיוק את הבעיה שבגללה הרשת
/// הועברה מ-`GridView(shrinkWrap: true)` ל-`SliverGrid`.
class PluginStoreBody extends StatelessWidget {
  const PluginStoreBody({
    super.key,
    required this.slivers,
    this.header,
    this.sidebar,
  });

  /// שורה קבועה בראש המסך שאינה נגללת (סנכרון ומועד הסנכרון האחרון).
  final Widget? header;

  /// סרגל הצד הקבוע של הקטגוריות, כמו ה-`aside` הדביק שבאתר. הוא **מחוץ**
  /// לאזור הגלילה כדי שגלילת התוכן לא תזיז אותו ולא תתחלק איתו.
  final Widget? sidebar;

  final List<Widget> slivers;

  /// המרווח האופקי מקצה המסך — זהה לשני צדי התוכן.
  static const double horizontalPadding = AppTokens.spaceLG;

  /// עוטף sliver במרווח האופקי של החנות. נקרא מכל מקום שמרכיב תוכן גליל,
  /// כדי שהמרווח יהיה במקום אחד.
  static Widget padded(Widget sliver, {double top = 0, double bottom = 0}) =>
      SliverPadding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          top,
          horizontalPadding,
          bottom,
        ),
        sliver: sliver,
      );

  /// עוטף widget רגיל כ-sliver ממורווח — לכותרות סעיף ולכרטיסי מצב.
  static Widget block(Widget child, {double top = 0, double bottom = 0}) =>
      padded(SliverToBoxAdapter(child: child), top: top, bottom: bottom);

  @override
  Widget build(BuildContext context) {
    final scroller = CustomScrollView(
      slivers: [
        ...slivers,
        const SliverToBoxAdapter(
          child: SizedBox(height: AppTokens.spaceXL + AppTokens.spaceMD),
        ),
      ],
    );

    return Column(
      children: [
        if (header != null) header!,
        Expanded(
          child: sidebar == null
              ? scroller
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    sidebar!,
                    Expanded(child: scroller),
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

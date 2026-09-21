import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../theme/theme_exports.dart';

/// רכיבי התצוגה הקטנים המשותפים למסכי החנות — חנות התוספים ומסך
/// התוכנות הנוספות.
///
/// אלה **תוספת** למערכת העיצוב של אוצריא ולא פורט ממנה: לכרטיס-חנות עם
/// תמונה ולגלולות מטא-דאטה אין מקבילה שם. הם נבנים מטוקנים קיימים בלבד
/// (`AppTokens`, `ColorScheme`) ואינם מיוצאים ל-`widgets/`, כדי שלא
/// ייחשבו בטעות לרכיבים מאושרים של מערכת העיצוב. ראו launcher_app/README.md.
/// רוחב הפענוח שיש לבקש מ-`Image.file` עבור תמונה שתוצג ב-[logicalWidth].
///
/// **למה זה חובה כאן:** בלי `cacheWidth` פלאטר מפענח את התמונה בגודל המקור.
/// תמונת חנות טיפוסית (1200×800) תופסת כ-3.8MB מפוענחת, וברשת של עשרות
/// תוספים — כולן חיות בבת אחת — זה מאות MB של RAM עבור אריחים ברוחב 300px.
/// עיגול ל-[_decodeStep] מונע פענוח מחדש בכל פיקסל של שינוי גודל החלון.
int? decodeWidthFor(BuildContext context, double logicalWidth) {
  if (!logicalWidth.isFinite || logicalWidth <= 0) return null;
  final physical = logicalWidth * MediaQuery.devicePixelRatioOf(context);
  return (physical / _decodeStep).ceil() * _decodeStep;
}

const int _decodeStep = 64;

/// גלולת מטא-דאטה קטנה (גרסה, מספר הורדות, סטטוס).
class StoreBadge extends StatelessWidget {
  const StoreBadge({
    super.key,
    required this.label,
    this.icon,
    this.leading,
    this.emphasized = false,
  });

  final String label;
  final IconData? icon;

  /// רכיב לפני התווית, כשסמל בודד אינו מספיק — הכוכבים של גלולת הדירוג.
  final Widget? leading;

  /// גלולה מודגשת בצבע ה-primary — לסטטוס התוסף.
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final background =
        emphasized ? cs.primaryContainer : cs.surfaceContainerHighest;
    final foreground = emphasized ? cs.onPrimaryContainer : cs.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 4),
          ] else if (icon != null) ...[
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 4),
          ],
          // ראו ההערה ב-StatusChip: שבב בודד רחב מהעמודה גלש במקום להתקצר.
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppTokens.fontSM,
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// גלולת תגית — לחיצה עליה מסננת את הרשימה.
class StoreTagPill extends StatelessWidget {
  const StoreTagPill({
    super.key,
    required this.label,
    this.active = false,
    this.onTap,
    this.icon,
  });

  final String label;
  final bool active;
  final VoidCallback? onTap;

  /// סמל קטן לפני התווית — לגלולות שהן פעולה ולא תגית (מתג הסינון).
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final foreground = active ? cs.onPrimary : cs.onSurfaceVariant;

    return Material(
      color: active ? cs.primary : cs.surfaceContainerHighest,
      borderRadius: AppTokens.borderRadiusAll,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        mouseCursor:
            onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: foreground),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppTokens.fontSM,
                    fontWeight: FontWeight.w600,
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "עינית" מעל כותרת סעיף — קו קצר ואחריו טקסט קטן ומודגש. זה הפורמט
/// של כותרות הסעיפים בחנות שבאתר ("מומלצי החנות", "רשימת תוספים").
class StoreSectionEyebrow extends StatelessWidget {
  const StoreSectionEyebrow(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 28, height: 1, color: cs.primary.withValues(alpha: .4)),
        const SizedBox(width: AppTokens.spaceSM),
        Text(
          text,
          style: TextStyle(
            fontSize: AppTokens.fontSM,
            fontWeight: FontWeight.bold,
            color: cs.primary,
          ),
        ),
      ],
    );
  }
}

/// תמונת הפריט מהדיסק המקומי. כשאין תמונה (או שהקובץ נמחק) מוצג
/// [placeholderIcon] על רקע primaryContainer — אין `flutter_svg` בפרויקט
/// ולכן לוגו ה-SVG של החנות המקורית לא הועבר.
class StoreThumbnail extends StatelessWidget {
  const StoreThumbnail({
    super.key,
    required this.imagePath,
    this.aspectRatio = 16 / 11,
    this.iconSize = 44,
    this.placeholderIcon = FluentIcons.puzzle_piece_24_regular,
  });

  final String? imagePath;
  final double aspectRatio;
  final double iconSize;

  /// מה מוצג כשאין תמונה — פאזל לתוסף, קופסה לתוכנה נוספת.
  final IconData placeholderIcon;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: ClipRRect(
        borderRadius: AppTokens.borderRadiusAll,
        child: _content(context),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final path = imagePath;
    if (path == null || path.isEmpty) return _placeholder(context);

    return LayoutBuilder(
      builder: (context, constraints) => Image.file(
        File(path),
        fit: BoxFit.cover,
        cacheWidth: decodeWidthFor(context, constraints.maxWidth),
        errorBuilder: (context, _, __) => _placeholder(context),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.primaryContainer,
      child: Center(
        child: Icon(
          placeholderIcon,
          size: iconSize,
          color: cs.onPrimaryContainer,
        ),
      ),
    );
  }
}

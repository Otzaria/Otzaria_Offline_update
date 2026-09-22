import 'dart:io';
import 'dart:math' as math;

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

/// **הכלל של גודל האייקון:** צלע האייקון היא חלק קבוע מרוחב המסגרת שלו,
/// ולא מספר פיקסלים. כרטיס צר מקבל אייקון קטן וכרטיס רחב אייקון גדול,
/// ולכן הכרטיס נראה אותו הדבר בכל רוחב חלון ובכל מספר עמודות — מספר
/// פיקסלים קבוע נכון לרוחב אחד בלבד, ובכל השאר הוא או זעיר או בולע.
const double kStoreIconRatio = 0.5;

/// האוויר מעל האייקון ומתחתיו, גם הוא כיחס מרוחב המסגרת. יחד עם
/// [kStoreIconRatio] הוא קובע את [kStoreIconFrameAspect].
const double kStoreIconGutterRatio = 0.065;

/// יחס המסגרת שמסביב לאייקון — רוחב חלקי גובה. **נגזר** משני היחסים
/// שלמעלה ולא נבחר בנפרד: מסגרת שגובהה אינו גובה האייקון ועוד האוויר
/// שלו היא בדיוק הפס הריק שהאייקון "מרחף" בתוכו.
const double kStoreIconFrameAspect =
    1 / (kStoreIconRatio + kStoreIconGutterRatio * 2);

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
  })  : _icon = false,
        _ratio = 0,
        _maxSize = 0;

  /// תצוגה של **אייקון** ולא של תמונת חנות: התמונה נכנסת שלמה, ממורכזת,
  /// על רקע ניטרלי, וגודלה נגזר מרוחב המסגרת לפי [kStoreIconRatio].
  ///
  /// ⚠️ זה לא סגנון — זה תיקון של באג. `BoxFit.cover` ממלא את המסגרת
  /// **וחותך** את מה שחורג, ואייקון ריבועי בתוך מסגרת רחבה נחתך מלמעלה
  /// ומלמטה: "האייקון בורח מהמסגרת ולא רואים את כולו".
  ///
  /// [maxSize] הוא חסם הטשטוש ולא העיצוב: אייקון של ווינדוס הוא 256×256
  /// לכל היותר, ומתיחה מעבר לזה רק מרככת אותו. מי שרוצה אייקון קטן יותר
  /// מצר את המסגרת — לא את החסם.
  const StoreThumbnail.icon({
    super.key,
    required this.imagePath,
    this.aspectRatio = kStoreIconFrameAspect,
    this.iconSize = 44,
    this.placeholderIcon = FluentIcons.puzzle_piece_24_regular,
    double ratio = kStoreIconRatio,
    double maxSize = 256,
  })  : _icon = true,
        _ratio = ratio,
        _maxSize = maxSize;

  final String? imagePath;
  final double aspectRatio;
  final double iconSize;

  /// מה מוצג כשאין תמונה — פאזל לתוסף, קופסה לתוכנה נוספת.
  final IconData placeholderIcon;

  final bool _icon;
  final double _ratio;
  final double _maxSize;

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
    return _icon ? _iconImage(context, path) : _coverImage(context, path);
  }

  Widget _coverImage(BuildContext context, String path) {
    return LayoutBuilder(
      builder: (context, constraints) => Image.file(
        File(path),
        fit: BoxFit.cover,
        cacheWidth: decodeWidthFor(context, constraints.maxWidth),
        errorBuilder: (context, _, __) => _placeholder(context),
      ),
    );
  }

  Widget _iconImage(BuildContext context, String path) {
    final cs = Theme.of(context).colorScheme;

    return ColoredBox(
      color: cs.surfaceContainerHighest,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = _iconEdgeFor(constraints);

          return Center(
            child: SizedBox(
              width: size,
              height: size,
              child: Image.file(
                File(path),
                fit: BoxFit.contain,
                cacheWidth: decodeWidthFor(context, size),
                errorBuilder: (context, _, __) => _placeholder(context),
              ),
            ),
          );
        },
      ),
    );
  }

  /// צלע האייקון: היחס מרוחב המסגרת, חסום ברזולוציית המקור וגם בגובה
  /// הפנוי — מסגרת שמישהו הצר ידנית אינה מקום להיחתך בו.
  double _iconEdgeFor(BoxConstraints constraints) {
    final byWidth = constraints.maxWidth * _ratio;
    // אותו יחס בדיוק, אבל נמדד מהגובה — כך האוויר נשאר פרופורציוני גם
    // במסגרת נמוכה מהיחס הקנוני.
    final byHeight =
        constraints.maxHeight * _ratio / (_ratio + kStoreIconGutterRatio * 2);
    return math.min(math.min(byWidth, byHeight), _maxSize);
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

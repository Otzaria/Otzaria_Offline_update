import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:plugins_manager/plugins_manager.dart';

import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';

/// רכיבי התצוגה הקטנים של חנות התוספים.
///
/// אלה **תוספת** למערכת העיצוב של אוצריא ולא פורט ממנה — לכרטיס-חנות עם
/// תמונה ולגלולות מטא-דאטה אין מקבילה שם. הם נבנים מטוקנים קיימים בלבד
/// (`AppTokens`, `ColorScheme`) ונשארים מקומיים לתיקייה הזו. ראו
/// launcher_app/README.md.

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

const Map<String, String> kPluginStatusLabels = {
  'stable': 'יציב',
  'beta': 'בטא',
  'experimental': 'ניסיוני',
};

String pluginStatusLabel(String status) =>
    kPluginStatusLabels[status] ?? 'לא ידוע';

/// גלולת מטא-דאטה קטנה (גרסה, מספר הורדות, סטטוס).
class PluginBadge extends StatelessWidget {
  const PluginBadge({
    super.key,
    required this.label,
    this.icon,
    this.emphasized = false,
  });

  final String label;
  final IconData? icon;

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
          if (icon != null) ...[
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: AppTokens.fontSM,
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

/// גלולת תגית — לחיצה עליה מסננת את הרשימה.
class PluginTagPill extends StatelessWidget {
  const PluginTagPill({
    super.key,
    required this.label,
    this.active = false,
    this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

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
          child: Text(
            label,
            style: TextStyle(
              fontSize: AppTokens.fontSM,
              fontWeight: FontWeight.w600,
              color: active ? cs.onPrimary : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// חיווי המצב מול ההתקנה בפועל. `StatusChip` נותן סמל **וגם** טקסט —
/// חובה לפי מערכת העיצוב, ולא צבע בלבד.
class PluginInstallChip extends StatelessWidget {
  const PluginInstallChip({
    super.key,
    required this.status,
    this.installedVersion,
  });

  final PluginInstallStatus status;
  final String? installedVersion;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      PluginInstallStatus.upToDate => const StatusChip(
          kind: StatusKind.ok,
          label: 'מותקן',
        ),
      PluginInstallStatus.updateAvailable => StatusChip(
          kind: StatusKind.updateAvailable,
          label: installedVersion == null
              ? 'עדכון זמין'
              : 'עדכון זמין (מותקן $installedVersion)',
        ),
      // "לא מותקן" ו-"טרם נבדק" אינם צריכים שבב — היעדר השבב הוא המצב
      // הרגיל בחנות, וכל תוסף שהיה מקבל אותו רק היה מוסיף רעש.
      PluginInstallStatus.notInstalled ||
      PluginInstallStatus.unknown =>
        const SizedBox.shrink(),
    };
  }
}

/// תמונת התוסף מהמראה המקומית. כשאין תמונה (או שהקובץ נמחק) מוצג
/// אייקון פאזל על רקע primaryContainer — אין `flutter_svg` בפרויקט ולכן
/// לוגו ה-SVG של החנות המקורית לא הועבר.
class PluginThumbnail extends StatelessWidget {
  const PluginThumbnail({
    super.key,
    required this.imagePath,
    this.aspectRatio = 16 / 11,
    this.iconSize = 44,
  });

  final String? imagePath;
  final double aspectRatio;
  final double iconSize;

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
          FluentIcons.puzzle_piece_24_regular,
          size: iconSize,
          color: cs.onPrimaryContainer,
        ),
      ),
    );
  }
}

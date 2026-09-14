// AppTitleBar — שורת הכותרת המותאמת של החלון, פורט מאוצריא
// (`otzaria/lib/navigation/view/custom_title_bar.dart`).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/app_strings_scope.dart';
import '../theme/theme_exports.dart';

/// גובה השורה — זהה לאוצריא.
const double kAppTitleBarHeight = 40;

/// שלושת כפתורי החלון של Windows 11, 46 לכל אחד.
const double _kWindowCaptionButtonsWidth = 138;

/// הרוחב שנשמר בפינה **השמאלית הפיזית** ב-macOS לשלושת הכפתורים העגולים של
/// המערכת. הם מצוירים בידי המערכת מעל החלון, ולכן תוכן שיושב שם נחתך תחתיהם
/// — וב-RTL זה דווקא הקצה שבו יושבים כפתורי החלון שלנו היו יושבים.
const double _kMacTrafficLightsWidth = 78;

/// שורת הזהות של האפליקציה, שהיא גם שורת הכותרת של החלון: הסמל והשם בצד
/// ההתחלה, שם המסך הפתוח באמצע, וכפתורי החלון בצד הסיום. כל מה שביניהם גורר
/// את החלון.
class AppTitleBar extends StatelessWidget {
  const AppTitleBar({
    super.key,
    required this.screenTitle,
    this.showWindowButtons,
    this.isMacOS,
  });

  /// שם המסך הפתוח — משתנה עם הלשונית שנבחרה בסרגל, כמו באוצריא.
  final String screenTitle;

  /// כפתורי מזעור/הגדלה/סגירה **בסגנון Windows**. `null` = לפי הפלטפורמה;
  /// בבדיקות widget מוזרק `false`, כי [WindowCaption] מדבר עם ערוץ פלטפורמה
  /// שאינו קיים שם.
  final bool? showWindowButtons;

  /// `null` = לפי הפלטפורמה. מוזרק בבדיקות כדי לאמת את שני הפריסות מאותה
  /// מכונה.
  final bool? isMacOS;

  bool get _isMacOS => isMacOS ?? Platform.isMacOS;

  /// ב-macOS מערכת ההפעלה מציירת את שלושת הכפתורים שלה
  /// (`windowButtonVisibility` ב-`main.dart`), ולכן אין כאן כפתורים משלנו:
  /// שתי שלישיות באותה שורה, אחת בכל קצה, זה מה שהיה מתקבל.
  bool get _showWindowButtons =>
      showWindowButtons ??
      (!_isMacOS && (Platform.isWindows || Platform.isLinux));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = context.strings.shell;

    return Container(
      height: kAppTitleBarHeight,
      decoration: BoxDecoration(
        color: AppSurfaces.topBarBackground(context),
        // הרקע זהה לרקע המסך — הקו התחתון הוא כל מה שמפריד ביניהם.
        border: Border(
          bottom: BorderSide(color: AppSurfaces.shellDivider(context)),
        ),
      ),
      // `EdgeInsets.only(left:)` ולא `EdgeInsetsDirectional`: הכפתורים של
      // macOS יושבים בפינה השמאלית הפיזית גם כשהממשק בעברית.
      padding: _isMacOS
          ? const EdgeInsets.only(left: _kMacTrafficLightsWidth)
          : EdgeInsets.zero,
      child: Row(
        children: [
          DragToMoveArea(
            child: Padding(
              padding: const EdgeInsetsDirectional.only(
                start: AppTokens.spaceMD,
                end: AppTokens.spaceMD,
              ),
              child: Row(
                children: [
                  Image.asset(
                    'assets/images/otzaria_logo.png',
                    height: 24,
                    filterQuality: FilterQuality.medium,
                    semanticLabel: s.otzariaLogoLabel,
                  ),
                  const SizedBox(width: AppTokens.spaceSM),
                  Text(
                    s.appTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: DragToMoveArea(
              child: Center(
                child: Text(
                  screenTitle,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: AppTokens.fontLG,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          if (_showWindowButtons)
            SizedBox(
              width: _kWindowCaptionButtonsWidth,
              height: kAppTitleBarHeight,
              // רקע שקוף — הכפתורים יושבים על צבע השורה עצמה.
              child: WindowCaption(
                brightness: theme.brightness,
                backgroundColor: Colors.transparent,
              ),
            ),
        ],
      ),
    );
  }
}

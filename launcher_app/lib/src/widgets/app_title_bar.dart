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

/// שורת הזהות של האפליקציה, שהיא גם שורת הכותרת של החלון: הסמל והשם בצד
/// ההתחלה, שם המסך הפתוח באמצע, וכפתורי החלון בצד הסיום. כל מה שביניהם גורר
/// את החלון.
class AppTitleBar extends StatelessWidget {
  const AppTitleBar(
      {super.key, required this.screenTitle, this.showWindowButtons});

  /// שם המסך הפתוח — משתנה עם הלשונית שנבחרה בסרגל, כמו באוצריא.
  final String screenTitle;

  /// כפתורי מזעור/הגדלה/סגירה. `null` = לפי הפלטפורמה; בבדיקות widget מוזרק
  /// `false`, כי [WindowCaption] מדבר עם ערוץ פלטפורמה שאינו קיים שם.
  final bool? showWindowButtons;

  bool get _showWindowButtons =>
      showWindowButtons ??
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

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

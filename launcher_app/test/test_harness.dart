// עוזרי בדיקה משותפים למסכי הלאנצ'ר. יושבים בקובץ נפרד (ולא ב-`*_test.dart`)
// כדי שכמה קובצי בדיקה יוכלו לחלוק אותם בלי לגרור זה את הבדיקות של זה.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/theme/theme_exports.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

/// המלל שהבדיקות משוות מולו. אף בדיקה לא כותבת מחרוזת עברית בציפייה —
/// המקור היחיד הוא `otzaria_l10n`, בדיוק כמו בקוד עצמו.
AppStrings stringsOf([AppLanguage language = AppLanguage.hebrew]) =>
    AppL10n.stringsFor(language);

/// עוטף מסך באותו MaterialApp שהאפליקציה בונה — כולל locale he-IL, שהוא
/// מה שקובע RTL גלובלי לכל עץ ה-widgets, ו-[AppStringsScope] שממנו המסכים
/// שואבים את המלל. שניהם חייבים להיות כאן כמו ב-`main.dart`, אחרת
/// `context.strings` נופל.
Widget wrap(Widget child, {AppLanguage language = AppLanguage.hebrew}) =>
    MaterialApp(
      localizationsDelegates: const [
        GlobalCupertinoLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('he', 'IL'), Locale('en')],
      locale: language == AppLanguage.hebrew
          ? const Locale('he', 'IL')
          : const Locale('en'),
      theme: AppThemeData.light(
        AppThemeData.createColorScheme(
          AppSeedColors.defaultLight,
          Brightness.light,
        ),
      ),
      builder: (context, navigator) => AppStringsScope(
        strings: AppL10n.stringsFor(language),
        child: navigator ?? const SizedBox.shrink(),
      ),
      home: child,
    );

/// קובע את גודל המשטח לבדיקה אחת ומחזיר אותו בסופה.
void useViewSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// משטח בדיקה גבוה — ה-ListView של [ScreenBody] בונה רק את מה שנראה,
/// ובחלון ברירת המחדל (800x600) הכרטיסים התחתונים לא היו נבנים בכלל.
///
/// [AppL10n] הגלובלי מוצב גם הוא: חלק מהמלל (למשל `pluginStatusLabel`)
/// נבנה מחוץ ל-widget ולכן קורא ממנו ולא מה-scope, בדיוק כמו באפליקציה
/// שבה `SettingsController` מציב את שניהם יחד.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  AppLanguage language = AppLanguage.hebrew,
  Size size = const Size(1400, 2800),
}) async {
  useViewSize(tester, size);
  AppL10n.use(language);
  addTearDown(() => AppL10n.use(AppLanguage.hebrew));
  await tester.pumpWidget(wrap(screen, language: language));
}

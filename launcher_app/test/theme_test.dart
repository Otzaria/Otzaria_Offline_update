// בדיקות לשכבת העיצוב (`lib/src/theme/`) — הטוקנים, בניית ה-ColorScheme
// והכלל שלפיו שקיפויות וצבעי אינטראקציה מוגדרים כאן ולא ברכיבים.

import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/theme/theme_exports.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

/// בונה את ערכת הנושא כמו `main.dart` — אותם seed וברירות מחדל.
ThemeData themeFor(Brightness brightness) {
  final cs = AppThemeData.createColorScheme(
    brightness == Brightness.dark
        ? AppSeedColors.defaultDark
        : AppSeedColors.defaultLight,
    brightness,
  );
  return brightness == Brightness.dark
      ? AppThemeData.dark(cs)
      : AppThemeData.light(cs);
}

/// שולף את צבע ה-overlay של סגנון כפתור במצב נתון.
Color? overlayFor(ButtonStyle? style, WidgetState state) =>
    style?.overlayColor?.resolve({state});

void main() {
  group('AppTokens', () {
    test('סולם המרווחים עולה, והרדיוס אחיד ב-8', () {
      expect(
        [
          AppTokens.spaceXS,
          AppTokens.spaceSM,
          AppTokens.spaceMD,
          AppTokens.spaceLG,
          AppTokens.spaceXL,
        ],
        [4.0, 8.0, 16.0, 24.0, 32.0],
      );

      expect(AppTokens.radius, 8);
      expect(
        AppTokens.borderRadiusAll,
        const BorderRadius.all(Radius.circular(8)),
      );
      expect(AppTokens.roundedShape.borderRadius, AppTokens.borderRadiusAll);
    });

    test('סולם הטיפוגרפיה עולה, וסגנוני ההגדרות נגזרים ממנו', () {
      expect(
        [
          AppTokens.fontSM,
          AppTokens.fontMD,
          AppTokens.fontLG,
          AppTokens.fontXL
        ],
        [12.0, 14.0, 16.0, 18.0],
      );
      expect(AppTextStyles.settingTitle.fontSize, AppTokens.fontLG);
      expect(
        AppTextStyles.settingSubtitle.fontSize,
        lessThan(AppTextStyles.settingTitle.fontSize!),
      );
    });

    test('משכי האנימציה עולים', () {
      expect(AppTokens.animFast, lessThan(AppTokens.animNormal));
      expect(AppTokens.animNormal, lessThan(AppTokens.animSlow));
    });
  });

  group('LayoutTokens', () {
    test('נקודות השבירה עולות ורוחב התוכן הוא 860', () {
      expect(LayoutBreakpoints.compact, lessThan(LayoutBreakpoints.medium));
      expect(LayoutBreakpoints.medium, lessThan(LayoutBreakpoints.expanded));
      expect(LayoutConstraints.panelContentMaxWidth, 860.0);
    });
  });

  group('AppSeedColors', () {
    // ברירות המחדל זהות לאוצריא — זה מה שגורם לשתי האפליקציות להיראות אותו דבר.
    test('ברירות המחדל הן הגוונים של אוצריא', () {
      expect(AppSeedColors.defaultLight, const Color(0xFF2C1B02));
      expect(AppSeedColors.defaultDark, const Color(0xFF9C27B0));
    });

    test('רשימת האפשרויות מלאה, בלי כפילות צבע או שם', () {
      const options = AppSeedColors.options;

      expect(options, hasLength(13));
      expect(options.map((o) => o.color).toSet(), hasLength(options.length));
      expect(options.map((o) => o.name).toSet(), hasLength(options.length));
      expect(
        options.map((o) => o.color),
        containsAll([AppSeedColors.defaultLight, AppSeedColors.defaultDark]),
      );
    });
  });

  group('createColorScheme', () {
    test('הבהירות שנתבקשה היא הבהירות שמתקבלת', () {
      for (final brightness in Brightness.values) {
        final cs = AppThemeData.createColorScheme(
          AppSeedColors.blue,
          brightness,
        );
        expect(cs.brightness, brightness);
      }
    });

    // צבע רווי מקבל גוון; צבע ניטרלי מקבל monochrome כדי שלא יקבל גוון מקרי.
    test('seed ניטרלי יוצא אפור, וצבעוני יוצא צבעוני', () {
      final neutral = AppThemeData.createColorScheme(
        AppSeedColors.grey,
        Brightness.light,
      );
      final colorful = AppThemeData.createColorScheme(
        AppSeedColors.blue,
        Brightness.light,
      );

      expect(HSLColor.fromColor(neutral.primary).saturation, lessThan(0.05));
      expect(HSLColor.fromColor(colorful.primary).saturation, greaterThan(0.1));
    });

    test('אותו seed מחזיר תמיד את אותה ערכה', () {
      expect(
        AppThemeData.createColorScheme(AppSeedColors.teal, Brightness.dark),
        AppThemeData.createColorScheme(AppSeedColors.teal, Brightness.dark),
      );
    });
  });

  group('AppThemeData', () {
    test('שתי הערכות M3, באותו רדיוס ובאותו מחסום דיאלוג', () {
      for (final brightness in Brightness.values) {
        final theme = themeFor(brightness);

        expect(theme.useMaterial3, isTrue);
        expect(theme.colorScheme.brightness, brightness);
        expect(theme.cardTheme.shape, AppTokens.roundedShape);
        expect(theme.dialogTheme.shape, AppTokens.roundedShape);
        expect(theme.dialogTheme.barrierColor, AppColors.dialogBarrier);
        expect(
          theme.dialogTheme.backgroundColor,
          theme.colorScheme.surfaceContainerHigh,
        );
        expect(
          theme.progressIndicatorTheme.color,
          theme.colorScheme.primary,
        );
        expect(
          theme.progressIndicatorTheme.borderRadius,
          AppTokens.borderRadiusAll,
        );
      }
    });

    // ה-hover של אוצריא: 8% מהצבע, ו-12% ללחיצה/מיקוד.
    test('ה-overlay של הכפתורים הוא 8% ו-12% מצבע הבסיס', () {
      final theme = themeFor(Brightness.light);
      final cs = theme.colorScheme;

      final cases = <String, (ButtonStyle?, Color)>{
        'filled': (theme.filledButtonTheme.style, cs.onPrimary),
        'text': (theme.textButtonTheme.style, cs.primary),
        'outlined': (theme.outlinedButtonTheme.style, cs.primary),
        'icon': (theme.iconButtonTheme.style, cs.primary),
      };

      cases.forEach((name, entry) {
        final (style, base) = entry;
        expect(
          overlayFor(style, WidgetState.hovered),
          base.withValues(alpha: 0.08),
          reason: name,
        );
        for (final state in [WidgetState.pressed, WidgetState.focused]) {
          expect(
            overlayFor(style, state),
            base.withValues(alpha: 0.12),
            reason: '$name/$state',
          );
        }
        // מצב רגיל נשאר בלי overlay בכלל.
        expect(overlayFor(style, WidgetState.disabled), isNull, reason: name);
      });
    });

    test('כל סגנונות הכפתורים משתמשים באותה צורה מעוגלת', () {
      final theme = themeFor(Brightness.dark);

      for (final style in [
        theme.filledButtonTheme.style,
        theme.textButtonTheme.style,
        theme.outlinedButtonTheme.style,
        theme.iconButtonTheme.style,
      ]) {
        expect(style?.shape?.resolve({}), AppTokens.roundedShape);
      }
    });
  });

  group('AppSurfaces', () {
    testWidgets('הרקעים נגזרים מהבהירות ונבדלים בין בהיר לכהה', (tester) async {
      final collected = {
        for (final brightness in Brightness.values)
          brightness: <String, Color>{}
      };

      // שתי הערכות באותו pump: `MaterialApp` מנפיש מעבר ערכה (200ms), ולכן
      // pump בודד אחרי החלפת theme היה מחזיר עדיין את הערכה הקודמת.
      await tester.pumpWidget(MaterialApp(
        home: Column(
          children: [
            for (final brightness in Brightness.values)
              Theme(
                data: themeFor(brightness),
                child: Builder(builder: (context) {
                  collected[brightness]!
                    ..['panel'] = AppSurfaces.panelBackground(context)
                    ..['topBar'] = AppSurfaces.topBarBackground(context)
                    ..['navRail'] = AppSurfaces.navRailBackground(context)
                    ..['card'] = AppSurfaces.card(context)
                    ..['selection'] = AppSurfaces.cardSelectionOverlay(context)
                    ..['section'] = AppSurfaces.panelSection(context)
                    // המפריד בין שורות בכרטיס הוא רקע הלוח עצמו.
                    ..['divider'] = AppSurfaces.cardRowDivider(context);
                  return const SizedBox.shrink();
                }),
              ),
          ],
        ),
      ));

      final light = collected[Brightness.light]!;
      final dark = collected[Brightness.dark]!;

      expect(light, hasLength(7));
      for (final key in light.keys) {
        expect(light[key], isNot(dark[key]), reason: key);
      }
      expect(light['divider'], light['panel']);
      // שורת הכותרת וסרגל הניווט נצבעים ברקע הלוח עצמו — בלי תפר מול התוכן.
      for (final surfaces in [light, dark]) {
        expect(surfaces['topBar'], surfaces['panel']);
        expect(surfaces['navRail'], surfaces['panel']);
      }
    });

    test('רקע שבב המצב נגזר מצבע החיווי בשקיפות אחידה', () {
      const base = Color(0xFF123456);
      final chip = AppSurfaces.statusChip(base);

      expect(chip, base.withValues(alpha: 0.12));
      // עדיין אותו גוון — רק השקיפות משתנה.
      expect(chip.withValues(alpha: 1.0), base);
    });
  });

  group('ערכת הנושא בפועל', () {
    // שתי הערכות ושתי השפות — הצירוף שהמשתמש באמת יכול לבחור.
    for (final brightness in Brightness.values) {
      for (final language in AppLanguage.values) {
        testWidgets(
          'רכיבים נבנים ב-${brightness.name}/${language.code}',
          (tester) async {
            await tester.pumpWidget(MaterialApp(
              localizationsDelegates: const [
                GlobalCupertinoLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
              ],
              supportedLocales: const [Locale('he', 'IL'), Locale('en')],
              locale: language == AppLanguage.hebrew
                  ? const Locale('he', 'IL')
                  : const Locale('en'),
              theme: themeFor(brightness),
              builder: (context, navigator) => AppStringsScope(
                strings: AppL10n.stringsFor(language),
                child: navigator ?? const SizedBox.shrink(),
              ),
              home: Builder(builder: (context) {
                final s = context.strings;
                return Scaffold(
                  backgroundColor: AppSurfaces.panelBackground(context),
                  body: SettingsCard(
                    title: s.settings.appearanceCardTitle,
                    children: [
                      InfoStatusRow(
                        icon: FluentIcons.info_24_regular,
                        title: s.libraryScreen.stateRowTitle,
                        kind: StatusKind.ok,
                        label: s.common.upToDate,
                      ),
                      SettingsActionTile.text(
                        title: s.settings.languageTitle,
                        actions: [
                          ActionButton.recommended(
                            text: s.common.install,
                            onPressed: () {},
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
            ));
            await tester.pumpAndSettle();

            expect(tester.takeException(), isNull);
            expect(
              find.text(AppL10n.stringsFor(language).common.upToDate),
              findsOneWidget,
            );
          },
        );
      }
    }
  });

  // הכלל מ-README: שקיפויות ו-hover מוגדרים ב-`theme/` בלבד. שלוש החריגות
  // הרשומות כאן קיימות בקוד היום — הבדיקה נועדה לתפוס **רביעית**.
  group('גבולות שכבת העיצוב', () {
    const knownDeviations = {
      // מפרט M3 למצב מושבת של Switch — פורט מילולית מאוצריא.
      'custom_switch.dart',
      // טוקן השקיפות של ה-toast, מקומי ל-Overlay.
      'ui_snack.dart',
      // ביטול hover על השורה כולה (Colors.transparent), לא צבע חדש.
      'settings_card.dart',
    };

    test('שקיפויות ו-hover ברכיבים — רק החריגות המתועדות', () {
      final offenders = <String>{};

      for (final entity in Directory('lib/src/widgets').listSync()) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        if (source.contains('withValues(alpha:') ||
            source.contains('hoverColor') ||
            source.contains('splashColor')) {
          offenders.add(entity.uri.pathSegments.last);
        }
      }

      expect(offenders, knownDeviations);
    });

    test('שכבת העיצוב מיוצאת כולה מה-barrel', () {
      final exported = File('lib/src/theme/theme_exports.dart')
          .readAsStringSync()
          .split('\n')
          .where((line) => line.startsWith('export '))
          .length;
      final files = Directory('lib/src/theme')
          .listSync()
          .whereType<File>()
          .where((f) =>
              f.path.endsWith('.dart') &&
              !f.path.endsWith('theme_exports.dart'))
          .length;

      expect(exported, files);
    });
  });
}

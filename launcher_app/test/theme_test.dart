// בדיקות לשכבת העיצוב (`lib/src/theme/`) — הטוקנים, הפלטה מול ערכי המוקאפ,
// והכלל שלפיו שקיפויות וצבעי אינטראקציה מוגדרים כאן ולא ברכיבים.

import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/theme/theme_exports.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

/// שולף את צבע ה-overlay של סגנון כפתור במצב נתון.
Color? overlayFor(ButtonStyle? style, WidgetState state) =>
    style?.overlayColor?.resolve({state});

/// [top] ב-[alpha] מעל [base], מעוגל ל-8 ביט כמו ה-hex של המוקאפ.
int _over(Color base, Color top, double alpha) =>
    Color.alphaBlend(top.withValues(alpha: alpha), base).toARGB32();

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

    test('המידות של המוקאפ', () {
      expect(AppTokens.titleBarHeight, 36);
      expect(AppTokens.captionButtonWidth, 46);
      expect(
        [
          AppTokens.buttonHeightSm,
          AppTokens.buttonHeight,
          AppTokens.buttonHeightLg,
        ],
        [32.0, 40.0, 44.0],
      );
      expect(AppTokens.chipHeight, 24);
      expect(AppTokens.rowMinHeight, 56);
      expect(AppTokens.taskFooterHeight, 68);
      expect(AppTokens.dialogWidth, 336);
      expect(AppTokens.dialogFormWidth, 440);
      // הממשק שטוח.
      expect(
        [AppTokens.elevation0, AppTokens.elevation1, AppTokens.elevation2],
        everyElement(0),
      );
    });

    test('סגנונות הטקסט לפי סולם המוקאפ', () {
      const semibold = FontWeight.w600;
      final cases = <String, (TextStyle, double, FontWeight?)>{
        'pageTitle': (AppTextStyles.pageTitle, 20, semibold),
        'heroTitle': (AppTextStyles.heroTitle, 24, semibold),
        'sectionLabel': (AppTextStyles.sectionLabel, 13, semibold),
        'rowTitle': (AppTextStyles.rowTitle, 14, semibold),
        'rowSub': (AppTextStyles.rowSub, 13, null),
        'rowValue': (AppTextStyles.rowValue, 16, null),
        'meta': (AppTextStyles.meta, 12, null),
        'percent': (AppTextStyles.percent, 40, semibold),
        'dialogTitle': (AppTextStyles.dialogTitle, 18, semibold),
        'dialogBody': (AppTextStyles.dialogBody, 14, null),
        'button': (AppTextStyles.button, 14, semibold),
        'buttonSm': (AppTextStyles.buttonSm, 13, semibold),
        'chip': (AppTextStyles.chip, 12, semibold),
      };
      cases.forEach((name, entry) {
        final (style, size, weight) = entry;
        expect(style.fontSize, size, reason: name);
        expect(style.fontWeight, weight, reason: name);
      });
      // אין Bold 700 בשפת העיצוב.
      for (final (style, _, _) in cases.values) {
        expect(style.fontWeight, isNot(FontWeight.bold));
      }
      expect(AppTextStyles.settingTitle, AppTextStyles.rowTitle);
      expect(AppTextStyles.settingSubtitle, AppTextStyles.rowSub);
    });

    test('משכי האנימציה עולים', () {
      expect(AppTokens.animFast, lessThan(AppTokens.animNormal));
      expect(AppTokens.animNormal, lessThan(AppTokens.animSlow));
    });
  });

  group('LayoutTokens', () {
    test('רוחב התוכן 720 (768 עם הריפוד), והדף הרחב 960', () {
      expect(LayoutBreakpoints.compact, lessThan(LayoutBreakpoints.medium));
      expect(LayoutBreakpoints.medium, lessThan(LayoutBreakpoints.expanded));
      expect(LayoutConstraints.panelContentMaxWidth, 720.0);
      expect(LayoutConstraints.wideContentMaxWidth, 960.0);
      expect(
        LayoutConstraints.pagePadding,
        const EdgeInsets.fromLTRB(24, 28, 24, 40),
      );
    });
  });

  group('הפלטה', () {
    final cs = AppThemeData.colorScheme;

    // ערכי `:root` במוקאפ — אם ה-seed או Flutter ישנו את הגוונים, זה ייפול.
    test('ColorScheme מה-seed הקבוע = ערכי המוקאפ', () {
      expect(AppThemeData.seed, const Color(0xFF2C1B02));
      final expected = <String, (Color, int)>{
        'surface': (cs.surface, 0xFFFFF8F4),
        'surfaceContainerLowest': (cs.surfaceContainerLowest, 0xFFFFFFFF),
        'surfaceContainerLow': (cs.surfaceContainerLow, 0xFFFFF1E5),
        'surfaceContainer': (cs.surfaceContainer, 0xFFF9ECDF),
        'surfaceContainerHigh': (cs.surfaceContainerHigh, 0xFFF3E6DA),
        'surfaceContainerHighest': (cs.surfaceContainerHighest, 0xFFEDE0D4),
        'onSurface': (cs.onSurface, 0xFF201B13),
        'onSurfaceVariant': (cs.onSurfaceVariant, 0xFF4F4539),
        'outline': (cs.outline, 0xFF817567),
        'outlineVariant': (cs.outlineVariant, 0xFFD3C4B4),
        'primary': (cs.primary, 0xFF805610),
        'onPrimary': (cs.onPrimary, 0xFFFFFFFF),
        'secondaryContainer': (cs.secondaryContainer, 0xFFFBDEBC),
        'onSecondaryContainer': (cs.onSecondaryContainer, 0xFF56442A),
        'error': (cs.error, 0xFFBA1A1A),
        'onError': (cs.onError, 0xFFFFFFFF),
        'errorContainer': (cs.errorContainer, 0xFFFFDAD6),
        'onErrorContainer': (cs.onErrorContainer, 0xFF93000A),
        'inverseSurface': (cs.inverseSurface, 0xFF362F27),
        'onInverseSurface': (cs.onInverseSurface, 0xFFFCEFE2),
      };
      expected.forEach((name, entry) {
        final (actual, hex) = entry;
        expect(actual.toARGB32(), hex, reason: name);
      });
      expect(cs.brightness, Brightness.light);
    });

    test('AppPalette = ערכי ה-ThemeExtension במוקאפ', () {
      const p = AppPalette.light;
      final expected = <String, (Color, int)>{
        'page': (p.page, 0xFFF6EDE5),
        'cardSelected': (p.cardSelected, 0xFFFEF0E3),
        'primaryHover': (p.primaryHover, 0xFF8A6423),
        'primaryPressed': (p.primaryPressed, 0xFF8F6A2D),
        'tonalHover': (p.tonalHover, 0xFFFBE1C1),
        'tonalPressed': (p.tonalPressed, 0xFFFBE2C4),
        'titleBarBorder': (p.titleBarBorder, 0xFFE1D4C8),
        'captionHover': (p.captionHover, 0xFFEDE4DC),
        'captionGlyph': (p.captionGlyph, 0xFF1A1918),
        'closeHover': (p.closeHover, 0xFFC42B1C),
        'closeGlyph': (p.closeGlyph, 0xFFFFFFFF),
        'disabledContainer': (p.disabledContainer, 0xFFDDD3CC),
        'disabledText': (p.disabledText, 0xFFA59D95),
        'dotDone': (p.dotDone, 0xFFBBA27A),
        'ornament': (p.ornament, 0xFFB2883E),
        'glow': (p.glow, 0xFFE9B96A),
        'rating': (p.rating, 0xFF9C6E28),
      };
      expected.forEach((name, entry) {
        final (actual, hex) = entry;
        expect(actual.toARGB32(), hex, reason: name);
      });
      expect(AppColors.ratingStar, p.rating);
    });

    // הקבועים שבפלטה הם שכבות מצב של ה-ColorScheme; אם אחד מהם יזוז, הכפתור
    // המצויר ידבר בגוון אחר מה-overlay של ה-theme.
    test('גווני המצב בפלטה נגזרים מה-ColorScheme', () {
      const p = AppPalette.light;
      expect(_over(cs.surface, cs.surfaceContainerHighest, 0.475),
          p.page.toARGB32());
      expect(_over(cs.surface, cs.secondaryContainer, 0.3),
          p.cardSelected.toARGB32());
      expect(_over(cs.primary, cs.onPrimary, 0.08), p.primaryHover.toARGB32());
      expect(
          _over(cs.primary, cs.onPrimary, 0.12), p.primaryPressed.toARGB32());
      expect(_over(cs.secondaryContainer, Colors.white, 0.08),
          p.tonalHover.toARGB32());
      expect(_over(cs.secondaryContainer, Colors.white, 0.12),
          p.tonalPressed.toARGB32());
      // disabledContainer נלקח מהמוקאפ כמו שהוא: החישוב יוצא DDD2CC.
    });
  });

  group('AppThemeData', () {
    final theme = AppThemeData.light();

    test('ערכה בהירה אחת: M3, Segoe UI, הפלטה, ובלי bodyMedium מוגדל', () {
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme, AppThemeData.colorScheme);
      expect(theme.textTheme.bodyMedium?.fontFamily, 'Segoe UI');
      // בלי ה-bodyMedium המוגדל (18) של הגרסה הקודמת.
      expect(theme.textTheme.bodyMedium?.fontSize, isNot(18));
      expect(theme.extension<AppPalette>(), AppPalette.light);
      expect(theme.scaffoldBackgroundColor, AppPalette.light.page);
    });

    test('רדיוס 8, בלי צל, ומחסום הדו-שיח', () {
      expect(theme.cardTheme.shape, AppTokens.roundedShape);
      expect(theme.cardTheme.elevation, 0);
      expect(theme.dialogTheme.shape, AppTokens.roundedShape);
      expect(theme.dialogTheme.elevation, 0);
      expect(theme.dialogTheme.barrierColor, AppColors.dialogBarrier);
      expect(
        theme.dialogTheme.backgroundColor,
        theme.colorScheme.surfaceContainerHigh,
      );
      expect(theme.popupMenuTheme.elevation, 0);
      expect(theme.menuTheme.style?.elevation?.resolve({}), 0);
      final tooltip = theme.tooltipTheme.decoration as BoxDecoration?;
      expect(tooltip?.boxShadow, isNull);
      expect(theme.progressIndicatorTheme.color, theme.colorScheme.primary);
      expect(
        theme.progressIndicatorTheme.borderRadius,
        AppTokens.borderRadiusAll,
      );
    });

    // ריחוף 8% מהצבע ו-12% ללחיצה. מיקוד אינו צובע — הוא טבעת.
    test('ה-overlay של הכפתורים הוא 8% ו-12% מצבע הבסיס', () {
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
        expect(
          overlayFor(style, WidgetState.pressed),
          base.withValues(alpha: 0.12),
          reason: name,
        );
        expect(
          overlayFor(style, WidgetState.focused),
          Colors.transparent,
          reason: name,
        );
        expect(overlayFor(style, WidgetState.disabled), isNull, reason: name);
      });
    });

    test('כל סגנונות הכפתורים משתמשים באותה צורה מעוגלת', () {
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
    testWidgets('הרקעים לפי המוקאפ', (tester) async {
      final collected = <String, Color>{};
      await tester.pumpWidget(MaterialApp(
        theme: AppThemeData.light(),
        home: Builder(builder: (context) {
          collected
            ..['panel'] = AppSurfaces.panelBackground(context)
            ..['topBar'] = AppSurfaces.topBarBackground(context)
            ..['divider'] = AppSurfaces.shellDivider(context)
            ..['card'] = AppSurfaces.card(context)
            ..['selected'] = AppSurfaces.cardSelected(context)
            ..['rowDivider'] = AppSurfaces.cardRowDivider(context)
            ..['banner'] = AppSurfaces.banner(context);
          return const SizedBox.shrink();
        }),
      ));

      final cs = AppThemeData.colorScheme;
      expect(collected['panel'], const Color(0xFFF6EDE5));
      expect(collected['topBar'], cs.surfaceContainerHigh);
      expect(collected['divider'], const Color(0xFFE1D4C8));
      expect(collected['card'], cs.surface);
      expect(collected['selected'], const Color(0xFFFEF0E3));
      // הרצועה בין שורות בכרטיס היא רקע הדף עצמו.
      expect(collected['rowDivider'], collected['panel']);
      expect(
        collected['banner']!.toARGB32(),
        _over(collected['panel']!, cs.secondaryContainer, 0.45),
      );
    });

    test('שכבת המצב: 8% בריחוף, 12% בלחיצה, כלום במיקוד וכשמושבת', () {
      const base = Color(0xFF123456);
      final layer = AppSurfaces.stateLayer(base);

      expect(layer.resolve({WidgetState.hovered}), base.withValues(alpha: .08));
      expect(layer.resolve({WidgetState.pressed}), base.withValues(alpha: .12));
      expect(layer.resolve({WidgetState.focused}), Colors.transparent);
      expect(layer.resolve({WidgetState.disabled}), isNull);
      expect(layer.resolve({}), isNull);
    });
  });

  group('ערכת הנושא בפועל', () {
    for (final language in AppLanguage.values) {
      testWidgets('רכיבים נבנים ב-${language.code}', (tester) async {
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
          theme: AppThemeData.light(),
          builder: (context, navigator) => AppStringsScope(
            strings: AppL10n.stringsFor(language),
            child: navigator ?? const SizedBox.shrink(),
          ),
          home: Builder(builder: (context) {
            final s = context.strings;
            return Scaffold(
              backgroundColor: AppSurfaces.panelBackground(context),
              body: SettingsCard(
                title: s.settings.groupGeneral,
                children: [
                  InfoStatusRow(
                    icon: FluentIcons.info_24_regular,
                    title: s.pages.libSourceTitle,
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
      });
    }
  });

  // הכלל מ-README: שקיפויות ו-hover מוגדרים ב-`theme/` בלבד. החריגה הרשומה
  // כאן קיימת בקוד היום — הבדיקה נועדה לתפוס **שנייה**.
  group('גבולות שכבת העיצוב', () {
    const knownDeviations = {
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

    // בהיר בלבד: שום קוד אינו מסתעף על בהירות, ואין ערכה כהה.
    test('אין מצב כהה ואין צל בשום מקום ב-lib', () {
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        for (final banned in [
          'Brightness.dark',
          'darkTheme',
          'ThemeMode.',
          'BoxShadow',
          'elevation: 8',
        ]) {
          if (source.contains(banned)) offenders.add('${entity.path}: $banned');
        }
      }
      expect(offenders, isEmpty);
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

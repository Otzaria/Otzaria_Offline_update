// בדיקות לשכבת הרכיבים המשותפת (`lib/src/widgets/`) ולמקור המלל שלה
// (`AppStringsScope`). שלושה דברים נבדקים כאן ולא במסכים: החלפת שפה חיה,
// כיווניות שנגזרת מה-locale בלבד, והתנהגות הרכיבים בהגדלת טקסט.

import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/theme/theme_exports.dart';
import 'package:launcher_app/src/widgets/screen_body.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

final AppStrings he = AppL10n.stringsFor(AppLanguage.hebrew);
final AppStrings en = AppL10n.stringsFor(AppLanguage.english);

/// עוטף רכיב באותו MaterialApp ש-`main.dart` בונה: ה-locale (ולא
/// `Directionality` ידני) הוא שקובע את הכיוון, וה-scope יושב ב-`builder`
/// כלומר מעל ה-Navigator — כך שגם דיאלוגים ומסלולים דחופים מוצאים אותו.
/// ערכת הנושא הכהה נבדקת ב-`theme_test.dart`; כאן די בבהירה.
Widget wrap(
  Widget child, {
  AppLanguage language = AppLanguage.hebrew,
  double textScale = 1.0,
}) =>
    MaterialApp(
      navigatorKey: navigatorKey,
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
        child: MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: navigator ?? const SizedBox.shrink(),
        ),
      ),
      home: Scaffold(body: child),
    );

/// הגדלות הטקסט שנבדקות — 2.0 הוא המקסימום שמערכות ההפעלה מציעות.
const List<double> textScales = [1.0, 1.3, 2.0];

/// קורא את ה-[IconData] שנצבע בפועל בתוך [RtlIcon] — כלומר אחרי ההיפוך.
IconData renderedIcon(WidgetTester tester, Finder rtlIcon) => tester
    .widget<Icon>(find.descendant(of: rtlIcon, matching: find.byType(Icon)))
    .icon!;

void main() {
  // המלל הגלובלי הוא מצב משותף בין בדיקות (AppDialog ו-UiSnack קוראים ממנו
  // ישירות), ולכן מוחזר לעברית אחרי כל בדיקה.
  tearDown(() => AppL10n.use(AppLanguage.hebrew));

  // ── AppStringsScope ────────────────────────────────────────────────────────

  group('AppStringsScope', () {
    testWidgets('החלפת שפה מרעננת גם תת-עץ const', (tester) async {
      _ConstLabel.builds = 0;
      await tester.pumpWidget(const MaterialApp(home: _LanguageSwitcher()));

      expect(find.text(he.common.confirm), findsOneWidget);
      final buildsBefore = _ConstLabel.builds;

      await tester.tap(find.byKey(const Key('toggle')));
      await tester.pump();

      // ה-widget עצמו זהה (const), ולכן רק ה-InheritedWidget יכול היה
      // לגרום לבנייה מחדש — בדיוק הסיבה שהוא לא קריאה ישירה ל-AppL10n.
      expect(_ConstLabel.builds, buildsBefore + 1);
      expect(find.text(en.common.confirm), findsOneWidget);
      expect(find.text(he.common.confirm), findsNothing);
    });

    testWidgets('אותה שפה שוב אינה מרעננת את תת-העץ', (tester) async {
      _ConstLabel.builds = 0;
      await tester.pumpWidget(
        const MaterialApp(
            home: _LanguageSwitcher(toggleTo: AppLanguage.hebrew)),
      );
      final buildsBefore = _ConstLabel.builds;

      await tester.tap(find.byKey(const Key('toggle')));
      await tester.pump();

      expect(_ConstLabel.builds, buildsBefore);
    });

    testWidgets('מסלול שנדחף מעל ה-Navigator מוצא את המלל', (tester) async {
      await tester.pumpWidget(wrap(
        Builder(
          builder: (context) => ActionButton.recommended(
            key: const Key('push'),
            text: he.common.confirm,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => Scaffold(
                  body: Text(context.strings.home.title),
                ),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.byKey(const Key('push')));
      await tester.pumpAndSettle();

      expect(find.text(he.home.title), findsOneWidget);
    });

    testWidgets('דיאלוג קורא את המלל מתוך המסלול שלו', (tester) async {
      await tester.pumpWidget(wrap(
        Builder(
          builder: (context) => ActionButton.recommended(
            key: const Key('open'),
            text: he.common.confirm,
            onPressed: () => showSingleActionDialog(
              context: context,
              title: he.settings.logTitle,
              // הקריאה נעשית **בתוך** מסלול הדיאלוג, מתחת ל-Navigator.
              customContent: Builder(
                builder: (context) =>
                    Text(context.strings.settings.logSubtitle),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();

      expect(find.text(he.settings.logSubtitle), findsOneWidget);
    });
  });

  // ── כיווניות ───────────────────────────────────────────────────────────────

  group('כיווניות', () {
    testWidgets('הכיוון נגזר מה-locale בלבד', (tester) async {
      const probe = SizedBox.shrink(key: Key('probe'));

      await tester.pumpWidget(wrap(probe));
      expect(
        Directionality.of(tester.element(find.byKey(const Key('probe')))),
        TextDirection.rtl,
      );

      await tester.pumpWidget(wrap(probe, language: AppLanguage.english));
      expect(
        Directionality.of(tester.element(find.byKey(const Key('probe')))),
        TextDirection.ltr,
      );
    });

    // ההיפוך הכפול: העוזרים מוסרים ל-RtlIcon את הסמל ההפוך, והוא מהפך בחזרה.
    testWidgets('חצי חזרה/קדימה נראים זהה בעברית ובאנגלית', (tester) async {
      Future<(IconData, IconData)> arrowsFor(AppLanguage language) async {
        await tester.pumpWidget(wrap(
          Builder(
            builder: (context) => Row(
              children: [
                RtlIcon(context.backArrowIcon, key: const Key('back')),
                RtlIcon(context.forwardArrowIcon, key: const Key('forward')),
              ],
            ),
          ),
          language: language,
        ));
        return (
          renderedIcon(tester, find.byKey(const Key('back'))),
          renderedIcon(tester, find.byKey(const Key('forward'))),
        );
      }

      final hebrew = await arrowsFor(AppLanguage.hebrew);
      final english = await arrowsFor(AppLanguage.english);

      expect(hebrew.$1, english.$1);
      expect(hebrew.$2, english.$2);
      // ושני החצים באמת מנוגדים — אחרת ההשוואה למעלה חסרת משמעות.
      expect(hebrew.$1, isNot(hebrew.$2));
    });

    testWidgets('RtlIcon מחליף אייקון ממופה ב-RTL ומשאיר אותו ב-LTR',
        (tester) async {
      const arrow = FluentIcons.arrow_right_24_regular;

      await tester.pumpWidget(wrap(const RtlIcon(arrow)));
      expect(
        renderedIcon(tester, find.byType(RtlIcon)),
        FluentIcons.arrow_left_24_regular,
      );

      await tester.pumpWidget(
        wrap(const RtlIcon(arrow), language: AppLanguage.english),
      );
      expect(renderedIcon(tester, find.byType(RtlIcon)), arrow);
    });

    testWidgets('אייקון בלי גרסת RTL מתהפך גאומטרית, ואייקון נייטרלי לא',
        (tester) async {
      Finder flipIn(Finder icon) =>
          find.descendant(of: icon, matching: find.byType(Transform));

      await tester.pumpWidget(wrap(const Row(
        children: [
          RtlIcon(FluentIcons.book_24_regular, key: Key('book')),
          RtlIcon(FluentIcons.settings_24_regular, key: Key('settings')),
        ],
      )));

      expect(flipIn(find.byKey(const Key('book'))), findsOneWidget);
      expect(flipIn(find.byKey(const Key('settings'))), findsNothing);

      await tester.pumpWidget(
        wrap(
          const RtlIcon(FluentIcons.book_24_regular, key: Key('book')),
          language: AppLanguage.english,
        ),
      );
      expect(flipIn(find.byKey(const Key('book'))), findsNothing);
    });

    testWidgets('RtlTextField יורש את כיוון השפה ואינו כופה RTL',
        (tester) async {
      for (final (language, expected) in [
        (AppLanguage.hebrew, TextDirection.rtl),
        (AppLanguage.english, TextDirection.ltr),
      ]) {
        await tester.pumpWidget(
          wrap(const RtlTextField(), language: language),
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).textDirection,
          expected,
        );
      }
    });

    testWidgets('RtlTextField מדווח על הקלדה, ומושבת אינו מקבל קלט',
        (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      String? seen;

      await tester.pumpWidget(wrap(RtlTextField(
        controller: controller,
        onChanged: (v) => seen = v,
        decoration: InputDecoration(labelText: he.plugins.filterSearchLabel),
      )));

      expect(find.text(he.plugins.filterSearchLabel), findsOneWidget);
      await tester.enterText(find.byType(TextField), he.plugins.statusStable);
      expect(seen, he.plugins.statusStable);

      await tester.pumpWidget(wrap(RtlTextField(
        controller: controller,
        enabled: false,
        onChanged: (v) => seen = v,
      )));
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    });

    // הכיווניות מגיעה מה-locale; החריג היחיד המותר הוא UiSnack שב-Overlay.
    test('אין Directionality ידני ברכיבים — חוץ מ-UiSnack', () {
      final offenders = [
        for (final file in Directory('lib/src/widgets').listSync())
          if (file is File &&
              file.path.endsWith('.dart') &&
              file.readAsStringSync().contains('Directionality('))
            file.uri.pathSegments.last,
      ];

      expect(offenders, ['ui_snack.dart']);
    });
  });

  // ── ActionButton ───────────────────────────────────────────────────────────

  group('ActionButton', () {
    testWidgets('כל הווריאנטים מציגים את הטקסט ומדווחים על לחיצה',
        (tester) async {
      var taps = 0;
      final label = he.common.install;

      for (final button in [
        ActionButton.recommended(text: label, onPressed: () => taps++),
        ActionButton.neutral(text: label, onPressed: () => taps++),
        ActionButton.ghost(text: label, onPressed: () => taps++),
        ActionButton.warning(text: label, onPressed: () => taps++),
      ]) {
        await tester.pumpWidget(wrap(button));
        expect(find.text(label), findsOneWidget);
        await tester.tap(find.text(label));
      }

      expect(taps, 4);
    });

    testWidgets('onPressed ריק משבית את הכפתור', (tester) async {
      await tester.pumpWidget(
        wrap(
            ActionButton.recommended(text: he.common.install, onPressed: null)),
      );

      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
    });

    testWidgets('isLoading מחליף את הטקסט במד ומשבית את הכפתור',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(wrap(ActionButton.recommended(
        text: he.common.install,
        isLoading: true,
        onPressed: () => taps++,
      )));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(he.common.install), findsNothing);
      await tester.tap(find.byType(FilledButton));
      expect(taps, 0);
    });

    testWidgets('כפתור עם אייקון מצייר אותו דרך RtlIcon', (tester) async {
      await tester.pumpWidget(wrap(ActionButton.neutral(
        text: he.common.retry,
        icon: FluentIcons.arrow_right_24_regular,
        onPressed: () {},
      )));

      expect(find.byType(RtlIcon), findsOneWidget);
      expect(
        renderedIcon(tester, find.byType(RtlIcon)),
        FluentIcons.arrow_left_24_regular,
      );
    });

    testWidgets('spinning מסובב את האייקון ומשאיר את הטקסט', (tester) async {
      await tester.pumpWidget(wrap(ActionButton.neutral(
        text: he.common.recheck,
        icon: FluentIcons.arrow_sync_24_regular,
        spinning: true,
        onPressed: () {},
      )));

      expect(find.text(he.common.recheck), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byType(RtlIcon),
          matching: find.byType(RotationTransition),
        ),
        findsOneWidget,
      );
    });

    testWidgets('SecondaryIconButton מציג tooltip ומדווח על לחיצה',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(wrap(SecondaryIconButton(
        icon: FluentIcons.folder_24_regular,
        tooltip: he.settings.openLogFolderButton,
        onPressed: () => taps++,
      )));

      expect(find.byTooltip(he.settings.openLogFolderButton), findsOneWidget);
      await tester.tap(find.byType(IconButton));
      expect(taps, 1);
    });
  });

  // ── RecheckButton ──────────────────────────────────────────────────────────

  group('RecheckButton', () {
    /// האם הכפתור שבפנים מבקש סיבוב כרגע.
    bool spinningOf(WidgetTester tester) => tester
        .widget<ActionButton>(
          find.widgetWithText(ActionButton, he.common.recheck),
        )
        .spinning;

    testWidgets('הסמל מסתובב לפחות שנייה גם כשהבדיקה מיידית', (tester) async {
      var checks = 0;
      await tester.pumpWidget(
        wrap(RecheckButton(onPressed: () async => checks++)),
      );

      expect(spinningOf(tester), isFalse);
      await tester.tap(find.text(he.common.recheck));
      await tester.pump();

      expect(checks, 1);
      expect(spinningOf(tester), isTrue);

      // הבדיקה כבר הסתיימה, והסמל עדיין מסתובב — זו כל הפואנטה.
      await tester.pump(const Duration(milliseconds: 500));
      expect(spinningOf(tester), isTrue);

      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(spinningOf(tester), isFalse);
    });

    testWidgets('לחיצה נוספת בזמן סיבוב אינה מריצה בדיקה שנייה',
        (tester) async {
      var checks = 0;
      await tester.pumpWidget(
        wrap(RecheckButton(onPressed: () async => checks++)),
      );

      await tester.tap(find.text(he.common.recheck));
      await tester.pump();
      await tester.tap(find.text(he.common.recheck));
      await tester.pump();

      expect(checks, 1);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('onPressed ריק משבית את הכפתור', (tester) async {
      await tester.pumpWidget(wrap(const RecheckButton(onPressed: null)));

      expect(
        tester
            .widget<ActionButton>(
              find.widgetWithText(ActionButton, he.common.recheck),
            )
            .onPressed,
        isNull,
      );
    });
  });

  // ── AppCard ────────────────────────────────────────────────────────────────

  group('AppCard', () {
    testWidgets('כרטיס יחיד מדווח על הקשה', (tester) async {
      var taps = 0;
      await tester.pumpWidget(wrap(AppCard(
        onTap: () => taps++,
        padding: const EdgeInsets.all(AppTokens.spaceMD),
        child: Text(he.home.appTileTitle),
      )));

      await tester.tap(find.text(he.home.appTileTitle));
      expect(taps, 1);
    });

    testWidgets('מקטע מפריד בין שורות ברווח הקבוע', (tester) async {
      await tester.pumpWidget(wrap(const AppCard.section(children: [
        SizedBox(key: Key('a'), height: 20, width: 100),
        SizedBox(key: Key('b'), height: 20, width: 100),
      ])));

      final gap = tester.getTopLeft(find.byKey(const Key('b'))).dy -
          tester.getBottomLeft(find.byKey(const Key('a'))).dy;
      expect(gap, AppCard.sectionSpacing);
    });

    testWidgets('כרטיס נבחר מקבל את שכבת הבחירה משכבת העיצוב', (tester) async {
      late Color expected;
      await tester.pumpWidget(wrap(Builder(builder: (context) {
        expected = AppSurfaces.cardSelectionOverlay(context);
        return const AppCard(selected: true, child: SizedBox(height: 20));
      })));

      final colors = tester
          .widgetList<ColoredBox>(find.descendant(
            of: find.byType(AppCard),
            matching: find.byType(ColoredBox),
          ))
          .map((box) => box.color);
      expect(colors, contains(expected));
    });
  });

  // ── SettingsCard / SettingsActionTile ──────────────────────────────────────

  group('SettingsCard', () {
    testWidgets('כותרת, תת-כותרת ושורות מוצגות', (tester) async {
      await tester.pumpWidget(wrap(SettingsCard(
        title: he.settings.automationCardTitle,
        subtitle: he.settings.automationCardSubtitle,
        children: [
          SettingsActionTile.text(
            icon: FluentIcons.timer_24_regular,
            title: he.settings.autoCheckTitle,
            subtitle: he.settings.autoCheckSubtitle,
          ),
        ],
      )));

      expect(find.text(he.settings.automationCardTitle), findsOneWidget);
      expect(find.text(he.settings.automationCardSubtitle), findsOneWidget);
      expect(find.text(he.settings.autoCheckTitle), findsOneWidget);
    });

    testWidgets('שורת נתיב נכתבת LTR עם סימני כיוון אחרי המפרידים',
        (tester) async {
      await tester.pumpWidget(wrap(SettingsCard(children: [
        SettingsActionTile.path(
          title: he.libraryScreen.dbFileTitle,
          path: r'C:\אוצריא\seforim.db',
          placeholder: he.libraryScreen.dbFileMissing,
        ),
      ])));

      // \u05de\u05e1\u05de\u05e0\u05d9\u05dd \u05dc\u05e4\u05d9 \u05e1\u05d9\u05de\u05df \u05d4\u05db\u05d9\u05d5\u05d5\u05df U+200E \u2014 \u05db\u05d5\u05ea\u05e8\u05ea \u05d4\u05e9\u05d5\u05e8\u05d4 \u05e2\u05e6\u05de\u05d4 \u05de\u05d6\u05db\u05d9\u05e8\u05d4 \u05d0\u05ea \u05e9\u05dd \u05d4\u05e7\u05d5\u05d1\u05e5.
      final subtitle = tester.widget<Text>(find.byWidgetPredicate(
        (w) => w is Text && (w.data?.contains('\u200e') ?? false),
      ));
      expect(subtitle.textDirection, TextDirection.ltr);
      expect(subtitle.data, contains('seforim.db'));
    });

    testWidgets('שורת נתיב ריקה מציגה את מלל ההיעדר, בכיוון השפה',
        (tester) async {
      await tester.pumpWidget(wrap(SettingsCard(children: [
        SettingsActionTile.path(
          title: he.libraryScreen.dbFileTitle,
          path: null,
          placeholder: he.libraryScreen.dbFileMissing,
        ),
      ])));

      final subtitle =
          tester.widget<Text>(find.text(he.libraryScreen.dbFileMissing));
      expect(subtitle.textDirection, isNull);
    });

    testWidgets('switchTile מתחלף גם ב-Enter, ומושבת אינו מגיב',
        (tester) async {
      var value = false;
      await tester.pumpWidget(wrap(StatefulBuilder(
        builder: (context, setState) => SettingsCard(children: [
          SettingsActionTile.switchTile(
            title: he.settings.syncLibraryTitle,
            value: value,
            onChanged: (v) => setState(() => value = v),
          ),
        ]),
      )));

      await tester.tap(find.text(he.settings.syncLibraryTitle));
      await tester.pumpAndSettle();
      expect(value, isTrue);

      // אחרי ההחלפה המיקוד עובר לשורה, ולכן Enter מגיע אליה.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(value, isFalse);

      var disabled = false;
      await tester.pumpWidget(wrap(SettingsCard(children: [
        SettingsActionTile.switchTile(
          title: he.settings.syncAppTitle,
          value: false,
          enabled: false,
          onChanged: (v) => disabled = v,
        ),
      ])));
      await tester.tap(find.text(he.settings.syncAppTitle));
      await tester.pumpAndSettle();
      expect(disabled, isFalse);
    });

    testWidgets('שורה צרה עוברת לפריסה אנכית במקום לדחוס את הכותרת',
        (tester) async {
      Widget tile() => SettingsCard(children: [
            SettingsActionTile.text(
              icon: FluentIcons.arrow_download_24_regular,
              title: he.settings.autoInstallLibraryTitle,
              actions: [
                ActionButton.neutral(
                  text: he.common.install,
                  onPressed: () {},
                ),
              ],
            ),
          ]);

      await tester.pumpWidget(wrap(SizedBox(width: 700, child: tile())));
      expect(find.byType(ListTile), findsOneWidget);

      await tester.pumpWidget(wrap(SizedBox(width: 280, child: tile())));
      // בפריסה האנכית אין יותר ListTile — הכותרת מעל והפעולות מתחתיה.
      expect(find.byType(ListTile), findsNothing);
      expect(find.text(he.settings.autoInstallLibraryTitle), findsOneWidget);
      expect(find.text(he.common.install), findsOneWidget);
    });

    testWidgets('segmentedTile מדווח על בחירה ומציג תת-כותרת של הנבחר',
        (tester) async {
      String? picked;
      await tester.pumpWidget(wrap(SettingsCard(children: [
        SettingsActionTile.segmentedTile<String>(
          title: he.settings.themeTitle,
          currentValue: 'light',
          onChanged: (v) => picked = v,
          options: [
            SegmentOption(value: 'light', label: he.settings.themeLight),
            SegmentOption(value: 'dark', label: he.settings.themeDark),
          ],
        ),
      ])));

      await tester.tap(find.text(he.settings.themeDark));
      await tester.pumpAndSettle();
      expect(picked, 'dark');
    });
  });

  // ── AppSegmentedControl ────────────────────────────────────────────────────

  group('AppSegmentedControl', () {
    testWidgets('מציג את כל האפשרויות ומדווח על הבחירה', (tester) async {
      int? picked;
      await tester.pumpWidget(wrap(AppSegmentedControl<int>(
        currentValue: 0,
        onChanged: (v) => picked = v,
        options: [
          SegmentOption(value: 0, label: he.settings.themeSystem),
          SegmentOption(value: 1, label: he.settings.themeLight),
          SegmentOption(value: 2, label: he.settings.themeDark),
        ],
      )));

      expect(find.text(he.settings.themeSystem), findsOneWidget);
      await tester.tap(find.text(he.settings.themeDark));
      await tester.pumpAndSettle();
      expect(picked, 2);
    });

    testWidgets('אייקון כיווני בסגמנט עובר דרך RtlIcon', (tester) async {
      await tester.pumpWidget(wrap(AppSegmentedControl<int>(
        currentValue: 0,
        onChanged: (_) {},
        options: [
          SegmentOption(
            value: 0,
            label: he.common.update,
            rtlIcon: FluentIcons.arrow_right_24_regular,
          ),
          SegmentOption(value: 1, label: he.common.install),
        ],
      )));

      expect(
        renderedIcon(tester, find.byType(RtlIcon).first),
        FluentIcons.arrow_left_24_regular,
      );
    });
  });

  // ── StatusChip / CustomSwitch / NavRailItem ────────────────────────────────

  group('חיוויים ופקדים', () {
    testWidgets('StatusChip מציג סמל וטקסט בכל סוג', (tester) async {
      for (final kind in StatusKind.values) {
        await tester.pumpWidget(
          wrap(StatusChip(kind: kind, label: he.common.upToDate)),
        );
        expect(find.text(he.common.upToDate), findsOneWidget);
        // "בעבודה" מצייר מד סיבובי במקום סמל סטטי — עדיין לא צבע בלבד.
        if (kind == StatusKind.working) {
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
        } else {
          expect(find.byType(Icon), findsOneWidget);
        }
      }
    });

    testWidgets('CustomSwitch מתחלף, ובלי onChanged הוא מושבת', (tester) async {
      var value = false;
      await tester.pumpWidget(wrap(StatefulBuilder(
        builder: (context, setState) => CustomSwitch(
          value: value,
          onChanged: (v) => setState(() => value = v),
        ),
      )));

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(value, isTrue);

      await tester.pumpWidget(
        wrap(const CustomSwitch(value: true, onChanged: null)),
      );
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    });

    testWidgets('NavRailItem מחליף לאייקון המלא כשהוא נבחר ומדווח על הקשה',
        (tester) async {
      var taps = 0;
      Widget item(bool selected) => NavRailItem(
            icon: FluentIcons.home_24_regular,
            iconFilled: FluentIcons.home_24_filled,
            label: he.shell.navHome,
            isSelected: selected,
            tooltip: he.shell.navHome,
            onTap: () => taps++,
          );

      await tester.pumpWidget(wrap(item(false)));
      expect(find.text(he.shell.navHome), findsOneWidget);
      expect(
        renderedIcon(tester, find.byType(RtlIcon)),
        FluentIcons.home_24_regular,
      );

      await tester.tap(find.byType(IconButton));
      expect(taps, 1);

      await tester.pumpWidget(wrap(item(true)));
      await tester.pumpAndSettle();
      expect(
        renderedIcon(tester, find.byType(RtlIcon)),
        FluentIcons.home_24_filled,
      );
    });

    testWidgets('NavRailItem הצר משתמש ברוחב שהוגדר כקבוע', (tester) async {
      await tester.pumpWidget(wrap(Align(
        alignment: Alignment.topRight,
        child: NavRailItem(
          icon: FluentIcons.home_24_regular,
          label: he.shell.navHome,
          isSelected: false,
          compact: true,
          onTap: () {},
        ),
      )));

      expect(
        tester.getSize(find.byType(NavRailItem)).width,
        NavRailItem.compactWidth,
      );
    });
  });

  // ── שורות המידע ────────────────────────────────────────────────────────────

  group('שורות מידע', () {
    testWidgets('InfoStatusRow מציג כותרת ושבב מצב', (tester) async {
      await tester.pumpWidget(wrap(SettingsCard(children: [
        InfoStatusRow(
          icon: FluentIcons.database_24_regular,
          title: he.libraryScreen.stateRowTitle,
          kind: StatusKind.ok,
          label: he.common.upToDate,
        ),
      ])));

      expect(find.text(he.libraryScreen.stateRowTitle), findsOneWidget);
      expect(find.byType(StatusChip), findsOneWidget);
      expect(find.text(he.common.upToDate), findsOneWidget);
    });

    testWidgets('InfoErrorRow מציג "נסה שוב" רק כשיש מה לנסות', (tester) async {
      var retries = 0;
      await tester.pumpWidget(wrap(SettingsCard(children: [
        InfoErrorRow(
          message: he.libraryDomain.mirrorMissing,
          onRetry: () async => retries++,
        ),
      ])));

      expect(find.text(he.common.error), findsOneWidget);
      expect(find.text(he.libraryDomain.mirrorMissing), findsOneWidget);
      await tester.tap(find.text(he.common.retry));
      expect(retries, 1);

      await tester.pumpWidget(wrap(SettingsCard(children: [
        InfoErrorRow(message: he.libraryDomain.mirrorMissing),
      ])));
      expect(find.text(he.common.retry), findsNothing);
    });

    testWidgets('InfoProgressRow מציג אחוז כשהוא ידוע ומד לא-קבוע כשלא',
        (tester) async {
      await tester.pumpWidget(wrap(InfoProgressRow(
        stage: he.libraryDomain.applyVerifying,
        progress: 0.42,
        detail: he.units.progressOf('1', '2'),
      )));

      expect(find.text('42%'), findsOneWidget);
      expect(find.text(he.units.progressOf('1', '2')), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        0.42,
      );

      await tester.pumpWidget(
        wrap(InfoProgressRow(stage: he.libraryDomain.applyVerifying)),
      );
      expect(find.textContaining('%'), findsNothing);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        isNull,
      );
    });

    testWidgets('CardActionsRow פורס את הפעולות שקיבל', (tester) async {
      await tester.pumpWidget(wrap(CardActionsRow(actions: [
        ActionButton.recommended(text: he.common.install, onPressed: () {}),
        ActionButton.ghost(text: he.common.launch, onPressed: () {}),
      ])));

      expect(find.byType(ActionButton), findsNWidgets(2));
      expect(find.byType(Wrap), findsOneWidget);
    });
  });

  // ── ScreenBody ─────────────────────────────────────────────────────────────

  group('ScreenBody', () {
    testWidgets('מציג כותרת, הסבר וילדים, ומגביל את רוחב התוכן',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(ScreenBody(
        title: he.settings.title,
        description: he.settings.description,
        children: [Text(he.settings.appearanceCardTitle)],
      )));

      expect(find.text(he.settings.title), findsOneWidget);
      expect(find.text(he.settings.description), findsOneWidget);
      expect(find.text(he.settings.appearanceCardTitle), findsOneWidget);
      expect(
        tester.getSize(find.byType(ListView)).width,
        LayoutConstraints.panelContentMaxWidth,
      );
    });
  });

  // ── UiSnack ────────────────────────────────────────────────────────────────

  group('UiSnack', () {
    // ההודעה יושבת ב-Overlay מעל ה-Navigator ולכן אינה יורשת כיווניות —
    // זה החריג היחיד שקורא את השפה ישירות מ-AppL10n.
    for (final (language, direction) in [
      (AppLanguage.hebrew, TextDirection.rtl),
      (AppLanguage.english, TextDirection.ltr),
    ]) {
      testWidgets('הודעה נפתחת בכיוון של ${language.code}', (tester) async {
        final message = AppL10n.stringsFor(language).plugins.saveDoneSnack;
        AppL10n.use(language);
        await tester.pumpWidget(
          wrap(const SizedBox.shrink(), language: language),
        );

        UiSnack.showSuccess(message);
        await tester.pump();

        expect(find.text(message), findsOneWidget);
        expect(
          Directionality.of(tester.element(find.text(message))),
          direction,
        );

        // מרוקן את טיימר הסגירה — טיימר תלוי מפיל את הבדיקה בסופה.
        await tester.pump(const Duration(seconds: 7));
        expect(find.text(message), findsNothing);
      });
    }

    testWidgets('שגיאה והודעה רגילה נבדלות בסמל', (tester) async {
      await tester.pumpWidget(wrap(const SizedBox.shrink()));

      UiSnack.showError(he.plugins.saveFailedSnack);
      await tester.pump();
      expect(find.text(he.plugins.saveFailedSnack), findsOneWidget);
      expect(
        tester.widget<Icon>(find.byType(Icon)).icon,
        FluentIcons.error_circle_24_regular,
      );

      // הודעה חדשה מחליפה את הקודמת — אין תור.
      UiSnack.show(he.plugins.loadingCatalog);
      await tester.pump();
      expect(find.text(he.plugins.saveFailedSnack), findsNothing);
      expect(
        tester.widget<Icon>(find.byType(Icon)).icon,
        FluentIcons.info_24_regular,
      );

      await tester.pump(const Duration(seconds: 7));
    });
  });

  // ── דיאלוגים ───────────────────────────────────────────────────────────────

  group('דיאלוגים', () {
    /// בונה מסך עם כפתור יחיד שפותח דיאלוג ושומר את התוצאה.
    Future<void> pumpOpener(
      WidgetTester tester,
      Future<void> Function(BuildContext context) open, {
      AppLanguage language = AppLanguage.hebrew,
    }) async {
      await tester.pumpWidget(wrap(
        Builder(
          builder: (context) => ActionButton.recommended(
            key: const Key('open'),
            text: AppL10n.stringsFor(language).common.close,
            onPressed: () => open(context),
          ),
        ),
        language: language,
      ));
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
    }

    testWidgets('showSingleActionDialog נסגר בכפתור האישור', (tester) async {
      await pumpOpener(
        tester,
        (context) => showSingleActionDialog(
          context: context,
          title: he.plugins.saveDialogTitle,
          content: he.plugins.syncDialogContent,
        ),
      );

      expect(find.text(he.plugins.saveDialogTitle), findsOneWidget);
      expect(find.text(he.plugins.syncDialogContent), findsOneWidget);
      // כפתור אחד בלבד — אין ביטול.
      expect(find.text(he.common.cancel), findsNothing);

      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(he.common.confirm),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('showTwoActionsDialog מחזיר true באישור ו-false בביטול',
        (tester) async {
      bool? result;
      Future<void> open(BuildContext context) async =>
          result = await showTwoActionsDialog(
            context: context,
            title: he.settings.resetDialogTitle,
            content: he.settings.resetDialogContent,
          );

      await pumpOpener(tester, open);
      await tester.tap(find.text(he.common.cancel));
      await tester.pumpAndSettle();
      expect(result, isFalse);

      await pumpOpener(tester, open);
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(he.common.confirm),
      ));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('showTwoActionsDialog מחזיר false גם כשנסגר בלחיצה בחוץ',
        (tester) async {
      bool? result;
      await pumpOpener(
        tester,
        (context) async => result = await showTwoActionsDialog(
          context: context,
          title: he.settings.resetDialogTitle,
        ),
      );

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(result, isFalse);
    });

    testWidgets('showWarningDialog מציג אזהרה, והביטול הוא הכפתור המומלץ',
        (tester) async {
      bool? result;
      await pumpOpener(
        tester,
        (context) async => result = await showWarningDialog(
          context: context,
          title: he.settings.resetDialogTitle,
          content: he.settings.resetDialogContent,
          subtitle: he.settings.resetDialogWarning,
          confirmText: he.settings.resetDialogConfirm,
        ),
      );

      expect(find.text(he.settings.resetDialogWarning), findsOneWidget);
      // האישור ההרסני הוא ווריאנט האזהרה, והביטול הוא ה-FilledButton.
      expect(
        find.widgetWithText(FilledButton, he.common.cancel),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextButton, he.settings.resetDialogConfirm),
        findsOneWidget,
      );

      await tester.tap(find.text(he.settings.resetDialogConfirm));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('תוויות ברירת המחדל של הדיאלוג עוברות לאנגלית', (tester) async {
      AppL10n.use(AppLanguage.english);
      await pumpOpener(
        tester,
        (context) => showSingleActionDialog(
          context: context,
          title: en.plugins.saveDialogTitle,
        ),
        language: AppLanguage.english,
      );

      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(en.common.confirm),
        ),
        findsOneWidget,
      );
      expect(find.text(he.common.confirm), findsNothing);
    });
  });

  // ── הגדלת טקסט ─────────────────────────────────────────────────────────────

  // גלישת RenderFlex נזרקת כחריג בבדיקות, ולכן takeException הוא הבדיקה.
  group('הגדלת טקסט אינה מגלישה את הרכיבים', () {
    /// הרכיבים יושבים באפליקציה בתוך ה-ListView של [ScreenBody], ולכן גם כאן
    /// באזור גליל — גובה שגדל אינו גלישה, רוחב שגדל כן.
    Future<void> expectNoOverflow(
      WidgetTester tester,
      Widget Function() build, {
      double width = 380,
      List<double> scales = textScales,
      AppLanguage language = AppLanguage.hebrew,
    }) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      for (final scale in scales) {
        await tester.pumpWidget(
          wrap(
            SingleChildScrollView(
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(width: width, child: build()),
              ),
            ),
            language: language,
            textScale: scale,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '${language.code} ×$scale',
        );
      }
    }

    testWidgets('כרטיס הגדרות עם מלל עברי ארוך', (tester) async {
      await expectNoOverflow(
        tester,
        () => SettingsCard(
          title: he.settings.automationCardTitle,
          subtitle: he.settings.automationCardSubtitle,
          children: [
            SettingsActionTile.switchTile(
              icon: FluentIcons.arrow_download_24_regular,
              title: he.settings.autoInstallLibraryTitle,
              subtitle: he.settings.autoInstallLibrarySubtitle,
              value: true,
              onChanged: (_) {},
            ),
            SettingsActionTile.text(
              icon: FluentIcons.database_24_regular,
              title: he.settings.syncLibraryTitle,
              subtitle: he.settings.syncLibrarySubtitle,
              actions: [
                ActionButton.neutral(
                  text: he.common.install,
                  onPressed: () {},
                ),
              ],
            ),
            SettingsActionTile.path(
              icon: FluentIcons.folder_24_regular,
              title: he.libraryScreen.dbFileTitle,
              path: r'C:\Users\דוגמה\AppData\Roaming\otzaria\books\seforim.db',
              placeholder: he.libraryScreen.dbFileMissing,
            ),
          ],
        ),
      );
    });

    testWidgets('שורת סגמנטד עם שלוש תוויות', (tester) async {
      await expectNoOverflow(
        tester,
        () => SettingsCard(children: [
          SettingsActionTile.segmentedTile<int>(
            icon: FluentIcons.text_font_size_24_regular,
            title: he.settings.textSizeTitle,
            currentValue: 1,
            onChanged: (_) {},
            options: [
              SegmentOption(value: 0, label: he.settings.textSizeSmall),
              SegmentOption(value: 1, label: he.settings.textSizeNormal),
              SegmentOption(value: 2, label: he.settings.textSizeLarge),
            ],
          ),
        ]),
      );
    });

    testWidgets('שורות מידע, מד התקדמות וכפתורים', (tester) async {
      await expectNoOverflow(
        tester,
        () => AppCard.section(children: [
          InfoErrorRow(
            message: he.libraryDomain.mirrorMissing,
            onRetry: () async {},
          ),
          InfoProgressRow(
            stage: he.libraryDomain.applyDecompressingFullDb,
            progress: 0.5,
            detail: he.units.progressOf('512MB', '1GB'),
          ),
          CardActionsRow(actions: [
            ActionButton.recommended(
              text: he.appScreen.installUpdateButton,
              onPressed: () {},
            ),
            ActionButton.ghost(text: he.common.launch, onPressed: () {}),
          ]),
        ]),
      );
    });

    /// שורת המצב עם [StatusChip] — הרוחב 380 הוא כרטיס בחלון צר סביר.
    Widget statusRow(AppStrings s) => SettingsCard(children: [
          InfoStatusRow(
            icon: FluentIcons.database_24_regular,
            title: s.libraryScreen.stateRowTitle,
            kind: StatusKind.updateAvailable,
            label: s.common.updateAvailable,
          ),
        ]);

    testWidgets('שורת מצב בהגדלות שהאפליקציה עצמה מציעה', (tester) async {
      // ההגדרות מגבילות ל-0.9/1.0/1.15 בלבד (`MediaQuery.withClampedTextScaling`
      // ב-main.dart), ולכן זה הטווח שהמשתמש יכול להגיע אליו בפועל.
      for (final language in AppLanguage.values) {
        await expectNoOverflow(
          tester,
          () => statusRow(AppL10n.stringsFor(language)),
          scales: const [0.9, 1.0, 1.15],
          language: language,
        );
      }
    });

    testWidgets(
      'שורת מצב בהגדלה גדולה',
      (tester) async {
        for (final language in AppLanguage.values) {
          await expectNoOverflow(
            tester,
            () => statusRow(AppL10n.stringsFor(language)),
            scales: const [1.3, 2.0],
            language: language,
          );
        }
      },
      // ההגדלות האלה אינן נגישות: `main.dart` מהדק את הסקאלה בדיוק לערך
      // שנבחר בהגדרות, והמקסימום שם הוא 1.15 — מכוסה בבדיקה שמעל. השורה
      // עדיין גולשת מעליו, ולכן הבדיקה נשמרת כתיעוד של הגבול.
      skip: true,
    );

    testWidgets('סרגל הניווט ברוחב הפריט הקבוע', (tester) async {
      await expectNoOverflow(
        tester,
        () => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final label in [
              he.shell.navHome,
              he.shell.navApp,
              he.shell.navLibrary,
              he.shell.navPlugins,
              he.shell.navSettings,
            ])
              NavRailItem(
                icon: FluentIcons.home_24_regular,
                label: label,
                isSelected: label == he.shell.navHome,
                onTap: () {},
              ),
          ],
        ),
        width: NavRailItem.width,
      );
    });

    testWidgets('גוף מסך שלם באנגלית ובעברית', (tester) async {
      for (final language in AppLanguage.values) {
        final s = AppL10n.stringsFor(language);
        for (final scale in textScales) {
          await tester.pumpWidget(wrap(
            ScreenBody(
              title: s.setupError.title,
              description: s.setupError.explanation,
              children: [
                SettingsCard(
                  title: s.settings.appearanceCardTitle,
                  subtitle: s.settings.appearanceCardSubtitle,
                  children: [
                    SettingsActionTile.text(
                      icon: FluentIcons.info_24_regular,
                      title: s.setupError.whatToDo,
                      subtitle: s.settings.languageSubtitle,
                      actions: [
                        ActionButton.neutral(
                          text: s.setupError.copyPathButton,
                          onPressed: () {},
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            language: language,
            textScale: scale,
          ));
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '${language.code} ×$scale',
          );
        }
      }
    });
  });
}

// ── עזרי בדיקה ────────────────────────────────────────────────────────────────

/// תת-עץ `const` שקורא מלל. הוא לא נבנה מחדש כשההורה נבנה (Flutter מדלג על
/// widget זהה), ולכן רק ה-InheritedWidget יכול לרענן אותו.
class _ConstLabel extends StatelessWidget {
  const _ConstLabel();

  static int builds = 0;

  @override
  Widget build(BuildContext context) {
    builds++;
    return Text(context.strings.common.confirm);
  }
}

class _LanguageSwitcher extends StatefulWidget {
  const _LanguageSwitcher({this.toggleTo = AppLanguage.english});

  final AppLanguage toggleTo;

  @override
  State<_LanguageSwitcher> createState() => _LanguageSwitcherState();
}

class _LanguageSwitcherState extends State<_LanguageSwitcher> {
  AppLanguage _language = AppLanguage.hebrew;

  @override
  Widget build(BuildContext context) => AppStringsScope(
        strings: AppL10n.stringsFor(_language),
        child: Scaffold(
          body: Column(
            children: [
              GestureDetector(
                key: const Key('toggle'),
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _language = widget.toggleTo),
                child: const SizedBox(width: 100, height: 40),
              ),
              const _ConstLabel(),
            ],
          ),
        ),
      );
}

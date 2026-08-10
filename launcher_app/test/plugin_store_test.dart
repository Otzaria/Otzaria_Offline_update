// בדיקות חנות התוספים — הרכיב הכבד היחיד בלאנצ'ר, ולכן זה שיש בו הכי
// הרבה מלכודות ביצועים: פענוח תמונות, וירטואליזציה של הרשת, וגליל מקונן.
//
// כל טעינה מהדיסק נעשית ב-[WidgetTester.runAsync] **לפני** ה-pump: קריאות
// `dart:io` אינן מסתיימות בתוך ה-fake-async של `testWidgets`, ו-
// `pumpAndSettle` היה נתקע על כל ספינר שממתין להן.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/plugins_module_controller.dart';
import 'package:launcher_app/src/screens/plugins/plugin_detail_view.dart';
import 'package:launcher_app/src/screens/plugins/plugin_filters_bar.dart';
import 'package:launcher_app/src/screens/plugins/plugin_store_body.dart';
import 'package:launcher_app/src/screens/plugins/plugin_store_card.dart';
import 'package:launcher_app/src/screens/plugins/plugin_store_nav.dart';
import 'package:launcher_app/src/screens/plugins/plugin_sync_overlay.dart';
import 'package:launcher_app/src/screens/plugins/plugin_updates_dialog.dart';
import 'package:launcher_app/src/screens/plugins/plugin_visuals.dart';
import 'package:launcher_app/src/screens/plugins/plugins_screen.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:plugins_manager/plugins_manager.dart';

import 'test_harness.dart';
import 'test_support.dart';

/// רשומת תוסף **מומצאת** לבדיקה. אין כאן שום נתון מחנות אמיתית: כל השמות,
/// התקצירים והתגיות נכתבו כאן. במסך הם ממלאים את מקום התוכן שמגיע
/// מ-`otzaria.org` — שאינו מתורגם לעולם, ולכן זהה בשתי השפות.
StorePlugin storePlugin(
  String id, {
  String? name,
  String status = 'stable',
  String version = '1.0.0',
  bool featured = false,
  bool direct = true,
  List<String> tags = const ['תגית-בדיקה-ג'],
  String? manifestId,
  String? imagePath,
  List<String> screenshots = const [],
  List<String> categories = const [],
  bool withLocalFile = false,
}) {
  final plugin = StorePlugin.fromApi({
    'id': id,
    'name': name ?? 'תוסף $id',
    'shortDescription': 'תקציר של $id',
    'description': 'תיאור מלא של $id',
    'version': version,
    'status': status,
    'author': 'מחבר',
    'originalDate': '2026-04-02',
    'tags': tags,
    'isPinned': featured,
    'supportsDirectInstall': direct,
    'downloadUrl': '/api/plugins/$id/download',
  }, 'https://otzaria.org');

  return plugin.copyWith(
    manifestId: manifestId,
    imagePath: imagePath,
    screenshotPaths: screenshots,
    categorySlugs: categories,
    localFile: withLocalFile
        ? PluginLocalFile(
            relativePath: 'files/$id/$id.otzplugin',
            fileName: '$id.otzplugin',
            ext: 'otzplugin',
            size: 2048,
          )
        : null,
  );
}

/// האם ה-Scrollable הזה הוא הגליל הפנימי של שדה טקסט (`EditableText`).
bool _isInsideTextField(Element element) {
  var found = false;
  element.visitAncestorElements((ancestor) {
    if (ancestor.widget is EditableText) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

void main() {
  late Directory tempDir;
  late PluginsModuleController plugins;
  final t = stringsOf().plugins;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('plugin_store_test');
    // הקונטרולרים כותבים ליומן במסלולי השגיאה; בלי init הם היו זורקים.
    await AppLogger.init(tempDir.path);
    plugins = PluginsModuleController(mirrorRootDir: tempDir.path);
  });

  tearDown(() async {
    plugins.dispose();
    AppLogger.resetForTest();
    await deleteTempDir(tempDir);
  });

  /// שומר קטלוג **מומצא** למראה שבתיקייה הזמנית וטוען אותו. שני השלבים
  /// חייבים לרוץ ב-runAsync.
  ///
  /// `installed` מאופס מיד אחרי הטעינה: `load` סורק גם את ההתקנה האמיתית
  /// של אוצריא במחשב, ואף בדיקה כאן לא אמורה להיות תלויה בה. בדיקה שצריכה
  /// מצב התקנה מציבה מפה משלה אחרי הקריאה.
  Future<void> seed(
    WidgetTester tester, {
    required List<StorePlugin> catalog,
    List<PluginStoreCategory> categories = const [],
    PluginStoreHome home = PluginStoreHome.empty,
  }) async {
    final store = PluginMirrorStore(tempDir.path);
    await tester.runAsync(() => store.save(PluginCatalog(
          lastSync: DateTime.utc(2026, 8, 6),
          plugins: catalog,
          categories: categories,
          home: home,
        )));
    await tester.runAsync(plugins.load);
    plugins.installed = const {};
  }

  // ── פענוח התמונות ────────────────────────────────────────────────────────

  testWidgets('decodeWidthFor מעגל כלפי מעלה לקפיצות של 64 לפי צפיפות המסך',
      (tester) async {
    late BuildContext ctx;
    Future<void> pumpWithRatio(double ratio) => tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(devicePixelRatio: ratio),
            child: Builder(builder: (context) {
              ctx = context;
              return const SizedBox();
            }),
          ),
        );

    await pumpWithRatio(1.0);
    expect(decodeWidthFor(ctx, 300), 320);
    expect(decodeWidthFor(ctx, 256), 256);

    // מסך צפוף דורש יותר פיקסלים לאותו רוחב לוגי.
    await pumpWithRatio(2.0);
    expect(decodeWidthFor(ctx, 300), 640);

    // רוחב לא ידוע — אין מה לבקש, ו-null משאיר את הפענוח כברירת המחדל.
    expect(decodeWidthFor(ctx, 0), isNull);
    expect(decodeWidthFor(ctx, -5), isNull);
    expect(decodeWidthFor(ctx, double.infinity), isNull);
  });

  testWidgets('כל תמונה שהרשת בונה מבקשת cacheWidth', (tester) async {
    await seed(tester, catalog: [
      for (var i = 0; i < 4; i++)
        storePlugin('p$i', imagePath: 'files/p$i/cover.png'),
    ]);

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images, isNotEmpty);
    for (final image in images) {
      // `Image.file` בלי cacheWidth מחזיר FileImage חשוף; עם cacheWidth הוא
      // עטוף ב-ResizeImage — וזה ההבדל בין ~3.8MB לתמונה לבין אריח.
      expect(image.image, isA<ResizeImage>());
      expect((image.image as ResizeImage).width, isNotNull);
    }
  });

  testWidgets('גם צילומי המסך בעמוד התוסף מפוענחים בגודל האריח',
      (tester) async {
    await seed(tester, catalog: [
      storePlugin(
        'a',
        imagePath: 'files/a/cover.png',
        screenshots: const ['files/a/s1.png', 'files/a/s2.png'],
      ),
    ]);

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.cardDetailsLink));
    await tester.pumpAndSettle();

    expect(find.text(t.screenshotsPanelTitle), findsOneWidget);
    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images.length, greaterThanOrEqualTo(3));
    for (final image in images) {
      expect(image.image, isA<ResizeImage>());
    }
  });

  // ── וירטואליזציה של הרשת ─────────────────────────────────────────────────

  testWidgets('כרטיסים שמחוץ למסך אינם נבנים, ונבנים בגלילה אליהם',
      (tester) async {
    await seed(tester, catalog: [
      for (var i = 0; i < 30; i++)
        storePlugin('p$i', name: 'תוסף מספר $i', imagePath: 'files/p$i/c.png'),
    ]);

    await pumpScreen(
      tester,
      PluginsScreen(controller: plugins),
      size: const Size(1000, 800),
    );
    await tester.pumpAndSettle();

    // `SliverGrid` בונה רק את מה שקרוב לחלון. עם `GridView(shrinkWrap: true)`
    // כל שלושים היו נבנים — ואיתם שלושים פענוחי תמונה.
    final built = find.byType(PluginStoreCard, skipOffstage: false);
    expect(tester.widgetList(built).length, lessThan(30));
    expect(find.text('תוסף מספר 29'), findsNothing);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -6000));
    await tester.pumpAndSettle();

    expect(find.text('תוסף מספר 29'), findsOneWidget);
    expect(find.text('תוסף מספר 0'), findsNothing);
  });

  // ── מבנה הגלילה ──────────────────────────────────────────────────────────

  testWidgets('אין גליל מקונן בתוך אזור התוכן, וסרגל הצד מחוצה לו',
      (tester) async {
    await seed(
      tester,
      catalog: [
        for (var i = 0; i < 12; i++)
          storePlugin('p$i', featured: true, categories: const ['study']),
      ],
      categories: const [
        PluginStoreCategory(
          slug: 'study',
          name: 'כלי לימוד',
          showOnHome: true,
          pluginIds: ['p0', 'p1', 'p2'],
        ),
      ],
    );

    await pumpScreen(
      tester,
      PluginsScreen(controller: plugins),
      size: const Size(1400, 1200),
    );
    await tester.pumpAndSettle();

    // אין אזור גלילה מקונן בתוך התוכן — גליל אופקי מקונן היה בולע את
    // גלגלת העכבר ומקפיא את גלילת העמוד, ורשימה מקוננת הייתה מבטלת את
    // הווירטואליזציה של הרשת.
    for (final type in const [ListView, GridView, SingleChildScrollView]) {
      expect(
        find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byWidgetPredicate((w) => w.runtimeType == type),
        ),
        findsNothing,
        reason: '$type מקונן בתוך אזור הגלילה של החנות',
      );
    }
    // ה-Scrollable היחיד שנשאר הוא של ה-CustomScrollView עצמו; הגליל
    // האופקי הפנימי של שדה החיפוש הוא חלק מ-`EditableText` ולא אזור תוכן.
    final content = [
      for (final element in find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .evaluate())
        if (!_isInsideTextField(element)) element,
    ];
    expect(content.length, 1);
    // סרגל הקטגוריות יושב מחוץ לאזור הגלילה, כמו ה-aside הדביק שבאתר.
    expect(find.byType(PluginStoreSidebar), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(PluginStoreSidebar),
      ),
      findsNothing,
    );
  });

  testWidgets('סרגל הצד נשאר במקומו בזמן שהתוכן נגלל', (tester) async {
    await seed(
      tester,
      catalog: [
        for (var i = 0; i < 24; i++) storePlugin('p$i', featured: true)
      ],
      categories: const [
        PluginStoreCategory(
            slug: 'study', name: 'כלי לימוד', pluginIds: ['p0']),
      ],
    );

    await pumpScreen(
      tester,
      PluginsScreen(controller: plugins),
      size: const Size(1400, 900),
    );
    await tester.pumpAndSettle();

    final before = tester.getTopLeft(find.text('כלי לימוד'));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -800));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('כלי לימוד')), before);
  });

  // ── ניווט הקטגוריות ──────────────────────────────────────────────────────

  testWidgets('מתחת לנקודת השבירה הקטגוריות הן שורת צ׳יפים ולא סרגל צד',
      (tester) async {
    await seed(
      tester,
      catalog: [storePlugin('a', featured: true)],
      categories: const [
        PluginStoreCategory(slug: 'study', name: 'כלי לימוד', pluginIds: ['a']),
      ],
    );

    await pumpScreen(
      tester,
      PluginsScreen(controller: plugins),
      size: const Size(900, 1200),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PluginStoreCategoryBar), findsOneWidget);
    expect(find.byType(PluginStoreSidebar), findsNothing);
    expect(find.text(t.storeHomeChip), findsOneWidget);
  });

  testWidgets('מראה בלי קטגוריות נפתחת ישר ב"כל התוספים" ובלי ניווט',
      (tester) async {
    await seed(tester, catalog: [storePlugin('a')]);

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    expect(find.byType(PluginStoreSidebar), findsNothing);
    expect(find.byType(PluginStoreCategoryBar), findsNothing);
    expect(find.text(t.listTitle), findsOneWidget);
  });

  testWidgets('בחירת קטגוריה מסרגל הצד פותחת את דף הקטגוריה', (tester) async {
    await seed(
      tester,
      catalog: [
        storePlugin('a', name: 'תוסף בקטגוריה', featured: true),
        storePlugin('b', name: 'תוסף מחוץ לקטגוריה', featured: true),
      ],
      categories: const [
        PluginStoreCategory(
          slug: 'study',
          name: 'כלי לימוד',
          description: 'תוספים שמסייעים בלימוד',
          pluginIds: ['a'],
        ),
      ],
    );

    await pumpScreen(
      tester,
      PluginsScreen(controller: plugins),
      size: const Size(1400, 1400),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(
      of: find.byType(PluginStoreSidebar),
      matching: find.text('כלי לימוד'),
    ));
    await tester.pumpAndSettle();

    expect(find.text(t.categoryOnePlugin), findsOneWidget);
    expect(find.text('תוסף בקטגוריה'), findsOneWidget);
    expect(find.text('תוסף מחוץ לקטגוריה'), findsNothing);
  });

  // ── מלל שהאתר לא מילא ────────────────────────────────────────────────────

  testWidgets('כשהאתר השאיר את כותרת החנות ריקה מוצגת ברירת המחדל שלנו',
      (tester) async {
    // זה החריג היחיד לכלל "תוכן מהאתר אינו מתורגם": כשאין תוכן, הכותרת
    // באה מ-otzaria_l10n ולכן כן מתחלפת עם השפה.
    await seed(tester, catalog: [storePlugin('a', featured: true)]);

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    expect(find.text(t.catalogTitleFallback), findsOneWidget);
    expect(find.text(t.catalogSubtitleFallback), findsOneWidget);

    final english = stringsOf(AppLanguage.english).plugins;
    await pumpScreen(
      tester,
      PluginsScreen(controller: plugins),
      language: AppLanguage.english,
    );
    await tester.pumpAndSettle();

    expect(find.text(english.catalogTitleFallback), findsOneWidget);
    expect(find.text(t.catalogTitleFallback), findsNothing);
  });

  testWidgets('הכרום מתורגם והתוכן מהאתר נשאר כמות שהוא', (tester) async {
    final english = stringsOf(AppLanguage.english).plugins;
    await seed(tester, catalog: [
      storePlugin('a', name: 'תוסף מהאתר', tags: const ['תגית מהאתר']),
    ]);

    await pumpScreen(
      tester,
      PluginsScreen(controller: plugins),
      language: AppLanguage.english,
    );
    await tester.pumpAndSettle();

    expect(find.text(english.syncButton), findsOneWidget);
    expect(find.text(english.listTitle), findsOneWidget);
    expect(find.text(t.syncButton), findsNothing);
    // שם התוסף והתגית מגיעים מ-otzaria.org ולכן אינם מתורגמים לעולם.
    expect(find.text('תוסף מהאתר'), findsOneWidget);
    expect(find.text('תגית מהאתר'), findsWidgets);
  });

  // ── מצב ההתקנה ───────────────────────────────────────────────────────────

  testWidgets('תוסף שקובצו טרם ירד מוצג בלי שבב התקנה ובלי שגיאה',
      (tester) async {
    // בלי manifestId אי אפשר להשוות מול ההתקנה של אוצריא — המצב הוא
    // PluginInstallStatus.unknown, וזה תקין ולא שגיאה.
    await seed(tester, catalog: [storePlugin('a', name: 'תוסף שטרם ירד')]);

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    expect(
      plugins.statusOf(plugins.plugins.single),
      PluginInstallStatus.unknown,
    );
    expect(find.text('תוסף שטרם ירד'), findsOneWidget);
    expect(find.text(t.installChipInstalled), findsNothing);
    expect(find.text(t.installChipUpdateAvailable), findsNothing);
    expect(find.byType(InfoErrorRow), findsNothing);

    // בלי קובץ מקומי אין מה לשמור, ולכן הכפתור מושבת — אבל ההתקנה הישירה
    // כן פעילה: היא מסוגלת להשלים את הקובץ.
    final save = tester.widget<ActionButton>(
      find.widgetWithText(ActionButton, t.saveButton),
    );
    expect(save.onPressed, isNull);

    await tester.tap(find.text(t.cardDetailsLink));
    await tester.pumpAndSettle();

    expect(find.text(t.infoLocalFileMissing), findsOneWidget);
    expect(find.text(t.installChipInstalled), findsNothing);
  });

  testWidgets('תוסף מותקן ומעודכן מקבל שבב "מותקן" כשהמתג כבוי',
      (tester) async {
    await seed(tester, catalog: [
      storePlugin('a', manifestId: 'id-a', version: '2.0.0'),
    ]);
    plugins.installed = {'id-a': '2.0.0'};
    plugins.setHideInstalled(false);

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    expect(find.text(t.installChipInstalled), findsWidgets);
  });

  // ── עמוד התוסף ───────────────────────────────────────────────────────────

  testWidgets('עמוד התוסף מציג מידע, תגיות וחזרה לחנות', (tester) async {
    await seed(tester, catalog: [
      storePlugin(
        'a',
        name: 'תוסף עם פרטים',
        tags: const ['תגית-בדיקה-ג', 'תגית-בדיקה-ד'],
        withLocalFile: true,
      ),
    ]);

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.cardDetailsLink));
    await tester.pumpAndSettle();

    expect(find.byType(PluginDetailView), findsOneWidget);
    expect(find.text(t.infoPanelTitle), findsOneWidget);
    expect(find.text(t.tagsPanelTitle), findsOneWidget);
    expect(find.text(t.infoVersion), findsOneWidget);
    expect(find.text(t.infoNetworkNotRequired), findsOneWidget);
    // יש קובץ במראה — ולכן שמירה אפשרית.
    final save = tester.widget<ActionButton>(
      find.widgetWithText(ActionButton, t.saveButton),
    );
    expect(save.onPressed, isNotNull);

    await tester.tap(find.text(t.backToStore));
    await tester.pumpAndSettle();
    expect(find.byType(PluginDetailView), findsNothing);
  });

  testWidgets('לחיצה על תגית בעמוד התוסף מסננת את "כל התוספים"',
      (tester) async {
    await seed(tester, catalog: [
      storePlugin('a', name: 'תוסף עם תגית', tags: const ['תגית-בדיקה-ד']),
      storePlugin('b', name: 'תוסף אחר', tags: const ['תגית-בדיקה-ג']),
    ]);

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.cardDetailsLink).first);
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(
      of: find.byType(PluginDetailView),
      matching: find.text('תגית-בדיקה-ד'),
    ));
    await tester.pumpAndSettle();

    expect(plugins.tagFilter, 'תגית-בדיקה-ד');
    expect(find.text('תוסף עם תגית'), findsOneWidget);
    expect(find.text('תוסף אחר'), findsNothing);
  });

  testWidgets('גלריית צילומי המסך נפתחת, מתקדמת ונסגרת ב-Esc', (tester) async {
    await seed(tester, catalog: [
      storePlugin(
        'a',
        screenshots: const ['files/a/s1.png', 'files/a/s2.png'],
      ),
    ]);

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.cardDetailsLink));
    await tester.pumpAndSettle();

    await tester.tap(find
        .descendant(
          of: find.byType(AspectRatio),
          matching: find.byType(Image),
        )
        .first);
    await tester.pumpAndSettle();

    expect(find.text('1 / 2'), findsOneWidget);
    await tester.tap(find.byTooltip(t.screenshotNext));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsNothing);
  });

  // ── שורת הסינון ──────────────────────────────────────────────────────────

  testWidgets('הסינון מופיע רק ב"כל התוספים" ומצמצם את הרשימה', (tester) async {
    await seed(tester, catalog: [
      storePlugin('a', name: 'תוסף בדיקה אלף', tags: const ['תגית-בדיקה-א']),
      storePlugin('b',
          name: 'תוסף בדיקה בית', status: 'beta', tags: const ['תגית-בדיקה-ב']),
    ]);

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    expect(find.byType(PluginFiltersBar), findsOneWidget);
    expect(find.text(t.filterSearchLabel), findsOneWidget);
    expect(find.text(t.summaryAllShown), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'בית');
    await tester.pumpAndSettle();

    expect(find.text('תוסף בדיקה בית'), findsOneWidget);
    expect(find.text('תוסף בדיקה אלף'), findsNothing);
    expect(find.text(t.summaryPartial(1, 2)), findsOneWidget);
  });

  testWidgets('סינון לפי סטטוס וסינון לפי תגית עובדים יחד', (tester) async {
    await seed(tester, catalog: [
      storePlugin('a', name: 'יציב עם תגית', tags: const ['תגית-בדיקה-א']),
      storePlugin('b', name: 'בטא עם תגית', status: 'beta', tags: const [
        'תגית-בדיקה-א',
      ]),
    ]);

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    await tester.tap(find.text(t.filterStatusAll));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.statusBeta).last);
    await tester.pumpAndSettle();

    expect(plugins.statusFilter, PluginStatusFilter.beta);
    expect(find.text('בטא עם תגית'), findsOneWidget);
    expect(find.text('יציב עם תגית'), findsNothing);

    await tester.tap(find.descendant(
      of: find.byType(PluginFiltersBar),
      matching: find.text('תגית-בדיקה-א'),
    ));
    await tester.pumpAndSettle();
    expect(plugins.tagFilter, 'תגית-בדיקה-א');
    expect(find.text('בטא עם תגית'), findsOneWidget);
  });

  testWidgets('רשימת התגיות מתקפלת מעל 14 תגיות', (tester) async {
    await seed(tester, catalog: [
      for (var i = 0; i < 20; i++) storePlugin('p$i', tags: ['תגית $i']),
    ]);

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    expect(find.text(t.showMoreTags), findsOneWidget);
    await tester.tap(find.text(t.showMoreTags));
    await tester.pumpAndSettle();
    expect(find.text(t.showFewerTags), findsOneWidget);
  });

  testWidgets('סינון שלא מחזיר כלום מציג מצב ריק מוסבר', (tester) async {
    await seed(tester, catalog: [storePlugin('a', name: 'תוסף בדיקה אלף')]);

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'אין דבר כזה');
    await tester.pumpAndSettle();

    // אותו נוסח בדיוק מופיע גם בשורת הסיכום וגם בכותרת הכרטיס הריק.
    expect(t.summaryNoResults, t.noResultsTitle);
    expect(find.text(t.noResultsTitle), findsNWidgets(2));
    expect(find.text(t.noResultsBody), findsOneWidget);
    expect(find.byType(PluginStoreCard), findsNothing);
  });

  // ── שכבת הסנכרון ─────────────────────────────────────────────────────────

  testWidgets('שכבת הסנכרון מציגה שלב, אחוזים ואזהרות', (tester) async {
    plugins.status = PluginsModuleStatus.syncing;
    plugins.syncMessage = 'מוריד תמונות (12 מתוך 40)';
    plugins.syncProgress = 0.3;
    plugins.syncWarnings.add('לא ניתן היה להוריד את קטגוריות האתר');

    await pumpScreen(tester, PluginSyncOverlay(controller: plugins));
    await tester.pump();

    expect(find.text(t.syncingOverlayTitle), findsOneWidget);
    expect(find.text('מוריד תמונות (12 מתוך 40)'), findsOneWidget);
    expect(find.text('30%'), findsOneWidget);
    // כשל בנכס בודד אינו עוצר סנכרון — הוא נאסף כאזהרה.
    expect(find.text('לא ניתן היה להוריד את קטגוריות האתר'), findsOneWidget);
  });

  testWidgets('בלי אחוזים השכבה מציגה את הודעת הפתיחה בלבד', (tester) async {
    plugins.status = PluginsModuleStatus.syncing;

    await pumpScreen(tester, PluginSyncOverlay(controller: plugins));
    await tester.pump();

    expect(find.text(t.syncingOverlayStarting), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });

  // ── דיאלוג העדכונים ──────────────────────────────────────────────────────

  testWidgets('דיאלוג העדכונים מפרט גרסאות ומחזיר את התוסף שנבחר',
      (tester) async {
    await seed(tester, catalog: [
      storePlugin('a', name: 'תוסף לעדכון', manifestId: 'id-a', version: '2.0'),
    ]);
    plugins.installed = {'id-a': '1.0'};

    String? selected;
    await pumpScreen(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => ActionButton.neutral(
            text: t.updatesDialogIntro,
            onPressed: () async {
              selected = await showPluginUpdatesDialog(
                context: context,
                controller: plugins,
                updatable: plugins.updatablePlugins,
              );
            },
          ),
        ),
      ),
    );

    expect(plugins.updatablePlugins.length, 1);
    await tester.tap(find.text(t.updatesDialogIntro));
    await tester.pumpAndSettle();

    expect(find.text(t.updatesDialogTitle(1)), findsOneWidget);
    expect(find.text(t.updatesDialogRow('1.0', '2.0')), findsOneWidget);

    await tester.tap(find.text('תוסף לעדכון'));
    await tester.pumpAndSettle();
    expect(selected, 'a');
  });

  testWidgets('הדיאלוג נפתח בכניסה למסך התוספים, ורק פעם אחת', (tester) async {
    // ב-AppShell המסך הזה נבנה רק בכניסה הראשונה ללשונית, ולכן זו גם
    // הנקודה שבה ההודעה מוצגת — לא בעליית התוכנה.
    await seed(tester, catalog: [
      storePlugin('a', name: 'תוסף לעדכון', manifestId: 'id-a', version: '2.0'),
    ]);
    plugins.installed = {'id-a': '1.0'};

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    expect(find.text(t.updatesDialogTitle(1)), findsOneWidget);
    await tester.tap(find.text(stringsOf().common.close));
    await tester.pumpAndSettle();
    expect(find.text(t.updatesDialogTitle(1)), findsNothing);

    // רענון נוסף של הקטלוג לא מציג אותה שוב באותה הרצה.
    plugins.setHideInstalled(false);
    await tester.pumpAndSettle();
    expect(find.text(t.updatesDialogTitle(1)), findsNothing);
    // השבב בשורת הסנכרון כן נשאר, כתזכורת שקטה.
    expect(find.text(t.updatesAvailableChip(1)), findsOneWidget);
  });

  testWidgets('בחירת תוסף מהדיאלוג פותחת את פרטיו ומבקשת מיקוד למסך',
      (tester) async {
    // הדיאלוג נפתח מעל כל מסך (המסך נשאר בעץ גם כשיוצאים ממנו), ולכן פתיחת
    // התוסף חייבת גם להחזיר את הניווט לכאן — אחרת הפרטים נפתחים מאחור.
    await seed(tester, catalog: [
      storePlugin('a', name: 'תוסף לעדכון', manifestId: 'id-a', version: '2.0'),
    ]);
    plugins.installed = {'id-a': '1.0'};

    var focusRequests = 0;
    await pumpScreen(
      tester,
      PluginsScreen(
        controller: plugins,
        onRequestFocus: () => focusRequests++,
      ),
    );
    await tester.pumpAndSettle();

    // אותו שם מופיע גם בכרטיס שברשת מאחורי הדיאלוג — הלחיצה היא על השורה
    // שבתוכו.
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('תוסף לעדכון'),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(PluginDetailView), findsOneWidget);
    expect(focusRequests, 1);
  });

  // ── דף הבית האצור ────────────────────────────────────────────────────────

  testWidgets('"הצג עוד נבחרים" נפתח פעם אחת ונשאר פתוח', (tester) async {
    await seed(tester, catalog: [
      for (var i = 0; i < 9; i++)
        storePlugin('p$i', name: 'נבחר $i', featured: true),
    ]);

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    expect(find.text(t.featuredTitle), findsOneWidget);
    expect(find.text('נבחר 8'), findsNothing);

    await tester.tap(find.text(t.showMoreFeatured));
    await tester.pumpAndSettle();

    expect(find.text('נבחר 8'), findsOneWidget);
    expect(find.text(t.showMoreFeatured), findsNothing);
  });

  testWidgets('כשהמתג מרוקן דף שלם מוצג הסבר עם כפתור לכיבויו', (tester) async {
    await seed(tester, catalog: [
      storePlugin('a', featured: true, manifestId: 'id-a', version: '1.0.0'),
    ]);
    plugins.installed = {'id-a': '1.0.0'};

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    expect(find.text(t.allInstalledTitle), findsOneWidget);
    await tester.tap(find.text(t.showInstalledButton));
    await tester.pumpAndSettle();

    expect(plugins.hideInstalled, isFalse);
    expect(find.text(t.featuredTitle), findsOneWidget);
  });

  // ── מצבי שגיאה וטעינה ────────────────────────────────────────────────────

  testWidgets('שגיאת טעינה מוצגת כשורת שגיאה עם ניסיון חוזר', (tester) async {
    plugins.status = PluginsModuleStatus.error;
    plugins.errorMessage = 'catalog.json פגום';

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pump();

    expect(find.byType(InfoErrorRow), findsOneWidget);
    expect(find.text('catalog.json פגום'), findsOneWidget);
  });

  testWidgets('בזמן טעינת הקטלוג מוצגת שורת התקדמות', (tester) async {
    plugins.status = PluginsModuleStatus.loading;

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pump();

    expect(find.text(t.loadingCatalog), findsOneWidget);
    expect(find.byType(InfoProgressRow), findsOneWidget);
  });

  test('PluginStoreBody.block עוטף כל תוכן כ-sliver ממורווח', () {
    // ה-API מקבל slivers בלבד; העוזרים הם הדרך היחידה להכניס תוכן רגיל.
    final sliver = PluginStoreBody.block(const Text('x'), top: 4);
    expect(sliver, isA<SliverPadding>());
    expect((sliver as SliverPadding).child, isA<SliverToBoxAdapter>());
  });
}

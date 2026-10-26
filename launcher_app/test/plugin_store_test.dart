// בדיקות חנות התוספים — הרכיב הכבד היחיד בלאנצ'ר, ולכן זה שיש בו הכי
// הרבה מלכודות ביצועים: פענוח תמונות, וירטואליזציה של הרשת, וגליל מקונן.
//
// כל טעינה מהדיסק נעשית ב-[WidgetTester.runAsync] **לפני** ה-pump: קריאות
// `dart:io` אינן מסתיימות בתוך ה-fake-async של `testWidgets`, ו-
// `pumpAndSettle` היה נתקע על כל ספינר שממתין להן.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/plugins_module_controller.dart';
import 'package:launcher_app/src/screens/plugins/plugin_detail_view.dart';
import 'package:launcher_app/src/screens/plugins/plugin_rating_panel.dart';
import 'package:launcher_app/src/screens/plugins/plugin_store_card.dart';
import 'package:launcher_app/src/screens/plugins/plugin_visuals.dart';
import 'package:launcher_app/src/screens/plugins/plugins_screen.dart';
import 'package:launcher_app/src/screens/plugins/store_app_export_flow.dart';
import 'package:launcher_app/src/screens/store_kit/store_kit.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;
import 'package:plugins_manager/plugins_manager.dart';

import 'store_fixtures.dart' show FixturePlugins;
import 'test_harness.dart';
import 'test_support.dart';

/// רשומת תוסף **מומצאת** לבדיקה. אין כאן שום נתון מחנות אמיתית: כל השמות,
/// התקצירים והתגיות נכתבו כאן. במסך הם ממלאים את מקום התוכן שמגיע
/// מ-`otzaria.org` — שאינו מתורגם לעולם, ולכן זהה בשתי השפות.
StorePlugin storePlugin(
  String id, {
  String? name,
  String? shortDescription,
  String status = 'stable',
  String version = '1.0.0',
  bool featured = false,
  bool direct = true,
  List<String> tags = const ['תגית-בדיקה-ג'],
  String? manifestId,
  String compatibleWith = '',
  String? imagePath,
  List<String> screenshots = const [],
  List<String> categories = const [],
  bool withLocalFile = false,
  num ratingAvg = 0,
  int ratingCount = 0,
  int ratingVerified = 0,
  List<int> ratingBreakdown = const [0, 0, 0, 0, 0],
}) {
  final plugin = StorePlugin.fromApi({
    'id': id,
    'name': name ?? 'תוסף $id',
    'shortDescription': shortDescription ?? 'תקציר של $id',
    'description': 'תיאור מלא של $id',
    'version': version,
    'status': status,
    'author': 'מחבר',
    'originalDate': '2026-04-02',
    'compatibleWith': compatibleWith,
    'tags': tags,
    'isPinned': featured,
    'supportsDirectInstall': direct,
    'downloadUrl': '/api/plugins/$id/download',
    'ratingAvg': ratingAvg,
    'ratingCount': ratingCount,
    'ratingVerifiedCount': ratingVerified,
    'ratingBreakdown': ratingBreakdown,
  }, 'https://otzaria.org');

  return plugin.copyWith(
    manifestId: manifestId,
    imagePath: imagePath,
    screenshotPaths: screenshots,
    categorySlugs: categories,
    localFiles: withLocalFile
        ? {
            version: PluginLocalFile(
              relativePath: 'files/$id/$id.otzplugin',
              fileName: '$id.otzplugin',
              ext: 'otzplugin',
              size: 2048,
            ),
          }
        : const {},
  );
}

/// קונטרולר שרושם את המסירות לאוצריא במקום לבצע אותן. ההתקנה האמיתית
/// מריצה תהליך (`otzaria://plugin/install-local`), ובבדיקה אין מה להריץ.
class _RecordingController extends PluginsModuleController {
  _RecordingController(String mirrorRootDir, {String? launchPath})
      : super(
          mirrorRootDir: mirrorRootDir,
          otzariaLaunchPath:
              launchPath == null ? null : (() async => launchPath),
        );

  final List<String> delivered = [];
  bool succeeds = true;

  /// תוספים שהמסירה שלהם נכשלת, ומסירות שממתינות עד שהבדיקה משחררת.
  final Set<String> failingIds = {};
  final Map<String, Completer<void>> holds = {};

  /// תוספים שהמסירה שלהם זורקת — דיסק או תהליך שנכשלו באמצע.
  final Set<String> throwingIds = {};

  /// מה שנשלח בהצלחה וממתין לאישור באוצריא — כמו ההמתנה האמיתית, בלי
  /// הטיימר שסורק את הדיסק. מתבטל כשהסריקה מגלה שהגרסה כבר מותקנת.
  final Set<String> sentIds = {};

  @override
  Future<PluginInstallResult> directInstall(StorePlugin plugin) async {
    delivered.add(plugin.id);
    await holds[plugin.id]?.future;
    if (throwingIds.contains(plugin.id)) {
      throw const FileSystemException('הקובץ נעול');
    }
    if (!succeeds || failingIds.contains(plugin.id)) {
      return const PluginInstallResult.failure('אוצריא לא נפתחה');
    }
    sentIds.add(plugin.id);
    notifyListeners();
    return const PluginInstallResult.ok();
  }

  @override
  bool isAwaitingInstallOf(StorePlugin plugin) =>
      sentIds.contains(plugin.id) &&
      statusOf(plugin) != PluginInstallStatus.upToDate;
}

/// סנכרון שמחזיר את [next] כשהבדיקה משחררת את [release] — בלי רשת.
class _OutcomeController extends PluginsModuleController {
  _OutcomeController(String dir) : super(mirrorRootDir: dir);

  PluginSyncOutcome? next;
  Completer<void> release = Completer<void>();
  bool _running = false;

  @override
  bool get isSyncing => _running;

  @override
  Future<void> sync({bool Function()? isCancelled}) async {
    _running = true;
    notifyListeners();
    await release.future;
    lastSyncOutcome = next;
    _running = false;
    notifyListeners();
  }
}

/// העתקת החנות שמסתיימת כשהבדיקה קוראת ל-[finish] — בלי לגעת בדיסק.
class _ExportController extends PluginsModuleController {
  _ExportController(String dir) : super(mirrorRootDir: dir);

  final Completer<StoreAppExportOutcome> _done = Completer();
  bool started = false;

  void finish(StoreAppExportOutcome outcome) => _done.complete(outcome);

  @override
  Future<StoreAppExportOutcome> exportStoreApp(String destinationDir) async {
    started = true;
    isExporting = true;
    notifyListeners();
    final outcome = await _done.future;
    isExporting = false;
    notifyListeners();
    return outcome;
  }
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
    DateTime? lastSync,
  }) async {
    final store = PluginMirrorStore(tempDir.path);
    await tester.runAsync(() => store.save(PluginCatalog(
          lastSync: lastSync ?? DateTime.utc(2026, 8, 6),
          plugins: catalog,
          categories: categories,
          home: home,
        )));
    await tester.runAsync(plugins.load);
    plugins.installed = const {};
  }

  /// אותו זרע, אבל עם קונטרולר שרושם את המסירות לאוצריא במקום לבצע אותן.
  /// [launchPath] מפעיל את זיהוי ההתקנה הניידת בסורק — כך שסריקה מחדש
  /// קוראת תיקיית תוספים אמיתית שהבדיקה בנתה.
  Future<_RecordingController> seedRecording(
    WidgetTester tester, {
    required List<StorePlugin> catalog,
    required Map<String, String> installed,
    String? launchPath,
  }) async {
    plugins.dispose();
    final recording =
        _RecordingController(tempDir.path, launchPath: launchPath);
    plugins = recording;
    await seed(tester, catalog: catalog);
    plugins.installed = installed;
    return recording;
  }

  /// לוחץ על כרטיס התוסף — כל הכרטיס הוא הקישור לדף הפרטים.
  Future<void> openCard(WidgetTester tester, String name) async {
    await tester.tap(find.widgetWithText(PluginStoreCard, name));
    await tester.pumpAndSettle();
  }

  /// הכפתור שהטקסט שלו [text], בתוך [scope] אם ניתן.
  ActionButton button(WidgetTester tester, String text, {Finder? scope}) =>
      tester.widget<ActionButton>(
        scope == null
            ? find.widgetWithText(ActionButton, text)
            : find.descendant(
                of: scope,
                matching: find.widgetWithText(ActionButton, text),
              ),
      );

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

  testWidgets('גם הסמל וצילום המסך בדף התוסף מפוענחים בגודל התצוגה',
      (tester) async {
    await seed(tester, catalog: [
      storePlugin(
        'a',
        name: 'תוסף עם צילומים',
        imagePath: 'files/a/cover.png',
        screenshots: const ['files/a/s1.png', 'files/a/s2.png'],
      ),
    ]);

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();
    await openCard(tester, 'תוסף עם צילומים');

    expect(find.text(t.screenshotsPanelTitle), findsOneWidget);
    // צילום אחד גדול בכל פעם (לא רצועה), ועוד הסמל שבראש.
    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images, hasLength(2));
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

  testWidgets('גובה הכרטיס קבוע — גם כשהתיאור קצר וגם כשהוא ארוך',
      (tester) async {
    await seed(tester, catalog: [
      storePlugin('a', name: 'קצר', shortDescription: 'תיאור קצר'),
      storePlugin('b', name: 'ארוך', shortDescription: 'תיאור ארוך מאוד ' * 30),
    ]);

    for (final width in [760.0, 1100.0]) {
      await pumpScreen(
        tester,
        PluginsScreen(controller: plugins),
        size: Size(width, 1400),
      );
      await tester.pumpAndSettle();
      final heights = [
        for (final name in ['קצר', 'ארוך'])
          tester.getSize(find.widgetWithText(PluginStoreCard, name)).height,
      ];
      expect(heights[0], heights[1], reason: 'ברוחב $width');
      expect(
        heights[0],
        StoreGridDelegate.twoColumns(width - 48)
            ? storeTileCardExtent(1)
            : storeRowCardExtent(1),
      );
    }
  });

  // ── מבנה הגלילה ──────────────────────────────────────────────────────────

  testWidgets('אין גליל מקונן — לא ברשת ולא בדף התוסף', (tester) async {
    await seed(
      tester,
      catalog: [
        for (var i = 0; i < 12; i++)
          storePlugin(
            'p$i',
            name: 'תוסף $i',
            screenshots: const ['files/s1.png', 'files/s2.png'],
          ),
      ],
      categories: const [
        PluginStoreCategory(
          slug: 'study',
          name: 'כלי לימוד',
          pluginIds: ['p0', 'p1', 'p2'],
        ),
      ],
    );

    void expectSingleScrollable() {
      // גליל אופקי מקונן היה בולע את גלגלת העכבר ומקפיא את גלילת העמוד,
      // ורשימה מקוננת הייתה מבטלת את הווירטואליזציה של הרשת.
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
      // הגליל הפנימי של שדה החיפוש הוא חלק מ-`EditableText`, לא אזור תוכן.
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
    }

    await pumpScreen(
      tester,
      PluginsScreen(controller: plugins),
      size: const Size(1400, 1200),
    );
    await tester.pumpAndSettle();
    expectSingleScrollable();

    await openCard(tester, 'תוסף 0');
    expect(find.byType(PluginDetailView), findsOneWidget);
    expectSingleScrollable();
  });

  // ── קטגוריות ─────────────────────────────────────────────────────────────

  testWidgets('מראה בלי קטגוריות — אין שורת שבבים', (tester) async {
    await seed(tester, catalog: [storePlugin('a')]);

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    expect(find.byType(StoreCategoryChip), findsNothing);
    expect(find.text(t.searchHint), findsOneWidget);
  });

  testWidgets('שבבי הקטגוריות: מונה, תיאור כרמז, וסינון בלחיצה',
      (tester) async {
    await seed(
      tester,
      catalog: [
        storePlugin('a', name: 'תוסף בקטגוריה'),
        storePlugin('b', name: 'תוסף מחוץ לקטגוריה'),
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

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    final chip = find.widgetWithText(StoreCategoryChip, 'כלי לימוד');
    expect(tester.widget<StoreCategoryChip>(chip).count, 1);
    expect(
      tester
          .widget<StoreCategoryChip>(
            find.widgetWithText(StoreCategoryChip, t.filterAll),
          )
          .count,
      2,
    );
    expect(find.byTooltip('תוספים שמסייעים בלימוד'), findsOneWidget);

    await tester.tap(chip);
    await tester.pumpAndSettle();

    expect(plugins.categoryFilter, 'study');
    expect(tester.widget<StoreCategoryChip>(chip).selected, isTrue);
    expect(find.text('תוסף בקטגוריה'), findsOneWidget);
    expect(find.text('תוסף מחוץ לקטגוריה'), findsNothing);
  });

  // ── שפה ──────────────────────────────────────────────────────────────────

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

    expect(find.text(english.storeTitle), findsOneWidget);
    expect(find.text(english.refreshButton), findsOneWidget);
    expect(find.text(english.filterNotInstalled), findsOneWidget);
    expect(find.text(t.refreshButton), findsNothing);
    // שם התוסף מגיע מ-otzaria.org ולכן אינו מתורגם לעולם.
    expect(find.text('תוסף מהאתר'), findsOneWidget);

    await openCard(tester, 'תוסף מהאתר');
    expect(find.text(english.infoPanelTitle), findsOneWidget);
    expect(find.text('תגית מהאתר'), findsOneWidget);
  });

  // ── מצב ההתקנה והפעולה ──────────────────────────────────────────────────

  testWidgets('תוסף שקובצו טרם ירד — "התקן באוצריא" פעיל, והערה על הקובץ',
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
    expect(find.text(t.installedLabel), findsNothing);
    expect(find.byType(InfoErrorRow), findsNothing);
    // ההתקנה הישירה פעילה: היא מסוגלת להשלים את הקובץ.
    expect(button(tester, t.installInOtzariaButton).onPressed, isNotNull);
    expect(find.text(t.noteFileMissing), findsOneWidget);

    // כשידוע שיש אינטרנט — בלי "(צריך אינטרנט)": הקובץ יירד מיד.
    await pumpScreen(tester, PluginsScreen(controller: plugins, online: true));
    await tester.pumpAndSettle();
    expect(find.text(t.noteFileMissingOnline), findsOneWidget);
    expect(find.text(t.noteFileMissing), findsNothing);
    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    await openCard(tester, 'תוסף שטרם ירד');

    expect(find.text(t.fileMissingTitle), findsOneWidget);
    expect(find.text(t.factNotOnDrive), findsOneWidget);
    // בלי קובץ אין מה לשמור — ולכן אין "שמור קובץ" לצד ההתקנה.
    expect(find.text(t.saveFileButton), findsNothing);
  });

  testWidgets('תוסף מותקן ומעודכן — "מותקן ✓" במקום כפתור', (tester) async {
    await seed(tester, catalog: [
      storePlugin('a', manifestId: 'id-a', version: '2.0.0'),
    ]);
    plugins.installed = {'id-a': '2.0.0'};

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    expect(find.text(t.installedLabel), findsOneWidget);
    expect(find.text(t.installInOtzariaButton), findsNothing);
  });

  testWidgets('גרסה ישנה מותקנת — "עדכן ל-X"', (tester) async {
    await seed(tester, catalog: [
      storePlugin('a', manifestId: 'id-a', version: '2.0.0'),
    ]);
    plugins.installed = {'id-a': '1.0.0'};

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(PluginStoreCard, t.updateToButton('2.0.0')),
      findsOneWidget,
    );
  });

  testWidgets('בלי אוצריא במחשב — הכפתור מושבת, וההסבר לצדו', (tester) async {
    await seed(tester, catalog: [storePlugin('a', name: 'תוסף')]);

    await pumpScreen(
      tester,
      PluginsScreen(controller: plugins, otzariaInstalled: false),
    );
    await tester.pumpAndSettle();

    expect(button(tester, t.installInOtzariaButton).onPressed, isNull);
    expect(find.text(t.noteNeedsOtzaria), findsOneWidget);
  });

  testWidgets('תוסף בלי התקנה ישירה — "שמור קובץ", פעיל רק כשהקובץ בכונן',
      (tester) async {
    await seed(tester, catalog: [
      storePlugin('a', name: 'בלי קובץ', direct: false),
      storePlugin('b', name: 'עם קובץ', direct: false, withLocalFile: true),
    ]);

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    ActionButton saveIn(String name) => button(
          tester,
          t.saveFileButton,
          scope: find.widgetWithText(PluginStoreCard, name),
        );
    expect(saveIn('בלי קובץ').onPressed, isNull);
    expect(saveIn('עם קובץ').onPressed, isNotNull);
    expect(find.text(t.noteSaveOnly), findsNWidgets(2));
  });

  testWidgets('אין בילד לאוצריא שבמחשב — מושבת עם הסבר, וגם בדף', (
    tester,
  ) async {
    await seed(tester, catalog: [
      storePlugin('a', name: 'דורש חדשה', compatibleWith: '2.0.0'),
    ]);
    plugins.appVersion = '1.0.0';

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    expect(find.text(t.incompatibleLabel), findsOneWidget);
    expect(find.text(t.noteNeedsApp('2.0.0')), findsOneWidget);
    expect(find.text(t.installInOtzariaButton), findsNothing);

    await openCard(tester, 'דורש חדשה');
    expect(find.text(t.incompatibleTitle), findsOneWidget);
    expect(
      find.text(t.incompatibleBodyVersions('2.0.0', '1.0.0')),
      findsOneWidget,
    );
  });

  testWidgets('מושבת באוצריא ותוסף בפיתוח — תווית ובאנר מסביר', (
    tester,
  ) async {
    plugins.dispose();
    final fixture = FixturePlugins(tempDir.path)
      ..disabled = {'id-a'}
      ..development = {'id-b'};
    plugins = fixture;
    await seed(tester, catalog: [
      storePlugin('a', name: 'מושבת', manifestId: 'id-a'),
      storePlugin('b', name: 'בפיתוח', manifestId: 'id-b'),
    ]);
    plugins.installed = {'id-a': '1.0.0'};

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    expect(find.text(t.disabledLabel), findsOneWidget);
    expect(find.text(t.developmentLabel), findsOneWidget);

    await openCard(tester, 'מושבת');
    expect(find.text(t.disabledTitle), findsOneWidget);
  });

  // ── דף התוסף ─────────────────────────────────────────────────────────────

  testWidgets('דף התוסף: ראש עם פעולה ושמירה, נתונים, מידע ותגיות',
      (tester) async {
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
    await openCard(tester, 'תוסף עם פרטים');

    expect(find.byType(PluginDetailView), findsOneWidget);
    final hero = find.byType(StoreDetailHero);
    expect(
      find.descendant(of: hero, matching: find.text('תוסף עם פרטים')),
      findsOneWidget,
    );
    // פעולה ראשית לפי המצב, ולצדה שמירת הקובץ — הוא בכונן.
    expect(
      button(tester, t.installInOtzariaButton, scope: hero).onPressed,
      isNotNull,
    );
    expect(button(tester, t.saveFileButton, scope: hero).onPressed, isNotNull);

    // חמישה תאי נתונים בחלון רחב.
    for (final label in [
      t.factRating,
      t.infoVersion,
      t.factCompatible,
      t.infoNetwork,
      t.factSize,
    ]) {
      expect(
        find.descendant(
            of: find.byType(StoreFacts), matching: find.text(label)),
        findsOneWidget,
        reason: label,
      );
    }
    expect(find.text(t.infoPanelTitle), findsOneWidget);
    expect(find.text(t.tagsPanelTitle), findsOneWidget);
    expect(find.text(t.descriptionTitle), findsOneWidget);
    // "מידע כללי" בלי פרטים טכניים: לא שם הקובץ, ולא ההתאמה שכבר ברצועה.
    expect(find.text('a.otzplugin'), findsNothing);
    expect(find.text(t.factNotOnDrive), findsNothing);
  });

  testWidgets('בדף צר נשארים שלושה תאי נתונים, בעמודה אחת', (tester) async {
    await seed(tester, catalog: [storePlugin('a', withLocalFile: true)]);

    await pumpScreen(
      tester,
      PluginDetailView(
        plugin: plugins.plugins.single,
        controller: plugins,
        onSave: () {},
        onInstall: () {},
        onTagSelected: (_) {},
        onCategorySelected: (_) {},
      ),
      size: const Size(700, 2000),
    );
    await tester.pumpAndSettle();

    final facts = find.byType(StoreFacts);
    expect(
      find.descendant(of: facts, matching: find.text(t.factRating)),
      findsNothing,
    );
    expect(
      find.descendant(of: facts, matching: find.text(t.factSize)),
      findsNothing,
    );
    expect(
      find.descendant(of: facts, matching: find.text(t.infoVersion)),
      findsOneWidget,
    );
    // המידע יורד מתחת לתיאור — עמודה אחת.
    expect(
      tester.getTopLeft(find.text(t.infoPanelTitle)).dy,
      greaterThan(tester.getTopLeft(find.text(t.ratingPanelTitle)).dy),
    );
  });

  testWidgets('הדירוג שבאתר מוצג בכרטיס ובדף — ואין דרך לדרג', (tester) async {
    await seed(tester, catalog: [
      storePlugin(
        'a',
        name: 'תוסף מדורג',
        ratingAvg: 4.5,
        ratingCount: 2,
        ratingVerified: 1,
        ratingBreakdown: const [0, 0, 0, 1, 1],
      ),
    ]);

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    // בכרטיס: ממוצע בספרה אחת ומספר המדרגים בסוגריים, כמו באתר.
    expect(find.text(t.ratingBadge('4.5', 2)), findsOneWidget);

    await openCard(tester, 'תוסף מדורג');

    final panel = find.byType(PluginRatingSummary);
    expect(find.text(t.ratingPanelTitle), findsOneWidget);
    expect(
      find.descendant(of: panel, matching: find.text('4.5')),
      findsOneWidget,
    );
    expect(find.text(t.ratingVerifiedLabel(1)), findsOneWidget);

    // הדירוג הוא תצוגה בלבד: בסעיף אין שום דבר שאפשר ללחוץ עליו.
    expect(
      find.descendant(of: panel, matching: find.byType(InkWell)),
      findsNothing,
    );
    expect(
      find.descendant(of: panel, matching: find.byType(ButtonStyleButton)),
      findsNothing,
    );
  });

  testWidgets('"נכון ל־" ותאריך הדירוג: סנכרון אחרי חצות מוצג ביום המקומי',
      (tester) async {
    // הסנכרון נרשם כזמן מקומי; קריאה ב-UTC הייתה מראה את אתמול (י"ב).
    await seed(
      tester,
      catalog: [storePlugin('a', name: 'תוסף בחצות')],
      lastSync: DateTime(2026, 10, 24, 0, 30),
    );
    const day = 'י"ג חשוון ה\'תשפ"ז';

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();
    expect(find.textContaining(t.asOfDate(day)), findsOneWidget);

    await openCard(tester, 'תוסף בחצות');
    expect(find.text(t.ratingAsOfNote(day)), findsOneWidget);
  });

  testWidgets('תוסף שטרם דורג — הסעיף אומר זאת, ואין דירוג ריק בכרטיס',
      (tester) async {
    await seed(tester, catalog: [storePlugin('a', name: 'תוסף בלי דירוג')]);

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();
    expect(find.text(t.ratingBadge('0.0', 0)), findsNothing);

    await openCard(tester, 'תוסף בלי דירוג');

    expect(find.text(t.ratingEmpty), findsWidgets);
    expect(find.text(t.ratingCountLabel(0)), findsNothing);
  });

  testWidgets('תגית בדף התוסף חוזרת לרשימה מסוננת, ו"עוד סינון" נפתח',
      (tester) async {
    await seed(tester, catalog: [
      storePlugin('a', name: 'תוסף עם תגית', tags: const ['תגית-בדיקה-ד']),
      storePlugin('b', name: 'תוסף אחר', tags: const ['תגית-בדיקה-ג']),
    ]);

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();
    await openCard(tester, 'תוסף עם תגית');

    await tester.tap(find.descendant(
      of: find.byType(PluginDetailView),
      matching: find.text('תגית-בדיקה-ד'),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(PluginDetailView), findsNothing);
    expect(plugins.tagFilter, 'תגית-בדיקה-ד');
    expect(find.text('תוסף עם תגית'), findsOneWidget);
    expect(find.text('תוסף אחר'), findsNothing);
    // המסנן שנבחר נראה — "עוד סינון" פתוח ומונה אותו.
    expect(find.text(t.moreFiltersCount(1)), findsOneWidget);
  });

  testWidgets('קטגוריה בדף התוסף חוזרת לרשימה עם השבב שלה', (tester) async {
    await seed(
      tester,
      catalog: [
        storePlugin('a', name: 'תוסף בקטגוריה', categories: const ['study']),
        storePlugin('b', name: 'תוסף אחר'),
      ],
      categories: const [
        PluginStoreCategory(slug: 'study', name: 'כלי לימוד', pluginIds: ['a']),
      ],
    );

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();
    await openCard(tester, 'תוסף בקטגוריה');

    await tester.tap(find.descendant(
      of: find.byType(PluginDetailView),
      matching: find.text('כלי לימוד'),
    ));
    await tester.pumpAndSettle();

    expect(plugins.categoryFilter, 'study');
    expect(find.text('תוסף אחר'), findsNothing);
  });

  testWidgets('צילומי המסך: נקודות מחליפות, והגדלה נפתחת, מתקדמת ונסגרת',
      (tester) async {
    await seed(tester, catalog: [
      storePlugin(
        'a',
        name: 'תוסף עם צילומים',
        screenshots: const ['files/a/s1.png', 'files/a/s2.png'],
      ),
    ]);

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();
    await openCard(tester, 'תוסף עם צילומים');

    String shownShot() {
      final image = tester.widget<Image>(find.descendant(
        of: find.byType(StoreScreenshots),
        matching: find.byType(Image),
      ));
      final file = (image.image as ResizeImage).imageProvider as FileImage;
      return file.file.path;
    }

    expect(p.basename(shownShot()), 's1.png');
    await tester.tap(find.byTooltip(t.screenshotNumber(2, 2)));
    await tester.pumpAndSettle();
    expect(p.basename(shownShot()), 's2.png');

    await tester.tap(find.byTooltip(t.screenshotNumber(1, 2)));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(t.screenshotZoom));
    await tester.pumpAndSettle();

    expect(find.text(t.screenshotNumber(1, 2)), findsOneWidget);
    await tester.tap(find.byTooltip(t.screenshotNext));
    await tester.pumpAndSettle();
    expect(find.text(t.screenshotNumber(2, 2)), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text(t.screenshotNumber(2, 2)), findsNothing);
  });

  // ── חיפוש וסינון ─────────────────────────────────────────────────────────

  testWidgets('החיפוש מצמצם, מתעלם מסופיות ומדגיש את ההתאמה', (tester) async {
    await seed(tester, catalog: [
      storePlugin('a', name: 'לוח שנה עברי'),
      storePlugin('b', name: 'מאגר ספרים'),
    ]);

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    // מ"ם סופית בשאילתה ("ספרימ") מוצאת את "ספרים" — כמו בתיבת החיפוש באתר.
    await tester.enterText(find.byType(TextField).first, 'ספרימ');
    await tester.pumpAndSettle();
    expect(find.text('מאגר ספרים'), findsOneWidget);
    expect(find.text('לוח שנה עברי'), findsNothing);

    // ההתאמה מודגשת בתוך השם (Text.rich עם רקע).
    final name = tester.widget<Text>(find.text('מאגר ספרים'));
    expect(name.textSpan, isNotNull);
    final marked = (name.textSpan! as TextSpan)
        .children!
        .whereType<TextSpan>()
        .where((span) => span.style?.backgroundColor != null);
    expect(marked.single.text, 'ספרים');

    // הכפתור שבשדה מנקה את החיפוש.
    await tester.tap(find.byTooltip(t.clearSearchTooltip));
    await tester.pumpAndSettle();
    expect(plugins.search, isEmpty);
    expect(find.text('לוח שנה עברי'), findsOneWidget);
  });

  testWidgets('"עוד סינון" מקופל; בפתיחה — יציבות ותגיות, ויחד',
      (tester) async {
    await seed(tester, catalog: [
      storePlugin('a', name: 'יציב עם תגית', tags: const ['תגית-בדיקה-א']),
      storePlugin('b',
          name: 'בטא עם תגית', status: 'beta', tags: const ['תגית-בדיקה-א']),
      storePlugin('c', name: 'בטא בלי', status: 'beta', tags: const []),
      storePlugin('d', name: 'סטטוס זר', status: 'deprecated', tags: const []),
    ]);

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    // בכרטיס, כמו בסינון: בטא מוצג כ"ניסיוני", וסטטוס לא מוכר — בלי שבב.
    expect(
      find.widgetWithText(StoreMetaChip, t.statusExperimental),
      findsNWidgets(2),
    );
    expect(find.text(t.filterStatusLabel), findsNothing);
    await tester.tap(find.text(t.moreFilters));
    await tester.pumpAndSettle();
    expect(find.text(t.filterStatusLabel), findsOneWidget);

    // "יציבות": הכול / יציב / ניסיוני — ו"ניסיוני" כולל את הבטא.
    expect(find.widgetWithText(StoreFilterChip, 'בטא'), findsNothing);
    await tester.tap(find.widgetWithText(StoreFilterChip, t.statusStable));
    await tester.pumpAndSettle();
    expect(find.text('יציב עם תגית'), findsOneWidget);
    expect(find.text('בטא בלי'), findsNothing);
    expect(find.text('סטטוס זר'), findsNothing);

    await tester
        .tap(find.widgetWithText(StoreFilterChip, t.statusExperimental));
    await tester.pumpAndSettle();
    expect(plugins.statusFilter, PluginStatusFilter.experimental);
    expect(find.text('יציב עם תגית'), findsNothing);
    expect(find.text('בטא בלי'), findsOneWidget);
    // סטטוס לא מוכר אינו "ניסיוני" — רק תחת "הכול".
    expect(find.text('סטטוס זר'), findsNothing);

    await tester.tap(find.widgetWithText(StoreFilterChip, 'תגית-בדיקה-א'));
    await tester.pumpAndSettle();
    expect(plugins.tagFilter, 'תגית-בדיקה-א');
    expect(find.text('בטא עם תגית'), findsOneWidget);
    expect(find.text('בטא בלי'), findsNothing);
    expect(find.text(t.moreFiltersCount(2)), findsOneWidget);
  });

  testWidgets('רשימת התגיות מתקפלת מעל 14 תגיות', (tester) async {
    await seed(tester, catalog: [
      for (var i = 0; i < 20; i++) storePlugin('p$i', tags: ['תגית $i']),
    ]);

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.moreFilters));
    await tester.pumpAndSettle();

    // התגיות ממוינות, ולכן "תגית 9" היא האחרונה.
    expect(find.text('תגית 9'), findsNothing);
    await tester.tap(find.text(t.showMoreTags));
    await tester.pumpAndSettle();
    expect(find.text(t.showFewerTags), findsOneWidget);
    expect(find.text('תגית 9'), findsOneWidget);
  });

  testWidgets('חיפוש שלא מחזיר כלום — הסבר, וכפתור שמנקה הכול', (tester) async {
    await seed(tester, catalog: [storePlugin('a', name: 'תוסף בדיקה אלף')]);

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'אין דבר כזה');
    await tester.pumpAndSettle();

    expect(find.text(t.noResultsForQuery('אין דבר כזה')), findsOneWidget);
    expect(find.text(t.noResultsBody), findsOneWidget);
    expect(find.byType(PluginStoreCard), findsNothing);

    await tester.tap(find.text(t.clearFiltersButton));
    await tester.pumpAndSettle();
    expect(find.text('תוסף בדיקה אלף'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      isEmpty,
    );
  });

  // ── רענון (סנכרון) ───────────────────────────────────────────────────────

  testWidgets('"רענון" רק כשמחובר ובכונן כתיב', (tester) async {
    await seed(tester, catalog: [storePlugin('a')]);

    for (final (online, readOnly, shown) in [
      (null, false, true),
      (true, false, true),
      (false, false, false),
      (true, true, false),
    ]) {
      await pumpScreen(
        tester,
        PluginsScreen(controller: plugins, online: online, readOnly: readOnly),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(t.refreshButton),
        shown ? findsOneWidget : findsNothing,
        reason: 'online=$online readOnly=$readOnly',
      );
    }
  });

  testWidgets('סנכרון מוצג בדף: שלב, אחוזים, אזהרות ועצירה', (tester) async {
    plugins.dispose();
    final fixture = FixturePlugins(tempDir.path);
    plugins = fixture;
    await seed(tester, catalog: [storePlugin('a', name: 'תוסף')]);
    fixture
      ..fakeSyncing = true
      ..syncMessage = 'מוריד תמונות (12 מתוך 40)'
      ..syncProgress = 0.3;
    fixture.syncWarnings.add('לא ניתן היה להוריד את קטגוריות האתר');

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pump();

    expect(find.text(t.syncingTitle), findsOneWidget);
    expect(find.text('מוריד תמונות (12 מתוך 40)'), findsOneWidget);
    expect(find.text('30%'), findsOneWidget);
    // כשל בנכס בודד אינו עוצר סנכרון — הוא נאסף כאזהרה.
    expect(find.text('לא ניתן היה להוריד את קטגוריות האתר'), findsOneWidget);
    // הרענון בראש הדף מושבת בזמן הסנכרון, והרשימה נשארת.
    expect(button(tester, t.refreshButton).onPressed, isNull);
    expect(find.text('תוסף'), findsOneWidget);

    await tester.tap(find.text(t.syncStopButton));
    await tester.pump();
    expect(button(tester, t.syncStopButton).onPressed, isNull);
  });

  testWidgets('שורת הסנכרון מתעדכנת מדיווח התקדמות בלי בנייה מחדש מבחוץ',
      (tester) async {
    plugins.dispose();
    final fixture = FixturePlugins(tempDir.path);
    plugins = fixture;
    await seed(tester, catalog: [storePlugin('a')]);
    fixture.fakeSyncing = true;
    var stateNotifications = 0;
    plugins.addListener(() => stateNotifications++);

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pump();
    expect(find.text(t.syncingOverlayStarting), findsOneWidget);

    plugins.syncMessage = 'step 2';
    plugins.syncProgress = 0.5;
    plugins.syncWarnings.add('warning 1');
    plugins.notifyProgress();
    await tester.pump();

    expect(find.text('step 2'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('warning 1'), findsOneWidget);
    expect(stateNotifications, 0);
  });

  testWidgets('שורת הייצוא מתעדכנת מדיווח התקדמות בלי בנייה מחדש מבחוץ',
      (tester) async {
    plugins.isExporting = true;
    plugins.exportMessage = 'step 1';
    plugins.exportProgress = 0.1;
    var stateNotifications = 0;
    plugins.addListener(() => stateNotifications++);

    await pumpScreen(tester, StoreAppCopyProgress(controller: plugins));
    await tester.pump();
    expect(find.text('10%'), findsOneWidget);

    plugins.exportMessage = 'step 2';
    plugins.exportProgress = 0.6;
    plugins.notifyProgress();
    await tester.pump();

    expect(find.text('step 2'), findsOneWidget);
    expect(find.text('60%'), findsOneWidget);
    expect(stateNotifications, 0);
  });

  testWidgets('"מתקדם" מקופל: ייצוא החנות (Windows) וטעינה מחדש מהכונן',
      (tester) async {
    await seed(tester, catalog: [storePlugin('a')]);

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    expect(
        find.descendant(
            of: find.byType(RowsCard), matching: find.text(t.reloadRowTitle)),
        findsNothing);
    await tester.tap(find.text(stringsOf().pages.advancedTitle));
    await tester.pumpAndSettle();

    expect(
        find.descendant(
            of: find.byType(RowsCard), matching: find.text(t.reloadRowTitle)),
        findsOneWidget);
    expect(
      find.text(t.storeAppButton),
      StoreAppExportButton.isSupported ? findsOneWidget : findsNothing,
    );
  });

  // ── פס העדכונים ──────────────────────────────────────────────────────────

  testWidgets('פס העדכונים: מספר ושמות, ובלי עדכונים — אין פס', (tester) async {
    await seed(tester, catalog: [
      storePlugin('a', name: 'ראשון', manifestId: 'id-a', version: '2.0'),
      storePlugin('b', name: 'שני', manifestId: 'id-b', version: '3.0'),
    ]);
    plugins.installed = {'id-a': '1.0', 'id-b': '3.0'};

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    expect(find.text(t.updatesAvailable(1)), findsOneWidget);
    expect(
        find.text(t.updatesBarNames(t.joinNames(['ראשון']))), findsOneWidget);
    expect(find.text(t.updateAllButton), findsOneWidget);

    // כמו בסוף סריקה: המפה מתחלפת והמאזינים מקבלים הודעה.
    plugins.installed = {'id-a': '2.0', 'id-b': '3.0'};
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    plugins.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text(t.updateAllButton), findsNothing);
    expect(find.text(t.updatesAvailable(1)), findsNothing);
  });

  testWidgets('כפתור העדכון בכרטיס מוסר את התוסף לאוצריא ומסמן "נשלח"',
      (tester) async {
    final controller = await seedRecording(
      tester,
      catalog: [
        storePlugin('a',
            name: 'תוסף לעדכון', manifestId: 'id-a', version: '2.0'),
      ],
      installed: {'id-a': '1.0'},
    );

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    await tester
        .tap(find.widgetWithText(ActionButton, t.updateToButton('2.0')));
    // בלי pumpAndSettle: "שולח" מסתובב, וההמתנה לא הייתה נגמרת.
    await tester.pump();
    await tester.pump();

    expect(controller.delivered, ['a']);
    expect(find.text(t.sentLabel), findsOneWidget);
    expect(find.text(t.updateToButton('2.0')), findsNothing);
    // הפס אומר שהכול נשלח ושאוצריא היא שמאשרת.
    expect(find.text(t.updatesSentTitle), findsOneWidget);
    expect(find.text(t.updateAllButton), findsNothing);
  });

  testWidgets('"עדכון הכול" מוסר אחד אחרי השני, וחוסם את הכרטיסים בינתיים',
      (tester) async {
    final controller = await seedRecording(
      tester,
      catalog: [
        storePlugin('a', name: 'ראשון', manifestId: 'id-a', version: '2.0'),
        storePlugin('b', name: 'שני', manifestId: 'id-b', version: '3.0'),
      ],
      installed: {'id-a': '1.0', 'id-b': '1.0'},
    );

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    await tester.tap(find.text(t.updateAllButton));
    await tester.pump();
    await tester.pump();

    // המסירה השנייה ממתינה בכוונה — אחרת אוצריא הסגורה הייתה נפתחת פעמיים.
    expect(controller.delivered, ['a']);
    expect(find.text(t.updatingAllLabel(2, 2)), findsOneWidget);
    expect(button(tester, t.updateToButton('3.0')).onPressed, isNull);

    await tester.pump(pluginUpdateDeliverySpacing);
    await tester.pump();

    expect(controller.delivered, ['a', 'b']);
    expect(find.text(t.sentLabel), findsNWidgets(2));
    expect(find.text(t.updatesSentTitle), findsOneWidget);
  });

  // המסירה עברה לקונטרולר: "עדכון כאן" שבבית משתמש בה גם כשהחנות סגורה.
  testWidgets('deliverUpdates: אחד אחרי השני במרווח, ומחזיר רק מה שנשלח',
      (tester) async {
    final controller = await seedRecording(
      tester,
      catalog: [
        storePlugin('a', name: 'ראשון', manifestId: 'id-a', version: '2.0'),
        storePlugin('b', name: 'שני', manifestId: 'id-b', version: '3.0'),
      ],
      installed: {'id-a': '1.0', 'id-b': '1.0'},
    );
    expect(controller.deliverableUpdates.map((p) => p.id), ['a', 'b']);

    final delivered = <String>[];
    List<StorePlugin>? sent;
    unawaited(controller
        .deliverUpdates(
          onDelivered: (plugin, result) => delivered.add(plugin.id),
        )
        .then((value) => sent = value));
    await tester.pump();
    expect(controller.delivered, ['a']);
    await tester
        .pump(pluginUpdateDeliverySpacing - const Duration(milliseconds: 1));
    expect(controller.delivered, ['a']);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(controller.delivered, ['a', 'b']);
    expect(delivered, ['a', 'b']);
    expect(sent!.map((p) => p.id), ['a', 'b']);

    controller.delivered.clear();
    controller.sentIds.clear();
    controller.succeeds = false;
    var cancelled = false;
    List<StorePlugin>? none;
    unawaited(controller
        .deliverUpdates(isCancelled: () => cancelled)
        .then((value) => none = value));
    await tester.pump();
    cancelled = true;
    await tester.pump(pluginUpdateDeliverySpacing);
    await tester.pump();
    expect(controller.delivered, ['a']);
    expect(none, isEmpty);
  });

  testWidgets('מסירה שנכשלה אינה מסומנת כנשלחה', (tester) async {
    final controller = await seedRecording(
      tester,
      catalog: [
        storePlugin('a',
            name: 'תוסף לעדכון', manifestId: 'id-a', version: '2.0'),
      ],
      installed: {'id-a': '1.0'},
    );
    controller.succeeds = false;

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    await tester
        .tap(find.widgetWithText(ActionButton, t.updateToButton('2.0')));
    await tester.pump();
    await tester.pump();

    expect(find.text(t.sentLabel), findsNothing);
    expect(find.text(t.updateToButton('2.0')), findsOneWidget);
    expect(find.text(t.updateAllButton), findsOneWidget);
  });

  /// התקנה ניידת מומצאת שהסורק יודע לקרוא — מחזירה את נתיב ההפעלה.
  /// [manifests] הוא `manifestId -> גרסה מותקנת`.
  String fakePortableInstall(Map<String, String> manifests) {
    final exePath = p.join(tempDir.path, 'otzaria.exe');
    File(exePath).writeAsStringSync('');
    File(p.join(tempDir.path, 'portable.marker')).writeAsStringSync('');
    manifests.forEach((id, version) {
      final dir = Directory(p.join(
          tempDir.path, 'otzaria_data', 'plugins', 'installed', id, 'current'))
        ..createSync(recursive: true);
      File(p.join(dir.path, 'manifest.json'))
          .writeAsStringSync('{"id":"$id","version":"$version"}');
    });
    return exePath;
  }

  testWidgets('סריקה מחדש הופכת כרטיס שנשלח ל"מותקן ✓"', (tester) async {
    // סריקה **אמיתית** של התקנה ניידת שהבדיקה בנתה, ולא מפה מזויפת.
    final exePath = fakePortableInstall({'id-a': '1.0'});
    final controller = await seedRecording(
      tester,
      catalog: [
        storePlugin('a',
            name: 'תוסף לעדכון', manifestId: 'id-a', version: '2.0'),
      ],
      installed: {'id-a': '1.0'},
      launchPath: exePath,
    );

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    await tester
        .tap(find.widgetWithText(ActionButton, t.updateToButton('2.0')));
    await tester.pump();
    await tester.pump();
    expect(controller.delivered, ['a']);
    expect(find.text(t.sentLabel), findsOneWidget);

    // אוצריא סיימה את ההתקנה; זו הסריקה שמגלה זאת.
    fakePortableInstall({'id-a': '2.0'});
    await tester.runAsync(plugins.refreshInstalled);
    await tester.pump();

    expect(plugins.updatablePlugins, isEmpty);
    expect(find.text(t.installedLabel), findsOneWidget);
    expect(find.text(t.sentLabel), findsNothing);
    expect(find.text(t.updatesSentTitle), findsNothing);
  });

  testWidgets('סריקה מיישרת את הפס — מה שכבר עדכני יורד, ומה שהתגלה נוסף',
      (tester) async {
    // הפס נקרא חי: מפה שלפני זיהוי ההתקנה אינה נשארת עליו.
    final exePath = fakePortableInstall({'id-a': '1.0', 'id-b': '3.0'});
    await seedRecording(
      tester,
      catalog: [
        storePlugin('a', name: 'ראשון', manifestId: 'id-a', version: '2.0'),
        storePlugin('b', name: 'שני', manifestId: 'id-b', version: '3.0'),
        storePlugin('c', name: 'שלישי', manifestId: 'id-c', version: '5.0'),
      ],
      installed: {'id-a': '1.0', 'id-b': '1.0'},
      launchPath: exePath,
    );

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();
    expect(find.text(t.updatesAvailable(2)), findsOneWidget);

    fakePortableInstall({'id-c': '4.0'});
    await tester.runAsync(plugins.refreshInstalled);
    await tester.pump();

    expect(
      find.text(t.updatesBarNames(t.joinNames(['ראשון', 'שלישי']))),
      findsOneWidget,
    );
    expect(find.text(t.updatesAvailable(2)), findsOneWidget);
  });

  // ── מצבי שגיאה, טעינה וריק ───────────────────────────────────────────────

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

  // ── תיקוני שלב 4: עדכון הכול, חסימות, "חדש", ייצוא ומצבים ────────────────

  /// ההודעות ש-UiSnack ניסה להציג. בבדיקה אין overlay, ולכן הן נכתבות
  /// ל-debugPrint — וזה מה שנאסף כאן.
  /// [restore] חובה בסוף הבדיקה עצמה — המסגרת בודקת את debugPrint לפני
  /// ה-tearDown.
  ({List<String> messages, void Function() restore}) captureSnacks() {
    final messages = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null && message.startsWith('UiSnack')) {
        messages.add(message);
      }
    };
    return (messages: messages, restore: () => debugPrint = original);
  }

  List<StorePlugin> threeUpdates() => [
        storePlugin('a', name: 'ראשון', manifestId: 'id-a', version: '2.0'),
        storePlugin('b', name: 'שני', manifestId: 'id-b', version: '3.0'),
        storePlugin('c', name: 'שלישי', manifestId: 'id-c', version: '4.0'),
      ];
  const threeInstalled = {'id-a': '1.0', 'id-b': '1.0', 'id-c': '1.0'};

  testWidgets('"עדכון הכול": הודעת סיכום אחת — כמה נשלחו וכמה נכשלו',
      (tester) async {
    final controller = await seedRecording(
      tester,
      catalog: threeUpdates(),
      installed: threeInstalled,
    );
    controller.failingIds.add('c');
    final (messages: snacks, :restore) = captureSnacks();

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.updateAllButton));
    await tester.pump();
    await tester.pump();
    for (var i = 0; i < 2; i++) {
      await tester.pump(pluginUpdateDeliverySpacing);
      await tester.pump();
    }

    expect(controller.delivered, ['a', 'b', 'c']);
    expect(plugins.isUpdatingAll, isFalse);
    // הודעה לכל כישלון הייתה נדרסת מיד בהודעת "נשלחו" — עכשיו יש אחת.
    restore();
    expect(snacks, hasLength(1));
    expect(snacks.single, contains(t.updateAllPartlySentSnack(2, 'שלישי')));
  });

  testWidgets('"עדכון הכול": מסירה שזורקת אינה משאירה את הריצה תקועה',
      (tester) async {
    final controller = await seedRecording(
      tester,
      catalog: threeUpdates(),
      installed: threeInstalled,
    );
    controller.throwingIds.addAll(['a', 'b']);
    final (messages: snacks, :restore) = captureSnacks();

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.updateAllButton));
    await tester.pump();
    await tester.pump();
    for (var i = 0; i < 2; i++) {
      await tester.pump(pluginUpdateDeliverySpacing);
      await tester.pump();
    }

    // החריגה נרשמת ככישלון של אותו תוסף, והרצף ממשיך לתוסף הבא.
    expect(controller.delivered, ['a', 'b', 'c']);
    expect(plugins.isUpdatingAll, isFalse);
    expect(plugins.isDelivering(threeUpdates().first), isFalse);
    expect(find.text(t.actionsBlockedUpdatingAll), findsNothing);
    restore();
    expect(
      snacks.single,
      contains(t.updateAllPartlySentSnack(1, t.joinNames(['ראשון', 'שני']))),
    );
  });

  testWidgets('"עדכון הכול": כשאף עדכון לא נשלח — בלי "0 נשלחו"',
      (tester) async {
    final controller = await seedRecording(
      tester,
      catalog: threeUpdates(),
      installed: threeInstalled,
    );
    controller.succeeds = false;
    final (messages: snacks, :restore) = captureSnacks();

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.updateAllButton));
    await tester.pump();
    await tester.pump();
    for (var i = 0; i < 2; i++) {
      await tester.pump(pluginUpdateDeliverySpacing);
      await tester.pump();
    }

    restore();
    final names = t.joinNames(['ראשון', 'שני', 'שלישי']);
    expect(snacks.single, contains(t.updateAllNoneSentSnack(names)));
    expect(snacks.single, isNot(contains('0')));
  });

  testWidgets('"עדכון הכול": "עצירה" עוצרת אחרי התוסף הנוכחי', (tester) async {
    final controller = await seedRecording(
      tester,
      catalog: threeUpdates(),
      installed: threeInstalled,
    );
    final (messages: snacks, :restore) = captureSnacks();

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.updateAllButton));
    await tester.pump();
    await tester.pump();
    expect(controller.delivered, ['a']);
    expect(plugins.isUpdatingAll, isTrue);

    await tester.tap(find.widgetWithText(ActionButton, t.syncStopButton));
    await tester.pump();
    expect(find.text(t.updateAllStoppingLabel), findsOneWidget);
    expect(button(tester, t.syncStopButton).onPressed, isNull);

    await tester.pump(pluginUpdateDeliverySpacing);
    await tester.pump();
    expect(controller.delivered, ['a']);
    expect(plugins.isUpdatingAll, isFalse);
    restore();
    expect(snacks.single, contains(t.updateAllStoppedSnack(1)));
  });

  testWidgets('"עדכון הכול": עצירה יחד עם כישלון — ההודעה אומרת שנעצר',
      (tester) async {
    final controller = await seedRecording(
      tester,
      catalog: threeUpdates(),
      installed: threeInstalled,
    );
    final hold = Completer<void>();
    controller.holds['a'] = hold;
    controller.failingIds.add('a');
    final (messages: snacks, :restore) = captureSnacks();

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.updateAllButton));
    await tester.pump();
    await tester.tap(find.widgetWithText(ActionButton, t.syncStopButton));
    await tester.pump();
    hold.complete();
    await tester.pump();
    await tester.pump();

    expect(controller.delivered, ['a']);
    expect(plugins.isUpdatingAll, isFalse);
    restore();
    expect(snacks.single, contains(t.updateAllStoppedPrefix));
    expect(snacks.single, contains(t.updateAllNoneSentSnack('ראשון')));
  });

  testWidgets('"עדכון הכול" הוא משימה ארוכה: רענון וייצוא מושבתים, ויש הסבר',
      (tester) async {
    await seedRecording(
      tester,
      catalog: threeUpdates(),
      installed: threeInstalled,
    );

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.updateAllButton));
    await tester.pump();
    await tester.pump();

    expect(plugins.isUpdatingAll, isTrue);
    expect(button(tester, t.refreshButton).onPressed, isNull);
    expect(find.text(t.actionsBlockedUpdatingAll), findsOneWidget);

    // ממשיך גם כשהמסך נסגר: הריצה בקונטרולר, ונעצרת רק ב"עצירה".
    await tester.pumpWidget(const SizedBox());
    await tester.pump(pluginUpdateDeliverySpacing);
    await tester.pump();
    await tester.pump(pluginUpdateDeliverySpacing);
    await tester.pump();
    expect(plugins.isUpdatingAll, isFalse);
  });

  testWidgets('משימה אחרת רצה: "עדכון הכול" וההתקנה מושבתים, ויש הסבר',
      (tester) async {
    final controller = await seedRecording(
      tester,
      catalog: threeUpdates(),
      installed: threeInstalled,
    );

    await pumpScreen(
      tester,
      PluginsScreen(controller: plugins, busyElsewhere: true),
    );
    await tester.pumpAndSettle();

    expect(find.text(t.actionsBlockedElsewhere), findsOneWidget);
    expect(button(tester, t.updateAllButton).onPressed, isNull);
    for (final element in find.byType(PluginAction).evaluate()) {
      expect((element.widget as PluginAction).blocked, isTrue);
    }
    expect(controller.delivered, isEmpty);
  });

  testWidgets('"בשליחה" לכל תוסף בנפרד — סיום אחד אינו מחזיר את השני',
      (tester) async {
    final controller = await seedRecording(
      tester,
      catalog: [
        storePlugin('a', name: 'ראשון', manifestId: 'id-a', version: '2.0'),
        storePlugin('b', name: 'שני', manifestId: 'id-b', version: '3.0'),
      ],
      installed: {'id-a': '1.0', 'id-b': '1.0'},
    );
    final holdA = Completer<void>();
    final holdB = Completer<void>();
    controller.holds['a'] = holdA;
    controller.holds['b'] = holdB;

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(ActionButton, t.updateToButton('2.0')));
    await tester.pump();
    await tester
        .tap(find.widgetWithText(ActionButton, t.updateToButton('3.0')));
    await tester.pump();
    final sending = find.byWidgetPredicate(
      (w) => w is ActionButton && w.isLoading && w.text == t.sendingLabel,
    );
    expect(sending, findsNWidgets(2));

    holdA.complete();
    await tester.pump();
    await tester.pump();
    // A הסתיים — B עדיין בשליחה, ואי אפשר לשלוח אותו פעם שנייה.
    expect(sending, findsOneWidget);
    expect(find.text(t.updateToButton('3.0')), findsNothing);

    holdB.complete();
    await tester.pump();
    await tester.pump();
    expect(sending, findsNothing);
    expect(controller.delivered, ['a', 'b']);
  });

  testWidgets(
      'בזמן סנכרון: פעולות הכרטיסים, הדף ו"טעינה מחדש" מושבתות, עם הסבר',
      (tester) async {
    plugins.dispose();
    final fixture = FixturePlugins(tempDir.path);
    plugins = fixture;
    await seed(tester, catalog: [
      storePlugin('a', name: 'תוסף בכונן', withLocalFile: true),
    ]);
    fixture.fakeSyncing = true;

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pump();

    expect(find.text(t.actionsBlockedSyncing), findsOneWidget);
    expect(button(tester, t.installInOtzariaButton).onPressed, isNull);

    await tester.tap(find.text(stringsOf().pages.advancedTitle));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(button(tester, t.reloadButton).onPressed, isNull);

    // בלי pumpAndSettle: "רענון" מסתובב כל זמן הסנכרון.
    await tester.tap(find.widgetWithText(PluginStoreCard, 'תוסף בכונן'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(button(tester, t.installInOtzariaButton).onPressed, isNull);
    expect(button(tester, t.saveFileButton).onPressed, isNull);
    expect(find.text(t.actionsBlockedSyncing), findsOneWidget);
  });

  testWidgets('בזמן ייצוא: הפעולות מושבתות עם הסבר', (tester) async {
    await seed(tester, catalog: [
      storePlugin('a', name: 'תוסף בכונן', withLocalFile: true),
    ]);
    plugins.isExporting = true;

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pump();

    expect(find.text(t.actionsBlockedExporting), findsOneWidget);
    expect(button(tester, t.installInOtzariaButton).onPressed, isNull);
    plugins.isExporting = false;
  });

  testWidgets('עצירת סנכרון: "נעצר" רק כשהסנכרון באמת נעצר', (tester) async {
    final (messages: snacks, :restore) = captureSnacks();
    plugins.dispose();
    final fake = _OutcomeController(tempDir.path);
    plugins = fake;
    await seed(tester, catalog: [storePlugin('a')]);

    for (final (cancelled, expected) in [
      (false, t.syncDoneSnack(0, 1)),
      (true, t.syncStoppedSnack),
    ]) {
      snacks.clear();
      fake.next = PluginSyncOutcome(
        catalog: PluginCatalog(plugins: [storePlugin('a')]),
        fetched: 0,
        skipped: 1,
        cancelled: cancelled,
      );
      await pumpScreen(tester, PluginsScreen(controller: plugins));
      await tester.pump();
      await tester.tap(find.text(t.refreshButton));
      await tester.pump();
      // לחיצה על "עצירה" אחרי שהתוסף האחרון כבר ירד — הסנכרון הושלם.
      await tester.tap(find.text(t.syncStopButton));
      fake.release.complete();
      await tester.pump();
      await tester.pump();
      expect(snacks.single, contains(expected), reason: 'cancelled=$cancelled');
      fake.release = Completer<void>();
    }
    restore();
  });

  testWidgets('תגית נבחרת נשארת גלויה גם כשרשימת התגיות מקופלת',
      (tester) async {
    await seed(tester, catalog: [
      for (var i = 0; i < 20; i++) storePlugin('p$i', tags: ['תגית $i']),
    ]);
    // "תגית 9" היא האחרונה במיון, מעבר ל-14 הראשונות.
    plugins.setTagFilter('תגית 9');

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    expect(find.text(t.showMoreTags), findsOneWidget);
    final chip = tester.widget<StoreFilterChip>(
        find.widgetWithText(StoreFilterChip, 'תגית 9'));
    expect(chip.selected, isTrue);
  });

  testWidgets('שבב "חדש": מה שחדש בכניסה, וגם מה שהגיע בסנכרון באותה הרצה',
      (tester) async {
    final state = Directory(p.join(tempDir.path, 'state'))..createSync();
    plugins.dispose();
    plugins = PluginsModuleController(
      mirrorRootDir: tempDir.path,
      stateDir: state.path,
    );
    // הטעינה הראשונה במחשב קובעת נקודת התחלה — "א" אינו חדש.
    await seed(tester, catalog: [storePlugin('a', name: 'ותיק')]);
    await seed(tester, catalog: [
      storePlugin('a', name: 'ותיק'),
      storePlugin('b', name: 'חדש בכניסה'),
    ]);

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    Finder chipOn(String name) => find.descendant(
          of: find.widgetWithText(PluginStoreCard, name),
          matching: find.text(t.newChip),
        );
    expect(chipOn('ותיק'), findsNothing);
    expect(chipOn('חדש בכניסה'), findsOneWidget);

    // סנכרון שמביא תוסף נוסף — כמו `sync`, שמסתיים ב-`load`.
    await seed(tester, catalog: [
      storePlugin('a', name: 'ותיק'),
      storePlugin('b', name: 'חדש בכניסה'),
      storePlugin('c', name: 'הגיע בסנכרון'),
    ]);
    await tester.pumpAndSettle();
    expect(chipOn('חדש בכניסה'), findsOneWidget);
    expect(chipOn('הגיע בסנכרון'), findsOneWidget);

    // נרשמו כ"נראו" — מה שחדש כבר אינו ממתין לסימון.
    expect(plugins.newPlugins, isEmpty);
  });

  testWidgets('בלי אינטרנט וקובץ שלא ירד: "הקובץ לא ירד לכונן" במקום התקנה',
      (tester) async {
    await seed(tester, catalog: [storePlugin('a', name: 'תוסף שטרם ירד')]);

    await pumpScreen(
      tester,
      PluginsScreen(controller: plugins, online: false),
    );
    await tester.pumpAndSettle();

    expect(find.text(t.installInOtzariaButton), findsNothing);
    expect(find.text(t.fileNotOnDriveLabel), findsOneWidget);
    expect(find.text(t.noteNextDriveDownload), findsOneWidget);

    await openCard(tester, 'תוסף שטרם ירד');
    expect(find.text(t.fileMissingTitle), findsOneWidget);
    expect(find.text(t.installInOtzariaButton), findsNothing);
  });

  testWidgets('כשל טעינה אינו מוצג יחד עם "אין תוספים"', (tester) async {
    plugins.status = PluginsModuleStatus.error;
    plugins.errorMessage = 'catalog.json פגום';

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pump();

    expect(find.byType(InfoErrorRow), findsOneWidget);
    expect(find.text(t.emptyTitle), findsNothing);
  });

  testWidgets('מצב ריק בלי אינטרנט: "איך זה עובד?" פותח את העזרה',
      (tester) async {
    var helped = 0;
    await pumpScreen(
      tester,
      PluginsScreen(
        controller: plugins,
        online: false,
        onOpenHelp: () => helped++,
      ),
    );
    await tester.pump();

    expect(find.text(t.emptyTitle), findsOneWidget);
    await tester.tap(find.text(t.howItWorksButton));
    expect(helped, 1);
  });

  testWidgets('מספרי הגרסאות ברשימת הגרסאות LTR, והתאריכים בשם חודש',
      (tester) async {
    final plugin = StorePlugin.fromApi(const {
      'id': 'v',
      'name': 'עם גרסאות',
      'shortDescription': 'תקציר',
      'description': 'תיאור',
      'version': '2.0.0',
      'status': 'stable',
      'author': 'מחבר',
      'originalDate': '2026-10-18',
      'tags': <String>[],
      'supportsDirectInstall': true,
      'downloadUrl': '/api/plugins/v/download',
      'versions': [
        {'version': '2.0.0', 'releasedAt': '2026-10-18', 'isLatest': true},
        {'version': '1.0.0', 'releasedAt': '2026-09-01'},
      ],
    }, 'https://otzaria.org');
    await seed(tester, catalog: [plugin]);

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();
    await openCard(tester, 'עם גרסאות');

    final version = tester.widget<Text>(find.text('1.0.0'));
    expect(version.textDirection, TextDirection.ltr);
    // תאריך עברי כמו באתר — לא "18 באוקטובר 2026".
    expect(find.text('ז\' חשוון ה\'תשפ"ז'), findsOneWidget);
  });

  testWidgets('דיאלוג סיום הייצוא מוצג גם אחרי שעברו לדף תוסף', (tester) async {
    if (!StoreAppExportButton.isSupported) return;
    plugins.dispose();
    final exporting = _ExportController(tempDir.path);
    plugins = exporting;
    await seed(tester, catalog: [storePlugin('a', name: 'תוסף כלשהו')]);
    exporting
      ..storeApp = const MirroredStoreApp(
        release: StoreAppRelease(
          tagName: 'v2',
          version: 2,
          assetName: 'store.exe',
          downloadUrl: 'https://example.invalid/store.exe',
          sizeBytes: 1024,
        ),
        filePath: 'store.exe',
      )
      ..rememberedStoreDir = tempDir.path;

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();
    await tester.tap(find.text(stringsOf().pages.advancedTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.storeAppUpdateButton));
    await tester.pumpAndSettle();
    // "לעדכן שם?" — כן.
    await tester.tap(find.text(t.storeAppOverwriteConfirm));
    await tester.pump();
    expect(exporting.started, isTrue);

    // באמצע ההעתקה עוברים לדף תוסף — הכפתור שהתחיל את הזרימה יוצא מהעץ.
    await openCard(tester, 'תוסף כלשהו');
    expect(find.byType(StoreAppExportButton), findsNothing);

    exporting.finish(StoreAppExportOutcome(
      destinationDir: tempDir.path,
      appPath: p.join(tempDir.path, 'store.exe'),
      plugins: 1,
      files: 2,
      bytes: 2048,
    ));
    await tester.pumpAndSettle();
    expect(find.text(t.storeAppDoneTitle), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is CopyPathButton && w.path == tempDir.path,
      ),
      findsOneWidget,
    );
  });

  testWidgets('שם בכרטיס: עד שתי שורות בכרטיס, ובשורה — אחת עם השם המלא בריחוף',
      (tester) async {
    const name = 'תוסף עם שם ארוך מאוד שלא נכנס בשורה אחת של כרטיס צר בכלל';
    await seed(tester, catalog: [storePlugin('a', name: name)]);

    StoreHighlightText title() => tester.widget<StoreHighlightText>(
          find.byWidgetPredicate(
            (w) => w is StoreHighlightText && w.text == name,
          ),
        );

    // רחב — שתי עמודות של כרטיסים.
    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();
    expect(title().maxLines, 2);
    expect(tester.takeException(), isNull);

    // צר — עמודה אחת של שורות.
    await pumpScreen(
      tester,
      PluginsScreen(controller: plugins),
      size: const Size(700, 1600),
    );
    await tester.pumpAndSettle();
    expect(title().maxLines, 1);
    expect(find.byTooltip(name), findsOneWidget);
  });

  test('StoreBody.block עוטף כל תוכן כ-sliver ממורווח', () {
    // ה-API מקבל slivers בלבד; העוזרים הם הדרך היחידה להכניס תוכן רגיל.
    final sliver = StoreBody.block(const Text('x'), top: 4);
    expect(sliver, isA<SliverPadding>());
    expect((sliver as SliverPadding).child, isA<SliverToBoxAdapter>());
  });
}

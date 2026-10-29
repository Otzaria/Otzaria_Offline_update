import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:launcher_app/src/app_report/launcher_crash_session.dart';
import 'package:launcher_app/src/controllers/download_plan.dart';
import 'package:launcher_app/src/controllers/error_reports_controller.dart';
import 'package:launcher_app/src/controllers/launcher_update_controller.dart';
import 'package:launcher_app/src/controllers/library_module_controller.dart';
import 'package:launcher_app/src/controllers/otzaria_module_controller.dart';
import 'package:launcher_app/src/controllers/plugins_module_controller.dart';
import 'package:launcher_app/src/controllers/search_feedback_controller.dart';
import 'package:launcher_app/src/screens/app_shell.dart';
import 'package:launcher_app/src/screens/custom_apps/custom_apps_manage_page.dart';
import 'package:launcher_app/src/screens/custom_apps/custom_apps_settings_card.dart';
import 'package:launcher_app/src/screens/faq/faq_body.dart';
import 'package:launcher_app/src/screens/help/help_page.dart';
import 'package:launcher_app/src/screens/home/home_page.dart';
import 'package:launcher_app/src/screens/launcher/launcher_update_page.dart';
import 'package:launcher_app/src/screens/library_screen.dart';
import 'package:launcher_app/src/screens/otzaria_advanced_page.dart';
import 'package:launcher_app/src/screens/plugins/plugin_detail_view.dart';
import 'package:launcher_app/src/screens/plugins/plugins_screen.dart';
import 'package:launcher_app/src/screens/reports/reports_page.dart';
import 'package:launcher_app/src/screens/settings_screen.dart';
import 'package:launcher_app/src/screens/store_kit/store_kit.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:launcher_app/src/services/mirror_download_undo.dart';
import 'package:launcher_app/src/services/notices_seen_store.dart';
import 'package:launcher_app/src/services/sleep_inhibitor.dart';
import 'package:launcher_app/src/settings/app_settings.dart';
import 'package:launcher_app/src/settings/safer_mode.dart';
import 'package:launcher_app/src/settings/settings_controller.dart';
import 'package:launcher_app/src/shell/app_session.dart';
import 'package:launcher_app/src/shell/home_guidance.dart' show GuidanceItem;
import 'package:launcher_app/src/shell/shell_keys.dart';
import 'package:launcher_app/src/shell/shell_navigator.dart';
import 'package:launcher_app/src/shell/shell_tasks.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;
import 'package:plugins_manager/plugins_manager.dart';

import 'home_fixtures.dart';
import 'test_harness.dart';
import 'test_support.dart';

String _source(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _appShellSource() => _source('lib/src/screens/app_shell.dart');

/// הזרימות והדגלים יושבים ב-[AppSession]; המסגרת מממשת רק את הדיאלוגים.
String _appSessionSource() => _source('lib/src/shell/app_session.dart');

/// גוף מתודה: מהחתימה עד הסוגר שבהזחה של מתודת מחלקה.
String _methodBody(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, greaterThan(-1), reason: signature);
  return source.substring(start, source.indexOf('\n  }\n', start));
}

void main() {
  late Directory tempDir;
  late SettingsController settings;
  final shell = stringsOf().shell;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('app_shell_test');
    await AppLogger.init(tempDir.path);
    settings = SettingsController(dataDir: tempDir.path);
    // בדיקת התהליך הייתה מריצה כאן `tasklist` אמיתי (ואיתו טיימר תלוי
    // שמפיל את הבדיקה), ולכן היא מוזרקת.
    await settings.update(
        const AppSettings(personalModeAsked: true, autoCheckUpdates: false));
  });

  tearDown(() async {
    settings.dispose();
    AppLogger.resetForTest();
    await deleteTempDir(tempDir);
  });

  Future<void> pumpShell(
    WidgetTester tester, {
    RunningOtzariaLocator locator = const _NeverRunningLocator(),
    AppLanguage language = AppLanguage.hebrew,
    MemoryNoticesStore? notices,
    bool readOnly = false,
    bool driveFull = false,
    SleepInhibitor? sleepInhibitor,
    SearchFeedbackController? searchFeedback,
    ErrorReportsController? errorReports,
  }) async {
    useViewSize(tester, const Size(1400, 1000));
    await tester.pumpWidget(
      wrap(
        AppShell(
          dataDir: tempDir.path,
          settings: settings,
          runningLocator: locator,
          readOnly: readOnly,
          driveFull: driveFull,
          sleepInhibitor: sleepInhibitor,
          searchFeedback: searchFeedback,
          errorReports: errorReports,
          // ברירת המחדל: ההסבר החד-פעמי כבר הוצג, כדי שלא יצוץ באמצע בדיקה
          // שאינה שלו.
          noticesStore: notices ??
              MemoryNoticesStore(seen: {NoticesSeenStore.errorReportsIntro}),
          // כפתורי החלון מדברים עם ערוץ פלטפורמה שאינו קיים בבדיקות widget.
          showWindowButtons: false,
        ),
        language: language,
      ),
    );
    await tester.pump();
  }

  /// [IndexedStack] מסתיר את מי שאינו נבחר, ולכן החיפוש חייב לכלול offstage —
  /// אחרת "לא נמצא" היה יכול להיות "נבנה אבל מוסתר".
  Finder screen(Type type) => find.byType(type, skipOffstage: false);

  AppSession sessionOf(WidgetTester tester) =>
      (tester.state(find.byType(AppShell)) as dynamic).session as AppSession;

  ShellNavigator navigatorOf(WidgetTester tester) =>
      (tester.state(find.byType(AppShell)) as dynamic).navigator
          as ShellNavigator;

  /// מקטע נפתח מהאריח שלו בבית, וההגדרות — מגלגל השיניים.
  Future<void> open(WidgetTester tester, ShellSection section) async {
    if (section == ShellSection.settings) {
      await tester.tap(find.byTooltip(shell.settingsTooltip));
    } else {
      await tester.tap(find.byKey(ShellKeys.tile(section)));
    }
    await tester.pump();
  }

  /// חזרה בכפתור שבראש דף המשנה המוצג.
  Future<void> back(WidgetTester tester) async {
    await tester.tap(find.byTooltip(shell.backTooltip));
    await tester.pump();
  }

  testWidgets('מניעת שינה נשמרת עד סיום כל הפעולות ומשוחררת בסגירה',
      (tester) async {
    var acquired = 0;
    var released = 0;
    final inhibitor = SleepInhibitor(acquire: () {
      acquired++;
      return () => released++;
    });
    await pumpShell(tester, sleepInhibitor: inhibitor, readOnly: true);
    final home = sessionOf(tester);
    expect(acquired, 0);

    void changed() => settings.notifyListeners();

    home.library.status = LibraryModuleStatus.updating;
    changed();
    expect(inhibitor.isActive, isTrue);
    home.otzaria.status = OtzariaModuleStatus.installing;
    changed();
    home.library.status = LibraryModuleStatus.error;
    changed();
    expect(acquired, 1);
    expect(released, 0);
    home.otzaria.status = OtzariaModuleStatus.error;
    changed();
    expect(released, 1);

    home.library.downloadStatus = MirrorDownloadStatus.downloading;
    changed();
    expect(inhibitor.isActive, isTrue);
    home.library.downloadStatus = MirrorDownloadStatus.done;
    changed();
    expect(inhibitor.isActive, isFalse);

    home.otzaria.downloadStatus = OtzariaDownloadStatus.downloading;
    changed();
    home.otzaria.downloadStatus = OtzariaDownloadStatus.error;
    changed();
    expect(inhibitor.isActive, isFalse);

    home.launcherUpdate.status = LauncherUpdateStatus.downloading;
    changed();
    expect(inhibitor.isActive, isTrue);
    home.launcherUpdate.status = LauncherUpdateStatus.error;
    changed();
    expect(inhibitor.isActive, isFalse);

    home.launcherUpdate.status = LauncherUpdateStatus.installing;
    changed();
    expect(inhibitor.isActive, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(inhibitor.isActive, isFalse);
    expect(acquired, 5);
    expect(released, 5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('בעלייה נבנה דף הבית בלבד — שאר המסכים כלל לא בעץ', (
    tester,
  ) async {
    await pumpShell(tester);

    expect(screen(HomePage), findsOneWidget);
    // חנות התוספים היא היקרה מכולן (רשת כרטיסים עם תמונה לכל תוסף), וזו
    // בדיוק הסיבה שה-IndexedStack אינו בונה את כל ילדיו.
    expect(screen(PluginsScreen), findsNothing);
    expect(screen(OtzariaAdvancedPage), findsNothing);
    expect(screen(LibraryScreen), findsNothing);
    expect(screen(SettingsScreen), findsNothing);
  });

  testWidgets('"?" בשורת הכותרת פותח את דף העזרה בגוף, בלי דו-שיח', (
    tester,
  ) async {
    await pumpShell(tester);

    expect(screen(HelpPage), findsNothing);
    await tester.tap(find.byTooltip(shell.helpTooltip));
    // בדיקות הרקע של המסגרת מסובבות מחוונים, ולכן לא pumpAndSettle.
    await tester.pump();

    expect(navigatorOf(tester).section, ShellSection.help);
    expect(screen(HelpPage), findsOneWidget);
    expect(screen(FaqBody), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    // דף משנה: חזרה ופירור "בית › שאלות נפוצות", והכלי "?" מסומן.
    expect(find.byTooltip(shell.backTooltip), findsOneWidget);
    expect(find.text(stringsOf().faq.title), findsAtLeastNWidgets(2));
    expect(
      find.descendant(
        of: find.byType(AppTitleBar),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.selected == true,
        ),
      ),
      findsOneWidget,
    );

    await back(tester);
    expect(navigatorOf(tester).section, ShellSection.home);
  });

  testWidgets('"עריכת השאלות הנפוצות" בהגדרות פותח את העזרה במצב עריכה', (
    tester,
  ) async {
    await pumpShell(tester);
    await open(tester, ShellSection.settings);

    await tester.scrollUntilVisible(
      find.text(stringsOf().pages.advancedTitle),
      300,
      scrollable: find
          .descendant(
            of: find.byType(SettingsScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pump();
    await tester.tap(find.text(stringsOf().pages.advancedTitle));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('settings.faqEdit')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('settings.faqEdit')));
    await tester.pump();
    await tester.pump();

    expect(navigatorOf(tester).section, ShellSection.help);
    expect(find.text(stringsOf().faq.editTitle), findsOneWidget);

    // חזרה מהעריכה מחזירה להגדרות שמהן באו, ולא לבית.
    await back(tester);
    await tester.pump();
    expect(navigatorOf(tester).section, ShellSection.settings);
    expect(screen(SettingsScreen), findsOneWidget);

    // והעריכה הסתיימה ביציאה: "?" פותח את השאלות.
    await tester.tap(find.byTooltip(shell.helpTooltip));
    await tester.pump();
    await tester.pump();
    expect(navigatorOf(tester).section, ShellSection.help);
    expect(find.text(stringsOf().faq.editTitle), findsNothing);
    expect(find.text(stringsOf().faq.editButton), findsOneWidget);
  });

  testWidgets('גלגל השיניים בשורת הכותרת פותח את ההגדרות ומסומן', (
    tester,
  ) async {
    await pumpShell(tester);

    await open(tester, ShellSection.settings);

    expect(screen(SettingsScreen), findsOneWidget);
    // דף משנה בתוך הגוף: חזרה ופירור "בית › הגדרות".
    expect(find.byTooltip(shell.backTooltip), findsOneWidget);
    expect(find.text(shell.breadcrumbHome), findsOneWidget);
    expect(
      find.text(stringsOf().settings.title),
      findsAtLeastNWidgets(2),
    );
    expect(
      find.descendant(
        of: find.byType(AppTitleBar),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.selected == true,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('מסך שנכנסים אליו נבנה, ונשאר בעץ גם אחרי מעבר משם', (
    tester,
  ) async {
    await pumpShell(tester);

    await open(tester, ShellSection.plugins);
    expect(screen(PluginsScreen), findsOneWidget);
    // שאר המסכים עדיין לא נבנו — הבנייה היא לפי ביקור, לא מראש.
    expect(screen(LibraryScreen), findsNothing);

    await back(tester);
    // נשאר בעץ עם המצב שלו — זו כל הנקודה של IndexedStack מדורג.
    expect(screen(PluginsScreen), findsOneWidget);
    expect(screen(HomePage), findsOneWidget);
  });

  testWidgets('מסך מוסתר אינו מריץ אנימציות — רק המוצג מקבל טיקרים', (
    tester,
  ) async {
    await pumpShell(tester);
    bool ticking(Type type) =>
        TickerMode.valuesOf(tester.element(screen(type))).enabled;

    expect(ticking(HomePage), isTrue);

    await open(tester, ShellSection.plugins);
    expect(ticking(PluginsScreen), isTrue);
    expect(ticking(HomePage), isFalse);

    await back(tester);
    expect(ticking(HomePage), isTrue);
    expect(ticking(PluginsScreen), isFalse);
  });

  testWidgets('"אוצריא — מתקדם": בחירת תיקייה מרעננת את התוספים', (
    tester,
  ) async {
    await pumpShell(tester);
    final s = sessionOf(tester);
    await open(tester, ShellSection.otzaria);

    final page =
        tester.widget<OtzariaAdvancedPage>(screen(OtzariaAdvancedPage));
    // תיקיית התוספים נגזרת מהתקנה שאומצה — אותה פונקציה של הקונטרולר.
    expect(page.onInstallAdopted, s.plugins.refreshInstalled);
    expect(page.otzaria, same(s.otzaria));
    expect(page.saferMode, same(s.saferMode));
  });

  testWidgets('כל חמשת המסכים נבנים אחרי ביקור בכולם', (tester) async {
    await pumpShell(tester);

    for (final section in [
      ShellSection.otzaria,
      ShellSection.library,
      ShellSection.plugins,
      ShellSection.settings,
    ]) {
      await open(tester, section);
      if (section != ShellSection.settings) await back(tester);
    }

    expect(screen(HomePage), findsOneWidget);
    expect(screen(OtzariaAdvancedPage), findsOneWidget);
    expect(screen(LibraryScreen), findsOneWidget);
    expect(screen(PluginsScreen), findsOneWidget);
    expect(screen(SettingsScreen), findsOneWidget);
  });

  testWidgets('אין דיאלוג בעלייה — גם לא זה של עדכוני התוספים', (tester) async {
    await pumpShell(tester);
    await tester.pump();

    // הדיאלוג של "יש עדכונים לתוספים" יושב ב-PluginsScreen, שלא נבנה עדיין;
    // זו התוצאה הנלווית המכוונת של הבנייה המדורגת.
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(screen(PluginsScreen), findsNothing);
  });

  group('הסבר חד-פעמי על דיווחי הטעויות — הודעה בבית', () {
    final t = stringsOf().errorReports;

    /// הנוסח נכתב לדו-שיח; בהודעה הפסקאות מתחברות לאחת.
    String oneParagraph(String text) => text.replaceAll('\n\n', ' ');

    /// הטעינה של "מה כבר הוצג" אסינכרונית — שני פריימים מספיקים לה.
    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump();
    }

    testWidgets('הרצה ראשונה: הודעה בבית, בלי דיאלוג, ונרשם רק ב"הבנתי"', (
      tester,
    ) async {
      final notices = MemoryNoticesStore();
      await pumpShell(tester, notices: notices);
      await settle(tester);

      expect(find.byKey(ShellKeys.reportsIntroNotice), findsOneWidget);
      expect(find.text(t.introDialogTitle), findsOneWidget);
      expect(find.text(oneParagraph(t.introDialogContent)), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(notices.marked, isEmpty);

      await tester.tap(find.text(t.introDialogConfirm));
      await settle(tester);

      expect(find.byKey(ShellKeys.reportsIntroNotice), findsNothing);
      expect(notices.marked, [NoticesSeenStore.errorReportsIntro]);
    });

    testWidgets('כונן נעול: בנוסח שמסביר שאי אפשר לאסוף', (tester) async {
      await pumpShell(tester, notices: MemoryNoticesStore(), readOnly: true);
      await settle(tester);

      expect(
        find.text(oneParagraph(t.introDialogContentReadOnly)),
        findsOneWidget,
      );
      expect(find.text(oneParagraph(t.introDialogContent)), findsNothing);
    });

    testWidgets('כונן מלא: בנוסח שמבקש לפנות מקום', (tester) async {
      await pumpShell(
        tester,
        notices: MemoryNoticesStore(),
        readOnly: true,
        driveFull: true,
      );
      await settle(tester);

      expect(
        find.text(oneParagraph(t.introDialogContentReadOnlyDriveFull)),
        findsOneWidget,
      );
      expect(
        find.text(oneParagraph(t.introDialogContentReadOnly)),
        findsNothing,
      );
    });

    testWidgets('כבר הוצג במחשב הזה → אין הודעה', (tester) async {
      await pumpShell(tester);
      await settle(tester);

      expect(find.byKey(ShellKeys.reportsIntroNotice), findsNothing);
      expect(find.text(t.introDialogTitle), findsNothing);
    });
  });

  testWidgets('סרגל הזהות מציג את שם התוכנה ואת הסמל', (tester) async {
    await pumpShell(tester);

    expect(find.text(shell.appTitle), findsOneWidget);
    final logo = tester.widget<Image>(find.byType(Image).first);
    expect(logo.semanticLabel, shell.otzariaLogoLabel);
    // מחווני המצב שהיו בסרגל העליון הוסרו — הם יושבים בדף הבית.
    expect(find.byType(StatusChip), findsWidgets);
  });

  testWidgets('בעלייה אין שום חיווי שגיאה, והבדיקה ברשת כבויה', (tester) async {
    await pumpShell(tester);
    await tester.pump();

    expect(find.byType(InfoErrorRow), findsNothing);
    expect(find.text(stringsOf().common.error), findsNothing);
    // עוד לא ידוע אם יש אינטרנט — לא "אין חיבור" ולא תקלה.
    expect(find.text(stringsOf().guide.eyebrowThisComputer), findsOneWidget);
  });

  testWidgets('checkOnline שנכשל (אין רשת) אינו מציג שגיאה אלא "אין חיבור"', (
    tester,
  ) async {
    // הבדיקה הקלה היא מטא-דאטה בלבד, וכשל בה הוא תוצאה **תקינה** —
    // המחשב המנותק הוא מקרה השימוש המרכזי של התוכנה.
    HttpOverrides.global = NoNetworkHttpOverrides();
    addTearDown(() => HttpOverrides.global = null);
    // שמירת ההגדרות כותבת לדיסק — חייבת לרוץ מחוץ ל-fake-async.
    await tester.runAsync(
      () => settings.update(
          const AppSettings(personalModeAsked: true, autoCheckUpdates: true)),
    );

    await pumpShell(tester);
    // ההצצה לתוספים ממתינה לבדיקה המקומית — היא שקובעת לאילו גרסאות אוצריא
    // לשאול על בילדי התוספים. זו סדרת קריאות `dart:io`, וכל אחת מתקדמת רק
    // ב-runAsync בעוד המיקרו-משימות שלה נשטפות ב-pump שאחריו.
    final offline = find.text(stringsOf().guide.eyebrowOffline);
    for (var i = 0; i < 40 && offline.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(seconds: 1));
    }

    expect(offline, findsOneWidget);
    expect(find.byType(InfoErrorRow), findsNothing);
    expect(find.text(stringsOf().common.error), findsNothing);
    // לא נמצא עדכון ברשת, ולכן גם אין הצעה להוריד.
    expect(find.text(stringsOf().guide.downloadButton), findsNothing);
  });

  testWidgets('אוצריא שנסגרה מזוהה בזמן שהלאנצ\'ר פתוח — בלי הפעלה מחדש שלו', (
    tester,
  ) async {
    // הבדיקה המקומית כבויה כאן בכוונה: היא קוראת מהדיסק ולא מסתיימת בתוך
    // ה-fake-async, ואז מצב התהליך היה נקבע רק אחרי סיום הבדיקה.
    await tester.runAsync(
      () => settings.update(
          const AppSettings(personalModeAsked: true, autoCheckUpdates: false)),
    );
    final locator = _MutableLocator(isRunning: true);

    await pumpShell(tester, locator: locator);
    await tester.pump();
    expect(sessionOf(tester).otzariaIsRunning, isTrue);

    // המשתמש סוגר את אוצריא. הרענון המחזורי אמור להבחין בזה מעצמו.
    locator.isRunning = false;
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();

    expect(sessionOf(tester).otzariaIsRunning, isFalse);

    // ומכאן הטיימר צריך להיכבות: אחרת `tasklist` (~300ms) היה רץ כל 3
    // שניות לנצח, על אוצריא שכבר סגורה.
    final probesWhenClosed = locator.probes;
    await tester.pump(const Duration(seconds: 12));
    expect(locator.probes, probesWhenClosed);
  });

  test('כל סיום של משימה ארוכה מעיר את ההצעה שנדחתה', () {
    final source = _appSessionSource();

    expect(
      _methodBody(source, 'void _rebuild() {'),
      contains('_offers.resume()'),
    );
    expect(
      source,
      contains('_update(() => _elevationPending = false);\n'
          '        _offers.resume();'),
    );
    expect(source, contains('Future<bool> closeOtzaria() => _offers.holdFor('));
    expect(source, contains('_downloads.isPreparing'));
    expect(source, contains('blocked: () => _blockedByReadOnly()'));
  });

  group('דף פרטי תוסף — נתיב בנווט', () {
    /// הקטלוג מוצב ישירות: הטעינה מהדיסק ממתינה לבדיקה המקומית של אוצריא,
    /// שאינה מסתיימת בתוך ה-fake-async של המסגרת.
    void givePlugin(WidgetTester tester) {
      sessionOf(tester).plugins
        ..plugins = [
          StorePlugin.fromApi(const {
            'id': 'a',
            'name': 'תוסף בדיקה',
            'shortDescription': 'תקציר',
            'description': 'תיאור',
            'version': '1.0.0',
            'status': 'stable',
            'author': 'מחבר',
            'originalDate': '2026-04-02',
            'tags': <String>[],
            'isPinned': false,
            'supportsDirectInstall': true,
            'downloadUrl': '/api/plugins/a/download',
          }, 'https://otzaria.org'),
        ]
        ..installed = const {}
        ..status = PluginsModuleStatus.ready;
    }

    Future<void> openDetails(WidgetTester tester) async {
      await open(tester, ShellSection.plugins);
      await tester.tap(find.byType(StoreItemCard).first);
      await tester.pump();
    }

    testWidgets('חזרה אחת בלבד: הראש חוזר לרשימה, ו-Esc גם', (tester) async {
      await pumpShell(tester);
      givePlugin(tester);
      final nav = navigatorOf(tester);

      await openDetails(tester);
      expect(nav.current, const PluginDetailRoute('a'));
      expect(screen(PluginDetailView), findsOneWidget);
      // חזרה אחת בלבד, והפירור הוא "בית › תוספים › התוסף".
      expect(find.byTooltip(shell.backTooltip), findsOneWidget);
      expect(find.text('תוסף בדיקה'), findsWidgets);

      await back(tester);
      expect(nav.section, ShellSection.plugins);
      expect(nav.current, const SectionRoute(ShellSection.plugins));
      expect(screen(PluginDetailView), findsNothing);

      await tester.tap(find.byType(StoreItemCard).first);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(nav.current, const SectionRoute(ShellSection.plugins));
      expect(screen(PluginDetailView), findsNothing);
    });

    testWidgets('תוסף שנמחק בזמן שפרטיו פתוחים — חוזרים לרשימה, וחזרה אחת לבית',
        (tester) async {
      await pumpShell(tester);
      givePlugin(tester);
      final nav = navigatorOf(tester);
      await openDetails(tester);
      expect(nav.current, const PluginDetailRoute('a'));

      final plugins = sessionOf(tester).plugins..plugins = const [];
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      plugins.notifyListeners();
      await tester.pump();

      expect(nav.current, const SectionRoute(ShellSection.plugins));
      expect(screen(PluginDetailView), findsNothing);
      await back(tester);
      expect(nav.current, const HomeRoute());
    });

    testWidgets('"תוספים" בפירור מחזיר לרשימה', (tester) async {
      await pumpShell(tester);
      givePlugin(tester);

      await openDetails(tester);
      await tester.tap(find.text(stringsOf().guide.tilePlugins).last);
      await tester.pump();
      expect(
        navigatorOf(tester).current,
        const SectionRoute(ShellSection.plugins),
      );
    });

    testWidgets('יציאה לבית מהפרטים — בכניסה הבאה מוצגת הרשימה', (
      tester,
    ) async {
      await pumpShell(tester);
      givePlugin(tester);

      await openDetails(tester);
      await tester.tap(find.text(shell.breadcrumbHome));
      await tester.pump();
      expect(navigatorOf(tester).section, ShellSection.home);

      await open(tester, ShellSection.plugins);
      expect(screen(PluginDetailView), findsNothing);
    });

    testWidgets('בזמן סנכרון החזרה והפירור נשארים פעילים', (tester) async {
      await pumpShell(tester);
      final plugins = sessionOf(tester).plugins
        ..status = PluginsModuleStatus.syncing;
      addTearDown(() => plugins.status = PluginsModuleStatus.idle);

      await open(tester, ShellSection.plugins);
      expect(find.byTooltip(shell.backTooltip).hitTestable(), findsOneWidget);
      expect(find.text(shell.breadcrumbHome).hitTestable(), findsOneWidget);

      await back(tester);
      expect(navigatorOf(tester).section, ShellSection.home);
    });
  });

  group('הבית בכונן מוגן', () {
    testWidgets('אין "בדוק עכשיו"; דיווחים שבכונן נאמרים, נעולים', (
      tester,
    ) async {
      final outbox = Directory(p.join(tempDir.path, 'reports', 'outbox'))
        ..createSync(recursive: true);
      File(p.join(outbox.path, 'r1.json')).writeAsStringSync('{}');

      await pumpShell(tester, readOnly: true);
      await tester.runAsync(sessionOf(tester).errorReports.refreshOutbox);
      await tester.pump();

      expect(find.byKey(ShellKeys.checkNow), findsNothing);
      final tile = find.byKey(ShellKeys.tile(ShellSection.reports));
      expect(tile, findsOneWidget);
      expect(
        find.descendant(
          of: tile,
          matching: find.text(stringsOf().guide.chipReportsLocked),
        ),
        findsOneWidget,
      );

      await open(tester, ShellSection.reports);
      expect(
        find.text(stringsOf().guide.reportsLockedNote(driveFull: false)),
        findsOneWidget,
      );
    });

    testWidgets('בכונן כתיב יש "בדוק עכשיו" ליד "נבדק ב-"', (tester) async {
      await pumpShell(tester);
      expect(find.byKey(ShellKeys.checkNow), findsOneWidget);
    });
  });

  group('דפי שלב 3 בתוך הגוף', () {
    testWidgets('עדכון הכלי הזה: דף משנה עם פירור, וחזרה לבית', (
      tester,
    ) async {
      await pumpShell(tester);
      await navigatorOf(tester).select(ShellSection.launcher);
      await tester.pump();

      expect(find.byType(LauncherUpdatePage), findsOneWidget);
      expect(find.text(stringsOf().pages.selfCrumb), findsOneWidget);
      await back(tester);
      expect(navigatorOf(tester).section, ShellSection.home);
    });

    testWidgets('דף הדיווחים נפתח גם כשאין מה לשלוח — מהניווט', (
      tester,
    ) async {
      await pumpShell(tester);
      expect(find.byKey(ShellKeys.tile(ShellSection.reports)), findsNothing);
      await navigatorOf(tester).select(ShellSection.reports);
      await tester.pump();
      expect(find.byType(ReportsPage), findsOneWidget);
      expect(find.text(stringsOf().pages.repNothingTitle), findsOneWidget);
    });
  });

  group('החלפת שפה במסך הפתיחה', () {
    testWidgets('נשמרת בהגדרות, והממשק עובר ל-LTR בלי לאבד את המסגרת', (
      tester,
    ) async {
      useViewSize(tester, const Size(1000, 800));
      await tester.runAsync(
        () => settings.update(
          settings.settings.copyWith(
            languagePreference: AppLanguagePreference.hebrew,
          ),
        ),
      );
      final opened = <ShellSection>[];
      Future<void>? saved;
      await tester.pumpWidget(
        ListenableBuilder(
          listenable: settings,
          builder: (context, _) => wrap(
            HomePage(
              model: homeScenario('first'),
              actions: HomeActions(
                onToggleLanguage: () => saved = toggleAppLanguage(settings),
                onOpenSection: opened.add,
              ),
            ),
            language: settings.settings.language,
          ),
        ),
      );
      final pageState = tester.element(find.byType(HomePage));
      expect(Directionality.of(pageState), TextDirection.rtl);

      // מחכים לשמירה עצמה: קריאה בזמן ה-rename שלה נכשלת בווינדוס ב-OS Error 5.
      await tester.runAsync(() async {
        await tester.tap(find.byKey(ShellKeys.welcomeLanguage));
        await saved;
      });
      await tester.pump();

      expect(settings.settings.language, AppLanguage.english);
      expect(
        Directionality.of(tester.element(find.byType(HomePage))),
        TextDirection.ltr,
      );
      expect(
        find.text(stringsOf(AppLanguage.english).guide.welcomeTitle),
        findsOneWidget,
      );
      expect(
        tester.widget<ActionButton>(find.byKey(ShellKeys.welcomeLanguage)).text,
        stringsOf(AppLanguage.english).settings.languageHebrew,
      );

      // נשמר בקובץ: טעינה חדשה של ההגדרות קוראת אנגלית.
      final reloaded = SettingsController(dataDir: tempDir.path);
      addTearDown(reloaded.dispose);
      await tester.runAsync(reloaded.load);
      expect(reloaded.settings.language, AppLanguage.english);
    });
  });

  group('ניווט בתוך הגוף', () {
    testWidgets('אריח פותח דף משנה עם פירור, וחזרה מחזירה לבית', (
      tester,
    ) async {
      await pumpShell(tester);
      final nav = navigatorOf(tester);

      await open(tester, ShellSection.library);
      expect(nav.section, ShellSection.library);
      expect(screen(LibraryScreen), findsOneWidget);
      expect(find.text(shell.breadcrumbHome), findsOneWidget);
      expect(find.text(stringsOf().guide.tileLibrary), findsWidgets);

      await back(tester);
      expect(nav.section, ShellSection.home);
      expect(find.byKey(ShellKeys.hero), findsOneWidget);
    });

    // כשבדיקת התוכנה נכשלה לא ידוע אם היא בכונן — אין "בכונן אין את התוכנה".
    testWidgets('דף הספרייה: בדיקת התוכנה שנכשלה אינה "אין בכונן"', (
      tester,
    ) async {
      await pumpShell(tester);
      await open(tester, ShellSection.library);
      final s = sessionOf(tester);
      bool? installable() =>
          tester.widget<LibraryScreen>(screen(LibraryScreen)).appInstallable;

      s.otzaria.status = OtzariaModuleStatus.upToDate;
      settings.notifyListeners();
      await tester.pump();
      expect(installable(), isFalse);

      s.otzaria.status = OtzariaModuleStatus.error;
      settings.notifyListeners();
      await tester.pump();
      expect(installable(), isNull);
    });

    testWidgets('"בית" בפירור מחזיר לבית', (tester) async {
      await pumpShell(tester);
      await open(tester, ShellSection.plugins);

      await tester.tap(find.text(shell.breadcrumbHome));
      await tester.pump();

      expect(navigatorOf(tester).section, ShellSection.home);
    });

    testWidgets('Esc הוא חזרה, ומהבית אינו עושה דבר', (tester) async {
      await pumpShell(tester);
      final nav = navigatorOf(tester);
      await open(tester, ShellSection.otzaria);
      expect(nav.section, ShellSection.otzaria);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(nav.section, ShellSection.home);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(nav.section, ShellSection.home);
      expect(nav.stack, [const HomeRoute()]);
    });

    testWidgets('בועת "חזרה" אינה נשארת מעל הבית: במקטע מוסתר אין בועות', (
      tester,
    ) async {
      await pumpShell(tester);
      await open(tester, ShellSection.settings);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      final backButton = find.byTooltip(shell.backTooltip);
      await mouse.moveTo(tester.getCenter(backButton));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text(shell.backTooltip), findsOneWidget);

      // לחיצה שנמשכת: הבועה מתחילה לדעוך, והמקטע מוסתר באמצע הדעיכה — בלי
      // טיקרים היא הייתה נשארת קפואה וחצי שקופה.
      await mouse.down(tester.getCenter(backButton));
      await tester.pump(const Duration(milliseconds: 30));
      await mouse.up();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(navigatorOf(tester).section, ShellSection.home);
      expect(find.text(shell.backTooltip, skipOffstage: false), findsNothing);
      final hidden = find.byWidgetPredicate(
        (w) => w is Tooltip && w.message == shell.backTooltip,
        skipOffstage: false,
      );
      expect(TooltipVisibility.of(tester.element(hidden)), isFalse);

      await open(tester, ShellSection.settings);
      expect(TooltipVisibility.of(tester.element(backButton)), isTrue);
    });

    testWidgets('Esc בשדה טקסט יוצא מהשדה במקום לחזור לבית', (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        wrap(Material(child: TextField(focusNode: focus))),
      );
      expect(leaveTextField(), isFalse);
      focus.requestFocus();
      await tester.pump();
      expect(leaveTextField(), isTrue);
      await tester.pump();
      expect(focus.hasFocus, isFalse);
      expect(leaveTextField(), isFalse);
    });

    testWidgets('Esc אינו יוצא משכבת משימה', (tester) async {
      await pumpShell(tester);
      final nav = navigatorOf(tester);
      await open(tester, ShellSection.plugins);
      nav.showTask();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(nav.showsTask, isTrue);
      nav.endTask();
    });

    testWidgets('גלגל השיניים מסומן רק בהגדרות', (tester) async {
      await pumpShell(tester);
      Finder selectedTool() => find.descendant(
            of: find.byType(AppTitleBar),
            matching: find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.selected == true,
            ),
          );

      await open(tester, ShellSection.library);
      expect(selectedTool(), findsNothing);
      await back(tester);
      await open(tester, ShellSection.settings);
      expect(selectedTool(), findsOneWidget);
    });

    testWidgets('אין אריח תוכנות נוספות ואין אריח דיווחים כשאין מה להציג', (
      tester,
    ) async {
      await pumpShell(tester);

      expect(find.byKey(ShellKeys.tile(ShellSection.otzaria)), findsOneWidget);
      expect(find.byKey(ShellKeys.tile(ShellSection.library)), findsOneWidget);
      expect(find.byKey(ShellKeys.tile(ShellSection.plugins)), findsOneWidget);
      expect(
        find.byKey(ShellKeys.tile(ShellSection.customApps)),
        findsNothing,
      );
      expect(find.byKey(ShellKeys.tile(ShellSection.reports)), findsNothing);
    });
  });

  // Custom-app management writes to mirror/apps on the drive (issue #25).
  for (final readOnly in [true, false]) {
    testWidgets('settings custom-apps card with readOnly=$readOnly', (
      tester,
    ) async {
      await pumpShell(tester, readOnly: readOnly);
      await open(tester, ShellSection.settings);

      final card = find.byType(CustomAppsSettingsCard, skipOffstage: false);
      expect(card, findsOneWidget);
      await tester.ensureVisible(card);
      await tester.pump();
      // שורה ולא כפתור: בכונן מוגן היא אינה לחיצה, והפירוט אומר למה.
      final row = tester.widget<AppRow>(
        find.descendant(of: card, matching: find.byType(AppRow)),
      );
      expect(row.onTap == null, readOnly);
      expect(
        find.descendant(
          of: card,
          matching: find.text(
            stringsOf().readOnlyDrive.customAppsManageDisabled,
          ),
        ),
        readOnly ? findsOneWidget : findsNothing,
      );
    });
  }

  testWidgets('settings custom-apps card on a full drive asks to free space', (
    tester,
  ) async {
    await pumpShell(tester, readOnly: true, driveFull: true);
    await open(tester, ShellSection.settings);

    final card = find.byType(CustomAppsSettingsCard, skipOffstage: false);
    await tester.ensureVisible(card);
    await tester.pump();
    final t = stringsOf().readOnlyDrive;
    expect(
      find.descendant(
        of: card,
        matching: find.text(t.customAppsManageDisabledDriveFull),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.text(t.customAppsManageDisabled),
      ),
      findsNothing,
    );
  });

  testWidgets('"ניהול" בהגדרות פותח את דף הניהול בתוך הגוף, וחזרה מחזירה', (
    tester,
  ) async {
    await pumpShell(tester);
    await open(tester, ShellSection.settings);
    final nav = navigatorOf(tester);

    final card = find.byType(CustomAppsSettingsCard, skipOffstage: false);
    await tester.ensureVisible(card);
    await tester.pump();
    await tester.tap(
      find.descendant(of: card, matching: find.byType(AppRow)),
    );
    await tester.pump();

    expect(nav.current, const CustomAppsManageRoute());
    expect(screen(CustomAppsManagePage), findsOneWidget);
    expect(screen(SettingsScreen), findsNothing);
    // הפירור: "בית › הגדרות › ניהול התוכנות".
    expect(
      find.text(stringsOf().customApps.manageDialogTitle),
      findsWidgets,
    );

    await back(tester);
    expect(nav.section, ShellSection.settings);
    expect(screen(CustomAppsManagePage), findsNothing);
    expect(screen(SettingsScreen), findsOneWidget);
  });

  testWidgets('ביטול הורדה מנקה את שתי תיקיות המראה של התוספים', (
    tester,
  ) async {
    await pumpShell(tester);

    final dynamic state = tester.state(find.byType(AppShell));
    final byComponent =
        state.session.downloadMirrorDirs as Map<MirrorComponent, List<String>>;
    final dirs = byComponent[MirrorComponent.plugins]!;
    final mirrorRoot = p.join(tempDir.path, 'mirror');
    final pluginDirs = PluginsManager.mirrorDirsIn(mirrorRoot);

    expect(pluginDirs, hasLength(2));
    expect(dirs, containsAll(pluginDirs));

    await tester.runAsync(() async {
      final undo = await MirrorDownloadUndo.capture(dirs);
      final written = [
        for (final dir in pluginDirs) File(p.join(dir, 'new', 'asset.bin')),
      ];
      for (final file in written) {
        file.parent.createSync(recursive: true);
        file.writeAsStringSync('x');
      }

      await undo.revert();

      for (final file in written) {
        expect(file.existsSync(), isFalse, reason: file.path);
      }
    });
  });

  group('מסכי המשימה — שכבה בגוף', () {
    final task = stringsOf().task;

    testWidgets('משימה נפתחת מעל הגוף, ושורת הכותרת נשארת', (tester) async {
      await pumpShell(tester);
      final s = sessionOf(tester);
      final nav = navigatorOf(tester);
      expect(find.byKey(ShellKeys.taskLayer), findsNothing);

      s.tasks.prepareDownload();
      await tester.pump();
      expect(nav.showsTask, isTrue);
      expect(find.byKey(ShellKeys.taskLayer), findsOneWidget);
      expect(find.text(task.preparingTitle), findsOneWidget);
      expect(find.byType(AppTitleBar), findsOneWidget);
      // הבית שמתחת אינו מקבל מיקוד ואינו מריץ טיקרים.
      final home = find.byType(HomePage, skipOffstage: false);
      expect(
        tester
            .widget<TickerMode>(find
                .ancestor(of: home, matching: find.byType(TickerMode))
                .first)
            .enabled,
        isFalse,
      );
      s.tasks.abandonDownload();
      await tester.pump();
      expect(nav.showsTask, isFalse);
      expect(find.byKey(ShellKeys.taskLayer), findsNothing);
    });

    testWidgets('Esc וגלגל השיניים אינם יוצאים ממשימה רצה', (tester) async {
      await pumpShell(tester);
      final s = sessionOf(tester);
      final nav = navigatorOf(tester);
      s.tasks.downloadRunning(const [MirrorComponent.app]);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(nav.showsTask, isTrue);
      await tester.tap(find.byTooltip(shell.settingsTooltip));
      await tester.pump();
      expect(nav.showsTask, isTrue);
      expect(nav.isBuilt(ShellSection.settings), isFalse);

      s.tasks.downloadDone();
      await tester.pump();
      expect(find.text(task.doneTitle), findsOneWidget);
      await tester.tap(find.byKey(ShellKeys.taskPrimary));
      await tester.pump();
      expect(s.tasks.hasTask, isFalse);
      expect(nav.showsTask, isFalse);
      expect(nav.section, ShellSection.home);
    });

    testWidgets('בזמן משימה רצה גלגל השיניים מושבת למראה, ובסיום חוזר',
        (tester) async {
      await pumpShell(tester);
      final s = sessionOf(tester);
      bool toolsEnabled() =>
          tester.widget<AppTitleBar>(find.byType(AppTitleBar)).toolsEnabled;
      expect(toolsEnabled(), isTrue);
      s.tasks.downloadRunning(const [MirrorComponent.app]);
      await tester.pump();
      expect(toolsEnabled(), isFalse);
      s.tasks.downloadDone();
      await tester.pump();
      expect(toolsEnabled(), isTrue);
    });

    testWidgets('באנר המנהל במסך הכשל נגזר מהמצב, לא מדגל הכשל',
        (tester) async {
      await pumpShell(tester);
      final s = sessionOf(tester);
      s.tasks
        ..startUpdateHere(const [GuidanceItem.library])
        ..updateFailed(const UpdateFailure(
          GuidanceItem.library,
          message: 'Access is denied',
          needsElevation: true,
        ));
      await tester.pump();
      // הדגל בכשל לבדו אינו מספיק: restartElevated היה חוזר בשקט.
      expect(find.byKey(ShellKeys.taskElevation), findsNothing);

      s.library.needsElevation = true;
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      s.library.notifyListeners();
      await tester.pump();
      expect(
        find.byKey(ShellKeys.taskElevation),
        Platform.isWindows ? findsOneWidget : findsNothing,
      );
    });

    testWidgets('מסך המשימה: התוכנה מובילה לבית, הספרייה והתוספים לדף שלהם',
        (tester) async {
      await pumpShell(tester);
      final s = sessionOf(tester);
      final nav = navigatorOf(tester);

      // נפתח מדף הספרייה — "לבית" אינו רק סגירת השכבה שמעליו.
      Future<void> finish(void Function() end) async {
        await open(tester, ShellSection.plugins);
        s.tasks.startUpdateHere(const [GuidanceItem.app]);
        end();
        await tester.pump();
      }

      await finish(() {
        s.tasks
          ..stageStopped(GuidanceItem.app, StageOutcome.stoppedWaiting)
          ..updateDone();
      });
      expect(find.text(task.stoppedWaitingTitle), findsOneWidget);
      await tester.tap(find.byKey(ShellKeys.taskPrimary));
      await tester.pump();
      expect(nav.stack, [const HomeRoute()]);

      await finish(() {
        s.tasks
          ..stageStopped(GuidanceItem.app, StageOutcome.stillOpen)
          ..updateCancelledByUser();
      });
      await tester.tap(find.byKey(ShellKeys.taskPrimary));
      await tester.pump();
      expect(nav.stack, [const HomeRoute()]);

      await finish(
        () => s.tasks.updateFailed(const UpdateFailure(GuidanceItem.app)),
      );
      expect(find.byKey(ShellKeys.taskSecondary), findsNothing);
      await tester.tap(find.text(task.backHome));
      await tester.pump();
      expect(nav.stack, [const HomeRoute()]);

      await finish(
        () => s.tasks.updateFailed(const UpdateFailure(GuidanceItem.library)),
      );
      await tester.tap(find.byKey(ShellKeys.taskSecondary));
      await tester.pump();
      expect(nav.section, ShellSection.library);
    });

    // `checkNow` מריץ את `checkAll`, ושם גם התקנה אוטומטית בלי דיאלוג.
    testWidgets('"בדוק שוב" בשגיאת התוכנה בודק את התוכנה בלבד', (tester) async {
      await tester.runAsync(
        () => settings.update(
          const AppSettings(
              personalModeAsked: true,
              autoCheckUpdates: false,
              autoInstall: true),
        ),
      );
      await pumpShell(tester);
      final s = sessionOf(tester);
      // הגיבור "בודק" כל עוד התוספים נטענים — כאן הם כבר נטענו.
      // הבדיקה של העלייה קודם — אחרת "בדוק שוב" מצטרף אליה.
      for (var i = 0; i < 100 && s.isCheckingNow; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      expect(s.isCheckingNow, isFalse);
      final startupCheck = s.lastCheckedAt;
      s.plugins.status = PluginsModuleStatus.ready;
      s.otzaria
        ..status = OtzariaModuleStatus.error
        ..errorMessage = 'broken';
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      s.otzaria.notifyListeners();
      await tester.pump();
      expect(find.byKey(ShellKeys.heroAppError), findsOneWidget);

      await tester.tap(find.byKey(ShellKeys.heroPrimary));
      for (var i = 0;
          i < 100 &&
              (s.otzaria.status == OtzariaModuleStatus.error ||
                  s.otzaria.status == OtzariaModuleStatus.checking);
          i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      expect(s.otzaria.status, isNot(OtzariaModuleStatus.error));
      // לא `checkNow`: הוא רושם "נבדק", ומריץ התקנה אוטומטית.
      expect(s.lastCheckedAt, startupCheck);
      expect(s.isCheckingNow, isFalse);
      expect(s.otzaria.lastInstallResult, isNull);
    });

    testWidgets('השאלה על החיפוש החכם — "חזרה" סוגרת בלי להוריד',
        (tester) async {
      await pumpShell(tester);
      final s = sessionOf(tester);
      final answer = s.tasks.askBeforeDownload();
      await tester.pump();
      expect(find.text(task.semanticTitle), findsOneWidget);
      await tester.tap(find.text(task.back));
      await tester.pump();
      expect(await answer, isNull);
      expect(find.byKey(ShellKeys.taskLayer), findsNothing);
    });

    test('הגיבור פותח את מסכי המשימה, לא את הדיאלוגים הישנים', () {
      final source = _appShellSource();
      expect(source, contains('onInstallHere: _updateHere,'));
      expect(source, contains('onUpdateHere: _updateHere,'));
      expect(source,
          contains('onDownload: () => unawaited(_session.downloadAll()),'));
      expect(source, contains('onShowProgress: _showProgress,'));
      expect(source, isNot(contains('onCancelDownload')));
      expect(
        source,
        contains(
            'void _updateHere() => unawaited(_session.updateHere(_hereItems));'),
      );
      expect(source, isNot(contains('installOtzariaHere')));
      expect(source, isNot(contains('HomeFlowDeps')));
    });

    test('ההורדה מדווחת למסך המשימה דרך ShellTasks', () {
      final session = _appSessionSource();
      final host = session.substring(
        session.indexOf('class _SessionDownloadHost'),
        session.indexOf('class _SessionUpdateHost'),
      );
      // "מתכונן" נפתח רק ב-downloadAll — ניקוי שהסתיים אחרי "ביטול" לא פותח אותו שוב.
      expect(host, isNot(contains('prepareDownload')));
      expect(host, contains('_session.tasks.askBeforeDownload()'));
      expect(host, contains('_session.tasks.downloadRunning('));
      expect(host, contains('flow.activeComponents,'));
      expect(host, contains('_session.tasks.downloadCancelled('));
      expect(host,
          contains('s.tasks.downloadDone(skipped: skipped, notes: notes)'));
      expect(host, contains('!skipped.contains(MirrorComponent.library)'));
      expect(host, contains('classifyDownloadFailure('));
      // הביטול עצמו לא השתנה: אישור אזהרה ואז `requestCancel` (שמחזיר את הכונן).
      final cancel = _methodBody(session, 'Future<void> cancelDownload()');
      expect(cancel, contains('prompts.confirmCancelDownload()'));
      expect(cancel, contains('_downloads.requestCancel()'));
    });
  });

  test('Ctrl+R ו-F5 מרעננים, ולא בזמן משימה ארוכה', () {
    final source = _appShellSource();
    expect(source, contains('LogicalKeyboardKey.keyR, control: true'));
    expect(source, contains('LogicalKeyboardKey.f5'));
    expect(
      'LogicalKeyboardKey.f5): () =>\n'
              '            unawaited(_session.refreshFromKeyboard())'
          .allMatches(source)
          .length,
      1,
    );
    expect(
      'control: true): () =>\n'
              '            unawaited(_session.refreshFromKeyboard())'
          .allMatches(source)
          .length,
      1,
    );
    final body = _methodBody(
      _appSessionSource(),
      'Future<void> refreshFromKeyboard()',
    );
    expect(body, contains('if (longTaskRunning || tasks.isRunning) return;'));
    // גם הצעת הדיווחים אינה קופצת מעל מסך משימה.
    final offers = _appSessionSource().substring(
      _appSessionSource().indexOf('late final ReportOfferCoordinator _offers'),
      _appSessionSource().indexOf('bool get isDownloading =>'),
    );
    expect(offers, contains('tasks.isRunning'));
  });

  group('חיווט הזרימות שהוצאו מהמסגרת', () {
    final source = _appSessionSource();
    final shellSource = _appShellSource();

    String bodyOf(String signature, String until) {
      final start = source.indexOf(signature);
      expect(start, greaterThan(-1), reason: signature);
      final end = source.indexOf(until, start);
      expect(end, greaterThan(start), reason: until);
      return source.substring(start, end);
    }

    test('ההתקנה האוטומטית נשענת על בדיקת תהליך טרייה ועל חסימת היציאה', () {
      final wiring = bodyOf(
        'late final AutoInstallFlow _autoInstall',
        'late final ReportOfferCoordinator _offers',
      );
      expect(wiring, contains('isOtzariaRunning: refreshProcessState,'));
      expect(wiring, contains('isDownloading: () => _downloads.isDownloading'));
      expect(wiring, contains('exitPending: () => exitPending'));
      expect(wiring, isNot(contains('otzariaIsRunning')));
    });

    // "סגור ועדכן" נמחק: "עדכון כאן" עצמו מבקש לסגור את אוצריא (ראו
    // screen_flows_test), והדילוג נאמר בפתיח של פס "אוצריא פתוחה כרגע".
    test('דילוג בגלל אוצריא פתוחה נשמר לפס, ואין כפתור שמתחרה בגיבור', () {
      final body = bodyOf(
        'Future<void> _autoInstallIfEnabled() async {',
        'downloadMirrorDirs',
      );
      expect(body, contains('_autoInstall.run('));
      expect(body, contains('settings.settings.autoInstall'));
      expect(body, contains('_autoInstallSkipped = skippedWhileRunning'));
      expect(body, isNot(contains('useWizard: true')));
      expect(source, isNot(contains('closeAndUpdate')));
      expect(shellSource, isNot(contains('closeAndUpdate')));
    });

    // ההתנהגות עצמה — app_session_test, קבוצת checkNow.
    test('"בדוק עכשיו" ו"בדוק שוב" מחווטים ל-checkNow; Ctrl+R/F5 מקומיים', () {
      expect(shellSource,
          contains('onRecheck: () => unawaited(_session.checkNow())'));
      expect(
        'unawaited(_session.refreshFromKeyboard())'.allMatches(shellSource),
        hasLength(2),
      );
    });

    test('"לא עכשיו" מסתיר את פס המנהל עד סוף ההרצה', () {
      final offers = source.substring(
        source.indexOf('bool get offersElevation =>'),
        source.indexOf('Future<void> restartElevated()'),
      );
      expect(offers, contains('!_elevationDismissed'));
      expect(
        offers,
        contains('void dismissElevation() => '
            '_update(() => _elevationDismissed = true);'),
      );
      expect(shellSource,
          contains('onDismissElevation: _session.dismissElevation'));
    });

    test('תורים ישנים: הודעה בבית עד "הבנתי", גם בלי מה לאסוף', () {
      final recount =
          _methodBody(source, 'Future<void> recountReportsToCollect() async {');
      expect(recount, contains('_errorReports.unmigratedLegacy.isNotEmpty'));
      expect(
        recount,
        contains('_notices.hasSeen(NoticesSeenStore.legacyReportsNotice)'),
      );
      final dismiss = _methodBody(
        source,
        'Future<void> dismissLegacyReportsNotice() async {',
      );
      expect(
        dismiss,
        contains('_notices.markSeen(NoticesSeenStore.legacyReportsNotice)'),
      );
    });

    test('איסוף מכפתור "איסוף" — בלי דו-שיח, וגם לא זה של התורים הישנים', () {
      final collect =
          _methodBody(shellSource, 'Future<void> _collectReports()');
      // הזרימה עצמה אינה פותחת דו-שיח (נבדק ב-error_reports_test); כאן —
      // שהיא מקבלת את מה שהגילוי הציג, וסופרת מחדש אחרי הלחיצה.
      expect(collect, contains('collectReportsToDrive('));
      expect(collect, contains('disclosedReports: s.errorReportsToCollect'));
      expect(
        collect,
        isNot(contains('searchFeedback:')),
      );
      expect(collect, contains('await s.recountReportsToCollect()'));
    });

    test('תוסף שהגיע בזמן שהמשתמש בחנות אינו "חדש" בבית', () {
      expect(shellSource, contains('..addListener(_onSessionChangeInStore)'));
      expect(
        shellSource,
        contains('..removeListener(_onSessionChangeInStore)'),
      );
      final body = _methodBody(shellSource, 'void _onSessionChangeInStore()');
      expect(body, contains('_navigator.section == ShellSection.plugins'));
      expect(body, contains('_session.markPluginsVisited()'));
    });

    // רענון אמיתי שאינו מוצא דבר דורש רשת; הזרימה נבדקת ב-shell_flows_test.
    test('רענון שרץ נמסר כ"בדקתי שוב", ובלעדיו — "לפי הבדיקה הקודמת"', () {
      final refresh = bodyOf(
        'Future<bool> _refreshStaleOnlineChecks(AppSettings s)',
        'Future<DownloadRollback> _captureDownloadRollback()',
      );
      expect(refresh, contains('if (!stale.any) return false;'));
      expect(refresh, contains('return true;'));
      final host = bodyOf(
        'class _SessionDownloadHost implements MirrorDownloadHost',
        'class _SessionLauncherHost',
      );
      expect(
        host,
        contains(
          'rechecked ? FoundNothing.rechecked : FoundNothing.earlierCheck',
        ),
      );
    });

    test('"בדוק עכשיו" מחזיר להצעה קבצים שנכשלו, לפני הבדיקה ברשת', () {
      final body = bodyOf(
        'Future<void> checkNow()',
        'Future<void> _asCheck(',
      );
      expect(
        body.indexOf('_library.forgetDownloadFailures()'),
        allOf(isNonNegative, lessThan(body.indexOf('await checkOnline()'))),
      );
    });

    test('הבדיקה המקוונת שלפני ההורדה מרעננת רק את מה שהתיישן', () {
      final body = bodyOf(
        'Future<bool> _refreshStaleOnlineChecks(AppSettings s)',
        'Future<DownloadRollback> _captureDownloadRollback()',
      );
      expect(body, contains('StaleOnlineChecks.of('));
      expect(body, contains('if (stale.app) _otzaria.checkOnline()'));
      expect(body, contains('if (stale.library) _library.checkOnline()'));
      expect(body, contains('if (stale.plugins) _plugins.checkOnline()'));
      expect(body, contains('_plugins.storeAppCheckedAt'));
      expect(body, contains('_library.onlineCheckError'));
    });

    test("ההורדה נחסמת בפעולה ארוכה ובהורדת הלאנצ'ר, והניקוי נדחה בה", () {
      final host = bodyOf(
        'class _SessionDownloadHost implements MirrorDownloadHost',
        'class _SessionLauncherHost',
      );
      expect(
        host,
        contains(
          '_session.longTaskRunning || _session._launcherUpdate.isDownloading',
        ),
      );
      expect(
        host,
        contains(
          'bool get launcherDownloading => '
          '_session._launcherUpdate.isDownloading',
        ),
      );
      expect(host, contains('_session._refreshStaleOnlineChecks(s)'));
      expect(host, contains('_session._sweepMirrorJunk()'));
    });

    test('ההחלפה של קובץ ההרצה נחסמת בכל פעולה שיציאה קוטעת', () {
      final start = source
          .indexOf('class _SessionLauncherHost implements LauncherUpdateHost');
      expect(start, greaterThan(-1));
      final host = source.substring(start);
      expect(host, contains('wouldInterrupt => _session.exitWouldInterrupt'));
      expect(host, contains('_session._blockedByReadOnly()'));
      expect(host, contains('isReadOnly => _session.readOnly'));
      final flow = bodyOf(
        'late final LauncherUpdateFlow _launcherFlow',
        'late final AutoInstallFlow _autoInstall',
      );
      expect(flow, contains('downloads: _downloads,'));
    });

    test('ביטול משחזר את המראה ומרענן את המודולים', () {
      final body = bodyOf(
        'Future<DownloadRollback> _captureDownloadRollback()',
        'void _rebuild()',
      );
      expect(body, contains('CancelledDownloadRollback.capture('));
      expect(body, contains('mirrorDirs: downloadMirrorDirs'));
    });
  });

  group('משוב החיפוש: איסוף והעלאה ברקע, בלי ממשק', () {
    late _ShellFeedback transport;
    late List<String> snacks;
    DebugPrintCallback? previousPrint;

    setUp(() {
      transport = _ShellFeedback();
      snacks = [];
      previousPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        if (message?.startsWith('UiSnack') ?? false) snacks.add(message!);
      };
    });

    // נבדק בסוף גוף הבדיקה, לפני tearDown — לכן משוחזר כאן.
    void restorePrint() => debugPrint = previousPrint!;

    SearchFeedbackController feedbackFor(_MutableLocator locator) =>
        SearchFeedbackController(
          transport: transport,
          resolveSource: () async {
            final probe = await locator.probe();
            return probe.isRunning || !transport.consent ? null : 'source';
          },
        );

    Future<void> settle(WidgetTester tester, bool Function() done) async {
      for (var i = 0; i < 40 && !done(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    void expectSilent(WidgetTester tester) {
      restorePrint();
      expect(find.byType(AlertDialog), findsNothing);
      expect(snacks, isEmpty);
      expect(find.text(stringsOf().pages.repSendStoredButton(2)), findsNothing);
      expect(
        find.textContaining(stringsOf().errorReports.uploadPendingOffline(2)),
        findsNothing,
      );
      expect(
        find.textContaining(stringsOf().errorReports.uploadPendingUnchecked(2)),
        findsNothing,
      );
    }

    testWidgets('בעלייה, גם כשהבדיקה האוטומטית כבויה: נאסף ומועלה בלי לחיצה', (
      tester,
    ) async {
      final locator = _MutableLocator(isRunning: false);
      await pumpShell(
        tester,
        locator: locator,
        searchFeedback: feedbackFor(locator),
      );
      await settle(tester, () => transport.uploads > 0);

      expect(transport.collections, 1);
      expect(transport.uploads, 1);
      expect(settings.settings.autoCheckUpdates, isFalse);
      expect(transport.sent, 2);
      expectSilent(tester);
      final notice = find.byKey(ShellKeys.searchFeedbackCollectedNotice);
      expect(notice, findsOneWidget);
      expect(find.text(stringsOf().errorReports.searchFeedbackCollected),
          findsOneWidget);
      expect(tester.widget<NoticeBanner>(notice).actions, isEmpty);
      expect(find.descendant(of: notice, matching: find.byType(ActionButton)),
          findsNothing);
    });

    testWidgets('אינו ממתין להסבר הדיווחים הפתוח ואינו מופיע בו', (
      tester,
    ) async {
      final locator = _MutableLocator(isRunning: false);
      await pumpShell(
        tester,
        locator: locator,
        notices: MemoryNoticesStore(),
        searchFeedback: feedbackFor(locator),
      );
      await settle(tester, () => transport.uploads > 0);

      restorePrint();
      expect(find.byKey(ShellKeys.reportsIntroNotice), findsOneWidget);
      expect(transport.sent, 2);
      expect(snacks, isEmpty);
    });

    testWidgets('בלי הסכמה באוצריא אין איסוף ואין העלאה', (tester) async {
      transport.consent = false;
      final locator = _MutableLocator(isRunning: false);
      await pumpShell(
        tester,
        locator: locator,
        searchFeedback: feedbackFor(locator),
      );
      await settle(tester, () => false);

      expect(transport.collections, 0);
      expect(transport.uploads, 0);
      expect(transport.sourceEvents, 2);
      expectSilent(tester);
      expect(find.byKey(ShellKeys.searchFeedbackCollectedNotice), findsNothing);
    });

    testWidgets('אוצריא פתוחה: ממתין, ואוסף מעצמו כשהיא נסגרת', (tester) async {
      final locator = _MutableLocator(isRunning: true);
      await pumpShell(
        tester,
        locator: locator,
        searchFeedback: feedbackFor(locator),
      );
      await settle(tester, () => false);
      expect(transport.collections, 0);
      expect(transport.sourceEvents, 2);

      locator.isRunning = false;
      await tester.pump(const Duration(seconds: 4));
      await settle(tester, () => transport.uploads > 0);

      expect(transport.collections, 1);
      expect(transport.sent, 2);
      expectSilent(tester);
    });

    testWidgets('כונן לקריאה בלבד: אין איסוף, העלאה או כתיבה, ואין הודעה', (
      tester,
    ) async {
      transport.carriedEvents = 3;
      final locator = _MutableLocator(isRunning: false);
      await pumpShell(
        tester,
        locator: locator,
        readOnly: true,
        searchFeedback: feedbackFor(locator),
      );
      await settle(tester, () => false);
      locator.isRunning = true;
      await tester.runAsync(
        () => sessionOf(tester).otzaria.refreshRunningState(force: true),
      );
      await tester.pump();
      locator.isRunning = false;
      await tester.pump(const Duration(seconds: 4));
      await settle(tester, () => false);

      expect(transport.collections, 0);
      expect(transport.uploads, 0);
      restorePrint();
      expect(transport.counts, 0);
      expect(snacks, isEmpty);
    });

    testWidgets('אין רשת: הנתונים נשמרים, וניסיון חוזר רק אחרי ההשהיה', (
      tester,
    ) async {
      transport.online = false;
      final locator = _MutableLocator(isRunning: false);
      await pumpShell(
        tester,
        locator: locator,
        searchFeedback: feedbackFor(locator),
      );
      await settle(tester, () => transport.uploads > 0);
      expect(transport.uploads, 1);
      expect(transport.carriedEvents, 2);

      final notice = find.byKey(ShellKeys.searchFeedbackCollectedNotice);
      expect(notice, findsOneWidget);
      expect(tester.widget<NoticeBanner>(notice).actions, isEmpty);

      await tester.pump(const Duration(minutes: 1));
      await settle(tester, () => false);
      expect(transport.uploads, 1);

      transport.online = true;
      await tester.pump(const Duration(minutes: 2));
      await settle(tester, () => transport.uploads > 1);
      expect(transport.uploads, 2);
      expect(transport.carriedEvents, 0);
      expectSilent(tester);
      expect(notice, findsOneWidget);
    });

    testWidgets('פירוק המסגרת מבטל את הניסיון החוזר', (tester) async {
      transport.online = false;
      final locator = _MutableLocator(isRunning: false);
      await pumpShell(
        tester,
        locator: locator,
        searchFeedback: feedbackFor(locator),
      );
      await settle(tester, () => transport.uploads > 0);
      await tester.pumpWidget(const SizedBox.shrink());
      transport.online = true;
      await tester.pump(const Duration(hours: 1));
      restorePrint();
      expect(transport.uploads, 1);
      expect(transport.closed, isTrue);
    });
  });

  group('דיווחי הטעויות לצד משוב החיפוש', () {
    testWidgets('משוב לבדו לא מוסיף אריח דיווחים או הודעת שליחה',
        (tester) async {
      final transport = _ShellFeedback();
      final locator = _MutableLocator(isRunning: false);
      final queue = _ShellReportQueue();
      final reports = ErrorReportsController(
          outbox: queue.outbox, resolveQueue: () async => queue);
      final feedback = SearchFeedbackController(
          transport: transport, resolveSource: () async => 'source');
      await pumpShell(tester,
          locator: locator, errorReports: reports, searchFeedback: feedback);
      for (var i = 0; i < 40 && transport.sent == 0; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(transport.sent, 2);
      expect(reports.outboxCount, 0);
      expect(sessionOf(tester).reportsToCollect, 0);
      expect(find.byKey(ShellKeys.tile(ShellSection.reports)), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('העלאת משוב ברקע אינה חוסמת ספירת דיווחים', (tester) async {
      final transport = _ShellFeedback()..uploadGate = Completer<void>();
      final locator = _MutableLocator(isRunning: false);
      final queue = _ShellReportQueue()..pending = 2;
      final reports = ErrorReportsController(
          outbox: queue.outbox, resolveQueue: () async => queue);
      final feedback = SearchFeedbackController(
          transport: transport, resolveSource: () async => 'source');
      await pumpShell(tester,
          locator: locator, errorReports: reports, searchFeedback: feedback);
      for (var i = 0; i < 40 && transport.uploads == 0; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(transport.uploads, 1);
      await tester.runAsync(() => sessionOf(tester).recountReportsToCollect());
      await tester.pump();
      expect(sessionOf(tester).reportsToCollect, 2);
      expect(sessionOf(tester).exitWouldInterrupt, isFalse);
      transport.uploadGate!.complete();
      await tester.runAsync(() => feedback.stopAndWait());
      await tester.pump();
      expect(transport.uploads, 1);
    });
  });

  group('פעולות שיציאה מהתהליך קוטעת', () {
    final source = _appSessionSource();
    final start = source.indexOf('bool get longTaskRunning');
    final getters = source.substring(
      start,
      source.indexOf('Future<void> installLauncherUpdate()', start),
    );

    test('הגטרים נמצאים', () {
      expect(start, greaterThan(-1));
      expect(getters, contains('bool get exitWouldInterrupt'));
    });

    test('כוללות התקנה, למידה והורדה של תוכנות מותאמות וייצוא החנות', () {
      expect(getters, contains('_customApps.isBusy'));
      expect(getters, contains('_customApps.isLearning'));
      expect(getters, contains('_customApps.isDownloadingAll'));
      expect(getters, contains('_plugins.isExporting'));
    });

    test('כוללות את ההמתנה ל-UAC ואת החלפת קובץ ההרצה', () {
      expect(
        getters,
        contains(
          'bool get exitPending =>'
          ' _elevationPending || _launcherUpdate.isInstalling;',
        ),
      );
      expect(
        getters.substring(
          0,
          getters.indexOf('bool get pluginSyncBlockedElsewhere'),
        ),
        contains('exitPending;'),
      );
    });

    test('כוללות איסוף והעלאה של דיווחים', () {
      expect(getters, contains('_errorReports.isCollecting'));
      expect(getters, contains('_errorReports.isUploading'));
      final interrupt = getters.substring(
        getters.indexOf('bool get exitWouldInterrupt'),
      );
      expect(interrupt, isNot(contains('_searchFeedback')));
    });
  });

  group('חסימת הסנכרון והייצוא בזמן פעולה אחרת', () {
    final source = _appSessionSource();
    final start = source.indexOf('bool get pluginSyncBlockedElsewhere');
    final getter = source.substring(
      start,
      source.indexOf('bool get exitPending', start),
    );

    test('הגטר כולל הורדה, החלפת מסד, התקנת אוצריא ותוכנות מותאמות', () {
      expect(start, greaterThan(-1));
      expect(getter, contains('_downloads.isDownloading'));
      expect(getter, contains('_library.isApplying'));
      expect(getter, contains('LibraryModuleStatus.updating'));
      expect(getter, contains('OtzariaModuleStatus.installing'));
      expect(getter, contains('_customApps.isBusy'));
    });

    test('מסך התוספים מקבל אותו', () {
      final shellSource = _appShellSource();
      final screen =
          shellSource.substring(shellSource.indexOf('PluginsScreen('));
      final args =
          screen.substring(0, screen.indexOf('ShellSection.reports =>'));
      expect(args, contains('busyElsewhere: s.pluginSyncBlockedElsewhere'));
    });
  });

  group('הפעלה מחדש כמנהל — פס בבית', () {
    final source = _appSessionSource();
    final shellSource = _appShellSource();
    String restartBody() =>
        _methodBody(source, 'Future<void> restartElevated() async {');
    final offers = source.substring(
      source.indexOf('bool get canRestartElevated =>'),
      source.indexOf('Future<void> restartElevated()'),
    );

    test('הפס מוצע רק ב-Windows, כשצריך, ולא בזמן פעולה שיציאה קוטעת', () {
      expect(offers, contains('Platform.isWindows'));
      expect(offers, contains('_needsElevation'));
      expect(offers, contains('!_elevationPending'));
      expect(offers, contains('!exitWouldInterrupt'));
      expect(shellSource, isNot(contains('offerElevation')));
    });

    test('לחיצה בזמן פעולה ארוכה אינה מפעילה מחדש', () {
      final body = restartBody();
      final busy = body.indexOf('if (exitWouldInterrupt)');
      final restart = body.indexOf('Elevation.restartElevated()');
      expect(busy, greaterThan(-1));
      expect(busy, lessThan(restart));
      expect(body.substring(busy, restart), contains('t.busyNotice'));
    });

    test('משוב ברקע נעצר לפני בדיקת החסימה', () {
      final body = restartBody();
      final stop = body.indexOf('_searchFeedback.stopAndWait()');
      expect(stop, greaterThan(-1));
      expect(stop, lessThan(body.indexOf('if (exitWouldInterrupt)')));
    });

    test('מסמנת המתנה ל-UAC סביב restartElevated ומאפסת בכשל', () {
      final body = restartBody();
      final pending = body.indexOf('_update(() => _elevationPending = true)');
      final restart = body.indexOf('Elevation.restartElevated()');
      expect(pending, greaterThan(-1));
      expect(pending, lessThan(restart));
      final reset = body.indexOf('_elevationPending = false', restart);
      expect(reset, greaterThan(restart));
      expect(body.substring(restart, reset), contains('finally'));
    });

    test(
      'ממשק המסגרת וההורדה חסומים בזמן ההמתנה ל-UAC או החלפת קובץ ההרצה',
      () {
        expect(shellSource, contains('absorbing: _session.exitPending'));
        expect(shellSource, contains('excluding: _session.exitPending'));
        final guard = source.substring(
          source.indexOf('bool get longTaskRunning'),
          source.indexOf('bool get exitPending'),
        );
        expect(guard, contains('exitPending'));
        final host = source.substring(
          source.indexOf('class _SessionDownloadHost'),
          source.indexOf('class _SessionLauncherHost'),
        );
        expect(host, contains('bool get isBlocked =>'));
        expect(host, contains('_session.longTaskRunning'));
        final wait = shellSource.substring(
          shellSource.indexOf('late final DialogQueue _dialogs'),
          shellSource.indexOf('void initState()'),
        );
        expect(
          wait,
          contains(
            '_session.exitPending || '
            '!(ModalRoute.of(context)?.isCurrent ?? true)',
          ),
        );
      },
    );

    test('הבית נבנה מחדש גם בסיום איסוף או העלאה של דיווחים', () {
      expect('..addListener(_onReportsChange)'.allMatches(source).length, 2);
      expect('removeListener(_onReportsChange)'.allMatches(source).length, 2);
      final listener = _methodBody(source, 'void _onReportsChange()');
      expect(listener, isNot(contains('notifyListeners')));
      expect(
        shellSource,
        contains(
          'Listenable.merge([\n'
          '        s.errorReports,\n'
          '        if (s.appReports != null) s.appReports!,',
        ),
      );
    });

    test('הבית נבנה מחדש כשאיש הקשר שבעזרה משתנה', () {
      expect(
        shellSource,
        contains('        if (s.appReports != null) s.appReports!,\n'
            '        s.faq,\n'),
      );
    });
  });

  group('מצב סייפר — הכניסה להגדרות', () {
    /// מפעיל את הנעילה על ההגדרות שהמסגרת כבר מחזיקה. `runAsync` כי הכתיבה
    /// לדיסק אינה מסתיימת בתוך ה-fake-async.
    Future<void> lockSettings(WidgetTester tester) => tester.runAsync(
          () => settings.update(
            AppSettings(
              personalModeAsked: true,
              autoCheckUpdates: false,
              saferModeEnabled: true,
              saferModePassword: SaferModePassword.encode('1234'),
            ),
          ),
        );

    testWidgets('לחיצה על ההגדרות פותחת דיאלוג סיסמה ואינה בונה את המסך', (
      tester,
    ) async {
      await lockSettings(tester);
      await pumpShell(tester);

      await open(tester, ShellSection.settings);
      await tester.pump();

      expect(find.text(stringsOf().saferMode.verifyTitle), findsOneWidget);
      // המסך עצמו כלל לא נבנה — גם לא מוסתר מאחורי הדיאלוג.
      expect(screen(SettingsScreen), findsNothing);
    });

    testWidgets('שאלת החיפוש החכם — "אל תציג שוב" מוסתר כשההגדרות נעולות', (
      tester,
    ) async {
      await lockSettings(tester);
      await pumpShell(tester);
      final s = sessionOf(tester);
      final answer = s.tasks.askBeforeDownload();
      await tester.pump();
      expect(find.text(stringsOf().task.semanticTitle), findsOneWidget);
      expect(find.byKey(ShellKeys.taskSemanticRemember), findsNothing);

      s.saferMode.unlock();
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      s.tasks.notifyListeners();
      await tester.pump();
      expect(find.byKey(ShellKeys.taskSemanticRemember), findsOneWidget);
      s.tasks.answer(null);
      expect(await answer, isNull);
    });

    testWidgets('"הורדה" בלי בחירה — הודעה בלבד, בלי מעבר ובלי בקשת סיסמה', (
      tester,
    ) async {
      await tester.runAsync(
        () => settings.update(
          AppSettings(
            personalModeAsked: true,
            autoCheckUpdates: false,
            saferModeEnabled: true,
            saferModePassword: SaferModePassword.encode('1234'),
            syncApp: false,
            syncPlugins: false,
            syncLibrary: false,
            personalUpdateMode: false,
          ),
        ),
      );
      await pumpShell(tester);

      await sessionOf(tester).downloadAll();
      await tester.pump();

      expect(find.text(stringsOf().saferMode.verifyTitle), findsNothing);
      expect(navigatorOf(tester).section, ShellSection.home);
    });

    testWidgets('ביטול הדיאלוג משאיר את המשתמש בדף הבית', (tester) async {
      await lockSettings(tester);
      await pumpShell(tester);

      await open(tester, ShellSection.settings);
      await tester.pump();
      await tester.tap(find.text(stringsOf().common.cancel));
      await tester.pump();

      expect(screen(SettingsScreen), findsNothing);
      expect(screen(HomePage), findsOneWidget);
    });

    testWidgets('ניהול התוכנות דרך הנווט עובר באותו שער', (tester) async {
      await lockSettings(tester);
      await pumpShell(tester);
      final dynamic state = tester.state(find.byType(AppShell));
      final nav = state.navigator as ShellNavigator;

      final entered = nav.push(const CustomAppsManageRoute());
      await tester.pump();
      expect(find.text(stringsOf().saferMode.verifyTitle), findsOneWidget);
      expect(nav.section, ShellSection.home);

      await tester.tap(find.text(stringsOf().common.cancel));
      await tester.pump();
      expect(await entered, isFalse);
      expect(nav.section, ShellSection.home);
      expect(screen(SettingsScreen), findsNothing);
    });

    testWidgets('סיסמה שגויה אינה פותחת את המסך', (tester) async {
      await lockSettings(tester);
      await pumpShell(tester);

      await open(tester, ShellSection.settings);
      await tester.pump();
      await tester.enterText(find.byType(TextField), '9999');
      await tester.tap(find.text(stringsOf().saferMode.enterButton));
      await tester.pump();

      expect(screen(SettingsScreen), findsNothing);
      // הדיאלוג נשאר פתוח — מי שטעה מנסה שוב.
      expect(find.text(stringsOf().saferMode.verifyTitle), findsOneWidget);
    });

    testWidgets('הסיסמה הנכונה פותחת, וכניסה חוזרת אינה נשאלת שוב', (
      tester,
    ) async {
      await lockSettings(tester);
      await pumpShell(tester);

      await open(tester, ShellSection.settings);
      await tester.pump();
      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text(stringsOf().saferMode.enterButton));
      await tester.pump();

      expect(screen(SettingsScreen), findsOneWidget);

      // אימות אחד מחזיק להרצה — יציאה וחזרה אינן מבקשות סיסמה שוב.
      await back(tester);
      await open(tester, ShellSection.settings);
      await tester.pump();

      expect(find.text(stringsOf().saferMode.verifyTitle), findsNothing);
      expect(screen(SettingsScreen), findsOneWidget);
    });

    /// שני ערוצים בכונן — רק אז מוצגת בחירת הגרסה.
    void offerChannels(AppSession s) {
      s.otzaria
        ..status = OtzariaModuleStatus.upToDate
        ..currentVersion = '1.0.0'
        ..latestVersion = '1.0.0'
        ..stableVersion = '1.0.0'
        ..prereleaseVersion = '1.1.0-beta'
        ..hasChannelChoice = true;
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      s.otzaria.notifyListeners();
    }

    testWidgets('"אוצריא — מתקדם" אינו נעול, אבל שינוי הגרסה מבקש סיסמה', (
      tester,
    ) async {
      await lockSettings(tester);
      await pumpShell(tester);
      final s = sessionOf(tester);
      final nav = navigatorOf(tester);
      offerChannels(s);
      await tester.pump();

      await open(tester, ShellSection.otzaria);
      await tester.pump();
      expect(find.text(stringsOf().saferMode.verifyTitle), findsNothing);
      expect(nav.stack, [
        const HomeRoute(),
        const SectionRoute(ShellSection.otzaria),
      ]);
      expect(find.byKey(ShellKeys.appAdvanced), findsOneWidget);
      expect(find.text(stringsOf().pages.appAdvancedPageTitle), findsWidgets);

      await tester.tap(find.text(stringsOf().appScreen.channelPrerelease));
      await tester.pump();
      expect(find.text(stringsOf().saferMode.verifyTitle), findsOneWidget);
      await tester.tap(find.text(stringsOf().common.cancel));
      await tester.pump();
      expect(settings.settings.preferAppPrerelease, isFalse);
      expect(s.saferMode.isLocked, isTrue);
      expect(screen(SettingsScreen), findsNothing);
    });

    testWidgets('הקישור מההגדרות פותח את המתקדם מעל הבית, ו"חזרה" מובילה לבית',
        (tester) async {
      await lockSettings(tester);
      await pumpShell(tester);
      final s = sessionOf(tester);
      final nav = navigatorOf(tester);

      await open(tester, ShellSection.settings);
      await tester.pump();
      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text(stringsOf().saferMode.enterButton));
      await tester.pump();
      expect(nav.section, ShellSection.settings);

      final link = find.byKey(const ValueKey('settings.otzariaAdvanced'));
      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pump();
      // לא "בית ← הגדרות ← מתקדם": "חזרה" הייתה נוחתת בהגדרות בלי שער.
      expect(nav.stack, [
        const HomeRoute(),
        const SectionRoute(ShellSection.otzaria),
      ]);

      s.saferMode.lock();
      await back(tester);
      expect(nav.stack, [const HomeRoute()]);
      expect(find.text(stringsOf().saferMode.verifyTitle), findsNothing);
    });

    testWidgets('העזרה אינה נעולה — רק העריכה שבה', (tester) async {
      await lockSettings(tester);
      await pumpShell(tester);

      await tester.tap(find.byTooltip(shell.helpTooltip));
      await tester.pump();

      expect(find.text(stringsOf().saferMode.verifyTitle), findsNothing);
      expect(screen(HelpPage), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('faq.edit')));
      await tester.pump();
      expect(find.text(stringsOf().saferMode.verifyFaqHint), findsOneWidget);
    });

    testWidgets('גם גלגל השיניים שבשורת הכותרת עובר בשער', (tester) async {
      await lockSettings(tester);
      await pumpShell(tester);

      await tester.tap(find.byTooltip(shell.settingsTooltip));
      await tester.pump();

      expect(find.text(stringsOf().saferMode.verifyTitle), findsOneWidget);
      expect(screen(SettingsScreen), findsNothing);
    });

    testWidgets('בלי סיסמה שמורה המתג אינו נועל כלום', (tester) async {
      // קובץ שנערך ביד יכול להדליק את המתג בלי סיסמה — וזה אינו נועל.
      await tester.runAsync(
        () => settings.update(
          const AppSettings(
              personalModeAsked: true,
              autoCheckUpdates: false,
              saferModeEnabled: true),
        ),
      );
      await pumpShell(tester);

      await open(tester, ShellSection.settings);
      await tester.pump();

      expect(find.text(stringsOf().saferMode.verifyTitle), findsNothing);
      expect(screen(SettingsScreen), findsOneWidget);
    });
  });

  group("בדיקת עדכון הלאנצ'ר מהמראה", () {
    Future<LauncherUpdateStatus> statusAfterStart(WidgetTester tester) async {
      LauncherUpdateController launcher() => sessionOf(tester).launcherUpdate;
      for (var i = 0;
          i < 40 && launcher().status == LauncherUpdateStatus.idle;
          i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      return launcher().status;
    }

    testWidgets('רצה בעלייה גם כשבדיקת העדכונים האוטומטית כבויה', (
      tester,
    ) async {
      await pumpShell(tester);
      expect(await statusAfterStart(tester), isNot(LauncherUpdateStatus.idle));
    });

    testWidgets('כונן לקריאה בלבד: אינה רצה', (tester) async {
      await pumpShell(tester, readOnly: true);
      expect(await statusAfterStart(tester), LauncherUpdateStatus.idle);
    });

    final source = _appSessionSource();

    test('הבדיקה הידנית ברשת קוראת גם את המראה, לפני ההצצה', () {
      final start = source.indexOf('Future<void> checkOnline() async {');
      final body = source.substring(
        start,
        source.indexOf('Future.wait', start),
      );
      expect(start, greaterThan(-1));
      expect(body, contains('await _launcherFlow.checkMirror()'));
    });
  });

  group('סגירת החלון בזמן פעולה ארוכה', () {
    for (final language in AppLanguage.values) {
      for (final installingLibrary in [true, false]) {
        testWidgets(
            '$language: אישור וביטול סגירה בזמן '
            '${installingLibrary ? 'עדכון ספרייה' : 'התקנת אוצריא'}',
            (tester) async {
          await pumpShell(tester, language: language, readOnly: true);
          addTearDown(LauncherCrashSession.resetForTest);
          final home = sessionOf(tester);
          if (installingLibrary) {
            home.library.status = LibraryModuleStatus.updating;
          } else {
            home.otzaria.status = OtzariaModuleStatus.installing;
          }
          final t = AppL10n.stringsFor(language).shell;
          for (final approved in [false, true]) {
            bool? result;
            final pending = LauncherCrashSession.closeGuard!()
                .then((allowed) => result = allowed);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));

            expect(find.text(t.closeWhileBusyTitle), findsOneWidget);
            expect(find.text(t.closeWhileInstallingPrompt), findsOneWidget);
            expect(result, isNull);

            await tester.tap(find.text(approved
                ? t.closeWhileInstallingConfirm
                : t.closeWhileBusyKeepGoing));
            await tester.pump(const Duration(milliseconds: 300));

            expect(await pending, approved);
          }
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('המסגרת רושמת שומר סגירה שמאשר כשאין פעולה, ומסירה בפירוק', (
      tester,
    ) async {
      await pumpShell(tester);
      final guard = LauncherCrashSession.closeGuard;
      expect(guard, isNotNull);
      expect(await guard!(), isTrue);

      await tester.pumpWidget(const SizedBox());
      expect(LauncherCrashSession.closeGuard, isNull);
    });

    final source = _appSessionSource();
    final start = source.indexOf('Future<bool> confirmClose() async {');
    final body = source.substring(start, source.indexOf('\n  }\n', start));

    test('גוף השומר נמצא', () => expect(start, greaterThan(-1)));

    test('שואל רק בזמן פעולה ארוכה', () {
      expect(body, contains('!(longTaskRunning || updatingHere)) return true'));
      expect(body, contains('prompts.confirmClose('));
      expect(
        _methodBody(
          _appShellSource(),
          'Future<bool> confirmClose({required bool downloading})',
        ),
        contains('showWarningDialog'),
      );
    });

    test('הורדה נעצרת עם שמירת ההתקדמות לפני הסגירה', () {
      expect(
          body, contains('await _downloads.cancelAndWait(keepProgress: true)'));
    });
  });
}

/// "אוצריא סגורה", בלי להריץ `tasklist` — ראו ה-setUp.
class _NeverRunningLocator extends RunningOtzariaLocator {
  const _NeverRunningLocator();

  @override
  Future<RunningOtzariaProbe> probe() async =>
      (isRunning: false, launchPath: null);
}

/// אוצריא שנסגרת באמצע הבדיקה: [isRunning] מוחלף בין בדיקה לבדיקה.
/// [probes] סופר דגימות, כדי לאמת גם שהרענון המחזורי **נכבה**.
class _MutableLocator extends RunningOtzariaLocator {
  _MutableLocator({required this.isRunning});

  bool isRunning;
  int probes = 0;

  @override
  Future<RunningOtzariaProbe> probe() async {
    probes++;
    return (isRunning: isRunning, launchPath: null);
  }

  @override
  Future<bool?> waitForExit(Duration timeout) async => null;
}

/// תור משוב בזיכרון לבדיקות המסגרת — בלי דיסק ובלי רשת.
class _ShellFeedback extends SearchFeedbackTransport {
  _ShellFeedback()
      : super('unused',
            client: MockClient((_) async => http.Response('{}', 200)));

  bool consent = true;
  bool online = true;
  bool closed = false;
  int sourceEvents = 2;
  int carriedEvents = 0;
  int collections = 0;
  int uploads = 0;
  int counts = 0;
  int sent = 0;
  DateTime? storedRetryAt;
  Completer<void>? uploadGate;

  @override
  Future<int> pendingForCollection(String sourceDirectory) async =>
      sourceEvents;

  @override
  Future<int> count() async {
    counts++;
    return carriedEvents;
  }

  @override
  Future<int> collect(String sourceDirectory,
      {required Future<bool> Function() mayCollect}) async {
    collections++;
    if (!await mayCollect()) return 0;
    final collected = sourceEvents;
    carriedEvents += collected;
    sourceEvents = 0;
    return collected;
  }

  @override
  Future<DateTime?> retryAt() async => storedRetryAt;

  @override
  Future<SearchFeedbackUploadResult> upload() async {
    uploads++;
    await uploadGate?.future;
    if (!online) {
      storedRetryAt = DateTime.now().add(const Duration(minutes: 2));
      return (sent: 0, rejected: 0, remaining: carriedEvents);
    }
    sent += carriedEvents;
    carriedEvents = 0;
    storedRetryAt = null;
    return (sent: sent, rejected: 0, remaining: 0);
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}

/// תור הדיווחים של אוצריא בזיכרון: איסוף מעביר את [pending] ל-[outbox].
class _ShellReportQueue implements OtzariaReportQueue {
  final outbox = _ShellOutbox();
  int pending = 0;
  int collects = 0;

  @override
  Future<int> countSendable() async => pending;

  @override
  Future<QueueCollectResult> collectTo(ReportOutbox outbox) async {
    collects++;
    final n = pending;
    for (var i = 0; i < n; i++) {
      await outbox.write(
        'r${this.outbox.reports.length}',
        utf8.encode(jsonEncode(OutboxReport.fileJson(
          reportId: 'r${this.outbox.reports.length}',
          bookTitle: 'ספר',
          createdAt: '2026-09-01T10:00:00Z',
          body: const {},
        ))),
      );
    }
    pending = 0;
    return (collected: n, error: null);
  }
}

class _ShellOutbox implements ReportOutbox {
  final reports = <OutboxReport>[];

  @override
  Future<List<OutboxReport>> list() async => List.of(reports);

  @override
  Future<int> count() async => reports.length;

  @override
  Future<Uint8List> requestBody(OutboxReport report) async =>
      Uint8List.fromList(utf8.encode('{}'));

  @override
  Future<void> remove(OutboxReport report) async =>
      reports.removeWhere((r) => r.reportId == report.reportId);

  @override
  Future<void> write(String reportId, Uint8List fileBytes) async {
    reports.removeWhere((r) => r.reportId == reportId);
    reports.add(OutboxReport.fromJson(
      jsonDecode(utf8.decode(fileBytes)) as Map<String, dynamic>,
      filePath: reportId,
    ));
  }

  @override
  Future<void> discard(String reportId) async =>
      reports.removeWhere((r) => r.reportId == reportId);
}

// צילומי סקירה: רק ב-Windows עם OTZ_VISUAL=1; השלב ב-OTZ_VISUAL_PHASE, אנגלית ב-OTZ_VISUAL_LANG=en.
// פלט: build/visual_review/<phase>[_en]/<state>.png, ו-<state>_narrow.png ב-760x560.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:launcher_app/src/app_report/launcher_crash_session.dart';
import 'package:launcher_app/src/controllers/app_reports_controller.dart';
import 'package:launcher_app/src/screens/app_shell.dart';
import 'package:launcher_app/src/screens/home/home_page.dart';
import 'package:launcher_app/src/screens/reports/reports_page.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:launcher_app/src/services/notices_seen_store.dart';
import 'package:launcher_app/src/settings/app_settings.dart';
import 'package:launcher_app/src/settings/settings_controller.dart';
import 'package:launcher_app/src/shell/shell_keys.dart';
import 'package:launcher_app/src/shell/shell_navigator.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';
import 'package:library_manager/library_manager.dart' show LibraryStateStore;
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;

import '../home_fixtures.dart';
import '../page_fixtures.dart';
import '../store_fixtures.dart';
import '../task_fixtures.dart';
import '../test_harness.dart';
import '../test_support.dart';
import 'visual_fonts.dart';

final _enabled =
    Platform.isWindows && Platform.environment['OTZ_VISUAL'] == '1';
final _english = Platform.environment['OTZ_VISUAL_LANG'] == 'en';
final _phase = Platform.environment['OTZ_VISUAL_PHASE'] ?? 'phase0';
final _outPhase = _english ? '${_phase}_en' : _phase;
final _language = _english ? AppLanguage.english : AppLanguage.hebrew;

const _sizes = {'': Size(1000, 720), '_narrow': Size(760, 560)};

/// מצב לצילום: שם הקובץ, ומה עושים אחרי שהמסגרת עלתה.
typedef VisualState = ({
  String name,
  Future<void> Function(WidgetTester tester) open,
});

/// מאז שלב 2 אין סרגל: המקטעים נפתחים מהאריחים שבבית.
Future<void> _tapTile(WidgetTester tester, ShellSection section) async {
  await tester.tap(find.byKey(ShellKeys.tile(section)));
  await tester.pump();
}

final List<VisualState> _phase0States = [
  (name: 'home', open: (_) async {}),
  // האריח פותח את "אוצריא — מתקדם"; מצב התוכנה עצמו בבית.
  (
    name: 'otzaria_advanced',
    open: (t) => _tapTile(t, ShellSection.otzaria),
  ),
  (name: 'library', open: (t) => _tapTile(t, ShellSection.library)),
  (name: 'plugins', open: (t) => _tapTile(t, ShellSection.plugins)),
  (
    name: 'settings',
    open: (t) => _tapTooltip(t, stringsOf(_language).shell.settingsTooltip),
  ),
];

Future<void> _tapTooltip(WidgetTester tester, String tooltip) async {
  await tester.tap(find.byTooltip(tooltip));
  await tester.pump();
}

final List<VisualState> _phase1States = [
  ..._phase0States,
  (
    name: 'help',
    open: (t) => _tapTooltip(t, stringsOf(_language).shell.helpTooltip)
  ),
];

Future<void> _tab(WidgetTester tester, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  }
  await tester.pump();
}

final List<VisualState> _phase1bStates = [
  ..._phase1States,
  // שורת הכותרת מעל השכבה של הדו-שיח, והכפתור הממוקד בצבע הרגיל.
  (
    name: 'dialog_hover_close',
    open: (t) async {
      await _tapTooltip(t, stringsOf(_language).shell.helpTooltip);
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(
        location: t.getCenter(
          find.bySemanticsLabel(stringsOf(_language).shell.windowClose),
        ),
      );
      await t.pump();
    },
  ),
  (name: 'focus_keyboard', open: (t) => _tab(t, 3)),
];

/// שלב 2a: המסגרת האמיתית (הבית ודפי המשנה). מצבי הבית של המוקאפ מצולמים
/// בנפרד, מהמודל — ראו `home_<scenario>`.
final List<VisualState> _phase2aStates = [
  (name: 'shell_home', open: (_) async {}),
  (name: 'shell_library', open: (t) => _tapTile(t, ShellSection.library)),
  (name: 'shell_plugins', open: (t) => _tapTile(t, ShellSection.plugins)),
  (
    name: 'shell_settings',
    open: (t) => _tapTooltip(t, stringsOf(_language).shell.settingsTooltip),
  ),
];

/// שלב 5: ההגדרות (מקופל ופתוח), דו-שיחי הנעילה והשאלות הנפוצות.
Future<void> _openSettings(WidgetTester tester) =>
    _tapTooltip(tester, stringsOf(_language).shell.settingsTooltip);

/// בלי דיווחים האריח אינו מוצג — ולכן דרך הנווט.
Future<void> _openReports(WidgetTester tester) async {
  final shell = tester.state(find.byType(AppShell)) as dynamic;
  (shell.navigator as ShellNavigator)
      .push(const SectionRoute(ShellSection.reports))
      .ignore();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _tapVisible(WidgetTester tester, Finder target) async {
  // רשימה עצלה: מה שמתחת לחלון עוד לא נבנה, ולכן גוללים עד שהוא נמצא.
  for (var i = 0; i < 12 && target.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(ListView).last, const Offset(0, -300));
    await tester.pump();
  }
  await tester.ensureVisible(target.first);
  await tester.pump();
  await tester.tap(target.first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _openSettingsAdvanced(WidgetTester tester) async {
  await _openSettings(tester);
  await _tapVisible(
      tester, find.text(stringsOf(_language).pages.advancedTitle));
}

/// סיסמה 1234 נקבעת דרך הדו-שיח — והנעילה פעילה אחריה.
Future<void> _setPassword(WidgetTester tester) async {
  await _openSettingsAdvanced(tester);
  await _tapVisible(
      tester, find.text(stringsOf(_language).saferMode.setPasswordButton));
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), '1234');
  await tester.enterText(fields.at(1), '1234');
  await tester.tap(find.text(stringsOf(_language).saferMode.setConfirm));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _scrollDown(WidgetTester tester) async {
  await tester.drag(find.byType(ListView).last, const Offset(0, -2000));
  await tester.pump();
}

final List<VisualState> _phase5States = [
  (name: 'settings', open: _openSettings),
  (
    name: 'settings_advanced',
    open: (t) async {
      await _openSettingsAdvanced(t);
      await _scrollDown(t);
    },
  ),
  (
    name: 'dlg_lang',
    open: (t) async {
      await _openSettings(t);
      await _tapVisible(t, find.byKey(const ValueKey('settings.language')));
    },
  ),
  (
    name: 'dlg_auto_install',
    open: (t) async {
      await _openSettings(t);
      await _tapVisible(
          t, find.text(stringsOf(_language).settings.autoInstallTitle));
    },
  ),
  (
    name: 'dlg_pw_set',
    open: (t) async {
      await _openSettingsAdvanced(t);
      await _tapVisible(
        t,
        find.text(stringsOf(_language).saferMode.setPasswordButton),
      );
    },
  ),
  (
    name: 'settings_locked',
    open: (t) async {
      await _setPassword(t);
      await _scrollDown(t);
    },
  ),
  (
    name: 'dlg_pw_enter',
    open: (t) async {
      await _setPassword(t);
      await _tapVisible(t, find.text(stringsOf(_language).saferMode.lockTitle));
    },
  ),
  (
    name: 'dlg_pw_change',
    open: (t) async {
      await _setPassword(t);
      await _tapVisible(
          t, find.text(stringsOf(_language).saferMode.changeButton));
    },
  ),
  (
    name: 'dlg_pw_delete',
    open: (t) async {
      await _setPassword(t);
      // המחיקה מושבתת כשהנעילה פעילה — מכבים אותה קודם.
      await _tapVisible(t, find.text(stringsOf(_language).saferMode.lockTitle));
      await t.enterText(find.byType(TextField), '1234');
      await t.tap(find.text(stringsOf(_language).common.confirm));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await t.pump(const Duration(milliseconds: 400));
      await _tapVisible(
          t, find.text(stringsOf(_language).saferMode.clearButton));
    },
  ),
  (
    name: 'dlg_reset',
    open: (t) async {
      await _openSettingsAdvanced(t);
      await _tapVisible(t, find.byKey(const ValueKey('settings.reset')));
    },
  ),
  (
    name: 'help',
    open: (t) => _tapTooltip(t, stringsOf(_language).shell.helpTooltip)
  ),
  (
    name: 'help_open',
    open: (t) async {
      await _tapTooltip(t, stringsOf(_language).shell.helpTooltip);
      await _tapVisible(t, find.text(stringsOf(_language).faq.qOfflineFlow));
    },
  ),
  (
    name: 'help_edit',
    open: (t) async {
      await _tapTooltip(t, stringsOf(_language).shell.helpTooltip);
      await _tapVisible(t, find.byKey(const ValueKey('faq.edit')));
    },
  ),
  (
    name: 'help_edit_bottom',
    open: (t) async {
      await _tapTooltip(t, stringsOf(_language).shell.helpTooltip);
      await _tapVisible(t, find.byKey(const ValueKey('faq.edit')));
      await _scrollDown(t);
    },
  ),
];

/// תיקוני שלב 5: אותם מצבים, ועוד "פרטיות ודיווחים" (עם דיווחי הכלי),
/// אזהרת העדכון למחשב מסוים, שגיאת החלפה ועריכה שנפתחה מההגדרות.
final List<VisualState> _phase5bStates = [
  ..._phase5States,
  (
    name: 'settings_privacy',
    open: (t) async {
      await _openSettings(t);
      await _tapVisible(
          t, find.text(stringsOf(_language).settings.groupPrivacy));
    },
  ),
  (
    name: 'dlg_personal',
    open: (t) async {
      await _openSettings(t);
      await _tapVisible(t, find.byKey(ShellKeys.settingsPersonalMine));
    },
  ),
  (
    name: 'dlg_pw_change_error',
    open: (t) async {
      await _setPassword(t);
      await _tapVisible(
          t, find.text(stringsOf(_language).saferMode.changeButton));
      final fields = find.byType(TextField);
      await t.enterText(fields.at(0), '9999');
      await t.enterText(fields.at(1), '5678');
      await t.enterText(fields.at(2), '5678');
      await t.tap(
        find
            .widgetWithText(
                ActionButton, stringsOf(_language).saferMode.changeButton)
            .last,
      );
      await t.pump(const Duration(milliseconds: 400));
    },
  ),
  (
    name: 'help_edit_from_settings',
    open: (t) async {
      await _openSettingsAdvanced(t);
      await _tapVisible(
          t, find.text(stringsOf(_language).settings.faqEditTitle));
    },
  ),
  (
    name: 'reports_page',
    open: _openReports,
  ),
  (
    name: 'dlg_app_report',
    open: (t) async {
      await _openReports(t);
      await _tapVisible(t, find.byKey(ShellKeys.reportsProblem));
    },
  ),
];

final List<VisualState> _stage3States = [
  (name: 'shell_home', open: (_) async {}),
  (
    name: 'otzaria_advanced',
    open: (t) => _tapTile(t, ShellSection.otzaria),
  ),
  (name: 'shell_settings', open: _openSettings),
  (
    name: 'otzaria_advanced_from_settings',
    open: (t) async {
      await _openSettings(t);
      await _tapVisible(
        t,
        find.byKey(const ValueKey('settings.otzariaAdvanced')),
      );
    },
  ),
];

/// דיווחי הכלי בלי רשת ובלי קבצים — רק כדי ש"פרטיות ודיווחים" תוצג.
class _QuietReportService extends AppReportService {
  _QuietReportService()
      : super(
          directory: '',
          client: MockClient((_) async => http.Response('', 500)),
        );

  @override
  void startAutomaticFlush() {}
  @override
  Future<int> getPendingReportsCount() async => 0;
  @override
  Future<int> getSentReportsTotal() async => 0;
}

class _QuietCollector implements AppReportAttachmentsCollector {
  @override
  Future<AppReportAttachments> collect() async =>
      const AppReportAttachments(diagnostics: {}, errorLog: '');
}

/// עדכון אישי: השאלה בהפעלה הראשונה, ההגדרות עם המחשבים שנרשמו ודף הספרייה.
Future<void> _closeQuestion(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pump(const Duration(milliseconds: 400));
}

final List<VisualState> _personalStates = [
  (name: 'personal_ask', open: (_) async {}),
  (
    name: 'personal_ask_chosen',
    open: (t) async {
      await t.tap(find.byKey(ShellKeys.personalAskMine));
      await t.pump(const Duration(milliseconds: 300));
    },
  ),
  (
    name: 'personal_settings',
    open: (t) async {
      await _closeQuestion(t);
      await _openSettings(t);
      await _tapVisible(
          t, find.text(stringsOf(_language).settings.personalGroupTitle));
    },
  ),
];

/// השלבים שמצלמים את ההגדרות עם דיווחי הכלי.
const _appReportsPhases = {'phase5b'};

/// שלב חדש מוסיף כאן את רשימת המצבים שלו.
final Map<String, List<VisualState>> _statesByPhase = {
  'phase0': _phase0States,
  'phase1': _phase1States,
  'phase1b': _phase1bStates,
  'phase2a': _phase2aStates,
  // תיקוני הסקירה של 2a — אותם מצבים, ומצבי הבית החדשים מ-home_fixtures.
  'phase2a2': _phase2aStates,
  // סבב 3: הגילוי שבדף הדיווחים — ראו `reports_<variant>`.
  'phase2a3': _phase2aStates,
  // מסכי המשימה מצולמים מהמודל — ראו `task_<scenario>`.
  'phase2b': _phase2aStates,
  // הדפים מצולמים מהקונטרולרים — ראו `page_<scenario>`.
  'phase3': _phase2aStates,
  // תיקוני 2b: מסכי המשימה שוב, והבית (היחידות הלטיניות).
  'phase2b2': const [],
  // תיקוני 3: הדפים בלבד, כולל המצבים שחסרו.
  'phase3b': const [],
  // החנות והתוכנות הנוספות מצולמות מה-fixtures — ראו `store_<scenario>`.
  'phase4': const [],
  'phase5': _phase5States,
  'phase5b': _phase5bStates,
  // שלב 3 של הבית: "אוצריא — מתקדם" מהאריח ומההגדרות, ומצבי הבית החדשים.
  'stage3': _stage3States,
  'personal': _personalStates,
};

/// השלבים שמצלמים את מצבי החנות.
const _storePhases = {'phase4', 'phase4b'};

/// הבית במצבי המוקאפ, בתוך שורת הכותרת — בלי סשן.
Set<String> get _homeScenarioPhases => const {
      'phase2a',
      'phase2a2',
      'phase2a3',
      'phase2b2',
      'stage2_home',
      'stage3',
      'fixbatch',
      'personal',
    };

/// מסכי המשימה מצולמים מהמודל — ראו `task_<scenario>`.
const _taskPhases = {'phase2b', 'phase2b2'};

/// דף הדיווחים עם כרטיס האיסוף — המונים מגיעים מהסשן, ולכן מצולם מהווידג'ט.
const _reportsVariants = {
  'reports_collect': (reports: 3, searchRecords: 5),
  'reports_only': (reports: 2, searchRecords: 0),
};

/// משלב 1 שורת הכותרת מצוירת כולה ב-Flutter, ולכן הכפתורים נכנסים לצילום.
bool get _showWindowButtons => _phase != 'phase0';

void main() {
  late Directory tempDir;
  late SettingsController settings;
  final boundary = GlobalKey();

  setUp(() async {
    if (!_enabled) return;
    // כפתורי החלון שואלים אם החלון מוגדל.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async => call.method == 'isMaximized' ? false : null,
    );
    tempDir = Directory.systemTemp.createTempSync('visual_review');
    await AppLogger.init(tempDir.path);
    settings = SettingsController(dataDir: tempDir.path);
    // עברית במפורש: "כמו במחשב" במכונת הבדיקה היא אנגלית, וההגדרות מציבות
    // אותה ב-`AppL10n` בכל שמירה — וכך "Cancel" נכנס לדו-שיחים בצילום.
    final personal = _phase == 'personal';
    if (personal) {
      final store = LibraryStateStore.inDir(p.join(tempDir.path, 'logs'));
      await store.recordKnownDbVersion('YOSEF-LAPTOP|user', 145,
          name: 'YOSEF-LAPTOP');
      await store.recordKnownDbVersion(
          await LibraryStateStore.currentMachineKey(), 146,
          name: 'BEIT-MIDRASH');
    }
    await settings.update(
      AppSettings(
        personalModeAsked: !personal,
        personalUpdateMode: personal,
        autoCheckUpdates: false,
        languagePreference: _english
            ? AppLanguagePreference.english
            : AppLanguagePreference.hebrew,
      ),
    );
  });

  tearDown(() async {
    if (!_enabled) return;
    LauncherCrashSession.resetForTest();
    settings.dispose();
    AppLogger.resetForTest();
    await deleteTempDir(tempDir);
  });

  /// נותן ל-I/O האמיתי (טעינת תוספים, פענוח תמונות) להסתיים לפני הצילום.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> capture(WidgetTester tester, String file) async {
    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final out = File(file)..parent.createSync(recursive: true);
      await out.writeAsBytes(png!.buffer.asUint8List());
    });
  }

  for (final state in _statesByPhase[_phase] ?? const <VisualState>[]) {
    for (final MapEntry(key: suffix, value: size) in _sizes.entries) {
      testWidgets('$_phase/${state.name}$suffix', skip: !_enabled, (
        tester,
      ) async {
        await tester.runAsync(loadVisualFonts);
        debugDisableShadows = false;
        // כמו `debugShowCheckedModeBanner: false` שב-main.dart.
        WidgetsApp.debugAllowBannerOverride = false;
        final reports = _appReportsPhases.contains(_phase)
            ? AppReportsController(
                service: _QuietReportService(),
                collector: _QuietCollector(),
                settings: settings,
                logsDirectory: tempDir.path,
                redactor: AppReportRedactor(environment: const {}),
                isProcessAlive: (_) => false,
              )
            : null;
        try {
          useViewSize(tester, size);
          AppL10n.use(_language);
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: wrap(
                AppShell(
                  dataDir: tempDir.path,
                  settings: settings,
                  runningLocator: const _NeverRunningLocator(),
                  noticesStore: MemoryNoticesStore(
                    seen: {NoticesSeenStore.errorReportsIntro},
                  ),
                  showWindowButtons: _showWindowButtons,
                  appReports: reports,
                ),
                language: _language,
              ),
            ),
          );
          await settle(tester);
          await state.open(tester);
          await settle(tester);
          await capture(
            tester,
            p.join('build', 'visual_review', _outPhase,
                '${state.name}$suffix.png'),
          );
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          reports?.dispose();
          debugDisableShadows = true;
          WidgetsApp.debugAllowBannerOverride = true;
        }
      });
    }
  }

  for (final scenario in homeScenarios) {
    for (final MapEntry(key: suffix, value: size) in _sizes.entries) {
      testWidgets('$_phase/home_$scenario$suffix',
          skip: !_enabled || !_homeScenarioPhases.contains(_phase), (
        tester,
      ) async {
        await tester.runAsync(loadVisualFonts);
        WidgetsApp.debugAllowBannerOverride = false;
        try {
          useViewSize(tester, size);
          AppL10n.use(_language);
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: wrap(
                Scaffold(
                  backgroundColor: const Color(0xFFF6EDE5),
                  body: Column(
                    children: [
                      AppTitleBar(
                        onHelp: () {},
                        onSettings: () {},
                        showWindowButtons: true,
                      ),
                      Expanded(
                        child: HomePage(
                          model: homeScenario(scenario),
                          taskProgress:
                              homeScenarioProgress(scenario, tempDir.path),
                        ),
                      ),
                    ],
                  ),
                ),
                language: _language,
              ),
            ),
          );
          await settle(tester);
          await capture(
            tester,
            p.join(
              'build',
              'visual_review',
              _outPhase,
              'home_$scenario$suffix.png',
            ),
          );
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          WidgetsApp.debugAllowBannerOverride = true;
        }
      });
    }
  }

  for (final scenario in taskScenarioNames) {
    for (final MapEntry(key: suffix, value: size) in _sizes.entries) {
      testWidgets('$_phase/task_$scenario$suffix',
          skip: !_enabled || !_taskPhases.contains(_phase), (tester) async {
        await tester.runAsync(loadVisualFonts);
        WidgetsApp.debugAllowBannerOverride = false;
        try {
          useViewSize(tester, size);
          // `formatBytes` קורא את השפה הגלובלית — בלי זה היחידות באנגלית.
          AppL10n.use(_language);
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: wrap(
                Scaffold(
                  backgroundColor: const Color(0xFFF6EDE5),
                  body: Column(
                    children: [
                      AppTitleBar(
                        onHelp: () {},
                        onSettings: () {},
                        showWindowButtons: true,
                      ),
                      Expanded(child: taskScenario(scenario)),
                    ],
                  ),
                ),
                language: _language,
              ),
            ),
          );
          await settle(tester);
          await capture(
            tester,
            p.join(
              'build',
              'visual_review',
              _outPhase,
              'task_$scenario$suffix.png',
            ),
          );
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          WidgetsApp.debugAllowBannerOverride = true;
        }
      });
    }
  }

  for (final MapEntry(key: name, value: counts) in _reportsVariants.entries) {
    for (final MapEntry(key: suffix, value: size) in _sizes.entries) {
      testWidgets('$_phase/$name$suffix',
          skip: !_enabled || _phase != 'phase2a3', (tester) async {
        await tester.runAsync(loadVisualFonts);
        WidgetsApp.debugAllowBannerOverride = false;
        try {
          useViewSize(tester, size);
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: wrap(
                Scaffold(
                  backgroundColor: const Color(0xFFF6EDE5),
                  body: Column(
                    children: [
                      AppTitleBar(
                        onHelp: () {},
                        onSettings: () {},
                        showWindowButtons: true,
                      ),
                      Expanded(
                        child: ReportsPage(
                          errorReports: null,
                          connection: null,
                          isUploadingAll: false,
                          busy: false,
                          reportsToCollect: counts.reports,
                          onCollect: () {},
                          onUpload: null,
                        ),
                      ),
                    ],
                  ),
                ),
                language: _language,
              ),
            ),
          );
          await settle(tester);
          await capture(
            tester,
            p.join('build', 'visual_review', _outPhase, '$name$suffix.png'),
          );
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          WidgetsApp.debugAllowBannerOverride = true;
        }
      });
    }
  }

  for (final MapEntry(key: name, value: build) in pageScenarios.entries) {
    for (final advanced in [
      false,
      if (advancedScenarios.contains(name)) true
    ]) {
      for (final MapEntry(key: suffix, value: size) in _sizes.entries) {
        final file = '$name${advanced ? '_advanced' : ''}$suffix';
        testWidgets('$_phase/page_$file',
            skip: !_enabled ||
                !{'phase3', 'phase2b2', 'phase3b', 'stage3', 'personal'}
                    .contains(_phase), (tester) async {
          await tester.runAsync(loadVisualFonts);
          WidgetsApp.debugAllowBannerOverride = false;
          try {
            useViewSize(tester, size);
            // מלל התחום (otzaria_l10n) נקרא מהשפה הגלובלית, לא מה-context.
            AppL10n.use(_language);
            final crumb = switch (name.split('_').first) {
              'otzaria' => stringsOf(_language).pages.appAdvancedPageTitle,
              'library' => stringsOf(_language).guide.tileLibrary,
              'reports' => stringsOf(_language).pages.repCrumb,
              _ => stringsOf(_language).pages.selfCrumb,
            };
            await tester.pumpWidget(
              RepaintBoundary(
                key: boundary,
                child: wrap(
                  Scaffold(
                    backgroundColor: const Color(0xFFF6EDE5),
                    body: Column(
                      children: [
                        AppTitleBar(
                          onHelp: () {},
                          onSettings: () {},
                          showWindowButtons: true,
                        ),
                        Expanded(
                          child: SubPageHeaderScope(
                            header: SubPageHeader(
                              onBack: () {},
                              onHome: () {},
                              trail: [(label: crumb, onTap: null)],
                            ),
                            child: build(tempDir.path, settings),
                          ),
                        ),
                      ],
                    ),
                  ),
                  language: _language,
                ),
              ),
            );
            await settle(tester);
            if (advanced) {
              await tester.drag(
                find.byType(ListView).first,
                const Offset(0, -2000),
              );
              await settle(tester);
              await tester
                  .tap(find.text(stringsOf(_language).pages.advancedTitle));
              await settle(tester);
              await tester.drag(
                find.byType(ListView).first,
                const Offset(0, -2000),
              );
              await settle(tester);
            }
            await capture(
              tester,
              p.join('build', 'visual_review', _outPhase, 'page_$file.png'),
            );
            await tester.pumpWidget(const SizedBox.shrink());
          } finally {
            WidgetsApp.debugAllowBannerOverride = true;
          }
        });
      }
    }
  }

  for (final MapEntry(key: name, value: scenario) in storeScenarios.entries) {
    for (final MapEntry(key: suffix, value: size) in _sizes.entries) {
      testWidgets('$_phase/store_$name$suffix',
          skip: !_enabled || !_storePhases.contains(_phase), (tester) async {
        await tester.runAsync(loadVisualFonts);
        WidgetsApp.debugAllowBannerOverride = false;
        final fixture = StoreFixture(tempDir.path);
        try {
          useViewSize(tester, size);
          AppL10n.use(_language);
          await tester.runAsync(fixture.paint);
          final screen = scenario.build(fixture);
          final s = stringsOf(_language);
          final section = name.startsWith('plugin') || name == 'lightbox'
              ? s.guide.tilePlugins
              : name.startsWith('manage') || name == 'addapp'
                  ? s.settings.title
                  : s.guide.tileCustomApps;
          final leaf = switch (name) {
            'plugin_cal' ||
            'plugin_cal_scrolled' ||
            'lightbox' =>
              'לוח שנה עברי',
            'plugin_tikkun' => 'תיקון קוראים',
            'plugin_colors' => 'סימניות צבעוניות',
            'plugin_nusach' || 'plugin_nusach_offline' => 'סידור לפי נוסח',
            'plugin_mydev' => 'התוסף שלי',
            'app_player' => 'נגן שיעורים',
            'app_detail_editor' => 'עורך מסמכים',
            'manage' ||
            'manage_empty' ||
            'addapp' =>
              s.customApps.manageDialogTitle,
            _ => null,
          };
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: wrap(
                Scaffold(
                  backgroundColor: const Color(0xFFF6EDE5),
                  body: Column(
                    children: [
                      AppTitleBar(
                        onHelp: () {},
                        onSettings: () {},
                        showWindowButtons: true,
                      ),
                      Expanded(
                        child: SubPageHeaderScope(
                          header: SubPageHeader(
                            onBack: () {},
                            onHome: () {},
                            trail: [
                              (
                                label: section,
                                onTap: leaf == null ? null : () {}
                              ),
                              if (leaf != null) (label: leaf, onTap: null),
                            ],
                          ),
                          child: screen,
                        ),
                      ),
                    ],
                  ),
                ),
                language: _language,
              ),
            ),
          );
          await settle(tester);
          if (scenario.after case final after?) {
            await after(tester, fixture);
            await settle(tester);
          }
          await capture(
            tester,
            p.join(
                'build', 'visual_review', _outPhase, 'store_$name$suffix.png'),
          );
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          fixture.dispose();
          WidgetsApp.debugAllowBannerOverride = true;
        }
      });
    }
  }

  // גלריית רכיבים: שדות, סגמנט, תפריט, מתג, פירור, אריחים וכרטיסים.
  testWidgets('$_phase/gallery', skip: !_enabled || _phase == 'phase0', (
    tester,
  ) async {
    await tester.runAsync(loadVisualFonts);
    WidgetsApp.debugAllowBannerOverride = false;
    try {
      useViewSize(tester, const Size(1000, 720));
      await tester.pumpWidget(
        RepaintBoundary(
            key: boundary, child: wrap(const _Gallery(), language: _language)),
      );
      await settle(tester);
      // מיקוד מהמקלדת על השדה השני — הטבעת שלו והמסגרת ב-primary.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await capture(
        tester,
        p.join('build', 'visual_review', _outPhase, 'gallery.png'),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      WidgetsApp.debugAllowBannerOverride = true;
    }
  });
}

class _Gallery extends StatelessWidget {
  const _Gallery();

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SubPageHeader(
              onBack: () {},
              onHome: () {},
              trail: [
                (label: s.guide.tileReports, onTap: () {}),
                (label: s.guide.tilePlugins, onTap: null),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: RtlTextField(
                    decoration: InputDecoration(
                      labelText: s.guide.tileApp,
                      helperText: s.guide.tileLibrary,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: RtlTextField(
                    decoration: InputDecoration(hintText: 'Search'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                AppSegmentedControl<int>(
                  options: [
                    SegmentOption(value: 0, label: s.shell.breadcrumbHome),
                    SegmentOption(value: 1, label: s.guide.tileApp),
                    SegmentOption(value: 2, label: s.guide.tileLibrary),
                  ],
                  currentValue: 1,
                  onChanged: (_) {},
                ),
                AppDropdownField<int>(
                  value: 0,
                  entries: [
                    AppMenuEntry(value: 0, label: s.shell.breadcrumbHome),
                    AppMenuEntry(value: 1, label: s.guide.tileApp),
                  ],
                  onSelected: (_) {},
                ),
                CustomSwitch(value: true, onChanged: (_) {}),
                CustomSwitch(value: false, onChanged: (_) {}),
                const CustomSwitch(value: true, onChanged: null),
              ],
            ),
            const SizedBox(height: 16),
            const Wrap(
              spacing: 12,
              children: [
                IconTile(icon: FluentIcons.info_24_regular),
                IconTile(
                    icon: FluentIcons.info_24_regular,
                    tone: IconTileTone.quiet),
                IconTile(
                    icon: FluentIcons.info_24_regular,
                    tone: IconTileTone.error),
                IconTile(
                    icon: FluentIcons.info_24_regular, size: IconTileSize.sm),
              ],
            ),
            const SizedBox(height: 16),
            AppCard.section(
              children: [
                ListTile(title: Text(s.shell.breadcrumbHome)),
                ListTile(title: Text(s.guide.tileApp)),
              ],
            ),
            const SizedBox(height: 16),
            OptionCard(
              icon: FluentIcons.arrow_download_24_regular,
              title: s.guide.tileLibrary,
              description: s.guide.tilePlugins,
              selected: true,
              onSelected: () {},
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              children: [
                ActionButton.recommended(
                    text: s.common.install, onPressed: () {}),
                ActionButton.neutral(text: s.common.cancel, onPressed: () {}),
                ActionButton.ghost(text: s.common.cancel, onPressed: () {}),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NeverRunningLocator extends RunningOtzariaLocator {
  const _NeverRunningLocator();

  @override
  Future<RunningOtzariaProbe> probe() async =>
      (isRunning: false, launchPath: null);
}

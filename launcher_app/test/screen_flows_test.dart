import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/launcher_update_controller.dart';
import 'package:launcher_app/src/controllers/library_module_controller.dart';
import 'package:launcher_app/src/controllers/otzaria_module_controller.dart';
import 'package:launcher_app/src/controllers/plugins_module_controller.dart';
import 'package:launcher_app/src/screens/library_screen.dart';
import 'package:launcher_app/src/screens/otzaria_advanced_page.dart';
import 'package:launcher_app/src/settings/settings_controller.dart';
import 'package:launcher_app/src/shell/shell_keys.dart';
import 'package:launcher_app/src/theme/theme_exports.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import 'test_harness.dart';

class _FakeOtzaria extends OtzariaModuleController {
  _FakeOtzaria(String dataDir) : super(dataDir: dataDir);

  void Function(_FakeOtzaria c)? onInstall;
  int installs = 0;

  @override
  Future<void> install({bool useWizard = true}) async {
    installs++;
    onInstall?.call(this);
  }

  bool running = false;
  bool closeSucceeds = true;
  int closes = 0;

  @override
  Future<bool> refreshRunningState({bool force = false}) async => running;

  @override
  Future<bool> closeRunning() async {
    closes++;
    if (closeSucceeds) running = false;
    return closeSucceeds;
  }
}

class _FakeLibrary extends LibraryModuleController {
  _FakeLibrary(String dataDir) : super(dataDir: dataDir);

  LibraryModuleStatus statusAfterApply = LibraryModuleStatus.upToDate;
  int updates = 0;
  int fullDownloads = 0;
  int checks = 0;
  VoidCallback? onUpdate;

  void _finishApply() {
    status = statusAfterApply;
    if (statusAfterApply == LibraryModuleStatus.upToDate) {
      localVersion = targetVersion;
    }
  }

  @override
  Future<void> update() async {
    updates++;
    onUpdate?.call();
    _finishApply();
  }

  @override
  Future<void> updateWithFullDownload() async {
    fullDownloads++;
    _finishApply();
  }

  @override
  Future<void> checkForUpdate({bool fresh = false}) async {
    checks++;
  }
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  useViewSize(tester, const Size(1400, 2800));
  AppL10n.use(AppLanguage.hebrew);
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      localizationsDelegates: const [
        GlobalCupertinoLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('he', 'IL'), Locale('en')],
      locale: const Locale('he', 'IL'),
      theme: AppThemeData.light(),
      builder: (context, navigator) => AppStringsScope(
        strings: AppL10n.stringsFor(AppLanguage.hebrew),
        child: navigator ?? const SizedBox.shrink(),
      ),
      home: screen,
    ),
  );
}

void main() {
  late Directory tempDir;
  late _FakeOtzaria otzaria;
  late _FakeLibrary library;
  late PluginsModuleController plugins;
  late SettingsController settings;
  late LauncherUpdateController launcherUpdate;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('launcher_flows_test');
    otzaria = _FakeOtzaria(tempDir.path);
    library = _FakeLibrary(tempDir.path);
    launcherUpdate = LauncherUpdateController(dataDir: tempDir.path);
    plugins = PluginsModuleController(mirrorRootDir: tempDir.path);
    settings = SettingsController(dataDir: tempDir.path);
  });

  tearDown(() {
    otzaria.dispose();
    library.dispose();
    plugins.dispose();
    launcherUpdate.dispose();
    settings.dispose();
    tempDir.deleteSync(recursive: true);
  });

  LibraryScreen libraryScreen({
    VoidCallback? onUpdateHere,
    VoidCallback? onInstallFull,
    bool busy = false,
  }) =>
      LibraryScreen(
        library: library,
        otzariaIsRunning: false,
        isDownloading: false,
        onProcessStateChanged: () async => false,
        onCloseOtzaria: () async => true,
        onRequestReindex: () async {},
        onGoToSettings: () {},
        onUpdateHere: onUpdateHere,
        onInstallFull: onInstallFull,
        busy: busy,
      );

  OtzariaAdvancedPage otzariaScreen({VoidCallback? onReinstall}) =>
      OtzariaAdvancedPage(
        otzaria: otzaria,
        settings: settings,
        onReinstall: onReinstall,
      );

  void libraryUpdateAvailable() {
    library.status = LibraryModuleStatus.updateAvailable;
    library.localVersion = 1;
    library.targetVersion = 2;
  }

  Future<void> openAdvanced(WidgetTester tester) async {
    await tester.tap(find.text(stringsOf().pages.advancedTitle));
    // מצב "בודק" מסתובב, ולכן בלי pumpAndSettle.
    await tester.pump();
  }

  // הדפים לא מריצים התקנה בעצמם: הפעולה עוברת למסך המשימה ("עדכון כאן"),
  // שבו נבדקת אוצריא הפתוחה ושם נאמרת התוצאה — ראו update_here_flow_test.
  group('עדכון הספרייה מהדף — דרך מסך המשימה', () {
    testWidgets('"עדכון הספרייה" מוסר למשימה, בלי דו-שיח ובלי החלה כאן', (
      tester,
    ) async {
      libraryUpdateAvailable();
      var tasks = 0;
      await _pump(tester, libraryScreen(onUpdateHere: () => tasks++));

      await tester.tap(find.byKey(ShellKeys.statusPrimary));
      await tester.pumpAndSettle();
      expect(tasks, 1);
      expect(find.byType(AppDialog), findsNothing);
      expect(library.updates, 0);
    });

    testWidgets('בזמן משימה אחרת — הכפתור מושבת', (tester) async {
      libraryUpdateAvailable();
      await _pump(tester, libraryScreen(onUpdateHere: () {}, busy: true));
      expect(
        tester
            .widget<ActionButton>(find.byKey(ShellKeys.statusPrimary))
            .onPressed,
        isNull,
      );
    });

    testWidgets('הספרייה המלאה: רק אחרי כשל, ומוסרת למשימה', (tester) async {
      final t = stringsOf().libraryScreen;
      var full = 0;
      await _pump(tester, libraryScreen(onInstallFull: () => full++));
      expect(
        find.widgetWithText(ActionButton, t.fullDownloadInsteadButton),
        findsNothing,
      );
      await openAdvanced(tester);
      // השורה במתקדם תמיד שם — מושבתת עם הסבר.
      expect(find.text(stringsOf().pages.libFullUnavailable), findsOneWidget);
      expect(
        tester
            .widget<ActionButton>(
              find.widgetWithText(ActionButton, t.fullDownloadInsteadButton),
            )
            .onPressed,
        isNull,
      );

      library.status = LibraryModuleStatus.error;
      library.canRetryWithFullDownload = true;
      await _pump(tester, libraryScreen(onInstallFull: () => full++));
      await tester.tap(
        find.widgetWithText(ActionButton, t.fullDownloadInsteadButton).first,
      );
      await tester.pumpAndSettle();
      expect(full, 1);
      expect(find.byType(AppDialog), findsNothing);
      expect(library.fullDownloads, 0);
    });
  });

  group('התקנה מחדש מ"אוצריא — מתקדם" — דרך מסך המשימה', () {
    testWidgets('התקנה מחדש במתקדם — רק כשהגרסה שבכונן היא המותקנת', (
      tester,
    ) async {
      final t = stringsOf().appScreen;
      otzaria.status = OtzariaModuleStatus.upToDate;
      otzaria.currentVersion = '0.9.96';
      otzaria.latestVersion = '0.9.96';
      var reinstalls = 0;
      await _pump(tester, otzariaScreen(onReinstall: () => reinstalls++));
      await tester.tap(find.widgetWithText(ActionButton, t.reinstallButton));
      await tester.pumpAndSettle();
      expect(reinstalls, 1);
      expect(otzaria.installs, 0);
    });
  });
}

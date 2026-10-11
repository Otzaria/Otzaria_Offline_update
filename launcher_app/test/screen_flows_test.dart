import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/launcher_update_controller.dart';
import 'package:launcher_app/src/controllers/library_module_controller.dart';
import 'package:launcher_app/src/controllers/otzaria_module_controller.dart';
import 'package:launcher_app/src/controllers/plugins_module_controller.dart';
import 'package:launcher_app/src/screens/home_screen.dart';
import 'package:launcher_app/src/screens/library_screen.dart';
import 'package:launcher_app/src/screens/otzaria_screen.dart';
import 'package:launcher_app/src/settings/settings_controller.dart';
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
}

class _FakeLibrary extends LibraryModuleController {
  _FakeLibrary(String dataDir) : super(dataDir: dataDir);

  LibraryModuleStatus statusAfterApply = LibraryModuleStatus.upToDate;
  int updates = 0;
  int fullDownloads = 0;
  int checks = 0;

  void _finishApply() {
    status = statusAfterApply;
    if (statusAfterApply == LibraryModuleStatus.upToDate) {
      localVersion = targetVersion;
    }
  }

  @override
  Future<void> update() async {
    updates++;
    _finishApply();
  }

  @override
  Future<void> updateWithFullDownload() async {
    fullDownloads++;
    _finishApply();
  }

  @override
  Future<void> checkForUpdate() async {
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
      theme: AppThemeData.light(
        AppThemeData.createColorScheme(
          AppSeedColors.defaultLight,
          Brightness.light,
        ),
      ),
      builder: (context, navigator) => AppStringsScope(
        strings: AppL10n.stringsFor(AppLanguage.hebrew),
        child: navigator ?? const SizedBox.shrink(),
      ),
      home: screen,
    ),
  );
}

Finder _inDialog(String text) => find.descendant(
      of: find.byType(AppDialog),
      matching: find.text(text),
    );

Future<void> _confirm(WidgetTester tester, String confirmText) async {
  await tester.tap(_inDialog(confirmText));
  await tester.pumpAndSettle();
}

Future<void> _drainSnack(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 7));

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

  HomeScreen home({
    Future<bool> Function()? onProcessStateChanged,
    Future<bool> Function()? onCloseOtzaria,
    Future<void> Function()? onRequestReindex,
  }) =>
      HomeScreen(
        otzaria: otzaria,
        library: library,
        plugins: plugins,
        launcherUpdate: launcherUpdate,
        settings: settings,
        otzariaIsRunning: false,
        onCloseOtzaria: onCloseOtzaria ?? () async => true,
        isDownloading: false,
        isCancellingDownload: false,
        isCheckingOnline: false,
        longTaskRunning: false,
        onProcessStateChanged: onProcessStateChanged ?? () async => false,
        onCheckOnline: () async {},
        onDownloadAll: () async {},
        onCancelDownload: () async {},
        onDownloadLauncherUpdate: () async {},
        onInstallLauncherUpdate: () async {},
        onRequestReindex: onRequestReindex ?? () async {},
        onGoToOtzaria: () {},
        onGoToLibrary: () {},
      );

  LibraryScreen libraryScreen({
    Future<bool> Function()? onProcessStateChanged,
    Future<void> Function()? onRequestReindex,
  }) =>
      LibraryScreen(
        library: library,
        otzariaIsRunning: false,
        isDownloading: false,
        onProcessStateChanged: onProcessStateChanged ?? () async => false,
        onCloseOtzaria: () async => true,
        onRequestReindex: onRequestReindex ?? () async {},
        onGoToSettings: () {},
      );

  OtzariaScreen otzariaScreen() => OtzariaScreen(
        otzaria: otzaria,
        settings: settings,
        otzariaIsRunning: false,
        onCloseOtzaria: () async => true,
      );

  void libraryUpdateAvailable() {
    library.status = LibraryModuleStatus.updateAvailable;
    library.localVersion = 1;
    library.targetVersion = 2;
  }

  group('אישור עדכון הספרייה — אותו מסלול מכל נקודת כניסה', () {
    testWidgets('מדף הבית: מעדכן, מודיע על ההצלחה ומציע עדכון אינדקס', (
      tester,
    ) async {
      final t = stringsOf().home;
      libraryUpdateAvailable();
      var reindex = 0;
      await _pump(tester, home(onRequestReindex: () async => reindex++));

      await tester.tap(find.text(stringsOf().common.update));
      await tester.pumpAndSettle();
      expect(_inDialog(t.libraryUpdateDialogTitle), findsOneWidget);
      expect(_inDialog(t.libraryUpdatePrompt('1', '2')), findsOneWidget);
      expect(_inDialog(t.doNotRemoveDriveWarning), findsOneWidget);
      await _confirm(tester, t.libraryUpdateConfirm);

      expect(library.updates, 1);
      expect(find.text(t.libraryUpdatedSnack('2')), findsOneWidget);
      expect(reindex, 1);
      await _drainSnack(tester);
    });

    testWidgets('ממסך הספרייה: אותו מסלול, עם כותרת המסך', (tester) async {
      final t = stringsOf().home;
      libraryUpdateAvailable();
      var reindex = 0;
      await _pump(
        tester,
        libraryScreen(onRequestReindex: () async => reindex++),
      );

      await tester.tap(
        find.widgetWithText(
          ActionButton,
          stringsOf().libraryScreen.installUpdateButton,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        _inDialog(stringsOf().libraryScreen.updateDialogTitle),
        findsOneWidget,
      );
      expect(_inDialog(t.libraryUpdatePrompt('1', '2')), findsOneWidget);
      await _confirm(tester, t.libraryUpdateConfirm);

      expect(library.updates, 1);
      expect(find.text(t.libraryUpdatedSnack('2')), findsOneWidget);
      expect(reindex, 1);
      await _drainSnack(tester);
    });

    testWidgets('עדכון שנכשל: בלי הודעת הצלחה, והצעת האינדקס עדיין נשאלת', (
      tester,
    ) async {
      final t = stringsOf().home;
      libraryUpdateAvailable();
      library.statusAfterApply = LibraryModuleStatus.error;
      var reindex = 0;
      await _pump(tester, home(onRequestReindex: () async => reindex++));

      await tester.tap(find.text(stringsOf().common.update));
      await tester.pumpAndSettle();
      await _confirm(tester, t.libraryUpdateConfirm);

      expect(library.updates, 1);
      expect(find.text(t.libraryUpdatedSnack('2')), findsNothing);
      expect(reindex, 1);
    });

    testWidgets('ביטול בדיאלוג: שום דבר לא רץ', (tester) async {
      libraryUpdateAvailable();
      var reindex = 0;
      await _pump(
        tester,
        libraryScreen(onRequestReindex: () async => reindex++),
      );

      await tester.tap(
        find.widgetWithText(
          ActionButton,
          stringsOf().libraryScreen.installUpdateButton,
        ),
      );
      await tester.pumpAndSettle();
      await _confirm(tester, stringsOf().common.cancel);

      expect(library.updates, 0);
      expect(reindex, 0);
    });

    testWidgets('הספרייה המלאה במקום הדלתא: מתקינה, מודיעה ומציעה אינדקס', (
      tester,
    ) async {
      final t = stringsOf().libraryScreen;
      libraryUpdateAvailable();
      library.status = LibraryModuleStatus.error;
      library.canRetryWithFullDownload = true;
      var reindex = 0;
      var checks = 0;
      await _pump(
        tester,
        libraryScreen(
          onProcessStateChanged: () async {
            checks++;
            return false;
          },
          onRequestReindex: () async => reindex++,
        ),
      );

      await tester.tap(
        find.widgetWithText(ActionButton, t.fullDownloadInsteadButton),
      );
      await tester.pumpAndSettle();
      expect(_inDialog(t.fullDownloadInsteadDialogTitle), findsOneWidget);
      await _confirm(tester, stringsOf().common.install);

      expect(checks, 1);
      expect(library.fullDownloads, 1);
      expect(library.updates, 0);
      expect(
        find.text(stringsOf().home.libraryUpdatedSnack('2')),
        findsOneWidget,
      );
      expect(reindex, 1);
      await _drainSnack(tester);
    });

    testWidgets('הספרייה המלאה נחסמת כשאוצריא פתוחה', (tester) async {
      final t = stringsOf().libraryScreen;
      libraryUpdateAvailable();
      library.status = LibraryModuleStatus.error;
      library.canRetryWithFullDownload = true;
      await _pump(
          tester, libraryScreen(onProcessStateChanged: () async => true));

      await tester.tap(
        find.widgetWithText(ActionButton, t.fullDownloadInsteadButton),
      );
      await tester.pumpAndSettle();

      expect(_inDialog(t.fullDownloadInsteadDialogTitle), findsNothing);
      expect(find.text(stringsOf().home.otzariaOpenSnack), findsOneWidget);
      expect(library.fullDownloads, 0);
      await _drainSnack(tester);
    });
  });

  group('התקנת אוצריא — טיפול אחיד בתוצאה', () {
    void appUpdateAvailable() {
      otzaria.status = OtzariaModuleStatus.updateAvailable;
      otzaria.currentVersion = '0.9.95';
      otzaria.latestVersion = '0.9.96';
    }

    testWidgets('מדף הבית: התקנה מוצלחת מודיעה על הגרסה', (tester) async {
      final t = stringsOf().home;
      appUpdateAvailable();
      otzaria.onInstall = (c) {
        c.status = OtzariaModuleStatus.upToDate;
        c.currentVersion = '0.9.96';
      };
      await _pump(tester, home());

      await tester.tap(find.text(stringsOf().common.install));
      await tester.pumpAndSettle();
      await _confirm(tester, t.appInstallConfirm);

      expect(otzaria.installs, 1);
      expect(find.text(t.appInstalledSnack('0.9.96')), findsOneWidget);
      await _drainSnack(tester);
    });

    testWidgets('ממסך התוכנה: התקנה מוצלחת מודיעה על הגרסה', (tester) async {
      final t = stringsOf().home;
      appUpdateAvailable();
      otzaria.onInstall = (c) {
        c.status = OtzariaModuleStatus.upToDate;
        c.currentVersion = '0.9.96';
      };
      await _pump(tester, otzariaScreen());

      await tester.tap(
        find.widgetWithText(
          ActionButton,
          stringsOf().appScreen.installUpdateButton,
        ),
      );
      await tester.pumpAndSettle();
      expect(_inDialog(t.appInstallDialogTitle), findsOneWidget);
      await _confirm(tester, t.appInstallConfirm);

      expect(otzaria.installs, 1);
      expect(find.text(t.appInstalledSnack('0.9.96')), findsOneWidget);
      await _drainSnack(tester);
    });

    testWidgets('ממסך התוכנה: התקנה חוזרת שבוטלה באשף אינה נקראת הצלחה', (
      tester,
    ) async {
      final t = stringsOf().appScreen;
      otzaria.status = OtzariaModuleStatus.upToDate;
      otzaria.currentVersion = '0.9.96';
      otzaria.latestVersion = '0.9.96';
      otzaria.onInstall = (c) {
        c.status = OtzariaModuleStatus.upToDate;
        c.noticeMessage = 'בוטל באשף';
      };
      await _pump(tester, otzariaScreen());

      await tester.tap(find.widgetWithText(ActionButton, t.reinstallButton));
      await tester.pumpAndSettle();
      expect(_inDialog(t.reinstallDialogTitle), findsOneWidget);
      await _confirm(tester, t.reinstallButton);

      expect(otzaria.installs, 1);
      expect(find.text('בוטל באשף'), findsOneWidget);
      expect(
        find.text(stringsOf().home.appInstalledSnack('0.9.96')),
        findsNothing,
      );
      await _drainSnack(tester);
    });

    testWidgets('מדף הבית: הודעה מהאשף גוברת על מצב "מעודכן"', (tester) async {
      final t = stringsOf().home;
      appUpdateAvailable();
      otzaria.currentVersion = null;
      library.isFreshInstall = true;
      library.status = LibraryModuleStatus.updateAvailable;
      library.targetVersion = 27;
      otzaria.onInstall = (c) {
        c.status = OtzariaModuleStatus.upToDate;
        c.currentVersion = '0.9.96';
        c.noticeMessage = 'האשף עדיין פתוח';
      };
      var processChecks = 0;
      await _pump(
        tester,
        home(
          onProcessStateChanged: () async {
            processChecks++;
            return false;
          },
        ),
      );

      await tester.tap(find.text(stringsOf().common.install).first);
      await tester.pumpAndSettle();
      await _confirm(tester, t.firstInstallConfirm);

      expect(otzaria.installs, 1);
      expect(find.text('האשף עדיין פתוח'), findsOneWidget);
      expect(find.text(t.appInstalledSnack('0.9.96')), findsNothing);
      expect(library.checks, 1);
      expect(processChecks, 0);
      expect(library.updates, 0);
      await _drainSnack(tester);
    });

    testWidgets('מדף הבית: התקנה שבוטלה באשף אינה ממשיכה לספרייה', (
      tester,
    ) async {
      final t = stringsOf().home;
      appUpdateAvailable();
      otzaria.currentVersion = null;
      library.isFreshInstall = true;
      library.status = LibraryModuleStatus.updateAvailable;
      library.targetVersion = 27;
      otzaria.onInstall = (c) {
        c.status = OtzariaModuleStatus.updateAvailable;
        c.noticeMessage = 'בוטל באשף';
      };
      await _pump(tester, home());

      await tester.tap(find.text(stringsOf().common.install).first);
      await tester.pumpAndSettle();
      await _confirm(tester, t.firstInstallConfirm);

      expect(find.text('בוטל באשף'), findsOneWidget);
      expect(library.checks, 0);
      expect(library.updates, 0);
      await _drainSnack(tester);
    });

    testWidgets('מחשב ריק: אחרי התוכנה הספרייה נבדקת מחדש ומותקנת', (
      tester,
    ) async {
      final t = stringsOf().home;
      appUpdateAvailable();
      otzaria.currentVersion = null;
      library.isFreshInstall = true;
      library.status = LibraryModuleStatus.updateAvailable;
      library.targetVersion = 27;
      otzaria.onInstall = (c) {
        c.status = OtzariaModuleStatus.upToDate;
        c.currentVersion = '0.9.96';
      };
      var reindex = 0;
      await _pump(tester, home(onRequestReindex: () async => reindex++));

      await tester.tap(find.text(stringsOf().common.install).first);
      await tester.pumpAndSettle();
      expect(_inDialog(t.firstInstallDialogTitle), findsOneWidget);
      await _confirm(tester, t.firstInstallConfirm);

      expect(otzaria.installs, 1);
      expect(library.checks, 1);
      expect(library.updates, 1);
      expect(find.text(t.libraryUpdatedSnack('27')), findsOneWidget);
      expect(reindex, 1);
      await _drainSnack(tester);
    });

    testWidgets('מחשב ריק: אוצריא שלא נסגרה — דילוג משאיר את הספרייה', (
      tester,
    ) async {
      final t = stringsOf().home;
      appUpdateAvailable();
      otzaria.currentVersion = null;
      library.isFreshInstall = true;
      library.status = LibraryModuleStatus.updateAvailable;
      library.targetVersion = 27;
      otzaria.onInstall = (c) {
        c.status = OtzariaModuleStatus.upToDate;
        c.currentVersion = '0.9.96';
      };
      var closes = 0;
      var reindex = 0;
      await _pump(
        tester,
        home(
          onProcessStateChanged: () async => true,
          onCloseOtzaria: () async {
            closes++;
            return false;
          },
          onRequestReindex: () async => reindex++,
        ),
      );

      await tester.tap(find.text(stringsOf().common.install).first);
      await tester.pumpAndSettle();
      await _confirm(tester, t.firstInstallConfirm);

      expect(closes, 1);
      expect(_inDialog(t.closeOtzariaForLibraryDialogTitle), findsOneWidget);
      await _confirm(tester, stringsOf().common.cancel);

      expect(library.checks, 1);
      expect(library.updates, 0);
      expect(reindex, 0);
      await _drainSnack(tester);
    });
  });
}

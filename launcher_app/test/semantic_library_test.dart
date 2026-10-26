import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/library_module_controller.dart';
import 'package:launcher_app/src/screens/library_screen.dart';
import 'package:launcher_app/src/shell/shell_keys.dart';
import 'package:library_manager/library_manager.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import 'test_harness.dart';

void main() {
  for (final pending in [false, true]) {
    for (final granted in [false, true]) {
      test('semantic update pending=$pending consent=$granted', () {
        final check = LibraryUpdateCheckResult(
          dbPath: 'seforim.db',
          semanticPending: pending,
          semanticConsentGranted: granted,
        );

        expect(check.dbUpdateAvailable, isFalse);
        expect(check.updateAvailable, pending && granted);
        expect(check.companionsPending, pending && granted);
      });
    }
  }

  group('semantic library controller and screen', () {
    late Directory tempDir;
    late LibraryModuleController library;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('semantic-library-ui-');
      library = LibraryModuleController(dataDir: tempDir.path);
    });

    tearDown(() async {
      library.dispose();
      await tempDir.delete(recursive: true);
      AppL10n.use(AppLanguage.hebrew);
    });

    for (final language in [AppLanguage.hebrew, AppLanguage.english]) {
      test('consented smart search is named as a companion in $language', () {
        AppL10n.use(language);
        library
          ..status = LibraryModuleStatus.updateAvailable
          ..semanticPending = true
          ..semanticConsentGranted = true;

        expect(library.semanticConsentRequired, isFalse);
        expect(library.companionsOnly, isTrue);
        expect(library.pendingCompanionNames,
            stringsOf(language).libraryDomain.companionSemanticName);

        library.semanticConsentGranted = false;
        expect(library.semanticConsentRequired, isTrue);
        expect(library.companionsOnly, isFalse);
        expect(library.pendingCompanionNames, isEmpty);
      });

      testWidgets('missing consent is explained in plain words in $language',
          (tester) async {
        final pages = stringsOf(language).pages;
        library
          ..status = LibraryModuleStatus.upToDate
          ..localVersion = 27
          ..targetVersion = 27
          ..semanticPending = true;
        var grants = 0;

        LibraryScreen screen() => LibraryScreen(
              library: library,
              otzariaIsRunning: false,
              isDownloading: false,
              onProcessStateChanged: () async => false,
              onCloseOtzaria: () async => true,
              onRequestReindex: () async {},
              onGoToSettings: () {},
              onGrantSemanticConsent: () async => grants++,
            );

        await pumpScreen(tester, screen(), language: language);
        expect(find.text(pages.libSemanticBody), findsOneWidget);
        expect(find.text(pages.libSemanticClosedNote), findsOneWidget);
        expect(tester.takeException(), isNull);
        // הלחיצה מגיעה לסשן — שם בדיקת התהליך הטרייה והגילוי המלא.
        await tester.tap(find.text(pages.libSemanticGrant));
        expect(grants, 1);

        library.semanticConsentGranted = true;
        await tester.pumpWidget(wrap(screen(), language: language));
        expect(find.text(pages.libSemanticBody), findsNothing);
        expect(find.text(pages.libSemanticGrant), findsNothing);
        expect(find.text(pages.libSemanticActiveBody), findsOneWidget);

        library
          ..semanticPending = false
          ..semanticConsentGranted = false;
        await tester.pumpWidget(wrap(screen(), language: language));
        expect(find.byKey(ShellKeys.libraryConsent), findsNothing);
      });
    }
  });
}

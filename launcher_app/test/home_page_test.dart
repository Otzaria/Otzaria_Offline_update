// דף הבית מהמודל: כל מצב של ההכוונה מציג את הגיבור, האריחים וההודעות
// הנכונים, וכל כפתור מפעיל את הפעולה שלו. בלי סשן ובלי קונטרולרים — מלבד
// בדיקות המדים בסוף, שקוראות מ-progress של קונטרולרים אמיתיים.

import 'dart:convert';
import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/launcher_update_controller.dart';
import 'package:launcher_app/src/controllers/library_module_controller.dart';
import 'package:launcher_app/src/controllers/otzaria_module_controller.dart';
import 'package:launcher_app/src/controllers/plugins_module_controller.dart';
import 'package:launcher_app/src/flows/library_flows.dart'
    show LibraryChangesCard;
import 'package:launcher_app/src/screens/home/home_page.dart';
import 'package:launcher_app/src/screens/home/home_progress.dart';
import 'package:launcher_app/src/screens/home/home_view_model.dart';
import 'package:launcher_app/src/screens/home/whats_new_dialog.dart';
import 'package:launcher_app/src/self_update/launcher_release.dart';
import 'package:launcher_app/src/services/byte_size.dart';
import 'package:launcher_app/src/shell/home_guidance.dart';
import 'package:launcher_app/src/shell/shell_keys.dart';
import 'package:launcher_app/src/shell/shell_navigator.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';
import 'package:library_manager/library_manager.dart' show LibraryChangesNote;
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;
import 'package:plugins_manager/plugins_manager.dart' show PluginsOnlineStatus;

import 'home_fixtures.dart';
import 'test_harness.dart';

void main() {
  final g = stringsOf().guide;
  final he = stringsOf();

  Finder inHero(Finder finder) =>
      find.descendant(of: find.byKey(ShellKeys.hero), matching: finder);

  ActionButton primary(WidgetTester tester) =>
      tester.widget<ActionButton>(find.byKey(ShellKeys.heroPrimary));

  for (final language in AppLanguage.values) {
    for (final size in [const Size(760, 560), const Size(1000, 720)]) {
      for (final scenario in ['uptodate', 'first']) {
        testWidgets('collected feedback notice: $language $size $scenario',
            (tester) async {
          await pumpScreen(
            tester,
            HomePage(
              model: HomeViewModel(
                guidance: homeScenario(scenario).guidance,
                searchFeedbackCollected: true,
                reportsIntro: true,
              ),
            ),
            language: language,
            size: size,
          );
          final notice = find.byKey(ShellKeys.searchFeedbackCollectedNotice);
          expect(notice, findsOneWidget);
          expect(
            find.descendant(
              of: notice,
              matching: find.text(
                stringsOf(language).errorReports.searchFeedbackCollected,
              ),
            ),
            findsOneWidget,
          );
          final collected = tester.widget<NoticeBanner>(notice);
          final reports = tester.widget<NoticeBanner>(
            find.byKey(ShellKeys.reportsIntroNotice),
          );
          expect(collected.kind, reports.kind);
          expect((collected.leading as IconTile).icon,
              (reports.leading as IconTile).icon);
          expect((collected.leading as IconTile).tone,
              (reports.leading as IconTile).tone);
          expect(collected.actions, isEmpty);
          expect(
              find.descendant(of: notice, matching: find.byType(ActionButton)),
              findsNothing);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  group('חיפוש חכם, קבצים שלא ירדו ובדיקה מחודשת', () {
    testWidgets('השורה המשנית מורידה, "נסה שוב" מנסה שוב — בלי "יש חדש"',
        (tester) async {
      final calls = <String>[];
      await pumpScreen(
        tester,
        HomePage(
          model: homeScenario('semanticOffer'),
          actions: HomeActions(
            onDownload: () => calls.add('download'),
            onDownloadSemantic: () => calls.add('semantic'),
            onRetryFailedDownloads: () => calls.add('retry'),
          ),
        ),
      );
      expect(inHero(find.text(g.upToDateTitle)), findsOneWidget);
      expect(find.text(g.semanticOfferNote), findsOneWidget);
      expect(
        find.text(g.failedDownloadsNote('תלמוד בבלי')),
        findsOneWidget,
      );

      await tester.tap(find.descendant(
        of: find.byKey(ShellKeys.heroSemanticOffer),
        matching: find.text(g.semanticOfferLink),
      ));
      await tester.tap(find.descendant(
        of: find.byKey(ShellKeys.heroFailedDownloads),
        matching: find.text(he.common.retry),
      ));
      expect(calls, ['semantic', 'retry']);
    });

    testWidgets('בלי הצעה — בלי שורה', (tester) async {
      await pumpScreen(tester, HomePage(model: homeScenario('uptodate')));
      expect(find.byKey(ShellKeys.heroSemanticOffer), findsNothing);
      expect(find.byKey(ShellKeys.heroFailedDownloads), findsNothing);
    });

    testWidgets('"בדקתי שוב — אין חדש" במקום "הכול מעודכן"', (tester) async {
      await pumpScreen(tester, HomePage(model: homeScenario('recheckNothing')));
      expect(inHero(find.text(g.recheckNothingTitle)), findsOneWidget);
      // השעה של הבדיקה שרצה, ובלי טענה על "מאז הבדיקה הקודמת".
      expect(
        find.text(g.recheckNothingBody('23:14', upToDate: true)),
        findsOneWidget,
      );
      expect(find.text(g.upToDateTitle), findsNothing);
    });

    test('latestOnlineCheck — רק בדיקות שהצליחו, המאוחרת מהן', () {
      final early = DateTime(2026, 10, 25, 9);
      final late = DateTime(2026, 10, 25, 11);
      expect(latestOnlineCheck(const []), isNull);
      expect(latestOnlineCheck([(late, 'offline'), (early, null)]), early);
      expect(
          latestOnlineCheck([(early, null), (null, null), (late, null)]), late);
      expect(latestOnlineCheck([(late, 'offline')]), isNull);
    });

    testWidgets('בלי בדיקה חדשה — "אין חדש" לפי הבדיקה הקודמת ושעתה',
        (tester) async {
      await pumpScreen(tester, HomePage(model: homeScenario('nothingNew')));
      expect(inHero(find.text(g.nothingNewTitle)), findsOneWidget);
      expect(
        find.text(g.nothingNewBody('23:14', upToDate: true)),
        findsOneWidget,
      );
    });

    testWidgets('חיפוש חכם שלא ירד — "אין חדש" בלי "הכונן מעודכן"',
        (tester) async {
      final m = homeScenario('nothingNew');
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: m.guidance,
            installedVersion: '0.10.4',
            foundNothing: FoundNothing.earlierCheck,
            onlineCheckedAt: m.onlineCheckedAt,
            semanticOffer: true,
          ),
        ),
      );
      final body = g.nothingNewBody('23:14', upToDate: false);
      expect(find.text(body), findsOneWidget);
      expect(
        find.text(g.nothingNewBody('23:14', upToDate: true)),
        findsNothing,
      );
      expect(find.byKey(ShellKeys.heroSemanticOffer), findsOneWidget);
      expect(find.text(g.upToDateTitle), findsNothing);
      expect(find.text(g.recheckNothingTitle), findsNothing);
    });

    for (final name in ['nothingNewAttention', 'nothingNewWelcome']) {
      testWidgets('$name: "אין חדש" נאמר גם כאן', (tester) async {
        await pumpScreen(tester, HomePage(model: homeScenario(name)));
        expect(find.byKey(ShellKeys.heroFoundNothing), findsOneWidget);
        expect(find.text(g.nothingNewNote('23:14')), findsOneWidget);
      });
    }

    testWidgets('יש מה להתקין כאן — "בדקתי שוב" כהערה', (tester) async {
      await pumpScreen(
        tester,
        HomePage(model: homeScenario('recheckNothingHere')),
      );
      expect(inHero(find.text(g.updateHereTitle)), findsOneWidget);
      expect(find.text(g.recheckNothingNote('23:14')), findsOneWidget);
      expect(find.byKey(ShellKeys.heroFailedDownloads), findsOneWidget);
    });
  });

  group('מצבי המוקאפ', () {
    final expectations = <String, ({String title, String? button})>{
      'offline': (title: g.updateHereTitle, button: g.updateHereButton),
      'online': (title: g.downloadTitle, button: g.downloadButton),
      'uptodate': (title: g.driveInstalledTitle, button: g.launchButton),
      'newer': (title: g.newerTitle, button: g.launchButton),
      'open': (title: g.updateHereTitle, button: g.updateHereButton),
      'readonly': (title: g.updateHereTitle, button: g.updateHereButton),
      'drivefull': (title: g.driveInstalledTitle, button: g.launchButton),
      'uptodateOnline': (title: g.upToDateTitle, button: g.launchButton),
      'checkFailed': (title: g.checkFailedTitle, button: g.launchButton),
      'othersPending': (title: g.othersPendingTitle, button: g.launchButton),
    };

    for (final MapEntry(key: name, value: want) in expectations.entries) {
      testWidgets('$name: גיבור עם כותרת וכפתור אחד ראשי', (tester) async {
        await pumpScreen(tester, HomePage(model: homeScenario(name)));

        expect(inHero(find.text(want.title)), findsOneWidget);
        expect(find.byKey(ShellKeys.heroPrimary), findsOneWidget);
        expect(primary(tester).text, want.button);
        expect(find.byKey(ShellKeys.welcome), findsNothing);
        // שלושת האריחים הקבועים תמיד שם.
        for (final section in [
          ShellSection.otzaria,
          ShellSection.library,
          ShellSection.plugins,
        ]) {
          expect(find.byKey(ShellKeys.tile(section)), findsOneWidget);
        }
      });
    }

    for (final name in ['first', 'firstOffline']) {
      testWidgets('$name: מסך הפתיחה במקום הבית', (tester) async {
        await pumpScreen(tester, HomePage(model: homeScenario(name)));

        expect(find.byKey(ShellKeys.welcome), findsOneWidget);
        expect(find.byKey(ShellKeys.hero), findsNothing);
        expect(find.text(g.welcomeTitle), findsOneWidget);
        final online = name == 'first';
        expect(
          find.text(g.welcomeDownloadButton),
          online ? findsOneWidget : findsNothing,
        );
        expect(
          find.text(g.welcomeHelpButton),
          online ? findsNothing : findsOneWidget,
        );
        expect(
          find.text(online ? g.welcomeLeadOnline : g.welcomeLeadOffline),
          findsOneWidget,
        );
        expect(find.text(g.youAreHere), findsOneWidget);
      });
    }

    testWidgets('offline: מה ייכלל — רשימה של תוכנה, ספרייה ותוספים, בלי גדלים',
        (
      tester,
    ) async {
      await pumpScreen(tester, HomePage(model: homeScenario('offline')));

      final list = find.byKey(ShellKeys.heroItems);
      Finder inList(String text) =>
          find.descendant(of: list, matching: find.text(text));
      final app = tester.getCenter(inList(g.itemUpdateTo('0.10.4')));
      final library = tester.getCenter(inList(g.itemLibraryUpdateTo(146)));
      final plugins = tester.getCenter(inList(g.itemPluginUpdates(3)));
      expect(app.dy, lessThan(library.dy));
      expect(library.dy, lessThan(plugins.dy));
      // הכול כבר בכונן — אין "עד X" ואין שורת סיכום.
      expect(find.byKey(ShellKeys.heroTotal), findsNothing);
      expect(find.textContaining(g.itemUpTo('')), findsNothing);
      expect(find.text(g.eyebrowOffline), findsOneWidget);
      expect(find.text(g.eyebrowOtzaria('0.10.3')), findsOneWidget);
    });

    testWidgets('online: הורדה ראשית, "לעדכן גם כאן" משני, והערה על הכונן', (
      tester,
    ) async {
      await pumpScreen(tester, HomePage(model: homeScenario('online')));

      // הגרסה הגולמית מהאתר ('v0.10.5+812') מוצגת בלי v ובלי build, וחנות
      // התוספים מתמזגת לשורת התוספים, בלי גרסה.
      final list = find.byKey(ShellKeys.heroItems);
      Finder inList(String text) =>
          find.descendant(of: list, matching: find.text(text));
      expect(inList(g.tileFactVersion('0.10.5')), findsOneWidget);
      expect(inList(he.pages.libVersion(147)), findsOneWidget);
      expect(inList(g.itemPluginsWithStore(3)), findsOneWidget);
      expect(find.textContaining('812'), findsNothing);
      expect(find.textContaining('v0.10'), findsNothing);
      // "עד X" לתוכנה ולספרייה; לתוספים אין חסם — והסיכום אומר זאת.
      expect(inList(g.itemUpTo(formatBytes(96 << 20))), findsOneWidget);
      expect(inList(g.itemUpTo(formatBytes(1229 << 20))), findsOneWidget);
      final pluginsRow = find.ancestor(
        of: inList(g.itemPluginsWithStore(3)),
        matching: find.byType(AppRow),
      );
      expect(
        find.descendant(
          of: pluginsRow,
          matching: find.textContaining(g.itemUpTo('')),
        ),
        findsNothing,
      );
      expect(
        inList(
          g.downloadTotal(
            formatBytes(1325 << 20),
            plusApp: false,
            plusLibrary: false,
            plusPlugins: true,
          ),
        ),
        findsOneWidget,
      );
      expect(inList(g.driveFree(formatBytes(29082 << 20))), findsOneWidget);
      // הסמל העגול יורד — הרשימה צריכה את הרוחב.
      expect(
        inHero(find.byIcon(FluentIcons.usb_stick_24_regular)),
        findsNothing,
      );
      expect(
        tester.widget<ActionButton>(find.byKey(ShellKeys.heroSecondary)).text,
        g.updateHereButton,
      );
      expect(find.text(g.updateHereTooNote('0.10.4')), findsOneWidget);
      expect(find.text(g.eyebrowOnline), findsOneWidget);
    });

    testWidgets('uptodate: מחשב לא מחובר — מה שבכונן מותקן, ופס התוספים החדשים',
        (
      tester,
    ) async {
      await pumpScreen(tester, HomePage(model: homeScenario('uptodate')));

      expect(find.text(g.driveInstalledBody('0.10.4')), findsOneWidget);
      expect(find.text(g.upToDateTitle), findsNothing);
      expect(find.text(g.offlineNote), findsOneWidget);
      // בלי שורה עליונה, בלי "בדוק שוב" בגיבור, ובלי המילה של הרשת.
      expect(find.byKey(ShellKeys.eyebrow), findsNothing);
      expect(find.byKey(ShellKeys.heroSecondary), findsNothing);
      expect(find.byKey(ShellKeys.checkNow), findsOneWidget);
      expect(find.textContaining('אינטרנט'), findsNothing);
      expect(find.textContaining('מעודכן לפי הכונן'), findsNothing);
      expect(find.byKey(ShellKeys.newPluginsBanner), findsOneWidget);
      expect(
        find.byKey(ShellKeys.tile(ShellSection.customApps)),
        findsOneWidget,
      );
      expect(find.byKey(ShellKeys.tile(ShellSection.reports)), findsNothing);
      expect(find.byKey(ShellKeys.launcherLine), findsNothing);
    });

    testWidgets('בלי תוכנות נוספות ובלי דיווחים — אין להם אריחים', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(guidance: homeScenario('uptodate').guidance),
        ),
      );
      expect(
        find.byKey(ShellKeys.tile(ShellSection.customApps)),
        findsNothing,
      );
      expect(find.byKey(ShellKeys.tile(ShellSection.reports)), findsNothing);
    });

    // דיווחי הכלי עצמו נשלחים מאותו דף — ולכן נספרים באותו אריח.
    testWidgets('דיווחי הכלי שממתינים נספרים באריח הדיווחים', (tester) async {
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: homeScenario('uptodate').guidance,
            reportsToSend: 1,
            toolReportsPending: 2,
          ),
        ),
      );
      expect(find.byKey(ShellKeys.tile(ShellSection.reports)), findsOneWidget);
      expect(find.text(stringsOf().guide.chipReportsToSend(3)), findsOneWidget);

      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: homeScenario('uptodate').guidance,
            toolReportsPending: 1,
          ),
        ),
      );
      expect(find.byKey(ShellKeys.tile(ShellSection.reports)), findsOneWidget);
    });

    testWidgets('newer: פס התוספים החדשים מוצג גם כשהמותקנת חדשה מהכונן', (
      tester,
    ) async {
      final newer = homeScenario('newer');
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: newer.guidance,
            installedVersion: newer.installedVersion,
            driveAppVersion: newer.driveAppVersion,
            newPlugins: const ['דף יומי'],
          ),
        ),
      );
      expect(newer.guidance.primary, GuidancePrimary.newerHereThanDrive);
      expect(find.byKey(ShellKeys.newPluginsBanner), findsOneWidget);
    });

    testWidgets('newer: בלי פעולה מהכונן, ושתי הגרסאות בגוף', (tester) async {
      await pumpScreen(tester, HomePage(model: homeScenario('newer')));

      expect(find.text(g.newerBody('0.10.5', '0.10.4')), findsOneWidget);
      expect(find.text(g.newerNote), findsOneWidget);
      expect(find.text(g.chipNewerHere), findsOneWidget);
      expect(find.byKey(ShellKeys.newPluginsBanner), findsNothing);
    });

    testWidgets('newer בערוץ שנבחר: הכותרת והגוף מציינים את הערוץ', (
      tester,
    ) async {
      final newer = homeScenario('newer');
      for (final stable in [true, false]) {
        await pumpScreen(
          tester,
          HomePage(
            model: HomeViewModel(
              guidance: newer.guidance,
              installedVersion: newer.installedVersion,
              driveAppVersion: newer.driveAppVersion,
              appAwaitsNewerStable: stable,
            ),
          ),
        );

        expect(find.text(g.newerChannelTitle(stable: stable)), findsOneWidget);
        expect(
          find.text(stringsOf().pages.appAwaitsNewer(stable: stable)),
          findsOneWidget,
        );
        expect(find.text(g.newerTitle), findsNothing);
        expect(find.text(g.newerBody('0.10.5', '0.10.4')), findsNothing);
      }
    });

    testWidgets('open: פס "אוצריא פתוחה כרגע" כמו במוקאפ, בלי כפתור', (
      tester,
    ) async {
      await pumpScreen(tester, HomePage(model: homeScenario('open')));

      final banner = find.byKey(ShellKeys.otzariaOpenBanner);
      expect(banner, findsOneWidget);
      expect(
        find.descendant(of: banner, matching: find.text(g.otzariaOpenTitle)),
        findsOneWidget,
      );
      // ההתקנה האוטומטית דילגה — נאמר בפתיח של אותו פס.
      expect(
        find.text('${g.autoInstallSkippedLead}${g.otzariaOpenBody}'),
        findsOneWidget,
      );
      expect(
        find.descendant(of: banner, matching: find.byType(ActionButton)),
        findsNothing,
      );
      expect(find.text(he.common.closeOtzariaButton), findsNothing);
    });

    testWidgets('readonly: הודעת הכונן המוגן, בלי שורת הורדה נעולה', (
      tester,
    ) async {
      await pumpScreen(tester, HomePage(model: homeScenario('readonly')));

      expect(find.byKey(ShellKeys.readOnlyNotice), findsOneWidget);
      expect(find.text(he.readOnlyDrive.bannerTitle), findsOneWidget);
      // בכונן מוגן אין בדיקה ברשת, ולכן גם אין מה "לנעול".
      expect(find.text(g.downloadButton), findsNothing);
      expect(find.text(g.checkNowLink), findsNothing);
      expect(find.byKey(ShellKeys.checkNow), findsNothing);
    });

    testWidgets('readonly: אריח הדיווחים מוצג, נעול ("לא זמין בכונן הזה")', (
      tester,
    ) async {
      await pumpScreen(tester, HomePage(model: homeScenario('readonly')));

      final tile = find.byKey(ShellKeys.tile(ShellSection.reports));
      expect(tile, findsOneWidget);
      final chip = tester.widget<StatusChip>(
        find.descendant(of: tile, matching: find.byType(StatusChip)),
      );
      expect(chip.kind, StatusKind.locked);
      expect(chip.label, g.chipReportsLocked);
    });

    testWidgets('drivefull: הודעת הכונן המלא, ואריח דיווחים נעול', (
      tester,
    ) async {
      await pumpScreen(tester, HomePage(model: homeScenario('drivefull')));

      expect(find.byKey(ShellKeys.driveFullNotice), findsOneWidget);
      expect(find.text(he.readOnlyDrive.bannerTitleDriveFull), findsOneWidget);
      expect(find.byKey(ShellKeys.newPluginsBanner), findsOneWidget);
      expect(
        find.byKey(ShellKeys.tile(ShellSection.customApps)),
        findsOneWidget,
      );
      expect(find.text(g.chipReportsLocked), findsOneWidget);
    });
  });

  group('הפעולות', () {
    testWidgets('הכפתורים הראשיים מפעילים את הזרימה של כל מצב', (
      tester,
    ) async {
      final calls = <String>[];
      final actions = HomeActions(
        onInstallHere: () => calls.add('install'),
        onUpdateHere: () => calls.add('update'),
        onDownload: () => calls.add('download'),
        onLaunch: () => calls.add('launch'),
        onRecheck: () => calls.add('recheck'),
      );
      Future<void> tapIn(String scenario, Key key) async {
        await pumpScreen(
          tester,
          HomePage(model: homeScenario(scenario), actions: actions),
        );
        await tester.tap(find.byKey(key));
        await tester.pump();
      }

      await tapIn('offline', ShellKeys.heroPrimary);
      await tapIn('online', ShellKeys.heroPrimary);
      await tapIn('online', ShellKeys.heroSecondary);
      await tapIn('uptodate', ShellKeys.heroPrimary);
      await tapIn('uptodateOnline', ShellKeys.heroSecondary);
      await tapIn('online', ShellKeys.heroLaunch);
      await tapIn('offline', ShellKeys.heroLaunch);
      expect(calls, [
        'update',
        'download',
        'update',
        'launch',
        'recheck',
        'launch',
        'launch',
      ]);
    });

    testWidgets('גיבור של עדכון — "פתח את אוצריא" רק כשאפשר להפעיל', (
      tester,
    ) async {
      // אוצריא פתוחה (open) או מצב רגוע, שבו ההפעלה היא הכפתור הראשי.
      for (final name in ['open', 'uptodate', 'newer']) {
        await pumpScreen(tester, HomePage(model: homeScenario(name)));
        expect(find.byKey(ShellKeys.heroLaunch), findsNothing, reason: name);
      }
    });

    testWidgets('התקנה ראשונה במחשב ריק כשבכונן יש תוכנה', (tester) async {
      var installs = 0;
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: deriveHomeGuidance(
              const GuidanceFacts(
                otzariaInstalled: false,
                otzariaMirrorVersion: '0.10.4',
                otzariaStatus: AppStatusFact.updateAvailable,
                libraryStatus: LibraryStatusFact.updateAvailable,
                libraryFreshInstall: true,
                online: false,
              ),
            ),
            driveAppVersion: '0.10.4',
          ),
          actions: HomeActions(onInstallHere: () => installs++),
        ),
      );

      expect(find.text(g.installHereTitle), findsOneWidget);
      expect(find.text(g.itemLibraryFull), findsOneWidget);
      expect(find.text(g.eyebrowNotInstalled), findsOneWidget);
      await tester.tap(find.byKey(ShellKeys.heroPrimary));
      expect(installs, 1);
    });

    testWidgets('"הורדת העדכונים" מושבתת בזמן בדיקה ברשת', (tester) async {
      final online = homeScenario('online');
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: online.guidance,
            online: true,
            installedVersion: online.installedVersion,
            onlineAppVersion: '0.10.5',
            isCheckingOnline: true,
          ),
        ),
      );
      expect(primary(tester).onPressed, isNull);
      // מושבת עם סיבה: המחוון מסתובב, כמו "בדוק עכשיו".
      expect(primary(tester).spinning, isTrue);
    });

    testWidgets('אריח פותח את המקטע שלו; פס התוספים החדשים פותח את החנות', (
      tester,
    ) async {
      final opened = <ShellSection>[];
      await pumpScreen(
        tester,
        HomePage(
          model: homeScenario('offline'),
          actions: HomeActions(onOpenSection: opened.add),
        ),
      );

      for (final section in [
        ShellSection.otzaria,
        ShellSection.library,
        ShellSection.plugins,
        ShellSection.customApps,
        ShellSection.reports,
      ]) {
        await tester.tap(find.byKey(ShellKeys.tile(section)));
      }
      await tester.tap(find.text(g.toPluginsButton));
      expect(opened, [
        ShellSection.otzaria,
        ShellSection.library,
        ShellSection.plugins,
        ShellSection.customApps,
        ShellSection.reports,
        ShellSection.plugins,
      ]);
      // אין מה להראות — אין "מה חדש?".
      expect(find.byKey(ShellKeys.heroWhatsNew), findsNothing);
    });

    testWidgets('הודעות במקום דיאלוגים: כל כפתור מפעיל את שלו', (tester) async {
      final calls = <String>[];
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: homeScenario('offline').guidance,
            installedVersion: '0.10.3',
            offersElevation: true,
            reportsIntro: true,
            legacyReportsNotice: true,
          ),
          actions: HomeActions(
            onRestartElevated: () => calls.add('elevate'),
            onDismissElevation: () => calls.add('notNow'),
            onDismissReportsIntro: () => calls.add('intro'),
            onDismissLegacyReports: () => calls.add('legacy'),
          ),
        ),
      );

      await tester.tap(find.text(he.elevation.bannerConfirm));
      await tester.tap(find.text(he.elevation.bannerDismiss));
      await tester.tap(
        find.descendant(
          of: find.byKey(ShellKeys.reportsIntroNotice),
          matching: find.text(he.errorReports.introDialogConfirm),
        ),
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(ShellKeys.legacyReportsNotice),
          matching: find.text(he.errorReports.introDialogConfirm),
        ),
      );
      expect(calls, ['elevate', 'notNow', 'intro', 'legacy']);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('הסבר הדיווחים בהודעה — פסקה אחת, בלי שורה ריקה', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: homeScenario('uptodate').guidance,
            reportsIntro: true,
          ),
        ),
      );
      final notice = tester.widget<NoticeBanner>(
        find.byKey(ShellKeys.reportsIntroNotice),
      );
      expect(he.errorReports.introDialogContent, contains('\n\n'));
      expect(notice.body, isNot(contains('\n')));
      // "הבנתי" באמצע גובה ההודעה (בלי השוליים התחתונים), לא בשורה הראשונה.
      final box = tester.getRect(find.byKey(ShellKeys.reportsIntroNotice));
      expect(
        tester.getCenter(find.text(he.errorReports.introDialogConfirm)).dy,
        closeTo(box.top + (box.height - 12) / 2, 1.5),
      );
    });

    testWidgets('אוצריא פתוחה בלי דילוג: אותו פס, בלי הפתיח על הדילוג', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: homeScenario('open').guidance,
            installedVersion: '0.10.3',
          ),
        ),
      );

      expect(find.byKey(ShellKeys.otzariaOpenBanner), findsOneWidget);
      expect(find.text(g.otzariaOpenBody), findsOneWidget);
      expect(find.textContaining(g.autoInstallSkippedLead), findsNothing);
    });

    testWidgets('דילוג אוטומטי כשאוצריא כבר נסגרה — אין פס "פתוחה"', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: homeScenario('offline').guidance,
            autoInstallSkipped: true,
          ),
        ),
      );
      expect(find.byKey(ShellKeys.otzariaOpenBanner), findsNothing);
      expect(find.textContaining(g.autoInstallSkippedLead), findsNothing);
    });

    // הורדה שהוסתרה ב"חזרה לבית": הביטול במסך המשימה, והבית מחזיר אליו.
    testWidgets('בזמן הורדה ברקע: מד ו"הצג התקדמות", בלי ביטול', (
      tester,
    ) async {
      var shown = 0;
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: deriveHomeGuidance(
              const GuidanceFacts(longTaskRunning: true),
            ),
            task: HomeTask.downloading,
          ),
          actions: HomeActions(onShowProgress: () => shown++),
          taskProgress: const Text('progress-slot'),
        ),
      );

      expect(find.text(g.taskDownloadingTitle), findsOneWidget);
      expect(find.text('progress-slot'), findsOneWidget);
      expect(find.text(he.common.cancel), findsNothing);
      expect(find.byKey(ShellKeys.heroSecondary), findsNothing);
      await tester.tap(find.byKey(ShellKeys.heroShowProgress));
      expect(shown, 1);
    });

    testWidgets('בזמן הורדה ברקע: "עדכון המחשב הזה" למה שכבר נכתב', (
      tester,
    ) async {
      var updates = 0;
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: deriveHomeGuidance(
              const GuidanceFacts(
                longTaskRunning: true,
                otzariaStatus: AppStatusFact.updateAvailable,
                libraryStatus: LibraryStatusFact.updateAvailable,
                hereDuringDownload: {GuidanceItem.app},
              ),
            ),
            task: HomeTask.downloading,
            installedVersion: 'v1',
          ),
          actions: HomeActions(onUpdateHere: () => updates++),
        ),
      );
      final button = find.byKey(ShellKeys.heroSecondary);
      expect(
        find.descendant(of: button, matching: find.text(g.updateHereButton)),
        findsOneWidget,
      );
      await tester.tap(button);
      expect(updates, 1);
    });

    testWidgets(
        'עדכון ספרייה לצד הורדה ברקע: "הצג התקדמות" לספרייה, ו"הצג את '
        'ההורדה" להורדה — שני כפתורים נפרדים', (tester) async {
      final pressed = <String>[];
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: deriveHomeGuidance(
              const GuidanceFacts(longTaskRunning: true),
            ),
            task: HomeTask.updatingLibrary,
            downloadBehind: true,
          ),
          actions: HomeActions(
            onShowProgress: () => pressed.add('library'),
            onShowDownload: () => pressed.add('download'),
          ),
        ),
      );

      expect(find.text(g.taskUpdatingLibraryTitle), findsOneWidget);
      await tester.tap(find.byKey(ShellKeys.heroShowProgress));
      await tester.tap(find.byKey(ShellKeys.heroShowDownload));
      expect(pressed, ['library', 'download']);
      expect(find.text(he.task.showDownload), findsOneWidget);
    });

    testWidgets('התקנת אוצריא לצד הורדה ברקע: ההתקדמות בגיבור, וההורדה בכפתור',
        (tester) async {
      var shown = 0;
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: deriveHomeGuidance(
              const GuidanceFacts(longTaskRunning: true),
            ),
            task: HomeTask.installingApp,
            downloadBehind: true,
          ),
          actions: HomeActions(onShowDownload: () => shown++),
          taskProgress: const Text('install-progress-slot'),
        ),
      );

      expect(find.text(g.taskInstallingAppTitle), findsOneWidget);
      expect(find.text('install-progress-slot'), findsOneWidget);
      await tester.tap(find.byKey(ShellKeys.heroShowDownload));
      expect(shown, 1);
    });

    testWidgets('תוצאת הורדה שהוזזה הצידה נגישה מהבית', (tester) async {
      var shown = 0;
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: deriveHomeGuidance(const GuidanceFacts()),
            downloadResultWaiting: true,
          ),
          actions: HomeActions(onShowDownload: () => shown++),
        ),
      );
      expect(find.text(he.task.showDownloadResult), findsOneWidget);
      await tester.tap(find.byKey(ShellKeys.heroShowDownload));
      expect(shown, 1);
    });
  });

  group('פעולה שרצה מחוץ לבית — נאמר מה רץ, ואיפה ההתקדמות', () {
    Future<List<ShellSection>> pumpTask(
      WidgetTester tester,
      HomeTask task,
    ) async {
      final opened = <ShellSection>[];
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: deriveHomeGuidance(
              const GuidanceFacts(longTaskRunning: true),
            ),
            task: task,
          ),
          actions: HomeActions(onOpenSection: opened.add),
        ),
      );
      return opened;
    }

    final cases = {
      HomeTask.syncingPlugins: (
        g.taskSyncingPluginsTitle,
        ShellSection.plugins
      ),
      HomeTask.updatingPlugins: (
        g.taskUpdatingPluginsTitle,
        ShellSection.plugins
      ),
      HomeTask.exportingStore: (
        g.taskExportingStoreTitle,
        ShellSection.plugins
      ),
      HomeTask.downloadingCustomApps: (
        g.taskDownloadingCustomAppsTitle,
        ShellSection.customApps,
      ),
      HomeTask.customApps: (g.taskCustomAppsTitle, ShellSection.customApps),
      HomeTask.installingLauncher: (
        g.taskInstallingLauncherTitle,
        ShellSection.launcher,
      ),
    };
    for (final MapEntry(key: task, value: (title, section)) in cases.entries) {
      testWidgets('$task: הכותרת והדף שלה', (tester) async {
        final opened = await pumpTask(tester, task);
        expect(find.text(title), findsOneWidget);
        expect(find.text(g.taskBusyTitle), findsNothing);
        await tester.tap(find.byKey(ShellKeys.heroShowProgress));
        expect(opened, [section]);
      });
    }

    testWidgets('הפעלה מחדש כמנהל — בלי דף להראות', (tester) async {
      await pumpTask(tester, HomeTask.restartingElevated);
      expect(find.text(g.taskRestartingElevatedTitle), findsOneWidget);
      expect(find.byKey(ShellKeys.heroShowProgress), findsNothing);
    });
  });

  group('הורדה לכונן — מה ייכלל ומה לא', () {
    HomeViewModel model({
      bool syncApp = true,
      bool syncPlugins = true,
      int pluginChanges = 0,
      bool catalogOnly = false,
      bool storeApp = false,
      bool libraryFailed = false,
    }) =>
        HomeViewModel(
          guidance: deriveHomeGuidance(
            GuidanceFacts(
              online: true,
              onlineApp: true,
              onlinePlugins: true,
              syncApp: syncApp,
              syncPlugins: syncPlugins,
            ),
          ),
          online: true,
          installedVersion: '0.10.4',
          onlineAppVersion: '0.10.5',
          onlinePluginChanges: pluginChanges,
          onlinePluginCatalogChanged: catalogOnly,
          onlineStoreApp: storeApp,
          syncApp: syncApp,
          syncPlugins: syncPlugins,
          libraryDownloadFailed: libraryFailed,
        );

    testWidgets('תוספים וחנות התוספים — שורה אחת, בלי מספר גרסה', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        HomePage(model: model(pluginChanges: 4, storeApp: true)),
      );
      expect(find.text(g.itemPluginsWithStore(4)), findsOneWidget);
      expect(find.text(g.itemPlugins(4)), findsNothing);
      expect(find.text(g.itemStoreApp), findsNothing);
      expect(inHero(find.text(g.tileFactVersion('0.10.5'))), findsOneWidget);
    });

    testWidgets('רק חנות התוספים התחדשה — "עדכון לחנות התוספים"', (
      tester,
    ) async {
      await pumpScreen(tester, HomePage(model: model(storeApp: true)));
      expect(find.text(g.itemStoreApp), findsOneWidget);
    });

    // תחליף ל'חנות שאין בה מה חדש אינה מוסיפה שורות לכרטיס'.
    testWidgets('בחנות אין מה חדש — אין שורת תוספים', (tester) async {
      await pumpScreen(tester, HomePage(model: model()));
      expect(inHero(find.text(g.tileApp)), findsOneWidget);
      expect(inHero(find.text(g.tilePlugins)), findsNothing);
    });

    testWidgets('בלי חסם ידוע — בלי מספר, ובלי סיכום', (tester) async {
      await pumpScreen(tester, HomePage(model: model(pluginChanges: 2)));
      expect(find.textContaining(g.itemUpTo('')), findsNothing);
      expect(find.byKey(ShellKeys.heroTotal), findsNothing);
    });

    test('תוסף שהקובץ שלו חסר בכונן נספר; תוסף שהוסר מהאתר — לא', () {
      expect(onlinePluginChangesOf(null), 0);
      expect(
        onlinePluginChangesOf(
          const PluginsOnlineStatus(
            newPlugins: ['a'],
            updatedPlugins: ['b', 'c'],
            missingPlugins: ['d'],
            removedPlugins: ['e'],
          ),
        ),
        4,
      );
      expect(
        onlinePluginChangesOf(
          const PluginsOnlineStatus(removedPlugins: ['e']),
        ),
        0,
      );
    });

    testWidgets('רק רשימת התוספים השתנתה (תוסף הוסר) — עדיין נאמר', (
      tester,
    ) async {
      await pumpScreen(tester, HomePage(model: model(catalogOnly: true)));
      expect(find.text(g.itemPluginsCatalog), findsOneWidget);
    });

    testWidgets('רכיב כבוי בהגדרות נאמר, עם קישור להגדרות', (tester) async {
      var settings = 0;
      await pumpScreen(
        tester,
        HomePage(
          model: model(syncPlugins: false, pluginChanges: 2),
          actions: HomeActions(onOpenSettings: () => settings++),
        ),
      );
      expect(
        find.text(g.syncOffNote(app: false, library: false, plugins: true)),
        findsOneWidget,
      );
      // התוספים לא יירדו, ולכן גם אינם ב"מה ייכלל".
      expect(find.text(g.itemPlugins(2)), findsNothing);
      await tester.tap(find.text(g.changeInSettingsLink));
      expect(settings, 1);
    });

    testWidgets('הורדת ספרייה שנכשלה נשארת כתובה עד ההורדה הבאה', (
      tester,
    ) async {
      await pumpScreen(tester, HomePage(model: model(libraryFailed: true)));
      expect(find.text(g.libraryRetryNote), findsOneWidget);
    });

    testWidgets('יש חדש באתר אבל שום רכיב לא מסומן — בלי כפתור הורדה', (
      tester,
    ) async {
      var settings = 0;
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: deriveHomeGuidance(
              const GuidanceFacts(
                online: true,
                onlineApp: true,
                syncApp: false,
                syncLibrary: false,
                syncPlugins: false,
              ),
            ),
            online: true,
            installedVersion: '0.10.4',
          ),
          actions: HomeActions(onOpenSettings: () => settings++),
        ),
      );
      expect(find.text(g.downloadButton), findsNothing);
      expect(find.text(g.noSyncSelectionNote), findsOneWidget);
      await tester.tap(find.text(g.chooseInSettingsLink));
      expect(settings, 1);
    });

    testWidgets(
        'יש חדש באתר רק ברכיב שההורדה שלו כבויה — נאמר מה, לא '
        '"לא נבחר שום דבר"', (tester) async {
      var settings = 0;
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: deriveHomeGuidance(
              const GuidanceFacts(
                online: true,
                onlineLibrary: true,
                syncLibrary: false,
              ),
            ),
            online: true,
            installedVersion: '0.10.4',
            onlineLibraryVersion: 33,
            syncLibrary: false,
          ),
          actions: HomeActions(onOpenSettings: () => settings++),
        ),
      );
      expect(find.text(g.noSyncSelectionNote), findsNothing);
      expect(
        find.text(
          g.syncOffOnlyNote(app: false, library: true, plugins: false),
        ),
        findsOneWidget,
      );
      expect(find.byKey(ShellKeys.homeSyncOffNote), findsOneWidget);
      await tester.tap(find.text(g.changeInSettingsLink));
      expect(settings, 1);
    });

    testWidgets('רק קבצים נלווים חדשים — לא "גרסה חדשה של הספרייה"', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: deriveHomeGuidance(
              const GuidanceFacts(
                online: true,
                onlineLibrary: true,
                syncLibrary: false,
              ),
            ),
            online: true,
            installedVersion: '0.10.4',
            onlineCompanionNames: 'התלמוד',
            syncLibrary: false,
          ),
        ),
      );
      expect(
        find.text(
          g.syncOffOnlyNote(
            app: false,
            library: true,
            plugins: false,
            libraryFilesOnly: true,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          g.syncOffOnlyNote(app: false, library: true, plugins: false),
        ),
        findsNothing,
      );
    });
  });

  group('שורת התחתית', () {
    HomeViewModel withLauncher(LauncherLine? line, {bool busy = false}) =>
        HomeViewModel(
          guidance: deriveHomeGuidance(
            GuidanceFacts(online: true, longTaskRunning: busy),
          ),
          online: true,
          launcher: line,
          onlineCheckedAt: DateTime(2026, 10, 23, 9, 5),
          driveName: 'E:',
        );

    testWidgets('גרסה חדשה באתר: "פרטים ועדכון" פותח את דף הכלי — לא התקנה', (
      tester,
    ) async {
      var opened = 0;
      await pumpScreen(
        tester,
        HomePage(
          model: withLauncher(
            const LauncherLine(LauncherLineKind.online, version: '3.3.0'),
          ),
          actions: HomeActions(onOpenLauncherUpdate: () => opened++),
        ),
      );
      expect(find.byTooltip(g.launcherOnline('3.3.0')), findsOneWidget);
      expect(find.text(he.launcherUpdate.installButton), findsNothing);
      await tester.tap(find.byKey(ShellKeys.launcherUpdateButton));
      expect(opened, 1);
    });

    testWidgets('גרסה שכבר בכונן: הקישור לדף הכלי, וחסום בזמן משימה', (
      tester,
    ) async {
      var opened = 0;
      const ready = LauncherLine(LauncherLineKind.ready, version: '3.3.0');
      await pumpScreen(
        tester,
        HomePage(
          model: withLauncher(ready),
          actions: HomeActions(onOpenLauncherUpdate: () => opened++),
        ),
      );
      expect(find.byTooltip(g.launcherOnDrive('3.3.0')), findsOneWidget);
      // ההתקנה עצמה בדף הכלי, לא בשורה שבבית.
      expect(find.text(he.launcherUpdate.installButton), findsNothing);
      await tester.tap(find.byKey(ShellKeys.launcherUpdateButton));
      expect(opened, 1);

      await pumpScreen(
        tester,
        HomePage(model: withLauncher(ready, busy: true)),
      );
      expect(
        tester
            .widget<ActionButton>(find.byKey(ShellKeys.launcherUpdateButton))
            .onPressed,
        isNull,
      );
    });

    testWidgets('בלי קובץ הרצה להחלפה: הקישור לדף הכלי, בלי כפתור התקנה', (
      tester,
    ) async {
      var opened = 0;
      await pumpScreen(
        tester,
        HomePage(
          model: withLauncher(
            const LauncherLine(LauncherLineKind.readyManual, version: '3.3.0'),
          ),
          actions: HomeActions(onOpenLauncherUpdate: () => opened++),
        ),
      );
      expect(find.byTooltip(g.launcherOnDrive('3.3.0')), findsOneWidget);
      expect(find.text(he.launcherUpdate.installButton), findsNothing);
      await tester.tap(find.byKey(ShellKeys.launcherUpdateButton));
      expect(opened, 1);
    });

    testWidgets('אין מה לומר על הכלי — אין שורה; "נבדק ב-" עם רמז Ctrl+R', (
      tester,
    ) async {
      await pumpScreen(tester, HomePage(model: withLauncher(null)));
      expect(find.byKey(ShellKeys.launcherLine), findsNothing);
      expect(find.text(g.checkedAt('09:05')), findsOneWidget);
      expect(
        tester.widget<Tooltip>(find.byKey(ShellKeys.checkedAt)).message,
        g.recheckHint,
      );
      expect(find.text(g.drive('E:')), findsOneWidget);
    });

    testWidgets('"בדוק עכשיו" תמיד ליד "נבדק ב-", ומפעיל את הבדיקה', (
      tester,
    ) async {
      var checks = 0;
      // מצב "עדכון כאן" — בלי "בדוק שוב" בגיבור, ובלי רשת שנבדקה.
      final here = homeScenario('offline');
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: here.guidance,
            online: true,
            installedVersion: '0.10.3',
            onlineCheckedAt: DateTime(2026, 10, 23, 9, 5),
          ),
          actions: HomeActions(onRecheck: () => checks++),
        ),
      );
      expect(find.text(g.recheckButton), findsNothing);
      final link = find.byKey(ShellKeys.checkNow);
      expect(link, findsOneWidget);
      // באותה שורה עם "נבדק ב-".
      expect(
        tester.getCenter(link).dy,
        closeTo(tester.getCenter(find.byKey(ShellKeys.checkedAt)).dy, 2),
      );
      await tester.tap(link);
      expect(checks, 1);
    });

    testWidgets('בזמן "בדוק עכשיו" — מחוון במקום הקישור', (tester) async {
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: homeScenario('offline').guidance,
            checkingNow: true,
          ),
        ),
      );
      final slot = find.byKey(ShellKeys.checkNow);
      expect(
        find.descendant(
          of: slot,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(find.text(g.checkNowLink), findsNothing);
    });

    testWidgets(
        'משימה שחוסמת את הבדיקה (ייצוא, סנכרון) — אין קישור, ו"בדוק שוב" מושבת',
        (tester) async {
      var checks = 0;
      final uptodate = homeScenario('uptodateOnline');
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: uptodate.guidance,
            online: true,
            installedVersion: uptodate.installedVersion,
            onlineCheckedAt: DateTime(2026, 10, 23, 9, 5),
            checkBlocked: true,
          ),
          actions: HomeActions(onRecheck: () => checks++),
        ),
      );
      expect(uptodate.guidance.primary, isNot(GuidancePrimary.taskInProgress));
      expect(find.byKey(ShellKeys.checkNow), findsNothing);
      expect(
        tester
            .widget<ActionButton>(find.byKey(ShellKeys.heroSecondary))
            .onPressed,
        isNull,
      );
      expect(checks, 0);
    });

    testWidgets('בזמן משימה אין "בדוק עכשיו", ו"פרטים ועדכון" מושבת', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        HomePage(
          model: withLauncher(
            const LauncherLine(LauncherLineKind.online, version: '3.3.0'),
            busy: true,
          ),
        ),
      );
      expect(find.byKey(ShellKeys.checkNow), findsNothing);
      expect(
        tester
            .widget<ActionButton>(find.byKey(ShellKeys.launcherUpdateButton))
            .onPressed,
        isNull,
      );
      // מושבת עם הסבר בריחוף.
      expect(find.byTooltip(he.pages.pageBusyNote), findsOneWidget);
    });

    testWidgets('שורת המצב צמודה לתחתית החלון, והמטא בקצה הסוף', (
      tester,
    ) async {
      await pumpScreen(tester, HomePage(model: withLauncher(null)));
      final bar = tester.getRect(find.byKey(ShellKeys.statusBar));
      final screen = tester.getRect(find.byType(HomePage));
      expect(bar.bottom, screen.bottom);
      expect(bar.width, screen.width);
      for (final key in [ShellKeys.driveLine, ShellKeys.checkedAt]) {
        expect(
          find.descendant(
            of: find.byKey(ShellKeys.statusBar),
            matching: find.byKey(key),
          ),
          findsOneWidget,
        );
      }
      // RTL: סוף השורה הוא השמאל.
      final checkNow = tester.getRect(find.byKey(ShellKeys.checkNow));
      expect(checkNow.left, closeTo(bar.left + 16, 1));
    });

    testWidgets('"לעזרה במקום" בתחתית הבית, מתחת לאריחים — רק כשהוגדר', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: deriveHomeGuidance(const GuidanceFacts(online: true)),
            installedVersion: '0.10.4',
            contactName: 'ר׳ ישראל',
            contactPhone: '050-0000000',
          ),
        ),
      );
      final contact = find.byKey(ShellKeys.homeContact);
      await tester.scrollUntilVisible(contact, 200);
      expect(
        find.descendant(of: contact, matching: find.text(he.faq.contactLead)),
        findsOneWidget,
      );
      final phone = find.descendant(
        of: contact,
        matching: find.text('050-0000000'),
      );
      expect(tester.widget<Text>(phone).textDirection, TextDirection.ltr);
      final tiles = find.byKey(
        ShellKeys.tile(ShellSection.library),
        skipOffstage: false,
      );
      expect(
        tester.getRect(contact).top,
        greaterThanOrEqualTo(tester.getRect(tiles).bottom),
      );
      // מעל שורת המצב, לא בתוכה.
      expect(
        find.descendant(
          of: find.byKey(ShellKeys.statusBar),
          matching: contact,
        ),
        findsNothing,
      );

      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: deriveHomeGuidance(const GuidanceFacts(online: true)),
            installedVersion: '0.10.4',
          ),
        ),
      );
      // עד סוף הרשימה — רשימה עצלה לא בונה מה שמחוץ לחלון.
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(tiles, findsOneWidget);
      expect(
          find.byKey(ShellKeys.homeContact, skipOffstage: false), findsNothing);
    });

    for (final (name, phone) in const [
      ('ר׳ ישראל', ''),
      ('', '050-0000000'),
    ]) {
      testWidgets('"לעזרה במקום" עם ${name.isEmpty ? 'טלפון' : 'שם'} בלבד', (
        tester,
      ) async {
        await pumpScreen(
          tester,
          HomePage(
            model: HomeViewModel(
              guidance: deriveHomeGuidance(const GuidanceFacts(online: true)),
              installedVersion: '0.10.4',
              contactName: name,
              contactPhone: phone,
            ),
          ),
        );
        final contact = find.byKey(ShellKeys.homeContact);
        await tester.scrollUntilVisible(contact, 200);
        final texts = tester
            .widgetList<Text>(
              find.descendant(of: contact, matching: find.byType(Text)),
            )
            .map((w) => w.data)
            .toList();
        expect(texts, [he.faq.contactLead, name.isEmpty ? phone : name]);
        if (phone.isNotEmpty) {
          final shown = find.descendant(
            of: contact,
            matching: find.text(phone),
          );
          expect(tester.widget<Text>(shown).textDirection, TextDirection.ltr);
        }
      });
    }

    testWidgets('כונן מוגן: שבב אדום עם מנעול ליד הכונן, ובלי מוגן — אין שבב', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: deriveHomeGuidance(const GuidanceFacts(readOnly: true)),
            driveName: 'E:',
          ),
        ),
      );
      final chip = find.descendant(
        of: find.byKey(ShellKeys.driveLine),
        matching: find.byKey(ShellKeys.driveLockedChip),
      );
      expect(chip, findsOneWidget);
      final widget = tester.widget<StatusChip>(chip);
      expect(widget.kind, StatusKind.error);
      expect(widget.label, g.driveReadOnlySuffix);
      expect(widget.icon, FluentIcons.lock_closed_16_regular);
      expect(
        tester
            .widget<IconTile>(
              find.descendant(
                of: find.byKey(ShellKeys.readOnlyNotice),
                matching: find.byType(IconTile),
              ),
            )
            .tone,
        IconTileTone.error,
      );

      await pumpScreen(tester, HomePage(model: withLauncher(null)));
      expect(find.byKey(ShellKeys.driveLine), findsOneWidget);
      expect(find.byKey(ShellKeys.driveLockedChip), findsNothing);
    });

    testWidgets('כונן מלא: השבב האדום אומר "מלא" עם סמל אחסון, לא מנעול', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: deriveHomeGuidance(
              const GuidanceFacts(readOnly: true, driveFull: true),
            ),
            driveName: 'E:',
          ),
        ),
      );
      final chip = find.descendant(
        of: find.byKey(ShellKeys.driveLine),
        matching: find.byKey(ShellKeys.driveLockedChip),
      );
      expect(chip, findsOneWidget);
      final widget = tester.widget<StatusChip>(chip);
      expect(widget.kind, StatusKind.error);
      expect(widget.label, g.driveFullSuffix);
      expect(widget.icon, FluentIcons.storage_16_regular);
    });

    testWidgets('"עדכון זמין" בתחילת שורת המצב — מימין בעברית', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        HomePage(
          model: withLauncher(
            const LauncherLine(LauncherLineKind.ready, version: '3.3.0'),
          ),
        ),
      );
      final bar = tester.getRect(find.byKey(ShellKeys.statusBar));
      final button = find.byKey(ShellKeys.launcherUpdateButton);
      expect(find.text(g.updateAvailableButton), findsOneWidget);
      expect(tester.getRect(button).right, closeTo(bar.right - 16, 1));
      expect(
        find.descendant(
          of: button,
          matching: find.byIcon(FluentIcons.arrow_download_24_regular),
        ),
        findsOneWidget,
      );
    });

    testWidgets('מצב החיבור בשורת המצב', (tester) async {
      await pumpScreen(tester, HomePage(model: homeScenario('offline')));
      expect(
        find.descendant(
          of: find.byKey(ShellKeys.connectionLine),
          matching: find.text(g.eyebrowOffline),
        ),
        findsOneWidget,
      );
    });

    testWidgets('שעת הבדיקה ברשת — רק במחשב מחובר', (tester) async {
      await pumpScreen(tester, HomePage(model: homeScenario('uptodateOnline')));
      expect(find.text(g.checkedAt('23:14')), findsOneWidget);

      // במחשב לא מחובר שורת המצב אינה מקבלת שעה, גם כשיש בדיקה ישנה.
      final online = homeScenario('uptodateOnline');
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: homeScenario('uptodate').guidance,
            online: false,
            onlineCheckedAt: online.onlineCheckedAt,
          ),
        ),
      );
      expect(find.byKey(ShellKeys.checkedAt), findsNothing);
      expect(find.byKey(ShellKeys.checkNow), findsOneWidget);
    });

    testWidgets('גרסת הכלי מוצגת בלי v', (tester) async {
      await pumpScreen(
        tester,
        HomePage(
          model: withLauncher(
            const LauncherLine(LauncherLineKind.online, version: 'v3.3.0'),
          ),
        ),
      );
      expect(find.byTooltip(g.launcherOnline('3.3.0')), findsOneWidget);
    });
  });

  group('מסך הפתיחה', () {
    testWidgets('כפתור השפה מציג את השפה האחרת ומחליף אותה', (tester) async {
      var toggles = 0;
      for (final language in AppLanguage.values) {
        await pumpScreen(
          tester,
          HomePage(
            model: homeScenario('first'),
            actions: HomeActions(onToggleLanguage: () => toggles++),
          ),
          language: language,
        );
        final s = stringsOf(language).settings;
        final other = language == AppLanguage.hebrew
            ? s.languageEnglish
            : s.languageHebrew;
        expect(
          tester
              .widget<ActionButton>(find.byKey(ShellKeys.welcomeLanguage))
              .text,
          other,
        );
        await tester.tap(find.byKey(ShellKeys.welcomeLanguage));
      }
      expect(toggles, 2);
    });

    testWidgets('בכונן מחובר הורדה; בלי אינטרנט — עזרה', (tester) async {
      final calls = <String>[];
      final actions = HomeActions(
        onDownload: () => calls.add('download'),
        onHelp: () => calls.add('help'),
      );
      for (final name in ['first', 'firstOffline']) {
        await pumpScreen(
          tester,
          HomePage(model: homeScenario(name), actions: actions),
        );
        await tester.tap(find.byKey(ShellKeys.welcomePrimary));
      }
      expect(calls, ['download', 'help']);
    });

    testWidgets('"הורדה" במסך הפתיחה מושבתת בזמן בדיקה ברשת, כמו בבית',
        (tester) async {
      final first = homeScenario('first');
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: first.guidance,
            online: true,
            isCheckingOnline: true,
          ),
        ),
      );
      expect(
        tester
            .widget<ActionButton>(find.byKey(ShellKeys.welcomePrimary))
            .onPressed,
        isNull,
      );
    });
  });

  group('המדים קוראים רק מ-progress', () {
    late Directory tempDir;
    late OtzariaModuleController otzaria;
    late LibraryModuleController library;
    late PluginsModuleController plugins;
    late LauncherUpdateController launcher;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('home_page_test');
      otzaria = OtzariaModuleController(
          dataDir: tempDir.path, platform: OtzariaTargetPlatform.windows);
      library = LibraryModuleController(dataDir: tempDir.path);
      plugins = PluginsModuleController(mirrorRootDir: tempDir.path);
      launcher = LauncherUpdateController(dataDir: tempDir.path);
    });

    tearDown(() {
      otzaria.dispose();
      library.dispose();
      plugins.dispose();
      launcher.dispose();
      tempDir.deleteSync(recursive: true);
    });

    Widget progress(HomeTask task) => HomeTaskProgress(
          task: task,
          otzaria: otzaria,
          library: library,
          plugins: plugins,
        );

    testWidgets('החלת ספרייה, הורדת תוכנה והורדת הכלי — בלי שינוי מצב', (
      tester,
    ) async {
      library.status = LibraryModuleStatus.updating;
      library.applyProgress = 0.1;
      otzaria.downloadStatus = OtzariaDownloadStatus.downloading;
      launcher.status = LauncherUpdateStatus.downloading;
      var stateNotifications = 0;
      void count() => stateNotifications++;
      library.addListener(count);
      otzaria.addListener(count);
      launcher.addListener(count);

      await pumpScreen(
        tester,
        Column(
          children: [
            progress(HomeTask.updatingLibrary),
            progress(HomeTask.downloading),
            LauncherDownloadPercent(controller: launcher),
          ],
        ),
      );
      expect(find.text('10%'), findsOneWidget);

      library.applyProgress = 0.42;
      library.notifyProgress();
      otzaria.downloadReceived = 30;
      otzaria.downloadTotal = 100;
      otzaria.notifyProgress();
      launcher.downloadReceived = 70;
      launcher.downloadTotal = 100;
      launcher.notifyProgress();
      await tester.pump();

      expect(find.text('42%'), findsOneWidget);
      expect(find.text('30%'), findsOneWidget);
      expect(find.text('70%'), findsOneWidget);
      expect(stateNotifications, 0);
    });

    testWidgets('הורדת הספרייה: שלב, שלב נלווה ובתים', (tester) async {
      library.downloadStatus = MirrorDownloadStatus.downloading;
      library.downloadStage = 'stage 1';
      library.downloadReceivedBytes = 10;
      library.downloadTotalBytes = 100;
      var stateNotifications = 0;
      library.addListener(() => stateNotifications++);

      await pumpScreen(tester, progress(HomeTask.downloading));
      expect(find.text('stage 1'), findsOneWidget);
      expect(find.text('10%'), findsOneWidget);

      library.downloadStage = 'stage 2';
      library.downloadCompanionStage = 'companion 2';
      library.downloadReceivedBytes = 2048;
      library.downloadTotalBytes = 4096;
      library.notifyProgress();
      await tester.pump();

      expect(find.text('stage 2'), findsOneWidget);
      expect(find.text('companion 2'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(find.text(formatBytesProgress(2048, 4096)!), findsOneWidget);
      expect(stateNotifications, 0);
    });

    testWidgets('סנכרון התוספים בתוך ההורדה', (tester) async {
      plugins.status = PluginsModuleStatus.syncing;
      plugins.syncMessage = 'sync 1';
      plugins.syncProgress = 0.2;
      var stateNotifications = 0;
      plugins.addListener(() => stateNotifications++);

      await pumpScreen(tester, progress(HomeTask.downloading));
      expect(find.text('sync 1'), findsOneWidget);
      expect(find.text('20%'), findsOneWidget);

      plugins.syncMessage = 'sync 2';
      plugins.syncProgress = 0.8;
      plugins.notifyProgress();
      await tester.pump();

      expect(find.text('sync 2'), findsOneWidget);
      expect(find.text('80%'), findsOneWidget);
      expect(stateNotifications, 0);
    });

    testWidgets('התקנת התוכנה: המד בגיבור, ו"הפסק להמתין" כשהאשף בחלון משלו',
        (tester) async {
      otzaria.status = OtzariaModuleStatus.installing;
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: deriveHomeGuidance(
              const GuidanceFacts(
                otzariaStatus: AppStatusFact.installing,
                installing: true,
              ),
            ),
            task: HomeTask.installingApp,
          ),
          taskProgress: progress(HomeTask.installingApp),
        ),
      );
      expect(inHero(find.text(g.taskInstallingAppTitle)), findsOneWidget);
      expect(find.byType(InfoProgressRow), findsOneWidget);
      // לא "הצג התקדמות" — ההתקדמות כבר כאן.
      expect(find.byKey(ShellKeys.heroShowProgress), findsNothing);
      expect(find.byKey(ShellKeys.heroStopWaiting), findsNothing);

      otzaria.installStage = he.appDomain.setupContinuesElsewhere;
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      otzaria.notifyListeners();
      await tester.pump();
      expect(find.text(he.appDomain.setupContinuesElsewhere), findsOneWidget);
      final stop = tester.widget<ActionButton>(
        find.byKey(ShellKeys.heroStopWaiting),
      );
      expect(stop.text, he.task.stopWaiting);
      expect(stop.onPressed, otzaria.stopWaitingForSetup);
    });

    testWidgets('"מה חדש?" — של הגרסה המותקנת כשאין עדכון, ושל הספרייה',
        (tester) async {
      await tester.runAsync(() async {
        writeAppMirror(tempDir.path, '1.0.0');
        await otzaria.checkForUpdate();
      });
      otzaria
        ..currentVersion = '1.0.0'
        ..status = OtzariaModuleStatus.upToDate;
      library
        ..changesNotes = const [
          LibraryChangesNote(releaseTag: 'v31-1', path: 'none.md'),
        ]
        ..changesNotesVersion = 31;
      final notes = whatsNewAppNotes(otzaria)!;
      expect(notes.installed, isTrue);

      await pumpScreen(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showHomeWhatsNewDialog(
              context,
              otzaria: otzaria,
              library: library,
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text(he.pages.appWhatsNew('1.0.0')), findsOneWidget);
      expect(find.text(he.pages.appInstalledNotesCaption), findsOneWidget);
      expect(find.text('מה התחדש ב-1.0.0'), findsOneWidget);
      expect(find.text(he.libraryScreen.changesTitle), findsOneWidget);
      expect(find.byType(LibraryChangesCard), findsOneWidget);

      await tester.tap(find.text(he.common.close));
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsNothing);
    });

    testWidgets('"מה חדש?" כשיש עדכון — של הגרסה שבכונן, בלי כיתוב "מותקנת"',
        (tester) async {
      await tester.runAsync(() async {
        writeAppMirror(tempDir.path, '1.1.0');
        await otzaria.checkForUpdate();
      });
      otzaria
        ..currentVersion = '1.0.0'
        ..status = OtzariaModuleStatus.updateAvailable;
      expect(whatsNewAppNotes(otzaria)?.installed, isFalse);

      await pumpScreen(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showHomeWhatsNewDialog(
              context,
              otzaria: otzaria,
              library: library,
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(he.pages.appWhatsNew('1.1.0')), findsOneWidget);
      expect(find.text(he.pages.appInstalledNotesCaption), findsNothing);
      expect(find.byType(LibraryChangesCard), findsNothing);
    });

    test('בלי הערות לשום דבר — אין "מה חדש?"', () {
      expect(whatsNewAppNotes(otzaria), isNull);
    });

    testWidgets('עדכון ספרייה: מד עם השלב והאזהרה לא לנתק', (tester) async {
      library.status = LibraryModuleStatus.updating;
      library.stageText = 'verify (2/3)';
      library.applyProgress = 0.37;

      await pumpScreen(tester, progress(HomeTask.updatingLibrary));

      expect(find.byType(InfoProgressRow), findsOneWidget);
      expect(find.text('verify (2/3)'), findsOneWidget);
      expect(find.text('37%'), findsOneWidget);
      expect(find.text(he.home.doNotRemoveDriveWarning), findsOneWidget);
    });
  });

  group('launcherLineOf — מה שורת הכלי אומרת', () {
    late Directory tempDir;
    late LauncherUpdateController c;
    const release = LauncherRelease(
      tagName: 'v9.9.9',
      name: 'Otzaria Updates v9.9.9',
      assetName: 'x.exe',
      downloadUrl: 'https://example/x.exe',
      sizeBytes: 42 << 20,
    );

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('launcher_line_test');
      c = LauncherUpdateController(dataDir: tempDir.path);
    });

    tearDown(() {
      c.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test('הכלי מעודכן — אין שורה', () {
      expect(launcherLineOf(c), isNull);
    });

    test('כשל בלי גרסה ידועה אינו עדכון שמחכה בגיבור', () {
      expect(launcherOffersUpdate(null), isFalse);
      expect(
        launcherOffersUpdate(
          const LauncherLine(LauncherLineKind.error, error: 'down'),
        ),
        isFalse,
      );
      expect(
        launcherOffersUpdate(
          const LauncherLine(LauncherLineKind.error, version: '3.3.0'),
        ),
        isTrue,
      );
      expect(
        launcherOffersUpdate(
          const LauncherLine(LauncherLineKind.ready, version: '3.3.0'),
        ),
        isTrue,
      );
    });

    test('נמצאה גרסה ברשת — הצעה לפרטים, לא התקנה', () {
      c
        ..onlineRelease = release
        ..onlineCheckedAt = DateTime(2026, 8, 1);
      final line = launcherLineOf(c)!;
      expect(line.kind, LauncherLineKind.online);
      expect(line.version, '9.9.9');
    });

    // אחרי עדכון עצמי התיקייה מחזיקה את הגרסה שרצה — היא אינה "חדשה".
    test('גרסה ישנה בתיקייה אינה מוצגת כגרסה החדשה', () {
      c
        ..status = LauncherUpdateStatus.upToDate
        ..downloadedVersion = c.currentVersion
        ..onlineRelease = release;
      final line = launcherLineOf(c)!;
      expect(line.kind, LauncherLineKind.online);
      expect(line.version, '9.9.9');
    });

    test('גרסה שכבר בכונן — התקנה, וגם בלי רשת', () {
      c
        ..status = LauncherUpdateStatus.readyToInstall
        ..downloadedVersion = '9.9.9'
        ..canInstall = true;
      final line = launcherLineOf(c)!;
      expect(line.kind, LauncherLineKind.ready);
      expect(line.version, '9.9.9');
    });

    test('בלי נתיב לקובץ ההרצה — הסבר במקום התקנה', () {
      c
        ..status = LauncherUpdateStatus.readyToInstall
        ..downloadedVersion = '9.9.9'
        ..canInstall = false;
      expect(launcherLineOf(c)!.kind, LauncherLineKind.readyManual);
    });
  });

  group('displayVersion — גרסה כפי שהמשתמש רואה', () {
    test('בלי v ובלי build', () {
      expect(displayVersion('v0.9.98+801'), '0.9.98');
      expect(displayVersion('0.9.98'), '0.9.98');
    });

    test('build נשאר רק כשבלעדיו שתי הגרסאות נראות זהות', () {
      expect(displayVersion('0.9.98+801', other: '0.9.98+799'), '0.9.98+801');
      expect(displayVersion('v0.9.98+801', other: '0.9.98+799'), '0.9.98+801');
      expect(displayVersion('0.9.98+801', other: '0.9.97+801'), '0.9.98');
      expect(displayVersion('0.9.98+801', other: 'v0.9.98+801'), '0.9.98');
    });

    test('build בצד אחד בלבד — אותה גרסה (sameBuild), ולכן בלי סיומת', () {
      expect(displayVersion('0.9.98+801', other: '0.9.98'), '0.9.98');
      expect(displayVersion('0.9.98', other: '0.9.98+801'), '0.9.98');
      expect(displayVersion('v0.9.98+801', other: 'v0.9.98'), '0.9.98');
    });

    testWidgets('אותה גרסה בשני build-ים: השבב באריח מבחין ביניהם', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: deriveHomeGuidance(
              const GuidanceFacts(
                otzariaStatus: AppStatusFact.updateAvailable,
                online: false,
              ),
            ),
            installedVersion: '0.9.98+799',
            driveAppVersion: '0.9.98+801',
            appTile: TileStatus.updateHere,
          ),
        ),
      );
      expect(find.text(he.pages.chipUpdateOnDrive), findsOneWidget);
      expect(
        find.text(g.tileFactDrive(g.tileFactVersion('0.9.98+801'))),
        findsOneWidget,
      );
      expect(find.text(g.eyebrowOtzaria('0.9.98+799')), findsOneWidget);
    });
  });

  group('אריחים מול הגיבור', () {
    StatusChip chipOf(WidgetTester tester, ShellSection section) =>
        tester.widget<StatusChip>(
          find.descendant(
            of: find.byKey(ShellKeys.tile(section)),
            matching: find.byType(StatusChip),
          ),
        );

    testWidgets('מה שההורדה תביא — "יש עדכון להוריד לכונן" עם סמל הורדה', (
      tester,
    ) async {
      await pumpScreen(tester, HomePage(model: homeScenario('downloadOnly')));
      expect(find.text(g.downloadTitle), findsOneWidget);
      for (final section in [
        ShellSection.otzaria,
        ShellSection.library,
        ShellSection.plugins,
      ]) {
        final chip = chipOf(tester, section);
        expect(chip.label, g.chipNewOnline, reason: section.name);
        expect(chip.kind, StatusKind.updateAvailable);
        expect(chip.icon, FluentIcons.arrow_download_16_regular);
      }
      expect(find.text(g.chipNotOnDrive), findsNothing);
    });

    testWidgets('בלי רשת: האריח מתאר את הכונן כרגיל', (tester) async {
      await pumpScreen(tester, HomePage(model: homeScenario('offline')));
      expect(find.text(g.chipNewOnline), findsNothing);
      expect(
        chipOf(tester, ShellSection.library).label,
        he.pages.chipUpdateOnDrive,
      );
    });

    testWidgets('שבב "מעודכן" — וי פשוט, לא וי בעיגול', (tester) async {
      await pumpScreen(tester, HomePage(model: homeScenario('uptodate')));
      final chip = chipOf(tester, ShellSection.library);
      expect(chip.kind, StatusKind.ok);
      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(ShellKeys.tile(ShellSection.library)),
          matching: find.byIcon(FluentIcons.checkmark_16_filled),
        ),
      );
      expect(icon.size, 14);
    });

    testWidgets('החיצים באריחים מלאים, ומצביעים פנימה: שמאלה בעברית', (
      tester,
    ) async {
      for (final (language, direction) in [
        (AppLanguage.hebrew, AxisDirection.left),
        (AppLanguage.english, AxisDirection.right),
      ]) {
        await pumpScreen(
          tester,
          HomePage(model: homeScenario('uptodate')),
          language: language,
        );
        final chevron = find.descendant(
          of: find.byKey(ShellKeys.tile(ShellSection.otzaria)),
          matching: find.byIcon(FluentIcons.chevron_right_20_filled),
        );
        expect(chevron, findsOneWidget);
        expect(drawnArrow(tester, chevron), direction, reason: '$language');
      }
    });

    testWidgets('התוכנה והספרייה: אותו שבב לאותו מצב, והעובדות בשורות', (
      tester,
    ) async {
      const facts = GuidanceFacts(
        online: false,
        otzariaStatus: AppStatusFact.needsDownload,
        libraryStatus: LibraryStatusFact.needsDownload,
      );
      final guidance = deriveHomeGuidance(facts);
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: guidance,
            online: false,
            installedVersion: '0.10.3',
            libraryHereVersion: 146,
            appTile: deriveTileStatus(GuidanceItem.app, facts),
            libraryTile: deriveTileStatus(GuidanceItem.library, facts),
          ),
        ),
      );
      final app = chipOf(tester, ShellSection.otzaria);
      final library = chipOf(tester, ShellSection.library);
      expect(app.label, g.chipNotOnDrive);
      expect((app.label, app.kind), (library.label, library.kind));
      expect(
        find.text(g.tileFactHere(g.tileFactVersion('0.10.3'))),
        findsOneWidget,
      );
      expect(
          find.text(g.tileFactHere(he.pages.libVersion(146))), findsOneWidget);
      expect(find.text(g.tileFactDrive(he.pages.nothingYet)), findsNWidgets(2));
      expect(find.textContaining(g.tileFactOnline('')), findsNothing);
    });

    testWidgets('מחובר: האריח אומר גם מה זמין להורדה', (tester) async {
      await pumpScreen(tester, HomePage(model: homeScenario('online')));
      expect(
        find.text(g.tileFactOnline(he.pages.libVersion(147))),
        findsOneWidget,
      );
    });

    testWidgets('מחובר ומעודכן: "ברשת:" גם כשאין חדש; לא מחובר — בלעדיה', (
      tester,
    ) async {
      await pumpScreen(tester, HomePage(model: homeScenario('uptodateOnline')));
      expect(
        find.text(g.tileFactOnline(he.pages.libVersion(146))),
        findsOneWidget,
      );
      expect(
        find.text(g.tileFactOnline(g.tileFactVersion('0.10.4'))),
        findsOneWidget,
      );

      await pumpScreen(tester, HomePage(model: homeScenario('uptodate')));
      expect(find.textContaining(g.tileFactOnline('')), findsNothing);
    });
  });

  group('הגיבור — ליטוש', () {
    testWidgets('"צריך בדיקה" בספרייה: הכפתור פותח את הדף שלה', (tester) async {
      final opened = <ShellSection>[];
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: deriveHomeGuidance(
              const GuidanceFacts(libraryStatus: LibraryStatusFact.error),
            ),
          ),
          actions: HomeActions(onOpenSection: opened.add),
        ),
      );
      expect(primary(tester).text, g.attentionLibraryButton);
      await tester.tap(find.byKey(ShellKeys.heroPrimary));
      expect(opened, [ShellSection.library]);
    });

    testWidgets('"בודק..." — מחוון פעילות, ו"פתיחת אוצריא" לא מחכה לו', (
      tester,
    ) async {
      var launches = 0;
      await pumpScreen(
        tester,
        HomePage(
          model: homeScenario('checking'),
          actions: HomeActions(onLaunch: () => launches++),
        ),
      );
      expect(find.text(g.checkingTitle), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(ShellKeys.heroChecking),
          matching: find.byType(AppProgressBar),
        ),
        findsOneWidget,
      );
      expect(primary(tester).text, g.launchButton);
      await tester.tap(find.byKey(ShellKeys.heroPrimary));
      expect(launches, 1);

      // בלי אוצריא מותקנת אין מה לפתוח.
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: homeScenario('checking').guidance,
          ),
        ),
      );
      expect(find.byKey(ShellKeys.heroPrimary), findsNothing);
    });

    testWidgets('בדיקה חלקית: מה לא נבדק ומה כן, ו"נסה שוב" בודק שוב', (
      tester,
    ) async {
      var checks = 0;
      await pumpScreen(
        tester,
        HomePage(
          model: homeScenario('checkFailed'),
          actions: HomeActions(onRecheck: () => checks++),
        ),
      );
      expect(
        find.text(
          g.checkFailedBody(
            appFailed: false,
            libraryFailed: true,
            pluginsFailed: false,
            appChecked: true,
            libraryChecked: false,
            pluginsChecked: true,
          ),
        ),
        findsOneWidget,
      );
      expect(find.text(g.upToDateTitle), findsNothing);
      final retry = find.byKey(ShellKeys.heroSecondary);
      expect(tester.widget<ActionButton>(retry).text, he.common.retry);
      await tester.tap(retry);
      expect(checks, 1);
      // האריח של הספרייה: "טרם נבדק", עם הגרסאות — ובלי "ברשת:".
      final libraryTile = find.byKey(ShellKeys.tile(ShellSection.library));
      final chip = tester.widget<StatusChip>(
        find.descendant(of: libraryTile, matching: find.byType(StatusChip)),
      );
      expect((chip.kind, chip.label),
          (StatusKind.unknown, he.common.notCheckedYet));
      expect(
        find.descendant(
          of: libraryTile,
          matching: find.text(g.tileFactDrive(he.pages.libVersion(146))),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: libraryTile,
          matching: find.textContaining(g.tileFactOnline('')),
        ),
        findsNothing,
      );
    });

    testWidgets('שבת: הערת השבת, בלי "לא הצלחתי לבדוק" ובלי "הכול מעודכן"', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: deriveHomeGuidance(
              const GuidanceFacts(
                online: true,
                pluginsProof: OnlineProof.unchecked,
                pluginsClosedForShabbat: true,
              ),
            ),
            online: true,
            installedVersion: '0.10.4',
          ),
        ),
      );
      expect(find.text(he.pluginsDomain.siteClosedForShabbat), findsOneWidget);
      expect(find.text(g.checkFailedTitle), findsNothing);
      expect(find.text(g.upToDateTitle), findsNothing);
      expect(find.text(g.checkOnlineNowNote), findsNothing);
    });

    testWidgets('הכלי ותוכנות נוספות מחכים — לא "הכול מעודכן", והשורות נפתחות',
        (tester) async {
      final calls = <Object>[];
      await pumpScreen(
        tester,
        HomePage(
          model: homeScenario('othersPending'),
          actions: HomeActions(
            onOpenLauncherUpdate: () => calls.add('launcher'),
            onOpenSection: calls.add,
          ),
        ),
      );
      expect(find.text(g.upToDateTitle), findsNothing);
      expect(find.text(g.upToDateBody('0.10.4')), findsOneWidget);
      final list = find.byKey(ShellKeys.heroItems);
      await tester.tap(
        find.descendant(of: list, matching: find.text(g.otherLauncherTitle)),
      );
      await tester.tap(
        find.descendant(of: list, matching: find.text(g.tileCustomApps)),
      );
      expect(calls, ['launcher', ShellSection.customApps]);
      expect(
        find.descendant(
          of: list,
          matching: find.text(g.otherLauncherOnline('3.3.0')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: list, matching: find.text(g.chipAppsPending(2))),
        findsOneWidget,
      );
    });
  });

  group('התוכנה והספרייה בבית', () {
    HomeActions recording(List<String> calls) => HomeActions(
          onWhatsNew: () => calls.add('whatsNew'),
          onRecheckApp: () => calls.add('recheckApp'),
          onRecheck: () => calls.add('checkNow'),
          onCloseOtzaria: () async {
            calls.add('close');
            return true;
          },
          onPickLibraryFolder: () => calls.add('pick'),
          onRegisterThisComputer: () => calls.add('register'),
          onGrantSemanticConsent: () => calls.add('consent'),
          onOpenSection: (section) => calls.add(section.name),
          onOpenSettings: () => calls.add('settings'),
        );

    testWidgets('שגיאת התוכנה בגיבור, ו"בדוק שוב" בודק את התוכנה בלבד',
        (tester) async {
      final calls = <String>[];
      await pumpScreen(
        tester,
        HomePage(model: homeScenario('appError'), actions: recording(calls)),
      );
      expect(inHero(find.text(g.attentionAppTitle)), findsOneWidget);
      expect(find.byKey(ShellKeys.heroAppError), findsOneWidget);
      expect(find.text('לא הצלחנו לקרוא את התיקייה שבכונן'), findsOneWidget);
      expect(primary(tester).text, g.recheckButton);
      await tester.tap(find.byKey(ShellKeys.heroPrimary));
      // לא `checkNow`: הוא מריץ גם התקנה אוטומטית.
      expect(calls, ['recheckApp']);
    });

    testWidgets('"בדוק שוב" של התוכנה מושבת כשמשימה רצה', (tester) async {
      final m = homeScenario('appError');
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: m.guidance,
            appError: m.appError,
            checkBlocked: true,
          ),
        ),
      );
      expect(primary(tester).onPressed, isNull);
    });

    testWidgets('"מה חדש?" בגיבור פותח חלון, גם כשאין עדכון', (tester) async {
      for (final name in ['openIdle', 'libraryNotices']) {
        final calls = <String>[];
        await pumpScreen(
          tester,
          HomePage(model: homeScenario(name), actions: recording(calls)),
        );
        await tester.tap(find.byKey(ShellKeys.heroWhatsNew));
        expect(calls, ['whatsNew'], reason: name);
      }
    });

    testWidgets('אוצריא פתוחה ואין מה להתקין — הפס עם "סגירת אוצריא"',
        (tester) async {
      final calls = <String>[];
      await pumpScreen(
        tester,
        HomePage(model: homeScenario('openIdle'), actions: recording(calls)),
      );
      final banner = find.byKey(ShellKeys.otzariaOpenBanner);
      expect(banner, findsOneWidget);
      expect(find.text(g.otzariaOpenIdleBody), findsOneWidget);
      await tester.tap(
        find.descendant(of: banner, matching: find.byType(ActionButton)),
      );
      await tester.pump();
      expect(calls, ['close']);
    });

    testWidgets('אוצריא פתוחה ויש מה להתקין — בלי כפתור שמתחרה ב"עדכון"',
        (tester) async {
      await pumpScreen(tester, HomePage(model: homeScenario('open')));
      final banner = find.byKey(ShellKeys.otzariaOpenBanner);
      expect(
        find.descendant(of: banner, matching: find.byType(ActionButton)),
        findsNothing,
      );
      expect(find.text(g.otzariaOpenIdleBody), findsNothing);
    });

    testWidgets('גרסה שממתינה בערוץ והאשף שלא ידוע — הערות שקטות בגיבור',
        (tester) async {
      final m = homeScenario('offline');
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: m.guidance,
            installedVersion: '0.10.3',
            appAwaitsNewerStable: true,
            appSetupNotice: 'setup-notice',
          ),
        ),
      );
      expect(inHero(find.text(g.updateHereTitle)), findsOneWidget);
      expect(find.byKey(ShellKeys.appAwaitsNewer), findsOneWidget);
      expect(
        find.text(he.pages.appAwaitsNewer(stable: true)),
        findsOneWidget,
      );
      expect(inHero(find.text('setup-notice')), findsOneWidget);
    });

    testWidgets('קבצים חסרים והסכמה לחיפוש חכם — הודעות מעל הגיבור',
        (tester) async {
      final calls = <String>[];
      await pumpScreen(
        tester,
        HomePage(
          model: homeScenario('libraryNotices'),
          actions: recording(calls),
        ),
      );
      // אין כאן מה ללחוץ — הערה בגיבור, מתחת לפעולה, ולא הודעה מעליה.
      final missing = inHero(find.byKey(ShellKeys.libraryMissingNotice));
      expect(missing, findsOneWidget);
      expect(
        find.text(g.libraryMissingFilesBody('מילון החיפוש המקורב')),
        findsOneWidget,
      );
      expect(
        tester.getRect(missing).top,
        greaterThan(tester.getRect(find.byKey(ShellKeys.heroPrimary)).bottom),
      );
      expect(find.text(g.semanticConsentBody), findsOneWidget);
      // מתחת לגיבור: בחלון נמוך הפעולה הראשית נשארת בתחילת הדף.
      expect(
        tester.getRect(find.byKey(ShellKeys.semanticConsentNotice)).top,
        greaterThan(tester.getRect(find.byKey(ShellKeys.hero)).bottom),
      );
      expect(find.byKey(ShellKeys.semanticConsentWhatIsSent), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byKey(ShellKeys.semanticConsentNotice),
          matching: find.text(he.pages.libSemanticGrant),
        ),
      );
      expect(calls, ['consent']);
    });

    testWidgets('כונן בלי הנלווים — הודעה משלו', (tester) async {
      final m = homeScenario('uptodate');
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: m.guidance,
            libraryCompanionsAbsent: true,
          ),
        ),
      );
      expect(inHero(find.byKey(ShellKeys.libraryAbsentNotice)), findsOneWidget);
      expect(find.text(g.libraryCompanionsAbsentBody), findsOneWidget);
    });

    testWidgets('קבצים שלא ירדו כבר נאמרים ב"נסה שוב" — בלי הערה שנייה',
        (tester) async {
      final m = homeScenario('semanticOffer');
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: m.guidance,
            installedVersion: '0.10.4',
            failedDownloads: 'תלמוד בבלי',
            libraryMissingNames: 'תלמוד בבלי',
          ),
        ),
      );
      expect(find.byKey(ShellKeys.heroFailedDownloads), findsOneWidget);
      expect(find.byKey(ShellKeys.libraryMissingNotice), findsNothing);
    });

    testWidgets('"צריך בדיקה" בלי "נסה שוב" — הקבצים החסרים עדיין נאמרים',
        (tester) async {
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: deriveHomeGuidance(
              const GuidanceFacts(libraryStatus: LibraryStatusFact.error),
            ),
            installedVersion: '0.10.4',
            failedDownloads: 'תלמוד בבלי',
            libraryMissingNames: 'מילון',
          ),
        ),
      );
      expect(inHero(find.text(g.attentionLibraryTitle)), findsOneWidget);
      expect(find.byKey(ShellKeys.heroFailedDownloads), findsNothing);
      expect(
          inHero(find.byKey(ShellKeys.libraryMissingNotice)), findsOneWidget);
    });

    testWidgets('שגיאת התוכנה כשהגיבור על משהו אחר — הערה עם "בדוק שוב"',
        (tester) async {
      final calls = <String>[];
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: deriveHomeGuidance(
              const GuidanceFacts(
                otzariaStatus: AppStatusFact.error,
                libraryStatus: LibraryStatusFact.updateAvailable,
                online: false,
              ),
            ),
            installedVersion: '0.10.3',
            appError: 'broken\nstack',
          ),
          actions: recording(calls),
        ),
      );
      expect(inHero(find.text(g.updateHereTitle)), findsOneWidget);
      final note = find.byKey(ShellKeys.heroAppErrorNote);
      expect(note, findsOneWidget);
      expect(find.descendant(of: note, matching: find.text('broken')),
          findsOneWidget);
      await tester.tap(
        find.descendant(of: note, matching: find.text(g.recheckButton)),
      );
      expect(calls, ['recheckApp']);
    });

    testWidgets('התקנה שלא נמצאה — קישור ל"אוצריא — מתקדם"', (tester) async {
      final calls = <String>[];
      final m = homeScenario('appError');
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: m.guidance,
            installedVersion: '0.10.4',
            appError: m.appError,
            appErrorPicksFolder: true,
          ),
          actions: recording(calls),
        ),
      );
      await tester.tap(find.byKey(ShellKeys.heroAppAdvanced));
      expect(calls, ['otzaria']);
    });

    testWidgets('הספרייה לא נמצאה: הגיבור עצמו מציע לבחור, בלי הודעה כפולה',
        (tester) async {
      final calls = <String>[];
      await pumpScreen(
        tester,
        HomePage(
          model: homeScenario('libraryNotFound'),
          actions: recording(calls),
        ),
      );
      expect(inHero(find.text(he.pages.libNotFoundTitle)), findsOneWidget);
      expect(find.text(he.pages.libNotFoundTitle), findsOneWidget);
      expect(find.byKey(ShellKeys.libraryNotFoundNotice), findsNothing);
      expect(primary(tester).text, he.pages.libPickFolderButton);
      await tester.tap(find.byKey(ShellKeys.heroPrimary));
      await tester.tap(find.byKey(ShellKeys.heroSecondary));
      expect(calls, ['pick', 'library']);
    });

    testWidgets('הספרייה לא נמצאה כשהגיבור על משהו אחר — הודעה עם הפעולה',
        (tester) async {
      final calls = <String>[];
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: deriveHomeGuidance(
              const GuidanceFacts(
                otzariaStatus: AppStatusFact.updateAvailable,
                libraryStatus: LibraryStatusFact.needsManualPath,
                online: false,
              ),
            ),
            installedVersion: '0.10.3',
            libraryNotFound: true,
          ),
          actions: recording(calls),
        ),
      );
      expect(inHero(find.text(g.updateHereTitle)), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byKey(ShellKeys.libraryNotFoundNotice),
          matching: find.text(he.pages.libPickFolderButton),
        ),
      );
      expect(calls, ['pick']);
    });

    testWidgets('הכונן הוכן למחשב אחר: "רישום גם של המחשב הזה" מהבית',
        (tester) async {
      final calls = <String>[];
      final s = he.libraryScreen;
      await pumpScreen(
        tester,
        HomePage(
          model: homeScenario('libraryElsewhere'),
          actions: recording(calls),
        ),
      );
      final notice = find.byKey(ShellKeys.libraryElsewhereNotice);
      expect(notice, findsOneWidget);
      expect(find.text(s.personalOtherMachineSubtitle('145')), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: notice,
          matching: find.text(s.personalVersionButton),
        ),
      );
      await tester.tap(
        find.descendant(
          of: notice,
          matching: find.text(s.personalOtherMachineSettingsButton),
        ),
      );
      expect(calls, ['register', 'settings']);
    });

    testWidgets('מחשב אחר בכונן מוגן — הרישום מושבת, ונאמר למה',
        (tester) async {
      final s = he.libraryScreen;
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: deriveHomeGuidance(
              const GuidanceFacts(
                readOnly: true,
                otzariaStatus: AppStatusFact.updateAvailable,
                libraryStatus: LibraryStatusFact.personalTargetElsewhere,
              ),
            ),
            installedVersion: '0.10.3',
            libraryElsewhereFrom: '',
          ),
        ),
      );
      final notice = find.byKey(ShellKeys.libraryElsewhereNotice);
      final capture = tester.widget<ActionButton>(
        find.descendant(
          of: notice,
          matching: find.widgetWithText(
            ActionButton,
            s.personalVersionButton,
          ),
        ),
      );
      expect(capture.onPressed, isNull);
      expect(
        find.textContaining(he.pages.libPersonalReadOnly),
        findsOneWidget,
      );
      // בלי גרסה רשומה — "לא ידוע", לא ריק.
      expect(
        find.textContaining(
          s.personalOtherMachineSubtitle(he.common.unknownValue),
        ),
        findsOneWidget,
      );
    });

    testWidgets('מחשב אחר כשהגיבור "צריך בדיקה" עליו — הפעולה בגיבור בלבד',
        (tester) async {
      final calls = <String>[];
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: deriveHomeGuidance(
              const GuidanceFacts(
                libraryStatus: LibraryStatusFact.personalTargetElsewhere,
                online: false,
              ),
            ),
            installedVersion: '0.10.4',
            libraryElsewhereFrom: '145',
          ),
          actions: recording(calls),
        ),
      );
      expect(find.byKey(ShellKeys.libraryElsewhereNotice), findsNothing);
      expect(
        inHero(find.text(he.libraryScreen.personalOtherMachineTitle)),
        findsOneWidget,
      );
      await tester.tap(find.byKey(ShellKeys.heroPrimary));
      expect(calls, ['register']);
    });

    testWidgets('פעולות הספרייה מושבתות כשמשימה רצה', (tester) async {
      final m = homeScenario('libraryNotices');
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: m.guidance,
            semanticConsent: true,
            checkBlocked: true,
          ),
        ),
      );
      final grant = tester.widget<ActionButton>(
        find.widgetWithText(ActionButton, he.pages.libSemanticGrant),
      );
      expect(grant.onPressed, isNull);
    });

    test('הודעות הספרייה בבית אינן אומרות "אינטרנט" (מחשב לא מחובר)', () {
      for (final text in [
        g.libraryMissingFilesBody('x'),
        g.libraryCompanionsAbsentBody,
        g.semanticConsentBody,
        g.otzariaOpenIdleBody,
        he.pages.libNotFoundBody,
        he.libraryScreen.personalOtherMachineSubtitle('1'),
        he.libraryScreen.personalPreparedHere,
        he.libraryScreen.personalCardThis('1'),
        he.libraryScreen.personalCardOthers(2, '1'),
        he.libraryScreen.personalChipElsewhere,
        he.libraryScreen.personalAskTitle,
        he.libraryScreen.personalAskMineBody,
        he.libraryScreen.personalAskMultipleBody,
        he.pages.libSemanticBody,
      ]) {
        expect(text, isNot(contains('אינטרנט')), reason: text);
      }
    });
  });

  group('מסך הפתיחה — מה עוד יש בכונן', () {
    testWidgets('תוכנות נוספות ודיווחים — קישורים, והודעות הכונן והבית', (
      tester,
    ) async {
      final opened = <ShellSection>[];
      await pumpScreen(
        tester,
        HomePage(
          model: homeScenario('firstWithApps'),
          actions: HomeActions(onOpenSection: opened.add),
        ),
      );
      expect(find.byKey(ShellKeys.welcome), findsOneWidget);
      expect(find.byKey(ShellKeys.readOnlyNotice), findsOneWidget);
      final links = find.byKey(ShellKeys.welcomeLinks);
      await tester.tap(
        find.descendant(of: links, matching: find.text(g.tileCustomApps)),
      );
      await tester.tap(
        find.descendant(of: links, matching: find.text(g.tileReports)),
      );
      expect(opened, [ShellSection.customApps, ShellSection.reports]);
    });

    testWidgets('בלי תוכנות ובלי דיווחים — אין שורת קישורים', (tester) async {
      await pumpScreen(tester, HomePage(model: homeScenario('first')));
      expect(find.byKey(ShellKeys.welcomeLinks), findsNothing);
    });

    testWidgets('כפתור השפה נשאר גם כשיש הודעת כונן, ומעליה', (tester) async {
      await pumpScreen(tester, HomePage(model: homeScenario('firstWithApps')));
      final language = find.byKey(ShellKeys.welcomeLanguage);
      expect(language, findsOneWidget);
      expect(
        tester.getRect(language).bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(ShellKeys.readOnlyNotice)).top,
        ),
      );
    });

    testWidgets('הפעלה כמנהל והסבר הדיווחים מוצגים גם במסך הפתיחה', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: homeScenario('first').guidance,
            offersElevation: true,
            reportsIntro: true,
          ),
        ),
      );
      expect(find.byKey(ShellKeys.welcome), findsOneWidget);
      expect(find.byKey(ShellKeys.elevationBanner), findsOneWidget);
      expect(find.byKey(ShellKeys.reportsIntroNotice), findsOneWidget);
    });
  });

  group('רק המחשב שלי — הבית', () {
    final l = he.libraryScreen;
    Finder inList(String text) => find.descendant(
          of: find.byKey(ShellKeys.heroItems),
          matching: find.text(text),
        );

    testWidgets('במחשב המחובר: למי ההורדה, הגודל מהמייצא, ו"שינוי"', (
      tester,
    ) async {
      final calls = <String>[];
      await pumpScreen(
        tester,
        HomePage(
          model: homeScenario('personalOnline'),
          actions: HomeActions(onOpenSettings: () => calls.add('settings')),
        ),
      );
      expect(
        inList(
          '${he.pages.libVersion(147)} · ${l.personalDownloadItem(1, '145')}',
        ),
        findsOneWidget,
      );
      expect(inList(g.itemUpTo(formatBytes(90 << 20))), findsOneWidget);
      expect(find.byKey(ShellKeys.personalDownloadNote), findsOneWidget);
      await tester.tap(find.text(l.personalChange));
      expect(calls, ['settings']);
    });

    testWidgets('בלי תשובה מהמייצא — בלי מספר לספרייה', (tester) async {
      await pumpScreen(
        tester,
        HomePage(model: homeScenario('personalOnlineNoSize')),
      );
      expect(
        inList(
          '${he.pages.libVersion(147)} · ${l.personalDownloadItem(2, '145')}',
        ),
        findsOneWidget,
      );
      expect(find.textContaining(g.itemUpTo('')), findsNothing);
      expect(find.text(l.personalDownloadNote(2)), findsOneWidget);
    });

    testWidgets('אף מחשב לא נרשם — הספרייה המלאה נאמרת מראש', (tester) async {
      await pumpScreen(
        tester,
        HomePage(model: homeScenario('personalNoneRegistered')),
      );
      expect(
        inList('${he.pages.libVersion(147)} · ${l.personalDownloadItemNone}'),
        findsOneWidget,
      );
      expect(find.byKey(ShellKeys.personalDownloadNote), findsNothing);
    });

    testWidgets('במחשב שנרשם מעצמו — הערה שקטה, בלי "אינטרנט"', (tester) async {
      await pumpScreen(
        tester,
        HomePage(model: homeScenario('personalPreparedHere')),
      );
      expect(find.byKey(ShellKeys.personalPreparedHere), findsOneWidget);
      expect(find.text(l.personalPreparedHere), findsOneWidget);
      expect(find.textContaining('אינטרנט'), findsNothing);
    });

    testWidgets('בלי בדיקה ברשת — קישור "רישום המחשב הזה" שרושם', (
      tester,
    ) async {
      final calls = <String>[];
      final base = homeScenario('personalPreparedHere');
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: base.guidance,
            installedVersion: base.installedVersion,
            personalMode: true,
            personalPending: true,
            personalPendingNeedsClick: true,
          ),
          actions: HomeActions(
            onRegisterThisComputer: () => calls.add('register'),
          ),
        ),
      );
      expect(find.byKey(ShellKeys.personalPendingNote), findsOneWidget);
      expect(find.text(l.personalPendingRegisterNote), findsOneWidget);
      expect(find.text(l.personalPendingNote), findsNothing);
      await tester.tap(find.text(l.personalVersionButton));
      expect(calls, ['register']);
    });

    testWidgets('במחשב מחובר — הבטחה למחשב האחר, בלי קישור', (tester) async {
      final base = homeScenario('personalPreparedHere');
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: base.guidance,
            installedVersion: base.installedVersion,
            personalMode: true,
            personalPending: true,
          ),
        ),
      );
      expect(find.text(l.personalPendingNote), findsOneWidget);
      expect(find.text(l.personalVersionButton), findsNothing);
    });

    testWidgets('כונן שהוכן למחשב אחר — האריח אינו שגיאה', (tester) async {
      await pumpScreen(
          tester, HomePage(model: homeScenario('libraryElsewhere')));
      final tile = find.byKey(ShellKeys.tile(ShellSection.library));
      expect(
        find.descendant(of: tile, matching: find.text(l.personalChipElsewhere)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tile, matching: find.text(g.chipAttention)),
        findsNothing,
      );
      expect(
        homeScenario('libraryElsewhere').libraryTile,
        TileStatus.preparedElsewhere,
      );
    });
  });
}

/// מראה של התוכנה עם גרסה יציבה אחת [tag] והערות "מה התחדש ב-[tag]".
void writeAppMirror(String dataDir, String tag) {
  final mirror = p.join(dataDir, 'mirror', 'app');
  final relative = 'installers/$tag/otzaria-$tag.exe';
  final installer = File(p.join(mirror, p.joinAll(relative.split('/'))))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('installer for $tag');
  File(p.join(mirror, 'latest-release.json')).writeAsStringSync(jsonEncode({
    'schemaVersion': 2,
    'syncedAt': '2026-08-01T00:00:00.000Z',
    'stable': {
      'tagName': tag,
      'name': 'אוצריא $tag',
      'isPrerelease': false,
      'isDraft': false,
      'publishedAt': '2026-08-01T00:00:00.000Z',
      'installerKind': 'windowsSetupExe',
      'installerAssetName': 'otzaria-$tag.exe',
      'installerDownloadUrl': 'https://example.invalid/otzaria-$tag.exe',
      'installerSizeBytes': installer.lengthSync(),
      'releaseNotes': 'מה התחדש ב-$tag',
      'installerPath': relative,
    },
  }));
}

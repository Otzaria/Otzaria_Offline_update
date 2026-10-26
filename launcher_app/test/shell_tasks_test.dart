import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/download_plan.dart';
import 'package:launcher_app/src/shell/download_failure.dart';
import 'package:launcher_app/src/shell/home_guidance.dart';
import 'package:launcher_app/src/shell/shell_tasks.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

void main() {
  late ShellTasks tasks;

  setUp(() => tasks = ShellTasks());
  tearDown(() => tasks.dispose());

  DownloadTask download() => tasks.current! as DownloadTask;
  DownloadTaskPhase? downloadPhase() => switch (tasks.current) {
        DownloadTask(:final phase) => phase,
        _ => null,
      };

  UpdateHereTask update() => tasks.current! as UpdateHereTask;

  group('הורדה', () {
    test('הכנה → שאלה → תשובה → רצה → סיום → סגירה', () async {
      tasks.prepareDownload();
      expect(downloadPhase(), DownloadTaskPhase.preparing);
      final answer = tasks.askBeforeDownload();
      expect(downloadPhase(), DownloadTaskPhase.question);
      tasks.answer((download: true, remember: true));
      expect(await answer, (download: true, remember: true));
      expect(downloadPhase(), DownloadTaskPhase.preparing);

      tasks.downloadRunning(
        const [MirrorComponent.library],
        expectedBytes: const {MirrorComponent.library: 42},
      );
      expect(downloadPhase(), DownloadTaskPhase.running);
      expect(download().components, [MirrorComponent.library]);
      expect(download().expectedBytes, {MirrorComponent.library: 42});

      tasks.downloadDone(skipped: const [MirrorComponent.plugins]);
      expect(downloadPhase(), DownloadTaskPhase.done);
      expect(download().skipped, [MirrorComponent.plugins]);
      expect(download().components, [MirrorComponent.library]);
      tasks.dismiss();
      expect(tasks.hasTask, isFalse);
    });

    test('חזרה מהשאלה = ביטול לפני שההורדה התחילה', () async {
      final answer = tasks.askBeforeDownload();
      tasks.answer(null);
      expect(await answer, isNull);
      expect(tasks.hasTask, isFalse);
    });

    test('כשל → "נסה שוב" מתחיל הכנה חדשה במקום המשימה שהסתיימה', () {
      tasks
        ..prepareDownload()
        ..downloadRunning(const [MirrorComponent.app]);
      const failure = DownloadFailure(
        DownloadFailureKind.network,
        components: [MirrorComponent.app],
        details: 'boom',
      );
      tasks.downloadFailed(failure);
      expect(downloadPhase(), DownloadTaskPhase.failed);
      expect(download().failure, same(failure));
      tasks.prepareDownload();
      expect(downloadPhase(), DownloadTaskPhase.preparing);
      expect(download().failure, isNull);
    });

    test('משימה רצה אינה נסגרת, ומשימה שנייה אינה נפתחת', () {
      tasks.downloadRunning(const [MirrorComponent.app]);
      expect(tasks.isRunning, isTrue);
      expect(tasks.dismiss, throwsStateError);
      expect(tasks.prepareDownload, throwsStateError);
      expect(() => tasks.startUpdateHere([GuidanceItem.app]), throwsStateError);
      tasks.downloadDone();
      expect(tasks.isRunning, isFalse);
    });

    test('ביטול בזמן השאלה מחזיר null ומנקה את המשימה', () async {
      final answer = tasks.askBeforeDownload();
      tasks.downloadCancelled();
      expect(await answer, isNull);
      expect(tasks.hasTask, isFalse);

      // תשובה מאוחרת אינה עושה דבר, ושאלה חדשה נפתחת כרגיל.
      tasks.answer((download: true, remember: false));
      expect(tasks.hasTask, isFalse);
      final again = tasks.askBeforeDownload();
      tasks.answer((download: true, remember: false));
      expect((await again)?.download, isTrue);
      expect(downloadPhase(), DownloadTaskPhase.preparing);
    });

    test('ביטול בזמן ריצה: "בוטלה", וכשל השחזור נאמר', () {
      tasks.downloadRunning(const [MirrorComponent.app]);
      tasks.downloadCancelled(revertFailed: true);
      expect(downloadPhase(), DownloadTaskPhase.cancelled);
      expect(download().revertFailed, isTrue);
      expect(tasks.isRunning, isFalse);
    });

    test('ביטול בזמן ריצה זוכר מה נשאר בכונן', () {
      tasks.downloadRunning(
          const [MirrorComponent.app, MirrorComponent.library]);
      tasks.downloadCancelled(kept: const [MirrorComponent.app]);
      expect(download().kept, [MirrorComponent.app]);
      expect(download().revertFailed, isFalse);
    });

    test('הזרימה חזרה בלי להתחיל — המסך נסגר; משימה רצה נשארת', () {
      tasks.prepareDownload();
      tasks.abandonDownload();
      expect(tasks.hasTask, isFalse);

      tasks.downloadRunning(const [MirrorComponent.app]);
      tasks.abandonDownload();
      expect(downloadPhase(), DownloadTaskPhase.running);
    });

    test('פירוק בזמן שאלה משחרר את הממתין', () async {
      final local = ShellTasks();
      final answer = local.askBeforeDownload();
      local.dispose();
      expect(await answer, isNull);
    });
  });

  group('עדכון כאן', () {
    test('סגירת אוצריא → שלבים לפי הסדר → סיום', () async {
      tasks.startUpdateHere(
        [GuidanceItem.library, GuidanceItem.app],
        libraryVersion: 27,
        appVersion: '0.9.96',
      );
      expect(update().currentStage, GuidanceItem.library);

      final close = tasks.askToCloseOtzaria();
      expect(update().phase, UpdateHereTaskPhase.closeOtzaria);
      expect(update().closeAfterWizard, isFalse);
      tasks.respond(true);
      expect(await close, isTrue);
      expect(update().phase, UpdateHereTaskPhase.running);

      tasks.stageRunning(GuidanceItem.library);
      tasks.stageFinished(GuidanceItem.library, StageOutcome.done);
      expect(update().currentStage, GuidanceItem.app);
      tasks.stageRunning(GuidanceItem.app);
      tasks.stageFinished(GuidanceItem.app, StageOutcome.done);
      tasks.updateDone();
      expect(update().phase, UpdateHereTaskPhase.done);
      expect(update().outcomes, {
        GuidanceItem.library: StageOutcome.done,
        GuidanceItem.app: StageOutcome.done,
      });
      expect(update().isFinished, isTrue);
    });

    test('ביטול באשף הוא סיום רגוע', () {
      tasks.startUpdateHere([GuidanceItem.app]);
      tasks.stageRunning(GuidanceItem.app);
      tasks.updateCancelledByUser();
      expect(update().phase, UpdateHereTaskPhase.cancelledByUser);
      expect(update().failure, isNull);
      tasks.dismiss();
      expect(tasks.hasTask, isFalse);
    });

    test('כשל שומר את השלב ואת ההודעה', () {
      tasks.startUpdateHere([GuidanceItem.library, GuidanceItem.app]);
      tasks.stageRunning(GuidanceItem.library);
      tasks.updateFailed(const UpdateFailure(
        GuidanceItem.library,
        message: 'locked',
        needsElevation: true,
      ));
      expect(update().phase, UpdateHereTaskPhase.failed);
      expect(update().failure!.stage, GuidanceItem.library);
      expect(update().failure!.needsElevation, isTrue);
      expect(() => tasks.updateDone(), throwsStateError);
    });

    test('"ביטול" לפני ששום דבר רץ סוגר את המסך', () async {
      tasks.startUpdateHere([GuidanceItem.app]);
      final answer = tasks.askOtherUser();
      expect(update().phase, UpdateHereTaskPhase.confirmElevatedOtherUser);
      tasks.respond(false);
      expect(await answer, isFalse);
      tasks.abandonUpdate();
      expect(tasks.hasTask, isFalse);
    });

    test('"הפסק להמתין" נרשם בשלב, ושלב חדש מאפס אותו', () {
      tasks.startUpdateHere([GuidanceItem.app, GuidanceItem.plugins]);
      tasks.stageRunning(GuidanceItem.app);
      tasks.requestStopWaiting();
      expect(update().stopWaitingRequested, isTrue);
      tasks.stageFinished(GuidanceItem.app, StageOutcome.stoppedWaiting);
      tasks.stageRunning(GuidanceItem.plugins);
      expect(update().stopWaitingRequested, isFalse);
    });

    test('שורות המסירה מתחילות "ממתין", ו"סיום בלי לחכות" משחרר', () async {
      tasks.startUpdateHere(
        [GuidanceItem.plugins],
        pluginNames: const ['לוח', 'מזומנים'],
      );
      expect(
        update().plugins.map((p) => p.state),
        everyElement(PluginDeliveryState.waiting),
      );
      tasks.pluginDeliveries(const [
        PluginDelivery('לוח', PluginDeliveryState.sent),
        PluginDelivery('מזומנים', PluginDeliveryState.waiting),
      ]);
      expect(update().plugins.first.state, PluginDeliveryState.sent);
      var released = false;
      unawaited(tasks.finishRequested.then((_) => released = true));
      tasks.finishWithoutWaiting();
      await Future<void>.delayed(Duration.zero);
      expect(released, isTrue);
    });

    test('"מתכונן" פעמיים — אותה משימה, בלי חריג', () {
      tasks.prepareDownload();
      final first = tasks.current;
      tasks.prepareDownload();
      expect(tasks.current, same(first));
    });

    test('בלי שלבים אין משימה', () {
      expect(() => tasks.startUpdateHere(const []), throwsArgumentError);
    });
  });

  group('סיווג כשל ההורדה', () {
    setUp(() => AppL10n.use(AppLanguage.hebrew));

    test('חוסר מקום — נדרשים ופנויים מתוך ההודעה של המנוע', () {
      final message =
          'Bad state: ${AppL10n.strings.libraryDomain.mirrorNotEnoughDiskSpace('E:\\mirror', '1.2 GB', '0.4 GB')}';
      final failure = classifyDownloadFailure(
        failed: const [MirrorComponent.library],
        errors: {MirrorComponent.library: message},
        shabbat: false,
      );
      expect(failure.kind, DownloadFailureKind.diskSpace);
      expect(failure.needed, '1.2 GB');
      expect(failure.free, '0.4 GB');
    });

    test('חוסר מקום מזוהה גם באנגלית', () {
      AppL10n.use(AppLanguage.english);
      addTearDown(() => AppL10n.use(AppLanguage.hebrew));
      final message = AppL10n.strings.libraryDomain
          .mirrorNotEnoughDiskSpace('/drive', '2 GB', '1 GB');
      expect(parseNotEnoughSpace(message), (needed: '2 GB', free: '1 GB'));
    });

    // המנוע זורק טקסט בשפה שהייתה פעילה; החלפת שפה אחרי הכשל לא תפספס.
    test('חוסר מקום מזוהה גם כשהשפה הוחלפה אחרי הכשל', () {
      final hebrew = const HebrewStrings()
          .libraryDomain
          .mirrorNotEnoughDiskSpace('E:\\mirror', '1.2 GB', '0.4 GB');
      AppL10n.use(AppLanguage.english);
      addTearDown(() => AppL10n.use(AppLanguage.hebrew));
      expect(
        parseNotEnoughSpace('Bad state: $hebrew'),
        (needed: '1.2 GB', free: '0.4 GB'),
      );
      final failure = classifyDownloadFailure(
        failed: const [MirrorComponent.library],
        errors: {MirrorComponent.library: hebrew},
        shabbat: false,
      );
      expect(failure.kind, DownloadFailureKind.diskSpace);
    });

    test('תעודה שנדחתה (נטפרי) — "מסנן", לא "אין אינטרנט"', () {
      final failure = classifyDownloadFailure(
        failed: const [MirrorComponent.library],
        errors: const {
          MirrorComponent.library: 'HandshakeException: Handshake error in '
              'client (OS Error: CERTIFICATE_VERIFY_FAILED: unable to get '
              'local issuer certificate)',
        },
        shabbat: false,
      );
      expect(failure.kind, DownloadFailureKind.blocked);
      expect(failure.details, contains('CERTIFICATE_VERIFY_FAILED'));
    });

    test('ניתוק בלחיצת היד בלי תעודה — רשת, לא "מסנן"', () {
      final failure = classifyDownloadFailure(
        failed: const [MirrorComponent.library],
        errors: const {
          MirrorComponent.library: 'HandshakeException: Connection terminated '
              'during handshake',
        },
        shabbat: false,
      );
      expect(failure.kind, DownloadFailureKind.network);
    });

    test('ניתוק רשת — רגוע, עם הפרטים הטכניים', () {
      final failure = classifyDownloadFailure(
        failed: const [MirrorComponent.library],
        errors: {
          MirrorComponent.library:
              'SocketException: Connection reset by peer (OS Error 10054)',
        },
        shabbat: false,
      );
      expect(failure.kind, DownloadFailureKind.network);
      expect(failure.details, contains('Connection reset'));
    });

    test('שבת — רק כשהתוספים הם שנכשלו', () {
      expect(
        classifyDownloadFailure(
          failed: const [MirrorComponent.plugins],
          errors: const {MirrorComponent.plugins: 'closed'},
          shabbat: true,
        ).kind,
        DownloadFailureKind.shabbat,
      );
      expect(
        classifyDownloadFailure(
          failed: const [MirrorComponent.library, MirrorComponent.plugins],
          errors: const {
            MirrorComponent.library: 'hash mismatch',
            MirrorComponent.plugins: 'closed',
          },
          shabbat: true,
        ).kind,
        DownloadFailureKind.other,
      );
    });

    test('שגיאה אחרת — אדומה, עם הפרטים', () {
      final failure = classifyDownloadFailure(
        failed: const [MirrorComponent.app],
        errors: const {MirrorComponent.app: 'SHA-256 mismatch'},
        shabbat: false,
      );
      expect(failure.kind, DownloadFailureKind.other);
      expect(failure.details, 'app: SHA-256 mismatch');
    });
  });
}

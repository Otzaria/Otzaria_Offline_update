import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/flows/update_here_flow.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:launcher_app/src/shell/home_guidance.dart';
import 'package:launcher_app/src/shell/shell_tasks.dart';

import 'test_support.dart';

class _App implements UpdateHereApp {
  _App(this.log);

  final List<String> log;

  @override
  bool isInstalled = true;
  @override
  bool hasUpdateAvailable = true;
  @override
  bool elevatedAsOtherUser = false;
  @override
  String? adminAccount;
  @override
  String? versionToInstall = '0.9.96';
  @override
  String? errorMessage;
  @override
  bool needsElevation = false;
  @override
  bool canReinstall = false;

  AppInstallOutcome outcome = AppInstallOutcome.installed;
  Completer<void>? gate;
  int installs = 0;
  int stops = 0;
  Object? throws;

  @override
  Future<AppInstallOutcome> installWithWizard() async {
    installs++;
    log.add('app');
    await gate?.future;
    if (throws case final error?) throw error;
    if (outcome == AppInstallOutcome.installed) {
      isInstalled = true;
      hasUpdateAvailable = false;
    }
    return outcome;
  }

  @override
  void stopWaiting() {
    stops++;
    gate?.complete();
  }
}

class _Library implements UpdateHereLibrary {
  _Library(this.log);

  final List<String> log;

  @override
  bool isFreshInstall = false;
  @override
  bool hasUpdateAvailable = true;
  @override
  int? targetVersion = 27;
  @override
  String? errorMessage;
  @override
  bool needsElevation = false;
  @override
  bool canApplyFull = false;
  @override
  bool semanticAwaitsConsent = false;

  bool succeeds = true;

  /// ההחלה הצליחה, אבל `_apply` השאיר הודעה (מיקום שצריך לכוון).
  String? noteAfterApply;
  ({int low, int high})? estimate;
  int fullApplies = 0;
  bool availableAfterRecheck = true;
  int applies = 0;
  int rechecks = 0;
  void Function()? onApply;

  @override
  ({int low, int high})? applyEstimate({bool full = false}) => estimate;

  @override
  String? applyNote;

  LibraryApplyResult get _result {
    if (!succeeds) return LibraryApplyResult.failed;
    errorMessage = applyNote = noteAfterApply;
    return noteAfterApply == null
        ? LibraryApplyResult.applied
        : LibraryApplyResult.appliedWithNote;
  }

  @override
  Future<LibraryApplyResult> apply() async {
    applies++;
    log.add('library');
    onApply?.call();
    if (succeeds) hasUpdateAvailable = false;
    return _result;
  }

  @override
  Future<LibraryApplyResult> applyFull() async {
    fullApplies++;
    log.add('library-full');
    if (succeeds) canApplyFull = false;
    return _result;
  }

  @override
  Future<void> recheck() async {
    rechecks++;
    log.add('recheck');
    hasUpdateAvailable = availableAfterRecheck;
  }
}

class _Plugins implements UpdateHerePlugins {
  _Plugins(this.log);

  final List<String> log;

  @override
  List<String> deliverableUpdates = const [];
  Completer<void>? gate;

  /// מה שהפורט מחשב ברגע המסירה; `null` — כמו [deliverableUpdates].
  List<String>? targetsAtDelivery;
  final failing = <String>{};

  @override
  Future<void> deliver(void Function(List<PluginDelivery> rows) onRow) async {
    log.add('plugins');
    final targets = targetsAtDelivery ?? deliverableUpdates;
    onRow([
      for (final name in targets)
        PluginDelivery(name, PluginDeliveryState.waiting),
    ]);
    await gate?.future;
    onRow([
      for (final name in targets)
        PluginDelivery(
          name,
          failing.contains(name)
              ? PluginDeliveryState.failed
              : PluginDeliveryState.sent,
        ),
    ]);
  }
}

class _Host implements UpdateHereHost {
  _Host(this.log);

  final List<String> log;

  @override
  final ShellTasks tasks = ShellTasks();
  @override
  bool isActive = true;

  bool running = false;
  bool closeSucceeds = true;
  int probes = 0;
  int closes = 0;
  int closeFailures = 0;

  @override
  Future<bool> isOtzariaRunning() async {
    probes++;
    return running;
  }

  @override
  Future<bool> closeOtzaria() async {
    closes++;
    log.add('close');
    if (closeSucceeds) running = false;
    return closeSucceeds;
  }

  @override
  void closeFailed() => closeFailures++;

  /// כמו הסשן: הסכמה חסרה שלא נענתה; כל תשובה (ורק תשובה) סוגרת אותה.
  bool consentUnanswered = false;
  bool? consentAnswer = false;
  int asks = 0;
  int declines = 0;
  int grants = 0;

  @override
  Future<bool> semanticConsentUnanswered() async => consentUnanswered;

  @override
  Future<bool?> askSemanticConsent() async {
    asks++;
    return consentAnswer;
  }

  @override
  Future<void> declineSemanticConsent() async {
    declines++;
    log.add('decline');
    consentUnanswered = false;
  }

  /// כמו `_writeSemanticConsent`: הצלחה רושמת תשובה ובודקת מחדש.
  bool grantSucceeds = true;
  String grantProblem = 'הכתיבה נכשלה';
  void Function()? onGranted;

  @override
  Future<String?> grantSemanticConsent() async {
    grants++;
    log.add(running ? 'grant-while-open' : 'grant');
    if (!grantSucceeds) return grantProblem;
    consentUnanswered = false;
    onGranted?.call();
    return null;
  }
}

void main() {
  late List<String> log;
  late _App app;
  late _Library library;
  late _Plugins plugins;
  late _Host host;
  late UpdateHereFlow flow;

  setUp(() {
    log = [];
    app = _App(log);
    library = _Library(log);
    plugins = _Plugins(log);
    host = _Host(log);
    flow = UpdateHereFlow(
      app: app,
      library: library,
      plugins: plugins,
      host: host,
    );
  });

  tearDown(() => host.tasks.dispose());

  UpdateHereTask? task() => host.tasks.current as UpdateHereTask?;

  /// מריץ עד שהזרימה מחכה למשתמש (או מסתיימת).
  Future<void> settle() => pumpEventQueue();

  const both = [GuidanceItem.library, GuidanceItem.app];

  group('שלבים שההורדה עוד כותבת', () {
    test('הספרייה חסומה — התוכנה לבדה, והחסימה נקראת ברגע ההתחלה', () async {
      var calls = 0;
      await flow.run(both, blocked: () {
        calls++;
        return {GuidanceItem.library};
      });
      expect(log, ['app']);
      expect(task()!.stages, [GuidanceItem.app]);
      expect(calls, greaterThan(0));
    });

    test('הכול חסום — אין משימה', () async {
      final started = await flow.run(
        both,
        blocked: () => {GuidanceItem.library, GuidanceItem.app},
      );
      expect(started, isFalse);
      expect(host.tasks.updateTask, isNull);
      expect(log, isEmpty);
    });

    test('התקנה ראשונה כשהתוכנה חסומה — גם הספרייה אינה רצה', () async {
      app.isInstalled = false;
      library.isFreshInstall = true;
      final started = await flow.run(both, blocked: () => {GuidanceItem.app});
      expect(started, isFalse);
      expect(log, isEmpty);
    });

    test('"נסה שוב" מחשב את החסימה מחדש', () async {
      app.outcome = AppInstallOutcome.failed;
      await flow.run(both, blocked: () => {GuidanceItem.library});
      expect(task()!.phase, UpdateHereTaskPhase.failed);
      app.outcome = AppInstallOutcome.installed;
      log.clear();
      await flow.retry(blocked: () => const {});
      expect(log, ['library', 'app']);
    });
  });

  group('עדכון', () {
    test('הספרייה ואז התוכנה, כמו ההתקנה האוטומטית', () async {
      await flow.run(both);
      expect(log, ['library', 'app']);
      expect(task()!.phase, UpdateHereTaskPhase.done);
      expect(task()!.outcomes, {
        GuidanceItem.library: StageOutcome.done,
        GuidanceItem.app: StageOutcome.done,
      });
      expect(task()!.libraryVersion, 27);
      expect(task()!.appVersion, '0.9.96');
    });

    // בדיקה טרייה לפני כל שלב — לא הערך מרגע הבנייה.
    test('בדיקת תהליך טרייה לפני כל שלב שאוצריא הפתוחה חוסמת', () async {
      await flow.run(both);
      expect(host.probes, 2);
      expect(host.closes, 0);
    });

    test('אוצריא פתוחה: מבקש לסגור, ורק אחרי "סגירה והמשך" סוגר', () async {
      host.running = true;
      final run = flow.run(both);
      await settle();
      expect(task()!.phase, UpdateHereTaskPhase.closeOtzaria);
      expect(task()!.closeAfterWizard, isFalse);
      expect(host.closes, 0);
      expect(library.applies, 0);

      host.tasks.respond(true);
      await run;
      expect(log, ['close', 'library', 'app']);
      expect(task()!.phase, UpdateHereTaskPhase.done);
    });

    test('"ביטול" בבקשת הסגירה — אוצריא לא נסגרת ושום דבר לא רץ', () async {
      host.running = true;
      final run = flow.run(both);
      await settle();
      host.tasks.respond(false);
      await run;
      expect(host.closes, 0);
      expect(library.applies, 0);
      expect(app.installs, 0);
      expect(host.tasks.hasTask, isFalse);
    });

    test('תוכנה בלבד, אוצריא פתוחה, "ביטול" — לא נסגרת ולא מותקנת', () async {
      host.running = true;
      final run = flow.run(const [GuidanceItem.app]);
      await settle();
      expect(task()!.stages, [GuidanceItem.app]);
      host.tasks.respond(false);
      await run;
      expect(host.closes, 0);
      expect(app.installs, 0);
    });

    test('אוצריא שלא נסגרה — הודעה, השאלה חוזרת, ושום דבר לא רץ', () async {
      host
        ..running = true
        ..closeSucceeds = false;
      final run = flow.run(const [GuidanceItem.library]);
      await settle();
      host.tasks.respond(true);
      await settle();
      expect(host.closeFailures, 1);
      expect(task()!.phase, UpdateHereTaskPhase.closeOtzaria);
      expect(library.applies, 0);
      host.tasks.respond(false);
      await run;
      expect(library.applies, 0);
    });

    test('אוצריא נפתחה שוב באמצע וסירבו לסגור — עצירה רגועה', () async {
      library.onApply = () => host.running = true;
      final run = flow.run(both);
      await settle();
      expect(task()!.phase, UpdateHereTaskPhase.closeOtzaria);
      host.tasks.respond(false);
      await run;
      expect(log, ['library']);
      expect(app.installs, 0);
      expect(host.closes, 0);
      expect(task()!.phase, UpdateHereTaskPhase.cancelledByUser);
      expect(task()!.outcomes[GuidanceItem.library], StageOutcome.done);
    });

    test('הספרייה נכשלה — מסך כשל עם ההודעה, והתוכנה לא רצה', () async {
      library
        ..succeeds = false
        ..errorMessage = 'אין מספיק מקום'
        ..needsElevation = true;
      await flow.run(both);
      expect(task()!.phase, UpdateHereTaskPhase.failed);
      expect(task()!.failure!.stage, GuidanceItem.library);
      expect(task()!.failure!.message, 'אין מספיק מקום');
      expect(task()!.failure!.needsElevation, isTrue);
      expect(app.installs, 0);
    });

    test('ביטול באשף — סיום רגוע, לא כשל', () async {
      app.outcome = AppInstallOutcome.cancelled;
      await flow.run(both);
      expect(task()!.phase, UpdateHereTaskPhase.cancelledByUser);
      expect(task()!.failure, isNull);
      expect(task()!.outcomes[GuidanceItem.library], StageOutcome.done);
    });

    test('התקנה שנכשלה — כשל עם הודעה והצעת הרשאות', () async {
      app
        ..outcome = AppInstallOutcome.failed
        ..errorMessage = 'Access is denied'
        ..needsElevation = true;
      await flow.run(const [GuidanceItem.app]);
      expect(task()!.phase, UpdateHereTaskPhase.failed);
      expect(task()!.failure!.stage, GuidanceItem.app);
      expect(task()!.failure!.needsElevation, isTrue);
    });

    // otzaria:// בזמן שהאשף אולי עוד מעתיק היה פותח את הגרסה הישנה.
    test('"הפסק להמתין" לאשף — השלב נגמר, והתוספים אינם נשלחים', () async {
      app
        ..gate = Completer<void>()
        ..outcome = AppInstallOutcome.stillOpen;
      plugins.deliverableUpdates = const ['לוח'];
      final run = flow.run(const [GuidanceItem.app, GuidanceItem.plugins]);
      await settle();
      expect(task()!.currentStage, GuidanceItem.app);
      flow.stopWaiting();
      await run;
      expect(app.stops, 1);
      expect(task()!.outcomes, {
        GuidanceItem.app: StageOutcome.stoppedWaiting,
        GuidanceItem.plugins: StageOutcome.skipped,
      });
      expect(log, ['app']);
      expect(task()!.phase, UpdateHereTaskPhase.done);
    });

    test('האשף עוד פתוח בלי שביקשו להפסיק — לא נקרא הצלחה ולא "נסגר"',
        () async {
      app.outcome = AppInstallOutcome.stillOpen;
      await flow.run(const [GuidanceItem.app]);
      expect(task()!.phase, UpdateHereTaskPhase.cancelledByUser);
      expect(task()!.outcomes, {GuidanceItem.app: StageOutcome.stillOpen});
      expect(task()!.stageIndex, 0);
    });

    test('תוספים אחרונים, ורק כשיש מה למסור; בלי לסגור את אוצריא', () async {
      plugins.deliverableUpdates = const ['לוח', 'מזומנים'];
      host.running = true;
      await flow.run(const [GuidanceItem.plugins]);
      expect(host.closes, 0);
      expect(task()!.stages, [GuidanceItem.plugins]);
      expect(task()!.plugins.map((p) => p.state),
          everyElement(PluginDeliveryState.sent));
      expect(task()!.phase, UpdateHereTaskPhase.done);

      host.tasks.dismiss();
      plugins.deliverableUpdates = const [];
      expect(await flow.run(const [GuidanceItem.plugins]), isFalse);
      expect(host.tasks.hasTask, isFalse);
    });

    test('"סיום בלי לחכות" — המסך עובר לסיום והמסירה ממשיכה', () async {
      plugins
        ..deliverableUpdates = const ['לוח']
        ..gate = Completer<void>();
      final run = flow.run(const [GuidanceItem.plugins]);
      await settle();
      expect(task()!.currentStage, GuidanceItem.plugins);
      host.tasks.finishWithoutWaiting();
      await run;
      expect(task()!.phase, UpdateHereTaskPhase.done);
      expect(task()!.plugins.single.state, PluginDeliveryState.waiting);
      plugins.gate!.complete();
      await settle();
      expect(task()!.plugins.single.state, PluginDeliveryState.sent);
    });

    test('מנהל של משתמש אחר נשאל קודם; "ביטול" לא מריץ כלום', () async {
      app.elevatedAsOtherUser = true;
      final run = flow.run(both);
      await settle();
      expect(task()!.phase, UpdateHereTaskPhase.confirmElevatedOtherUser);
      host.tasks.respond(false);
      await run;
      expect(log, isEmpty);
      expect(host.tasks.hasTask, isFalse);
    });

    test('מנהל של משתמש אחר — רק כשהתוכנה בעדכון', () async {
      app.elevatedAsOtherUser = true;
      await flow.run(const [GuidanceItem.library]);
      expect(log, ['library']);
    });
  });

  group('התקנה ראשונה', () {
    setUp(() {
      app.isInstalled = false;
      library.isFreshInstall = true;
    });

    test('מחשב ריק: התוכנה, בדיקה מחדש, ואז הספרייה — בלי תוספים', () async {
      plugins.deliverableUpdates = const ['לוח'];
      await flow.run(const [
        GuidanceItem.app,
        GuidanceItem.library,
        GuidanceItem.plugins,
      ]);
      expect(log, ['app', 'recheck', 'library']);
      expect(task()!.firstInstall, isTrue);
      expect(task()!.stages, [GuidanceItem.app, GuidanceItem.library]);
      expect(task()!.phase, UpdateHereTaskPhase.done);
    });

    test('אין אוצריא אבל יש כבר מסד: התוכנה בלבד', () async {
      library.isFreshInstall = false;
      await flow.run(both);
      expect(log, ['app']);
      expect(task()!.stages, [GuidanceItem.app]);
    });

    test('אוצריא שהאשף פתח נסגרת לבד, בלי לשאול', () async {
      app.gate = Completer<void>();
      final run = flow.run(both);
      await settle();
      host.running = true;
      app.gate!.complete();
      await run;
      expect(log, ['app', 'recheck', 'close', 'library']);
      expect(task()!.phase, UpdateHereTaskPhase.done);
    });

    test('לא נסגרה לבד — שאלה; "לא עכשיו" משאיר את הספרייה', () async {
      app.gate = Completer<void>();
      host.closeSucceeds = false;
      final run = flow.run(both);
      await settle();
      host.running = true;
      app.gate!.complete();
      await settle();
      expect(task()!.phase, UpdateHereTaskPhase.closeOtzaria);
      expect(task()!.closeAfterWizard, isTrue);
      host.tasks.respond(false);
      await run;
      expect(library.applies, 0);
      expect(task()!.outcomes[GuidanceItem.library], StageOutcome.skipped);
      expect(task()!.phase, UpdateHereTaskPhase.done);
    });

    test('ביטול באשף אינו ממשיך לספרייה ואינו בודק אותה', () async {
      app.outcome = AppInstallOutcome.cancelled;
      await flow.run(both);
      expect(log, ['app']);
      expect(task()!.phase, UpdateHereTaskPhase.cancelledByUser);
    });

    test('האשף עוד פתוח אבל אוצריא כבר מותקנת — הספרייה נבדקת ולא מותקנת',
        () async {
      app.outcome = AppInstallOutcome.stillOpen;
      // האשף הניח את אוצריא לפני שחזר.
      app.gate = Completer<void>();
      final run = flow.run(both);
      await settle();
      app.isInstalled = true;
      app.gate!.complete();
      await run;
      expect(log, ['app', 'recheck']);
      expect(library.applies, 0);
      expect(task()!.phase, UpdateHereTaskPhase.cancelledByUser);
    });

    test('אחרי האשף אין בספרייה מה להתקין — השלב מדולג', () async {
      library.availableAfterRecheck = false;
      await flow.run(both);
      expect(log, ['app', 'recheck']);
      expect(task()!.outcomes[GuidanceItem.library], StageOutcome.skipped);
      expect(task()!.phase, UpdateHereTaskPhase.done);
    });
  });

  group('מ"אוצריא — מתקדם" ומדף הספרייה', () {
    test('התקנה מחדש: אותה גרסה רצה באשף, ורק כשהיא בכונן', () async {
      app.hasUpdateAvailable = false;
      expect(await flow.run(const [GuidanceItem.app]), isFalse);
      expect(app.installs, 0);

      app.canReinstall = true;
      // בלי בקשה מפורשת — "אין עדכון" נשאר "אין מה להתקין".
      expect(await flow.run(const [GuidanceItem.app]), isFalse);
      expect(
        await flow.run(const [GuidanceItem.app], reinstallApp: true),
        isTrue,
      );
      expect(log, ['app']);
      expect(task()!.outcomes[GuidanceItem.app], StageOutcome.done);
    });

    test('הספרייה המלאה: רק אחרי כשל, ובמקום העדכון הרגיל', () async {
      library.hasUpdateAvailable = false;
      expect(
        await flow.run(const [GuidanceItem.library], fullLibrary: true),
        isFalse,
      );
      library.canApplyFull = true;
      await flow.run(const [GuidanceItem.library], fullLibrary: true);
      expect(log, ['library-full']);
      expect(library.applies, 0);
      expect(library.fullApplies, 1);
      expect(task()!.phase, UpdateHereTaskPhase.done);
    });
  });

  group('"נסה שוב" — אותה בקשה', () {
    test('הספרייה המלאה נכשלה — שוב הספרייה המלאה בלבד', () async {
      library
        ..canApplyFull = true
        ..succeeds = false;
      app.hasUpdateAvailable = true;
      await flow.run(const [GuidanceItem.library], fullLibrary: true);
      expect(task()!.phase, UpdateHereTaskPhase.failed);

      library.succeeds = true;
      expect(await flow.retry(), isTrue);
      expect(log, ['library-full', 'library-full']);
      expect(library.applies, 0);
      expect(app.installs, 0);
      expect(task()!.phase, UpdateHereTaskPhase.done);
    });

    test('התקנה מחדש נכשלה — שוב התקנה מחדש, ולא "אין מה להתקין"', () async {
      app
        ..hasUpdateAvailable = false
        ..canReinstall = true
        ..outcome = AppInstallOutcome.failed;
      await flow.run(const [GuidanceItem.app], reinstallApp: true);
      expect(task()!.phase, UpdateHereTaskPhase.failed);

      app.outcome = AppInstallOutcome.installed;
      expect(await flow.retry(), isTrue);
      expect(app.installs, 2);
      expect(library.applies, 0);
      expect(task()!.phase, UpdateHereTaskPhase.done);
    });

    test('אחרי ביטול באשף — התקנה מחדש שוב; בזמן ריצה — כלום', () async {
      app
        ..hasUpdateAvailable = false
        ..canReinstall = true
        ..outcome = AppInstallOutcome.cancelled;
      await flow.run(const [GuidanceItem.app], reinstallApp: true);
      expect(task()!.phase, UpdateHereTaskPhase.cancelledByUser);

      app
        ..outcome = AppInstallOutcome.installed
        ..gate = Completer<void>();
      final retry = flow.retry();
      await settle();
      expect(task()!.isFinished, isFalse);
      expect(await flow.retry(), isFalse);
      app.gate!.complete();
      expect(await retry, isTrue);
      expect(app.installs, 2);
      expect(task()!.phase, UpdateHereTaskPhase.done);
    });
  });

  group('תיקוני QA של 2b', () {
    test('ספרייה שהוחלה עם הערה — סיום עם ההערה, לא כשל', () async {
      library.noteAfterApply = 'צריך לכוון את אוצריא לספרייה';
      await flow.run(both);
      expect(task()!.phase, UpdateHereTaskPhase.done);
      expect(task()!.failure, isNull);
      expect(task()!.outcomes[GuidanceItem.library], StageOutcome.done);
      expect(task()!.libraryNote, 'צריך לכוון את אוצריא לספרייה');
      expect(log, ['library', 'app']);
    });

    test('ספרייה שהוחלה בלי הערה — בלי הערה', () async {
      await flow.run(const [GuidanceItem.library]);
      expect(task()!.libraryNote, isNull);
    });

    test('אומדן ההחלה והחשבון נשמרים במשימה', () async {
      library.estimate = (low: 3, high: 12);
      app
        ..elevatedAsOtherUser = true
        ..adminAccount = 'Admin';
      final run = flow.run(both);
      await settle();
      expect(task()!.libraryMinutes, (low: 3, high: 12));
      expect(task()!.account, 'Admin');
      host.tasks.respond(true);
      await run;
    });

    test('"הפסק להמתין" בהתקנה ראשונה — נשאר על התוכנה, לא "אוצריא פתוחה"',
        () async {
      app
        ..isInstalled = false
        ..gate = Completer<void>()
        ..outcome = AppInstallOutcome.stillOpen;
      library.isFreshInstall = true;
      final run = flow.run(both);
      await settle();
      flow.stopWaiting();
      await run;
      expect(task()!.phase, UpdateHereTaskPhase.cancelledByUser);
      expect(task()!.stageIndex, 0);
      expect(task()!.stages[task()!.stageIndex], GuidanceItem.app);
      expect(task()!.outcomes, {GuidanceItem.app: StageOutcome.stoppedWaiting});
      expect(library.applies, 0);
    });

    test('היעד של המסירה נקבע ברגע המסירה, לא בפתיחת המשימה', () async {
      plugins
        ..deliverableUpdates = const ['לוח', 'מזומנים']
        ..targetsAtDelivery = const ['לוח'];
      await flow.run(const [GuidanceItem.plugins]);
      expect(task()!.plugins.map((p) => p.name), ['לוח']);
      expect(task()!.outcomes[GuidanceItem.plugins], StageOutcome.done);
    });

    test('יעד שהתרוקן — השלב מדולג, ולא "נשלחו"', () async {
      plugins
        ..deliverableUpdates = const ['לוח']
        ..targetsAtDelivery = const [];
      await flow.run(const [GuidanceItem.plugins]);
      expect(task()!.plugins, isEmpty);
      expect(task()!.outcomes[GuidanceItem.plugins], StageOutcome.skipped);
    });

    test('תוסף שלא נשלח נשאר "נכשל" במשימה', () async {
      plugins
        ..deliverableUpdates = const ['לוח', 'מזומנים']
        ..failing.add('מזומנים');
      await flow.run(const [GuidanceItem.plugins]);
      expect(
        {for (final p in task()!.plugins) p.name: p.state},
        {
          'לוח': PluginDeliveryState.sent,
          'מזומנים': PluginDeliveryState.failed,
        },
      );
    });

    test('מסירה ישנה אינה כותבת על משימה חדשה', () async {
      final oldGate = Completer<void>();
      plugins
        ..deliverableUpdates = const ['לוח']
        ..gate = oldGate;
      final first = flow.run(const [GuidanceItem.plugins]);
      await settle();
      host.tasks.finishWithoutWaiting();
      await first;
      final oldId = task()!.id;
      host.tasks.dismiss();

      plugins.gate = null;
      await flow.run(const [GuidanceItem.library]);
      expect(task()!.id, isNot(oldId));
      final before = task()!.plugins;

      // המסירה הישנה מסתיימת רק עכשיו — ודיווח השורות שלה אינו נכתב.
      oldGate.complete();
      await settle();
      expect(task()!.plugins, same(before));
      expect(task()!.plugins, isEmpty);
    });

    test('run שזורק — המשימה עוברת לכשל ולא נתקעת', () async {
      app.throws = StateError('boom');
      await flow.run(const [GuidanceItem.app]);
      expect(task()!.phase, UpdateHereTaskPhase.failed);
      expect(task()!.failure!.stage, GuidanceItem.app);
      expect(task()!.failure!.message, contains('boom'));
      expect(host.tasks.isRunning, isFalse);
    });

    test('run שזורק — החריג נרשם ביומן עם ה-stack trace', () async {
      final dir = await Directory.systemTemp.createTemp('update-here-log-');
      AppLogger.resetForTest();
      final logger = await AppLogger.init(dir.path);
      addTearDown(() async {
        AppLogger.resetForTest();
        await deleteTempDir(dir);
      });
      app.throws = StateError('boom');
      await flow.run(const [GuidanceItem.app]);
      await logger.flush();
      final log = await File(logger.filePath).readAsString();
      expect(log, contains('Bad state: boom'));
      expect(log, contains('#0'));
    });

    test('הסשן פורק בזמן שאלה — הזרימה אינה נוגעת במשימה', () async {
      host.running = true;
      final run = flow.run(both);
      await settle();
      expect(task()!.phase, UpdateHereTaskPhase.closeOtzaria);
      host.isActive = false;
      host.tasks.respond(false);
      await run;
      // בלי _abandon/updateCancelledByUser על notifier מפורק.
      expect(task()!.phase, UpdateHereTaskPhase.running);
      expect(library.applies, 0);
    });
  });

  group('החלון על החיפוש החכם', () {
    setUp(() {
      host.consentUnanswered = true;
      library.semanticAwaitsConsent = true;
    });

    test('הסכמה — נכתבת לפני הספרייה, והעדכון ממשיך', () async {
      host.consentAnswer = true;
      await flow.run(both);
      expect(host.asks, 1);
      expect(log, ['grant', 'library', 'app']);
      expect(task()!.phase, UpdateHereTaskPhase.done);
    });

    test('הסכמה כשאוצריא פתוחה — נכתבת רק אחרי "סגירה והמשך"', () async {
      host
        ..consentAnswer = true
        ..running = true;
      final run = flow.run(both);
      await settle();
      expect(task()!.phase, UpdateHereTaskPhase.closeOtzaria);
      expect(host.grants, 0);
      host.tasks.respond(true);
      await run;
      expect(log, ['close', 'grant', 'library', 'app']);
    });

    test('הסכמה ואז "ביטול" בסגירת אוצריא — לא נכתב, ושואל שוב', () async {
      host
        ..consentAnswer = true
        ..running = true;
      final run = flow.run(both);
      await settle();
      host.tasks.respond(false);
      await run;
      expect(host.grants, 0);
      expect(host.declines, 0);
      expect(host.consentUnanswered, isTrue);
      host.running = false;
      await flow.run(both);
      expect(host.asks, 2);
    });

    test('הסיבה אינה נבלעת בהערת ההחלה — שתיהן בשורה', () async {
      host
        ..consentAnswer = true
        ..grantSucceeds = false;
      library.noteAfterApply = 'כוון את אוצריא לתיקייה';
      await flow.run(const [GuidanceItem.library]);
      expect(task()!.libraryNote, contains('כוון את אוצריא לתיקייה'));
      expect(task()!.libraryNote, contains(host.grantProblem));
    });

    test('הכתיבה נכשלה — שלב הספרייה רץ בכל זאת, עם הסיבה', () async {
      host
        ..consentAnswer = true
        ..grantSucceeds = false;
      await flow.run(both);
      expect(log, ['grant', 'library', 'app']);
      expect(host.consentUnanswered, isTrue);
      expect(task()!.libraryNote, host.grantProblem);
      expect(task()!.librarySemanticOnly, isFalse);
    });

    test('"המשך בלי" — נרשם, והעדכון רץ בלי לכתוב הסכמה', () async {
      host.consentAnswer = false;
      await flow.run(both);
      expect(log, ['decline', 'library', 'app']);
      expect(host.grants, 0);
      expect(task()!.phase, UpdateHereTaskPhase.done);
    });

    test('אחרי תשובה — לא שואל שוב', () async {
      await flow.run(const [GuidanceItem.library]);
      library.hasUpdateAvailable = true;
      await flow.run(const [GuidanceItem.library]);
      expect(host.asks, 1);
    });

    test('"חזרה" — שום דבר לא מתחיל, ובפעם הבאה שואל שוב', () async {
      host.consentAnswer = null;
      expect(await flow.run(both), isTrue);
      expect(host.tasks.hasTask, isFalse);
      expect(log, isEmpty);
      await flow.run(both);
      expect(host.asks, 2);
    });

    test('בלי הספרייה בבקשה, או בלי אוצריא מותקנת — לא שואל', () async {
      await flow.run(const [GuidanceItem.app]);
      expect(host.asks, 0);

      app
        ..isInstalled = false
        ..hasUpdateAvailable = true;
      library.isFreshInstall = true;
      await flow.run(both);
      expect(host.asks, 0);
    });

    test('"נסה שוב" עובר באותו חלון', () async {
      host.consentUnanswered = false;
      library.succeeds = false;
      await flow.run(const [GuidanceItem.library]);
      expect(task()!.phase, UpdateHereTaskPhase.failed);
      host.consentUnanswered = true;
      library.succeeds = true;
      await flow.retry();
      expect(host.asks, 1);
      expect(log.last, 'library');
    });

    group('רק החיפוש החכם בכונן (הספרייה מעודכנת)', () {
      setUp(() {
        library.hasUpdateAvailable = false;
        host.onGranted = () => library.hasUpdateAvailable = true;
      });

      test('הסכמה — הספרייה מתקינה את החיפוש החכם בלבד', () async {
        host.consentAnswer = true;
        expect(await flow.run(const [GuidanceItem.library]), isTrue);
        expect(log, ['grant', 'library']);
        expect(task()!.libraryVersion, isNull);
        expect(task()!.librarySemanticOnly, isTrue);
        expect(task()!.phase, UpdateHereTaskPhase.done);
      });

      test('"המשך בלי" — אין משימה, רק התשובה נרשמת', () async {
        host.consentAnswer = false;
        expect(await flow.run(const [GuidanceItem.library]), isTrue);
        expect(log, ['decline']);
        expect(host.tasks.hasTask, isFalse);
      });

      test('הסכמה שלא נכתבה — השלב מדולג, לא כשל', () async {
        host
          ..consentAnswer = true
          ..grantSucceeds = false;
        await flow.run(const [GuidanceItem.library]);
        expect(library.applies, 0);
        expect(task()!.outcomes[GuidanceItem.library], StageOutcome.skipped);
        // הסיבה, ולא "אפשר להתקין אחר כך מדף הבית".
        expect(task()!.libraryNote, host.grantProblem);
      });

      test('אחרי תשובה אין שלב בשבילו', () async {
        host.consentUnanswered = false;
        expect(await flow.run(const [GuidanceItem.library]), isFalse);
        expect(host.asks, 0);
      });
    });
  });
}

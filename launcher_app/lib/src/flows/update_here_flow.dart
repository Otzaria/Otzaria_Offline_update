import 'dart:async';

import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../services/app_logger.dart';
import '../shell/home_guidance.dart' show GuidanceItem;
import '../shell/shell_tasks.dart';

/// איך נגמרה הרצת אשף ההתקנה של אוצריא.
enum AppInstallOutcome {
  installed,

  /// האשף בוטל — החלטה של המשתמש.
  cancelled,

  /// האשף עוד פתוח (או שהפסקנו להמתין לו) — לא ידוע אם ההתקנה הסתיימה.
  stillOpen,
  failed,
}

/// איך נגמרה החלת הספרייה. ההצלחה נקבעת מהגרסה שהותקנה, לא מהיעדר הודעה:
/// [appliedWithNote] — המסד הוחלף, אבל יש מה לומר (מיקום, קובץ נלווה).
enum LibraryApplyResult { applied, appliedWithNote, failed }

abstract interface class UpdateHereApp {
  bool get isInstalled;
  bool get hasUpdateAvailable;
  bool get elevatedAsOtherUser;

  /// שם החשבון שהכלי רץ בו כמנהל, כשידוע.
  String? get adminAccount;
  String? get versionToInstall;
  String? get errorMessage;
  bool get needsElevation;

  /// הגרסה שבכונן היא זו שמותקנת — "התקנה מחדש" אפשרית.
  bool get canReinstall;

  /// האשף של אוצריא — המשתמש ממשיך בו בחלון נפרד.
  Future<AppInstallOutcome> installWithWizard();
  void stopWaiting();
}

abstract interface class UpdateHereLibrary {
  bool get isFreshInstall;
  bool get hasUpdateAvailable;
  int? get targetVersion;

  /// חיפוש חכם בכונן מחכה להסכמה — אינו "עדכון" עד שהיא נכתבת.
  bool get semanticAwaitsConsent;

  /// תוכנית הספרייה מוגבלת לאוצריא שמותקנת, ובכונן מתקין חדש יותר: היא
  /// נבדקת מחדש רק אחרי שהתוכנה מותקנת.
  bool get awaitsAppUpdate;

  /// הכשל, אחרי [LibraryApplyResult.failed].
  String? get errorMessage;

  /// אחרי [LibraryApplyResult.appliedWithNote] — ההערה עצמה.
  String? get applyNote;
  bool get needsElevation;

  /// בכונן יש ספרייה מלאה שאפשר להתקין במקום עדכון שנכשל.
  bool get canApplyFull;

  /// האומדן לתוכנית שתוחל, בדקות, כשידוע.
  ({int low, int high})? applyEstimate({bool full = false});

  Future<LibraryApplyResult> apply();

  /// כמו [apply], מהספרייה המלאה שבכונן.
  Future<LibraryApplyResult> applyFull();

  /// `false` — הבדיקה עצמה נכשלה ([errorMessage]); "אין עדכון" הוא `true`.
  Future<bool> recheck();

  /// למה החיפוש החכם פתוח אחרי הבדיקה האחרונה; `null` — סגור, או שההסכמה
  /// היא שמטפלת בו.
  String? get semanticOpenNote;
}

abstract interface class UpdateHerePlugins {
  /// שמות התוספים שאפשר למסור לאוצריא עכשיו.
  List<String> get deliverableUpdates;

  /// מוסר אותם אחד אחד. [onRow] נקרא **מיד** עם כל השורות כ"ממתין" — היעד
  /// מחושב כאן, ולא ברגע שהמשימה נפתחה — ואחר כך אחרי כל שינוי.
  Future<void> deliver(void Function(List<PluginDelivery> rows) onRow);
}

/// מה הזרימה צריכה מהסשן ומשכבת המשימה (`ShellTasks`).
abstract interface class UpdateHereHost {
  bool get isActive;

  /// בדיקת תהליך טרייה — לא ערך שנלכד קודם.
  Future<bool> isOtzariaRunning();
  Future<bool> closeOtzaria();

  /// סגירה נכשלה — הודעה, והשאלה חוזרת.
  void closeFailed();
  ShellTasks get tasks;

  /// חיפוש חכם בכונן מחכה להסכמה, והחלון עליו עוד לא נענה במחשב הזה.
  Future<bool> semanticConsentUnanswered();

  /// `null` — "חזרה": אין תשובה, ושום דבר לא מתחיל.
  Future<bool?> askSemanticConsent();
  Future<void> declineSemanticConsent();

  /// אחרי שאוצריא נסגרה: הכתיבה להגדרות שלה דורשת אותה סגורה. מחזיר את מה
  /// שיש לומר כשלא נכתבה (חסימת שרת, כשל) — במסך המשימה, לא בהודעה צפה.
  Future<String?> grantSemanticConsent();
}

/// "עדכון כאן": הספרייה, התוכנה ואז התוספים; בהתקנה ראשונה התוכנה ואז הספרייה.
/// אוצריא נסגרת רק אחרי "סגירה והמשך", חוץ מאחרי אשף שפתח אותה בעצמו.
class UpdateHereFlow {
  UpdateHereFlow({
    required this.app,
    required this.library,
    required this.plugins,
    required this.host,
  });

  final UpdateHereApp app;
  final UpdateHereLibrary library;
  final UpdateHerePlugins plugins;
  final UpdateHereHost host;

  ShellTasks get _tasks => host.tasks;

  /// השלבים לפי מה שבאמת יש להתקין מתוך [items], בסדר ההרצה.
  /// [reinstallApp] — גם אותה גרסה; [fullLibrary] — הספרייה המלאה שבכונן;
  /// [semantic] — הספרייה נכללת גם רק בשביל החלון על החיפוש החכם;
  /// [recheckLibrary] — "נסה שוב" אחרי שהבדיקה של הספרייה נכשלה בסוף האשף.
  List<GuidanceItem> stagesFor(
    List<GuidanceItem> items, {
    bool reinstallApp = false,
    bool fullLibrary = false,
    bool semantic = false,
    bool recheckLibrary = false,
  }) {
    if (!app.isInstalled) {
      return [
        if (app.hasUpdateAvailable) GuidanceItem.app,
        if (app.hasUpdateAvailable &&
            library.isFreshInstall &&
            library.hasUpdateAvailable)
          GuidanceItem.library,
      ];
    }
    // "נסה שוב" אחרי כשל בדיקה: התוכנה כבר הותקנה.
    final installsApp = !recheckLibrary &&
        items.contains(GuidanceItem.app) &&
        _canInstallApp(reinstallApp);
    // תוכנית הספרייה נגזרת מהתוכנה שמותקנת: עד שהחדשה מותקנת אין מה להחיל,
    // ולכן היא רצה אחריה ולא בלחיצה נוספת.
    final afterApp = installsApp && library.awaitsAppUpdate;
    final installsLibrary = items.contains(GuidanceItem.library) &&
        (fullLibrary
            ? library.canApplyFull
            : library.hasUpdateAvailable ||
                semantic ||
                afterApp ||
                recheckLibrary);
    return [
      if (installsLibrary && !afterApp) GuidanceItem.library,
      if (installsApp) GuidanceItem.app,
      if (installsLibrary && afterApp) GuidanceItem.library,
      if (items.contains(GuidanceItem.plugins) &&
          (plugins.deliverableUpdates.isNotEmpty ||
              installsApp ||
              recheckLibrary))
        GuidanceItem.plugins,
    ];
  }

  bool _canInstallApp(bool reinstall) =>
      app.hasUpdateAvailable || (reinstall && app.canReinstall);

  /// `false` — אין מה להתקין, והמשימה לא נפתחה. חריג באמצע מעביר את
  /// המשימה לכשל: משימה רצה חוסמת את Esc ואת הסרגל, ובלי זה אין ממנה יציאה.
  /// [blocked] — שלבים שההורדה שרצה עוד כותבת את המראה שלהם; הם יחכו לפעם הבאה.
  Future<bool> run(
    List<GuidanceItem> items, {
    bool reinstallApp = false,
    bool fullLibrary = false,
    Set<GuidanceItem> Function()? blocked,
  }) =>
      _start(
        items,
        reinstallApp: reinstallApp,
        fullLibrary: fullLibrary,
        blocked: blocked,
      );

  /// הבדיקה של הספרייה אחרי התקנת התוכנה נכשלה: התוכנה הותקנה, ו"נסה שוב"
  /// בודק את הספרייה שוב במקום לחשוב שאין מה להתקין.
  bool _libraryRecheckFailed = false;

  Future<bool> _start(
    List<GuidanceItem> items, {
    required bool reinstallApp,
    required bool fullLibrary,
    Set<GuidanceItem> Function()? blocked,
    bool recheckLibrary = false,
  }) async {
    _libraryRecheckFailed = false;
    // ספרייה מלאה שממתינה לתוכנה רצה אחריה, כמו העדכון הרגיל.
    if (fullLibrary &&
        !recheckLibrary &&
        items.contains(GuidanceItem.library) &&
        !items.contains(GuidanceItem.app) &&
        app.isInstalled &&
        app.hasUpdateAvailable &&
        library.awaitsAppUpdate) {
      items = [...items, GuidanceItem.app];
    }
    var fullBlockedByApp = false;
    // ההסכמה נכתבת להגדרות של אוצריא, ולכן רק כשהיא מותקנת.
    final wantsAsk = app.isInstalled &&
        items.contains(GuidanceItem.library) &&
        !(blocked?.call().contains(GuidanceItem.library) ?? false) &&
        library.semanticAwaitsConsent &&
        await host.semanticConsentUnanswered();
    if (!host.isActive) return true;
    List<GuidanceItem> stagesNow({required bool semantic}) {
      final stages = stagesFor(
        items,
        reinstallApp: reinstallApp,
        fullLibrary: fullLibrary,
        semantic: semantic,
        recheckLibrary: recheckLibrary,
      );
      // נקרא שוב אחרי חלון ההסכמה: ההורדה עשויה להתקדם בינתיים.
      final now = blocked?.call() ?? const {};
      // בהתקנה ראשונה הספרייה תלויה בתוכנה שתותקן לפניה.
      if (!app.isInstalled && now.contains(GuidanceItem.app)) return [];
      final allowed = [
        for (final stage in stages)
          if (!now.contains(stage)) stage,
      ];
      // הספרייה שממתינה לתוכנה אינה רצה בלעדיה.
      if (!recheckLibrary &&
          library.awaitsAppUpdate &&
          app.hasUpdateAvailable &&
          (fullLibrary || !library.hasUpdateAvailable) &&
          !allowed.contains(GuidanceItem.app) &&
          allowed.remove(GuidanceItem.library) &&
          fullLibrary) {
        fullBlockedByApp = true;
      }
      return allowed;
    }

    // ספרייה שנשמטת מהשלבים אינה שואלת: ההסכמה לא הייתה נכתבת.
    final asks =
        wantsAsk && stagesNow(semantic: true).contains(GuidanceItem.library);
    var stages = stagesNow(semantic: asks);
    if (stages.isEmpty && fullBlockedByApp) {
      _tasks.startUpdateHere(
        const [GuidanceItem.library],
        libraryVersion: library.targetVersion,
        request: (
          items: List.unmodifiable(items),
          reinstallApp: reinstallApp,
          fullLibrary: true,
        ),
      );
      _tasks
        ..stageFinished(
          GuidanceItem.library,
          StageOutcome.skipped,
          note: AppL10n.strings.task.libraryAwaitsApp,
        )
        ..updateDone();
      return true;
    }
    if (stages.isEmpty) return false;
    var grantConsent = false;
    if (asks) {
      final approve = await host.askSemanticConsent();
      if (approve == null || !host.isActive || _tasks.updateInProgress) {
        return true;
      }
      if (approve) {
        grantConsent = true;
        stages = stagesNow(semantic: true);
      } else {
        await host.declineSemanticConsent();
        stages = stagesNow(semantic: false);
      }
      if (stages.isEmpty || !host.isActive) return true;
    }
    final hasApp = stages.contains(GuidanceItem.app);
    final libraryUpdate = stages.contains(GuidanceItem.library) &&
        (fullLibrary ||
            library.hasUpdateAvailable ||
            (library.awaitsAppUpdate && app.hasUpdateAvailable));
    final id = _tasks.startUpdateHere(
      stages,
      firstInstall: !app.isInstalled,
      appVersion: hasApp ? app.versionToInstall : null,
      libraryVersion: libraryUpdate ? library.targetVersion : null,
      libraryMinutes:
          libraryUpdate ? library.applyEstimate(full: fullLibrary) : null,
      librarySemanticOnly: grantConsent && !libraryUpdate,
      account: hasApp && app.elevatedAsOtherUser ? app.adminAccount : null,
      pluginNames: stages.contains(GuidanceItem.plugins)
          ? plugins.deliverableUpdates
          : const [],
      request: (
        items: List.unmodifiable(items),
        reinstallApp: reinstallApp,
        fullLibrary: fullLibrary,
      ),
    );
    try {
      await _run(
        id,
        stages,
        first: !app.isInstalled,
        reinstallApp: reinstallApp,
        fullLibrary: fullLibrary,
        grantConsent: grantConsent,
        recheckLibrary: recheckLibrary,
      );
    } catch (error, stackTrace) {
      AppLogger.maybeInstance
          ?.error('העדכון במחשב הזה נעצר בחריג', error, stackTrace);
      _failIfRunning(id, error);
    }
    return true;
  }

  /// "נסה שוב" אחרי כשל או ביטול — אותה בקשה, לא מה שמוצג עכשיו בבית.
  Future<bool> retry({Set<GuidanceItem> Function()? blocked}) async {
    final request = switch (_tasks.updateTask) {
      UpdateHereTask(:final request?, isFinished: true) => request,
      _ => null,
    };
    if (request == null) return false;
    return _start(
      request.items,
      reinstallApp: request.reinstallApp,
      fullLibrary: request.fullLibrary,
      blocked: blocked,
      recheckLibrary: _libraryRecheckFailed,
    );
  }

  Future<void> _run(
    int id,
    List<GuidanceItem> stages, {
    required bool first,
    required bool reinstallApp,
    required bool fullLibrary,
    required bool grantConsent,
    required bool recheckLibrary,
  }) async {
    if (stages.contains(GuidanceItem.app) && app.elevatedAsOtherUser) {
      final go = await _tasks.askOtherUser();
      if (!host.isActive) return;
      if (!go) return _tasks.abandonUpdate();
    }

    var ranAny = false;
    for (final stage in stages) {
      if (!host.isActive) return;
      final keepGoing = switch (stage) {
        GuidanceItem.library => await _library(
            afterApp: recheckLibrary ||
                (stages.contains(GuidanceItem.app) &&
                    stages.indexOf(GuidanceItem.app) <
                        stages.indexOf(GuidanceItem.library)),
            ranAny: ranAny,
            full: fullLibrary,
            grantConsent: grantConsent,
          ),
        GuidanceItem.app => await _app(
            first: first,
            ranAny: ranAny,
            reinstall: reinstallApp,
          ),
        GuidanceItem.plugins => await _plugins(id),
      };
      if (!host.isActive) return;
      if (keepGoing == null) return _tasks.abandonUpdate();
      if (!keepGoing) return;
      ranAny = true;
    }
    _tasks.updateDone();
  }

  void _failIfRunning(int id, Object error) {
    if (!host.isActive || !_tasks.isCurrentUpdate(id)) return;
    final task = _tasks.updateTask!;
    if (task.isFinished) return;
    _tasks.updateFailed(UpdateFailure(
      task.currentStage ?? task.stages.first,
      message: '$error',
    ));
  }

  /// `null` — המשתמש ביטל לפני ששום דבר רץ.
  Future<bool?> _ensureClosed({required bool ranAny}) async {
    while (await host.isOtzariaRunning()) {
      if (!host.isActive) return false;
      final close = await _tasks.askToCloseOtzaria();
      if (!host.isActive) return false;
      if (!close) {
        if (!ranAny) return null;
        _tasks.updateCancelledByUser();
        return false;
      }
      if (await host.closeOtzaria()) return true;
      host.closeFailed();
    }
    return true;
  }

  /// [afterApp] — התוכנה הותקנה זה עתה: האשף עשוי היה לפתוח את אוצריא, ותוכנית
  /// הספרייה (והמסד, בהתקנה ראשונה) נקבעים לפי מה שהותקן.
  Future<bool?> _library({
    required bool afterApp,
    required bool ranAny,
    bool full = false,
    bool grantConsent = false,
  }) async {
    String? consentNote;
    if (afterApp) {
      // האשף אולי עוד מעתיק קבצים: הספרייה לא תוחל לפני שהתוכנה הותקנה.
      if (_appStoppedWaiting) {
        _tasks.stageFinished(GuidanceItem.library, StageOutcome.skipped);
        return true;
      }
      final checked = await library.recheck();
      if (!host.isActive) return false;
      if (!checked) {
        _libraryRecheckFailed = true;
        _tasks.updateFailed(UpdateFailure(
          GuidanceItem.library,
          message: library.errorMessage,
          needsElevation: library.needsElevation,
        ));
        return false;
      }
      final updates = library.hasUpdateAvailable;
      if (!updates && !grantConsent && !full) {
        _tasks.stageFinished(
          GuidanceItem.library,
          StageOutcome.skipped,
          note: library.semanticOpenNote,
        );
        return true;
      }
      _tasks.libraryPlan(
        version: updates ? library.targetVersion : null,
        minutes: updates ? library.applyEstimate(full: full) : null,
        semanticOnly: grantConsent && !updates,
      );
      // האשף פתח את אוצריא; סוגרים אותה לבד, ושואלים רק אם לא נסגרה.
      if (await host.isOtzariaRunning() && !await host.closeOtzaria()) {
        while (await host.isOtzariaRunning()) {
          if (!host.isActive) return false;
          final close = await _tasks.askToCloseOtzaria(afterWizard: true);
          if (!host.isActive) return false;
          if (!close) {
            _tasks.stageFinished(GuidanceItem.library, StageOutcome.skipped);
            return true;
          }
          if (await host.closeOtzaria()) break;
          host.closeFailed();
        }
      }
    } else {
      final closed = await _ensureClosed(ranAny: ranAny);
      if (closed != true) return closed;
    }
    if (grantConsent) {
      consentNote = await host.grantSemanticConsent();
      if (!host.isActive) return false;
      // הכתיבה נכשלה והחיפוש החכם היה כל מה שיש — אין מה להחיל.
      if (!full && !library.hasUpdateAvailable) {
        _tasks.stageFinished(
          GuidanceItem.library,
          StageOutcome.skipped,
          note: consentNote ?? library.semanticOpenNote,
        );
        return true;
      }
    }
    if (!host.isActive) return false;
    _tasks.stageRunning(GuidanceItem.library);
    final result = await (full ? library.applyFull() : library.apply());
    if (!host.isActive) return false;
    if (result == LibraryApplyResult.failed) {
      _tasks.updateFailed(UpdateFailure(
        GuidanceItem.library,
        message: library.errorMessage,
        needsElevation: library.needsElevation,
      ));
      return false;
    }
    // שתי ההערות: הסיבה שהחיפוש החכם לא הותקן אינה נבלעת בהערת ההחלה.
    final notes = [
      if (result == LibraryApplyResult.appliedWithNote) library.applyNote,
      consentNote,
    ].nonNulls;
    _tasks.stageFinished(
      GuidanceItem.library,
      StageOutcome.done,
      note: notes.isEmpty ? null : notes.join('\n'),
    );
    return true;
  }

  Future<bool?> _app({
    required bool first,
    required bool ranAny,
    bool reinstall = false,
  }) async {
    final closed = await _ensureClosed(ranAny: ranAny);
    if (closed != true) return closed;
    if (!_canInstallApp(reinstall)) {
      _tasks.stageFinished(GuidanceItem.app, StageOutcome.skipped);
      return true;
    }
    _tasks.stageRunning(GuidanceItem.app);
    final outcome = await app.installWithWizard();
    if (!host.isActive) return false;
    final stopped = switch (_tasks.updateTask) {
      UpdateHereTask(:final stopWaitingRequested) => stopWaitingRequested,
      _ => false,
    };
    switch (outcome) {
      case AppInstallOutcome.installed:
        _tasks.stageFinished(GuidanceItem.app, StageOutcome.done);
        return true;
      case AppInstallOutcome.stillOpen when stopped:
        // בהתקנה ראשונה אין התקנה ודאית שהספרייה יכולה להיתלות בה.
        if (first) {
          _tasks
            ..stageStopped(GuidanceItem.app, StageOutcome.stoppedWaiting)
            ..updateCancelledByUser();
          return false;
        }
        _tasks.stageFinished(GuidanceItem.app, StageOutcome.stoppedWaiting);
        return true;
      case AppInstallOutcome.stillOpen:
        if (first && app.isInstalled) await library.recheck();
        if (!host.isActive) return false;
        _tasks
          ..stageStopped(GuidanceItem.app, StageOutcome.stillOpen)
          ..updateCancelledByUser();
        return false;
      case AppInstallOutcome.cancelled:
        if (first && app.isInstalled) await library.recheck();
        if (host.isActive) _tasks.updateCancelledByUser();
        return false;
      case AppInstallOutcome.failed:
        _tasks.updateFailed(UpdateFailure(
          GuidanceItem.app,
          message: app.errorMessage,
          needsElevation: app.needsElevation,
        ));
        return false;
    }
  }

  bool get _appStoppedWaiting => switch (_tasks.updateTask) {
        UpdateHereTask(:final outcomes) =>
          outcomes[GuidanceItem.app] == StageOutcome.stoppedWaiting,
        _ => false,
      };

  Future<bool> _plugins(int id) async {
    // האשף אולי עוד מעתיק קבצים: otzaria:// היה פותח את הגרסה הישנה.
    if (_appStoppedWaiting) {
      _tasks.stageFinished(GuidanceItem.plugins, StageOutcome.skipped);
      return true;
    }
    _tasks.stageRunning(GuidanceItem.plugins);
    final delivery = plugins.deliver((rows) {
      if (host.isActive && _tasks.isCurrentUpdate(id)) {
        _tasks.pluginDeliveries(rows);
      }
    });
    await Future.any([delivery, _tasks.finishRequested]);
    if (!host.isActive) return false;
    final rows = switch (_tasks.updateTask) {
      UpdateHereTask(:final plugins) => plugins,
      _ => const <PluginDelivery>[],
    };
    _tasks.stageFinished(
      GuidanceItem.plugins,
      rows.isEmpty ? StageOutcome.skipped : StageOutcome.done,
    );
    return true;
  }

  /// "הפסק להמתין" לאשף ההתקנה.
  void stopWaiting() {
    _tasks.requestStopWaiting();
    app.stopWaiting();
  }
}

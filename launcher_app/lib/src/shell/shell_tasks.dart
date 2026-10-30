import 'dart:async';

import 'package:flutter/foundation.dart';

import '../controllers/download_plan.dart'
    show MirrorComponent, SemanticSearchAnswer;
import 'home_guidance.dart' show GuidanceItem;

enum DownloadTaskPhase { preparing, question, running, cancelled, done, failed }

enum UpdateHereTaskPhase {
  confirmElevatedOtherUser,
  closeOtzaria,
  running,
  done,
  cancelledByUser,
  failed,
}

/// למה ההורדה נכשלה — קובע את התג ואת הנוסח של מסך הכשל. [blocked] — החיבור
/// המאובטח נדחה (תעודה), לרוב בגלל מסנן אינטרנט.
enum DownloadFailureKind {
  network,
  blocked,
  shabbat,
  diskSpace,
  snapshot,
  libraryInstaller,
  other
}

class DownloadFailure {
  const DownloadFailure(
    this.kind, {
    this.components = const [],
    this.details,
    this.needed,
    this.free,
    this.dir,
  });

  final DownloadFailureKind kind;

  /// הרכיבים שלא ירדו. מה שירד לפניהם נשאר בכונן.
  final List<MirrorComponent> components;

  /// "פרטים טכניים" — הודעות החריגים כמו שהן.
  final String? details;

  /// ב-[DownloadFailureKind.diskSpace]: כמה נדרש וכמה פנוי, מעוצבים. `null`
  /// כשהמערכת לא סיפקה מדידה — אז המסך אומר רק איזה כונן התמלא ([dir]).
  final String? needed;
  final String? free;
  final String? dir;
}

/// איך הסתיים שלב ב"עדכון כאן".
enum StageOutcome {
  done,

  /// "הפסק להמתין" לאשף — לא ידוע אם ההתקנה הסתיימה.
  stoppedWaiting,

  /// האשף עדיין רץ אחרי הזמן הקצוב — ההתקנה עשויה עוד להסתיים.
  stillOpen,

  /// לא נדרש בסוף (למשל הספרייה אחרי התקנה ראשונה), או נדחה לפעם אחרת.
  skipped,
}

enum PluginDeliveryState { waiting, sent, failed }

/// שורת תוסף בשלב המסירה. "נשלח" ולא "הותקן": את ההתקנה מאשרים באוצריא.
class PluginDelivery {
  const PluginDelivery(this.name, this.state);

  final String name;
  final PluginDeliveryState state;
}

class UpdateFailure {
  const UpdateFailure(this.stage, {this.message, this.needsElevation = false});

  final GuidanceItem stage;
  final String? message;
  final bool needsElevation;
}

/// משימה שמוצגת בשכבת המשימה של הגוף. בלתי משתנה: כל מעבר יוצר עותק.
sealed class ShellTask {
  const ShellTask();

  /// סיום (טוב או רע) — רק אז מותר לסגור את המסך.
  bool get isFinished;
}

final class DownloadTask extends ShellTask {
  const DownloadTask({
    required this.phase,
    this.components = const [],
    this.expectedBytes = const {},
    this.skipped = const [],
    this.failure,
    this.revertFailed = false,
    this.kept = const [],
    this.notes = const [],
  });

  final DownloadTaskPhase phase;

  /// מה ירד בהורדה הזו, לפי הסדר.
  final List<MirrorComponent> components;

  /// הגודל הצפוי לכל רכיב לפי הבדיקה ברשת; רכיב שגודלו לא ידוע חסר.
  final Map<MirrorComponent, int> expectedBytes;

  /// מה דולג כי באתר אין בו חדש.
  final List<MirrorComponent> skipped;
  final DownloadFailure? failure;

  /// הביטול לא הצליח להחזיר את הכונן במלואו.
  final bool revertFailed;

  /// בביטול: רכיבים שירדו עד הסוף ונשארו בכונן.
  final List<MirrorComponent> kept;

  final List<String> notes;

  @override
  bool get isFinished => switch (phase) {
        DownloadTaskPhase.cancelled ||
        DownloadTaskPhase.done ||
        DownloadTaskPhase.failed =>
          true,
        _ => false,
      };

  DownloadTask _copy({
    DownloadTaskPhase? phase,
    List<MirrorComponent>? components,
    Map<MirrorComponent, int>? expectedBytes,
    List<MirrorComponent>? skipped,
    DownloadFailure? failure,
    bool? revertFailed,
    List<MirrorComponent>? kept,
    List<String>? notes,
  }) =>
      DownloadTask(
        phase: phase ?? this.phase,
        components: components ?? this.components,
        expectedBytes: expectedBytes ?? this.expectedBytes,
        skipped: skipped ?? this.skipped,
        failure: failure ?? this.failure,
        revertFailed: revertFailed ?? this.revertFailed,
        kept: kept ?? this.kept,
        notes: notes ?? this.notes,
      );
}

/// מה שהתבקש ב"עדכון כאן" — "נסה שוב" מריץ בדיוק אותו דבר.
typedef UpdateHereRequest = ({
  List<GuidanceItem> items,
  bool reinstallApp,
  bool fullLibrary,
});

final class UpdateHereTask extends ShellTask {
  const UpdateHereTask({
    required this.phase,
    required this.stages,
    this.request,
    this.id = 0,
    this.stageIndex = 0,
    this.firstInstall = false,
    this.appVersion,
    this.libraryVersion,
    this.libraryMinutes,
    this.librarySemanticOnly = false,
    this.account,
    this.outcomes = const {},
    this.libraryNote,
    this.plugins = const [],
    this.closeAfterWizard = false,
    this.stopWaitingRequested = false,
    this.failure,
  });

  /// מזהה ההרצה — מסירה שנמשכת אחרי הסיום לא תכתוב על הרצה חדשה.
  final int id;
  final UpdateHereTaskPhase phase;
  final UpdateHereRequest? request;

  /// סדר ההתקנה — ראו `UpdateHereFlow.stagesFor`.
  final List<GuidanceItem> stages;
  final int stageIndex;

  /// אין אוצריא במחשב: "התקנת אוצריא" ולא "עדכון".
  final bool firstInstall;
  final String? appVersion;
  final int? libraryVersion;

  /// אומדן ההחלה של הספרייה, בדקות, כשידוע.
  final ({int low, int high})? libraryMinutes;

  /// שלב הספרייה הוא רק החיפוש החכם (אחרי ההסכמה בחלון) — בלי גרסת מסד.
  final bool librarySemanticOnly;

  /// החשבון שהכלי רץ בו כמנהל — במסך "משתמש אחר", כשידוע.
  final String? account;
  final Map<GuidanceItem, StageOutcome> outcomes;

  /// הספרייה הותקנה, אבל עם הערה (למשל מיקום שצריך לכוון באוצריא).
  final String? libraryNote;
  final List<PluginDelivery> plugins;

  /// הסגירה נדרשת אחרי האשף (שפתח את אוצריא), לא לפני ההתחלה.
  final bool closeAfterWizard;
  final bool stopWaitingRequested;
  final UpdateFailure? failure;

  GuidanceItem? get currentStage =>
      !isFinished && stageIndex < stages.length ? stages[stageIndex] : null;

  @override
  bool get isFinished => switch (phase) {
        UpdateHereTaskPhase.done ||
        UpdateHereTaskPhase.cancelledByUser ||
        UpdateHereTaskPhase.failed =>
          true,
        _ => false,
      };

  UpdateHereTask _copy({
    UpdateHereTaskPhase? phase,
    int? stageIndex,
    Map<GuidanceItem, StageOutcome>? outcomes,
    String? libraryNote,
    List<PluginDelivery>? plugins,
    bool? closeAfterWizard,
    bool? stopWaitingRequested,
    UpdateFailure? failure,
  }) =>
      UpdateHereTask(
        id: id,
        phase: phase ?? this.phase,
        request: request,
        stages: stages,
        stageIndex: stageIndex ?? this.stageIndex,
        firstInstall: firstInstall,
        appVersion: appVersion,
        libraryVersion: libraryVersion,
        libraryMinutes: libraryMinutes,
        librarySemanticOnly: librarySemanticOnly,
        account: account,
        outcomes: outcomes ?? this.outcomes,
        libraryNote: libraryNote ?? this.libraryNote,
        plugins: plugins ?? this.plugins,
        closeAfterWizard: closeAfterWizard ?? this.closeAfterWizard,
        stopWaitingRequested: stopWaitingRequested ?? this.stopWaitingRequested,
        failure: failure ?? this.failure,
      );
}

/// מכונת המצבים של מסכי המשימה: הורדה אחת ו"עדכון כאן" אחד, אחד בחזית.
/// מעבר לא חוקי נזרק, כי הוא באג בזרימה ולא מצב שהמשתמש יכול להגיע אליו.
class ShellTasks extends ChangeNotifier {
  DownloadTask? _download;
  UpdateHereTask? _update;
  bool _downloadHidden = false;
  Completer<SemanticSearchAnswer?>? _question;
  Completer<bool>? _decision;
  Completer<void>? _finishNow;
  int _lastUpdateId = 0;

  /// המשימה שבחזית. "עדכון כאן" גובר: הוא שואל שאלות, וההורדה ממשיכה מאחוריו.
  ShellTask? get current => _update ?? (_downloadHidden ? null : _download);
  bool get hasTask => current != null;

  DownloadTask? get downloadTask => _download;
  UpdateHereTask? get updateTask => _update;

  /// משימה שעוד לא הסתיימה מוצגת — ולכן אין לצאת ממסך המשימה.
  bool get isRunning => current?.isFinished == false;

  bool get downloadInProgress => _download?.isFinished == false;
  bool get updateInProgress => _update?.isFinished == false;

  /// משימה כלשהי עוד רצה, גם הורדה שהוסתרה.
  bool get anyRunning => downloadInProgress || updateInProgress;

  /// ההורדה רצה ברקע — המשתמש חזר לבית.
  bool get downloadHidden => _downloadHidden && downloadInProgress;

  /// "חזרה לבית" בזמן ההורדה: היא ממשיכה, והבית מציג אותה.
  void hideDownload() {
    if (_download?.phase != DownloadTaskPhase.running || _downloadHidden) {
      return;
    }
    _downloadHidden = true;
    notifyListeners();
  }

  /// הורדה שהסתיימה מאחורי "עדכון כאן" והוזזה הצידה — תוצאתה מחכה בבית.
  bool get downloadParked =>
      _downloadHidden && (_download?.isFinished ?? false);

  /// "פתח את הדף" ממשימה שהסתיימה: היא נסגרת, והורדה שהסתיימה מאחוריה זזה
  /// הצידה במקום לעלות לחזית ולחסום את המעבר.
  void leaveTask() {
    final task = current;
    if (task is! UpdateHereTask || !(_download?.isFinished ?? false)) {
      return dismiss();
    }
    if (!task.isFinished) {
      throw StateError('cannot leave a running update');
    }
    _update = null;
    _downloadHidden = true;
    notifyListeners();
  }

  /// "הצג התקדמות" בבית, וגם תוצאה שהוזזה הצידה.
  void showDownload() {
    if (!_downloadHidden) return;
    _downloadHidden = false;
    notifyListeners();
  }

  static const _downloadMoves = {
    DownloadTaskPhase.preparing: {
      DownloadTaskPhase.question,
      DownloadTaskPhase.running,
      DownloadTaskPhase.failed,
    },
    DownloadTaskPhase.question: {DownloadTaskPhase.preparing},
    DownloadTaskPhase.running: {
      DownloadTaskPhase.cancelled,
      DownloadTaskPhase.done,
      DownloadTaskPhase.failed,
    },
  };

  // ── הורדה לכונן ──

  /// ההורדה מתכוננת. מחליף משימה שהסתיימה, כך ש"נסה שוב" אינו חוזר לבית
  /// בדרך; כבר מתכונן — אין שינוי.
  void prepareDownload() {
    final task = _download;
    if (task != null && task.phase == DownloadTaskPhase.preparing) return;
    if (task?.isFinished == false) {
      throw StateError('a download is already running');
    }
    // "עדכון כאן" שהסתיים אינו נשאר בחזית מעל ההורדה החדשה.
    if (_update?.isFinished ?? false) _update = null;
    _downloadHidden = false;
    _setDownload(const DownloadTask(phase: DownloadTaskPhase.preparing));
  }

  /// השאלה שלפני ההורדה ("להוריד גם חיפוש חכם?"). `null` = חזרה, כלומר
  /// ביטול לפני שההורדה התחילה.
  Future<SemanticSearchAnswer?> askBeforeDownload() {
    if (_download == null) prepareDownload();
    _moveDownload(DownloadTaskPhase.question);
    return (_question = Completer<SemanticSearchAnswer?>()).future;
  }

  void answer(SemanticSearchAnswer? value) {
    final question = _question;
    if (question == null || question.isCompleted) return;
    _question = null;
    if (value == null) {
      _setDownload(null);
    } else {
      _moveDownload(DownloadTaskPhase.preparing);
    }
    question.complete(value);
  }

  /// ההורדה התחילה בפועל — [components] הם מה שירד, לפי הסדר.
  void downloadRunning(
    List<MirrorComponent> components, {
    Map<MirrorComponent, int> expectedBytes = const {},
  }) {
    if (_download == null) prepareDownload();
    if (_download?.phase == DownloadTaskPhase.running) return;
    _moveDownload(
      DownloadTaskPhase.running,
      components: components,
      expectedBytes: expectedBytes,
    );
  }

  /// הזרימה חזרה בלי להתחיל (חסימה, בלי בחירה) — המסך נסגר בשקט.
  void abandonDownload() {
    final task = _download;
    if (task == null) return;
    if (task.phase == DownloadTaskPhase.question) return answer(null);
    if (task.phase == DownloadTaskPhase.preparing) _setDownload(null);
  }

  /// ביטול לפני שההורדה התחילה הוא תשובה ריקה לשאלה, לא מצב "בוטל".
  void downloadCancelled({
    bool revertFailed = false,
    List<MirrorComponent> kept = const [],
  }) =>
      _question != null
          ? answer(null)
          : _moveDownload(
              DownloadTaskPhase.cancelled,
              revertFailed: revertFailed,
              kept: kept,
            );

  void downloadFailed(DownloadFailure failure,
          {List<String> notes = const []}) =>
      _moveDownload(DownloadTaskPhase.failed, failure: failure, notes: notes);

  void downloadDone(
          {List<MirrorComponent> skipped = const [],
          List<String> notes = const []}) =>
      _moveDownload(DownloadTaskPhase.done, skipped: skipped, notes: notes);

  // ── עדכון במחשב הזה ──

  /// מחזיר את מזהה ההרצה — ראו [isCurrentUpdate].
  int startUpdateHere(
    List<GuidanceItem> stages, {
    bool firstInstall = false,
    String? appVersion,
    int? libraryVersion,
    ({int low, int high})? libraryMinutes,
    bool librarySemanticOnly = false,
    String? account,
    List<String> pluginNames = const [],
    UpdateHereRequest? request,
  }) {
    if (updateInProgress) throw StateError('an update is already running');
    // "התקנה כאן" ממסך הסיום — רק תוצאה שבחזית; שמאחורי עדכון או בצד עוד לא נראתה.
    if (_update == null &&
        !downloadParked &&
        (_download?.isFinished ?? false)) {
      _download = null;
    }
    if (stages.isEmpty) throw ArgumentError.value(stages, 'stages');
    _finishNow = Completer<void>();
    final id = ++_lastUpdateId;
    _setUpdate(UpdateHereTask(
      id: id,
      phase: UpdateHereTaskPhase.running,
      request: request,
      stages: List.unmodifiable(stages),
      firstInstall: firstInstall,
      appVersion: appVersion,
      libraryVersion: libraryVersion,
      libraryMinutes: libraryMinutes,
      librarySemanticOnly: librarySemanticOnly,
      account: account,
      plugins: [
        for (final name in pluginNames)
          PluginDelivery(name, PluginDeliveryState.waiting),
      ],
    ));
    return id;
  }

  /// "עדכון כאן" [id] עדיין מוצג (גם אם הסתיים) — ולא הרצה חדשה שהחליפה אותו.
  bool isCurrentUpdate(int id) => switch (_update) {
        UpdateHereTask(id: final current) => current == id,
        _ => false,
      };

  /// "הכלי פועל כמנהל בחשבון אחר" — `true` = "המשך בכל זאת".
  Future<bool> askOtherUser() =>
      _ask(UpdateHereTaskPhase.confirmElevatedOtherUser);

  /// "צריך לסגור את אוצריא" — `true` = "סגירה והמשך".
  Future<bool> askToCloseOtzaria({bool afterWizard = false}) => _ask(
        UpdateHereTaskPhase.closeOtzaria,
        closeAfterWizard: afterWizard,
      );

  /// תשובת המשתמש לשאלה שבמסך המשימה.
  void respond(bool value) {
    final decision = _decision;
    if (decision == null || decision.isCompleted) return;
    _decision = null;
    _moveUpdate(UpdateHereTaskPhase.running);
    decision.complete(value);
  }

  void stageRunning(GuidanceItem stage) {
    final task = _updateTask();
    final index = task.stages.indexOf(stage);
    if (index < 0) throw ArgumentError.value(stage, 'stage');
    _setUpdate(task._copy(
      phase: UpdateHereTaskPhase.running,
      stageIndex: index,
      stopWaitingRequested: false,
    ));
  }

  /// [note] — הספרייה הותקנה, אבל יש מה לומר עליה.
  void stageFinished(GuidanceItem stage, StageOutcome outcome, {String? note}) {
    final task = _updateTask();
    _setUpdate(task._copy(
      outcomes: {...task.outcomes, stage: outcome},
      stageIndex: task.stages.indexOf(stage) + 1,
      libraryNote: note,
    ));
  }

  /// השלב נעצר במקומו (האשף עוד פתוח / הפסקנו להמתין) — בלי לעבור הלאה,
  /// כדי שמסך הסיום ידבר על השלב הזה ולא על הבא.
  void stageStopped(GuidanceItem stage, StageOutcome outcome) {
    final task = _updateTask();
    _setUpdate(task._copy(outcomes: {...task.outcomes, stage: outcome}));
  }

  void pluginDeliveries(List<PluginDelivery> rows) =>
      _setUpdate(_updateTask()._copy(plugins: List.unmodifiable(rows)));

  /// "הפסק להמתין" לאשף ההתקנה.
  void requestStopWaiting() {
    final task = _update;
    if (task == null || task.isFinished) return;
    _setUpdate(task._copy(stopWaitingRequested: true));
  }

  /// "סיום בלי לחכות" במסירת התוספים: המסירה ממשיכה, המסך עובר לסיום.
  void finishWithoutWaiting() {
    final finish = _finishNow;
    if (finish != null && !finish.isCompleted) finish.complete();
  }

  Future<void> get finishRequested => (_finishNow ??= Completer<void>()).future;

  void updateDone() => _moveUpdate(UpdateHereTaskPhase.done);

  /// ביטול באשף של אוצריא הוא החלטה של המשתמש — סיום רגוע, לא כשל.
  void updateCancelledByUser() =>
      _moveUpdate(UpdateHereTaskPhase.cancelledByUser);

  void updateFailed(UpdateFailure failure) =>
      _moveUpdate(UpdateHereTaskPhase.failed, failure: failure);

  /// "ביטול" לפני ששום שלב רץ — המסך נסגר וחוזרים למה שהיה.
  void abandonUpdate() {
    final task = _update;
    if (task != null && !task.isFinished) _setUpdate(null);
  }

  /// סוגר משימה שהסתיימה. משימה רצה אינה נסגרת מכאן.
  void dismiss() {
    final task = current;
    if (task == null) return;
    if (!task.isFinished) {
      throw StateError('cannot dismiss a running task: $task');
    }
    if (task is UpdateHereTask) {
      _setUpdate(null);
    } else {
      _setDownload(null);
    }
  }

  @override
  void dispose() {
    final question = _question;
    _question = null;
    if (question != null && !question.isCompleted) question.complete(null);
    final decision = _decision;
    _decision = null;
    if (decision != null && !decision.isCompleted) decision.complete(false);
    finishWithoutWaiting();
    super.dispose();
  }

  Future<bool> _ask(UpdateHereTaskPhase phase,
      {bool closeAfterWizard = false}) {
    final task = _updateTask();
    if (task.isFinished || _decision != null) {
      throw StateError('cannot ask in $task');
    }
    _setUpdate(task._copy(phase: phase, closeAfterWizard: closeAfterWizard));
    return (_decision = Completer<bool>()).future;
  }

  void _moveDownload(
    DownloadTaskPhase to, {
    List<MirrorComponent>? components,
    Map<MirrorComponent, int>? expectedBytes,
    List<MirrorComponent>? skipped,
    DownloadFailure? failure,
    bool? revertFailed,
    List<MirrorComponent>? kept,
    List<String>? notes,
  }) {
    final task = _download;
    if (task == null || !(_downloadMoves[task.phase]?.contains(to) ?? false)) {
      throw StateError('illegal download move: $task -> $to');
    }
    _setDownload(task._copy(
      phase: to,
      components: components,
      expectedBytes: expectedBytes,
      skipped: skipped,
      failure: failure,
      revertFailed: revertFailed,
      kept: kept,
      notes: notes,
    ));
  }

  void _moveUpdate(UpdateHereTaskPhase to, {UpdateFailure? failure}) {
    final task = _update;
    if (task == null || task.isFinished) {
      throw StateError('illegal update move: $task -> $to');
    }
    _setUpdate(task._copy(phase: to, failure: failure));
  }

  UpdateHereTask _updateTask() {
    final task = _update;
    if (task == null) {
      throw StateError('expected an update task, got $task');
    }
    return task;
  }

  void _setDownload(DownloadTask? task) {
    _download = task;
    // הורדה שהסתיימה ברקע עולה לחזית עם התוצאה שלה.
    if (task == null || task.isFinished) _downloadHidden = false;
    notifyListeners();
  }

  void _setUpdate(UpdateHereTask? task) {
    _update = task;
    notifyListeners();
  }
}

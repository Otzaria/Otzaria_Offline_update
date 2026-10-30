import '../settings/app_settings.dart';
import 'download_plan.dart';

abstract interface class AppMirrorModule {
  bool get hasStaleFullPackage;
  OnlineProof get onlineProof;
  Future<void> download({required bool Function() isCancelled});
  bool get downloadFailed;

  /// ההורדה האחרונה נכשלה כי הכונן התמלא — אז אין להמשיך לכתוב אליו.
  bool get storageFull;
}

abstract interface class LibraryMirrorModule {
  bool get hasBlockedLibrary;
  bool get shouldOfferSemanticDownload;
  bool get personalUpdateMode;
  OnlineProof get libraryOnlineProof;
  Future<void> download({
    required bool includeSemanticSearch,
    required bool Function() isCancelled,
  });
  bool get downloadFailed;
  bool get storageFull;
  bool get downloadNeedsRetry;

  /// בודק ברקע כמה ירד, בזמן שרכיבים קודמים יורדים.
  void startDownloadSizeProbe();
  void clearDownloadSizeProbe();
}

abstract interface class PluginsMirrorModule {
  OnlineProof get catalogOnlineProof;
  OnlineProof get storeAppOnlineProof;
  Future<void> sync({required bool Function() isCancelled});
  Future<void> syncStoreApp();
  bool get lastSyncFailed;
  bool get storageFull;
}

abstract interface class DownloadRollback {
  /// מחזיר רק את [inProgress]; רכיבים שהסתיימו נשארים בכונן.
  Future<void> rollback(Set<MirrorComponent> inProgress);
}

abstract interface class MirrorDownloadHost {
  bool get isActive;

  /// פעולה שחוסמת כל הורדה (יציאה, "עדכון כאן").
  bool get isBlocked;

  /// פעולה אחרת קוראת או כותבת עכשיו את המראה של [component].
  bool blocksComponent(MirrorComponent component);

  /// מישהו אחר משתמש במראה — הניקוי שבסוף ההורדה היה מוחק לו קבצים.
  bool get mirrorInUse;
  AppSettings get settings;

  /// `true` כשבדיקה אחת לפחות רצה עכשיו ברשת.
  Future<bool> refreshStaleOnlineChecks(AppSettings s);

  /// `null` = חזרה מהשאלה: ההורדה לא מתחילה, ושום דבר לא נשמר.
  Future<SemanticSearchAnswer?> confirmSemanticSearch();
  Future<DownloadRollback> captureRollback();
  Future<void> sweepMirror();
  void stateChanged();
  void downloadSnapshotFailed(Object error);

  /// [kept]: רכיבים שירדו עד הסוף ונשארו בכונן.
  void downloadCancelled({
    Object? revertError,
    List<MirrorComponent> kept = const [],
  });
  void downloadEnded();

  /// התוכנית התנגשה בפעולה אחרת ([blocksComponent]) — לא ירד דבר.
  void downloadBlocked();

  /// אין מה להביא — לא נפתח מסך "לא ירד דבר". [rechecked]: הבדיקה רעננה עכשיו.
  void downloadFoundNothing({required bool rechecked});

  /// חריג שלא נתפס בזרימה — המסך עובר לכשל, ולא נשאר תקוע ב"מתכונן".
  /// [abandoned]: הזרימה בוטלה, והמסך שפתוח עכשיו שייך לבקשה אחרת.
  void downloadCrashed(
    Object error,
    StackTrace stackTrace, {
    bool abandoned = false,
  });
  void downloadFinished({
    required List<MirrorComponent> failed,
    required List<MirrorComponent> skipped,
  });
}

class MirrorDownloadFlow {
  MirrorDownloadFlow({
    required this.app,
    required this.library,
    required this.plugins,
    required this.host,
  });

  final AppMirrorModule app;
  final LibraryMirrorModule library;
  final PluginsMirrorModule plugins;
  final MirrorDownloadHost host;

  bool _isDownloading = false;
  bool _cancelRequested = false;
  bool _keepProgress = false;
  bool _isPreparing = false;
  bool _abandonRequested = false;
  int _abandonCount = 0;
  Future<void>? _run;
  Future<void>? _sweep;
  DownloadPlan? _plan;
  List<MirrorComponent> _components = const [];
  final Set<MirrorComponent> _running = {};
  final Set<MirrorComponent> _finished = {};

  bool get isDownloading => _isDownloading;

  /// התוכנית של ההורדה שרצה עכשיו, ו[activeComponents] — מה ממנה ירוץ.
  DownloadPlan? get activePlan => _isDownloading ? _plan : null;
  List<MirrorComponent> get activeComponents =>
      _isDownloading ? _components : const [];

  /// מה יורד ברגע זה — הספרייה והתוספים רצים יחד.
  Set<MirrorComponent> get runningComponents =>
      _isDownloading ? Set.unmodifiable(_running) : const {};

  /// מה מההורדה הזו הסתיים (גם בכשל) ולא ייכתב עוד.
  Set<MirrorComponent> get finishedComponents =>
      _isDownloading ? Set.unmodifiable(_finished) : const {};

  /// מה מההורדה הזו עוד עשוי לכתוב למראה — רץ, או ממתין לתורו.
  Set<MirrorComponent> get pendingComponents => _isDownloading
      ? {
          for (final c in _components)
            if (!_finished.contains(c)) c
        }
      : const {};
  bool get isCancelling => _cancelRequested;
  bool get isPreparing => _isPreparing;

  /// "ביטול" ב"מתכונן": הזרימה תחזור בלי להוריד דבר.
  bool get isAbandoned => _isPreparing && _abandonRequested;
  Future<void>? get pendingSweep => _sweep;

  /// [forceSemantic]: השורה "חיפוש חכם זמין" — מורידה בלי לשאול, במצב "לשאול".
  Future<void> downloadAll({bool forceSemantic = false}) async {
    if (_isPreparing) {
      // "ביטול" ואז "הורדה" לפני שהזרימה שבוטלה חזרה: מחכים לה ומתחילים מחדש.
      final abandoned = _run;
      if (!_abandonRequested || abandoned == null) return;
      final abandonCount = _abandonCount;
      await abandoned.then((_) {}, onError: (_) {});
      // "ביטול" נוסף בזמן ההמתנה מבטל גם את הבקשה הזו.
      if (_isPreparing || !host.isActive || abandonCount != _abandonCount) {
        return;
      }
    }
    _isPreparing = true;
    _abandonRequested = false;
    final run = _run = _downloadAll(forceSemantic: forceSemantic);
    try {
      await run;
    } catch (error, stackTrace) {
      if (host.isActive) {
        host.downloadCrashed(error, stackTrace, abandoned: _abandonRequested);
      }
    } finally {
      _isPreparing = false;
      _run = null;
    }
  }

  /// "ביטול" לפני שההורדה התחילה: הזרימה חוזרת אחרי הבדיקה ברשת, בלי
  /// לשאול ובלי להוריד.
  void abandonPreparing() {
    if (!_isPreparing || _isDownloading) return;
    _abandonRequested = true;
    _abandonCount++;
  }

  void requestCancel() {
    _cancelRequested = true;
    host.stateChanged();
  }

  Future<void> cancelAndWait({bool keepProgress = false}) async {
    if (_run case final run? when _isDownloading) {
      if (!_cancelRequested) _keepProgress = keepProgress;
      requestCancel();
      await run;
    }
  }

  Future<void> _downloadAll({required bool forceSemantic}) async {
    if (_sweep case final sweep?) {
      await sweep;
      if (!host.isActive || _abandonRequested) return;
    }
    final s = host.settings;
    if (!s.hasSyncSelection || host.isBlocked) return;

    final rechecked = await host.refreshStaleOnlineChecks(s);
    if (!host.isActive || _abandonRequested) return;

    final skipApp = DownloadPlan.shouldSkipApp(
      s,
      hasStaleFullPackage: app.hasStaleFullPackage,
      online: app.onlineProof,
    );
    DownloadPlan planWith({required bool semantic}) => DownloadPlan(
          skipApp: skipApp,
          includeSemanticSearch: semantic,
          skipLibrary: !(s.syncApp && !skipApp && library.hasBlockedLibrary) &&
              DownloadPlan.shouldSkipLibrary(
                s,
                includeSemanticSearch: semantic,
                personalUpdateMode: library.personalUpdateMode,
                online: library.libraryOnlineProof,
              ),
          skipPlugins: DownloadPlan.shouldSkipPlugins(
            s,
            catalog: plugins.catalogOnlineProof,
          ),
          skipStoreApp: DownloadPlan.shouldSkipStoreApp(
            s,
            storeApp: plugins.storeAppOnlineProof,
          ),
        );
    final offer = s.downloadsLibrary && library.shouldOfferSemanticDownload;
    var includeSemanticSearch = false;
    switch (s.semanticDownload) {
      case SemanticDownloadPreference.never:
        break;
      case SemanticDownloadPreference.always:
        includeSemanticSearch = offer;
      case SemanticDownloadPreference.ask when forceSemantic:
        includeSemanticSearch = offer;
      case SemanticDownloadPreference.ask:
        // שואלים רק כשיש הורדה אמיתית; בלעדיה "כן" היה מריץ ספרייה בשביל כלום.
        if (offer && _componentsOf(planWith(semantic: false), s).isNotEmpty) {
          final answer = await host.confirmSemanticSearch();
          if (answer == null) return;
          includeSemanticSearch = answer.download;
        }
    }
    if (!host.isActive || host.isBlocked || _abandonRequested) return;
    final plan = planWith(semantic: includeSemanticSearch);
    final components = _componentsOf(plan, s);
    if (components.isEmpty) {
      host.downloadFoundNothing(rechecked: rechecked);
      return;
    }
    if (components.any(host.blocksComponent)) {
      host.downloadBlocked();
      return;
    }

    _plan = plan;
    _components = components;
    _running.clear();
    _finished.clear();
    _isDownloading = true;
    _cancelRequested = false;
    _keepProgress = false;
    host.stateChanged();

    try {
      final DownloadRollback rollback;
      try {
        rollback = await host.captureRollback();
      } catch (error) {
        _isDownloading = false;
        _cancelRequested = false;
        host.stateChanged();
        host.downloadSnapshotFailed(error);
        return;
      }
      bool cancelled() => _cancelRequested;
      library.clearDownloadSizeProbe();
      // כשהספרייה ראשונה הגודל האמיתי מגיע מיד. לחיפוש החכם אין תכנון מוקדם.
      if (plan.runsLibrary(s) && plan.runsApp(s) && !includeSemanticSearch) {
        library.startDownloadSizeProbe();
      }

      // כונן מלא משותק: רכיב נוסף רק היה נכשל באותה כתיבה, ומה שהסתיים נשמר.
      final storageFullIn = <MirrorComponent>{};
      bool go() => !cancelled() && storageFullIn.isEmpty;
      final interrupted = <MirrorComponent>{};

      Future<void> run(
        MirrorComponent component,
        List<Future<void> Function()> steps,
        bool Function() full,
      ) async {
        if (!go()) return;
        _running.add(component);
        host.stateChanged();
        try {
          for (final (i, step) in steps.indexed) {
            if (i > 0 && !go()) break;
            await step();
            if (full()) storageFullIn.add(component);
          }
        } finally {
          _running.remove(component);
          // רכיב שחזר אחרי בקשת ביטול נחשב קטוע — גם אם הספיק להסתיים.
          (cancelled() ? interrupted : _finished).add(component);
          if (host.isActive) host.stateChanged();
        }
      }

      // הספרייה והתוספים בוחרים לפי המתקין שבכונן, ולכן התוכנה ראשונה.
      if (plan.runsApp(s)) {
        await run(
          MirrorComponent.app,
          [() => app.download(isCancelled: cancelled)],
          () => app.storageFull,
        );
      }
      // כל אחד במראה משלו ובשורשי שחזור משלו — אין סיבה שיחכו זה לזה.
      await Future.wait([
        if (plan.runsLibrary(s))
          run(
            MirrorComponent.library,
            [
              () => library.download(
                    includeSemanticSearch: includeSemanticSearch,
                    isCancelled: cancelled,
                  ),
            ],
            () => library.storageFull,
          ),
        if (plan.runsPlugins(s) || plan.runsStoreApp(s))
          run(
            MirrorComponent.plugins,
            [
              if (plan.runsPlugins(s))
                () => plugins.sync(isCancelled: cancelled),
              if (plan.runsStoreApp(s)) plugins.syncStoreApp,
            ],
            () => plugins.storageFull,
          ),
      ]);

      if (cancelled()) {
        if (_keepProgress) return;
        final failed = plan.failed(
          s,
          appFailed: app.downloadFailed,
          libraryFailed: library.downloadFailed,
          pluginsFailed: plugins.lastSyncFailed,
        );
        final kept = [
          for (final c in _components)
            if (_finished.contains(c) && !failed.contains(c)) c,
        ];
        Object? revertError;
        try {
          await rollback.rollback(interrupted);
        } catch (error) {
          revertError = error;
        }
        if (!host.isActive) return;
        _isDownloading = false;
        _cancelRequested = false;
        host.stateChanged();
        host.downloadCancelled(revertError: revertError, kept: kept);
        return;
      }
      if (!host.isActive) return;

      _isDownloading = false;
      host.stateChanged();
      host.downloadEnded();

      final failed = plan.failed(
        s,
        appFailed: app.downloadFailed,
        libraryFailed: library.downloadFailed,
        pluginsFailed: plugins.lastSyncFailed,
      );
      for (final full in storageFullIn) {
        if (!failed.contains(full)) failed.add(full);
      }
      if (failed.isEmpty && !library.downloadNeedsRetry && !host.mirrorInUse) {
        _sweep = _sweepMirror();
      }
      host.downloadFinished(failed: failed, skipped: plan.skipped);
    } finally {
      if (_isDownloading) {
        _isDownloading = false;
        _cancelRequested = false;
        if (host.isActive) host.stateChanged();
      }
    }
  }

  static List<MirrorComponent> _componentsOf(
          DownloadPlan plan, AppSettings s) =>
      [
        if (plan.runsApp(s)) MirrorComponent.app,
        if (plan.runsLibrary(s)) MirrorComponent.library,
        if (plan.runsPlugins(s) || plan.runsStoreApp(s))
          MirrorComponent.plugins,
      ];

  Future<void> _sweepMirror() async {
    try {
      await host.sweepMirror();
    } finally {
      _sweep = null;
      if (host.isActive) host.stateChanged();
    }
  }
}

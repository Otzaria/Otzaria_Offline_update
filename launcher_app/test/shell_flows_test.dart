import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/auto_install_flow.dart';
import 'package:launcher_app/src/controllers/download_plan.dart';
import 'package:launcher_app/src/controllers/launcher_update_flow.dart';
import 'package:launcher_app/src/controllers/mirror_download_flow.dart';
import 'package:launcher_app/src/settings/app_settings.dart';

final _checkedAt = DateTime.now();
final _proven =
    OnlineProof(checkedAt: _checkedAt, error: null, hasUpdate: false);
final _hasNew =
    OnlineProof(checkedAt: _checkedAt, error: null, hasUpdate: true);
const SemanticSearchAnswer _yes = (download: true, remember: false);
const SemanticSearchAnswer _no = (download: false, remember: false);

class _FakeApp implements AppMirrorModule, AutoInstallApp {
  _FakeApp(this.log);

  final List<String> log;

  @override
  bool hasStaleFullPackage = false;
  @override
  OnlineProof onlineProof = _hasNew;
  @override
  bool downloadFailed = false;
  @override
  bool storageFull = false;
  @override
  bool isInstalled = true;
  @override
  bool hasUpdateAvailable = true;

  Future<void> Function()? onDownload;
  Future<void> Function()? onInstall;
  bool? installedWithWizard;

  @override
  Future<void> download({required bool Function() isCancelled}) async {
    log.add('app');
    await onDownload?.call();
  }

  @override
  Future<void> install({required bool useWizard}) async {
    installedWithWizard = useWizard;
    log.add('install app');
    await onInstall?.call();
  }
}

class _FakeLibrary implements LibraryMirrorModule, AutoInstallLibrary {
  _FakeLibrary(this.log);

  final List<String> log;

  @override
  bool shouldOfferSemanticDownload = false;
  @override
  bool personalUpdateMode = false;
  @override
  OnlineProof libraryOnlineProof = _hasNew;
  @override
  bool downloadFailed = false;
  @override
  bool storageFull = false;
  @override
  bool downloadNeedsRetry = false;
  @override
  bool hasBlockedLibrary = false;
  @override
  bool isFreshInstall = false;
  @override
  bool hasUpdateAvailable = true;

  bool? includedSemanticSearch;
  Future<void> Function()? onDownload;
  Future<void> Function()? onUpdate;
  Future<void> Function()? onRecheck;

  @override
  Future<void> download({
    required bool includeSemanticSearch,
    required bool Function() isCancelled,
  }) async {
    includedSemanticSearch = includeSemanticSearch;
    log.add('library');
    await onDownload?.call();
  }

  var probes = 0;

  @override
  void startDownloadSizeProbe() => probes++;

  @override
  void clearDownloadSizeProbe() {}

  @override
  Future<void> update() async {
    log.add('update library');
    await onUpdate?.call();
  }

  @override
  Future<void> recheck() async {
    log.add('recheck library');
    await onRecheck?.call();
  }
}

class _FakePlugins implements PluginsMirrorModule {
  _FakePlugins(this.log);

  final List<String> log;
  void Function()? onSync;
  void Function()? onStoreApp;

  @override
  OnlineProof catalogOnlineProof = _hasNew;
  @override
  OnlineProof storeAppOnlineProof = _hasNew;
  @override
  bool lastSyncFailed = false;
  @override
  bool storageFull = false;

  @override
  Future<void> sync({required bool Function() isCancelled}) async {
    log.add('plugins');
    onSync?.call();
  }

  @override
  Future<void> syncStoreApp() async {
    log.add('store app');
    onStoreApp?.call();
  }
}

class _FakeRollback implements DownloadRollback {
  _FakeRollback(this.log);

  final List<String> log;
  Completer<void>? gate;
  MirrorComponent? reverted;

  @override
  Future<void> rollback(MirrorComponent? inProgress) async {
    reverted = inProgress;
    log.add('rollback');
    await gate?.future;
    if (error case final error?) throw error;
  }

  Object? error;
}

class _FakeDownloadHost implements MirrorDownloadHost {
  _FakeDownloadHost(this.log) : rollback = _FakeRollback(log);

  final List<String> log;
  final _FakeRollback rollback;
  MirrorDownloadFlow? flow;

  @override
  bool isActive = true;
  @override
  bool isBlocked = false;
  @override
  bool launcherDownloading = false;
  @override
  AppSettings settings = const AppSettings();

  Future<void> Function(AppSettings s)? onRefresh;
  Future<SemanticSearchAnswer?> Function()? onConfirmSemantic;
  Completer<void>? sweepGate;
  int sweeps = 0;
  List<MirrorComponent>? failed;
  List<MirrorComponent>? skipped;

  bool refreshed = true;

  @override
  Future<bool> refreshStaleOnlineChecks(AppSettings s) async {
    log.add('refresh');
    await onRefresh?.call(s);
    return refreshed;
  }

  @override
  Future<SemanticSearchAnswer?> confirmSemanticSearch() async {
    log.add('ask semantic');
    final answer = onConfirmSemantic;
    return answer == null ? _no : await answer();
  }

  @override
  Future<DownloadRollback> captureRollback() async {
    log.add('capture');
    if (captureError case final error?) throw error;
    return rollback;
  }

  Object? captureError;

  @override
  Future<void> sweepMirror() async {
    sweeps++;
    log.add('sweep');
    await sweepGate?.future;
  }

  @override
  void stateChanged() => log.add(
        'changed downloading=${flow?.isDownloading} '
        'cancelling=${flow?.isCancelling}',
      );

  @override
  void downloadSnapshotFailed(Object error) => log.add('snapshot failed');

  List<MirrorComponent>? kept;

  @override
  void downloadCancelled({
    Object? revertError,
    List<MirrorComponent> kept = const [],
  }) {
    this.kept = kept;
    log.add(revertError == null ? 'cancelled' : 'cancelled revert failed');
  }

  @override
  void downloadEnded() => log.add('ended');

  @override
  void downloadFoundNothing({required bool rechecked}) =>
      log.add(rechecked ? 'found nothing' : 'found nothing unchecked');

  Object? crashed;

  @override
  void downloadCrashed(
    Object error,
    StackTrace stackTrace, {
    bool abandoned = false,
  }) {
    log.add(abandoned ? 'crashed abandoned' : 'crashed');
    crashed = error;
  }

  @override
  void downloadFinished({
    required List<MirrorComponent> failed,
    required List<MirrorComponent> skipped,
  }) {
    log.add('finished');
    this.failed = failed;
    this.skipped = skipped;
  }
}

class _FakeLauncher implements LauncherUpdateTarget {
  _FakeLauncher(this.log);

  final List<String> log;

  @override
  bool isDownloading = false;
  @override
  bool isInstalling = false;
  @override
  bool hasUpdateReady = true;
  @override
  bool canInstall = true;
  @override
  String? downloadedVersion = '2.0.0';
  @override
  String? errorMessage;

  bool downloadResult = true;
  bool restarted = true;
  Completer<void>? checkGate;
  int checks = 0;

  @override
  Future<void> checkForUpdate() async {
    checks++;
    log.add('mirror check');
    await checkGate?.future;
  }

  @override
  Future<bool> download() async {
    log.add('launcher download');
    return downloadResult;
  }

  @override
  Future<bool> install() async {
    log.add('launcher install');
    return restarted;
  }
}

class _FakeLauncherHost implements LauncherUpdateHost {
  _FakeLauncherHost(this.log);

  final List<String> log;

  @override
  bool isActive = true;
  @override
  bool isReadOnly = false;
  @override
  bool wouldInterrupt = false;

  bool approve = true;
  void Function()? whileDialogOpen;

  @override
  bool blockedByReadOnly() => isReadOnly;

  int settles = 0;
  void Function()? onSettle;

  @override
  Future<void> settleBackgroundWork() async {
    settles++;
    onSettle?.call();
  }

  @override
  Future<bool> confirmInstall(String version) async {
    log.add('confirm $version');
    whileDialogOpen?.call();
    return approve;
  }

  @override
  void notify(LauncherUpdateNotice notice, {String? detail}) =>
      log.add(detail == null ? notice.name : '${notice.name} $detail');
}

void main() {
  late List<String> log;
  late _FakeApp app;
  late _FakeLibrary library;
  late _FakePlugins plugins;
  late _FakeDownloadHost host;
  late MirrorDownloadFlow flow;

  setUp(() {
    log = [];
    app = _FakeApp(log);
    library = _FakeLibrary(log);
    plugins = _FakePlugins(log);
    host = _FakeDownloadHost(log);
    flow = MirrorDownloadFlow(
      app: app,
      library: library,
      plugins: plugins,
      host: host,
    );
    host.flow = flow;
  });

  List<String> componentsRun() => [
        for (final entry in log)
          if (const ['app', 'library', 'plugins', 'store app'].contains(entry))
            entry,
      ];

  group('MirrorDownloadFlow', () {
    test(
        'an app download rechecks a library previously limited by its installer',
        () async {
      library.libraryOnlineProof = _proven;
      library.hasBlockedLibrary = true;
      await flow.downloadAll();
      expect(componentsRun(), containsAllInOrder(['app', 'library']));
    });
    test('cancelling plugins keeps the app and library that already finished',
        () async {
      plugins.onSync = flow.requestCancel;
      await flow.downloadAll();
      expect(host.rollback.reverted, MirrorComponent.plugins);
      expect(host.kept, [MirrorComponent.app, MirrorComponent.library]);
      plugins.onSync = null;
      await flow.downloadAll();
      expect(host.failed, isEmpty);
    });
    group('הכונן התמלא', () {
      void fullIn(_FakeLibrary l) {
        l.downloadFailed = true;
        l.storageFull = true;
      }

      test('בספרייה: לא מתחילים תוספים ותוכנת חנות, והספרייה נכשלת', () async {
        library.onDownload = () async => fullIn(library);
        await flow.downloadAll();
        expect(componentsRun(), ['app', 'library']);
        expect(host.failed, [MirrorComponent.library]);
        expect(log, isNot(contains('sweep')));
        expect(flow.isDownloading, isFalse);
      });

      test('באפליקציה: לא מתחילים ספרייה ותוספים', () async {
        app.onDownload = () async {
          app.downloadFailed = true;
          app.storageFull = true;
        };
        await flow.downloadAll();
        expect(componentsRun(), ['app']);
        expect(host.failed, [MirrorComponent.app]);
      });

      test('בתוספים: לא מתחילים את תוכנת החנות', () async {
        plugins.onSync = () {
          plugins.lastSyncFailed = true;
          plugins.storageFull = true;
        };
        await flow.downloadAll();
        expect(componentsRun(), ['app', 'library', 'plugins']);
        expect(host.failed, [MirrorComponent.plugins]);
      });

      test('תוכנת החנות שנכשלה בכתיבה מסמנת את התוספים ככושלים', () async {
        plugins.onStoreApp = () => plugins.storageFull = true;
        await flow.downloadAll();
        expect(host.failed, [MirrorComponent.plugins]);
      });

      test('כשל רגיל בספרייה לא עוצר את התוספים', () async {
        library.onDownload = () async => library.downloadFailed = true;
        await flow.downloadAll();
        expect(componentsRun(), ['app', 'library', 'plugins', 'store app']);
        expect(host.failed, [MirrorComponent.library]);
      });

      test('דגל ישן של רכיב שלא רץ בהורדה הזו אינו עוצר דבר', () async {
        library.libraryOnlineProof = _proven;
        library.storageFull = true;
        await flow.downloadAll();
        expect(componentsRun(), ['app', 'plugins', 'store app']);
        expect(host.failed, isEmpty);
      });

      test('ביטול שהתבקש יחד עם הכשל נשאר ביטול', () async {
        library.onDownload = () async {
          fullIn(library);
          flow.requestCancel();
        };
        await flow.downloadAll();
        expect(log, contains('cancelled'));
        expect(log, isNot(contains('finished')));
        expect(componentsRun(), ['app', 'library']);
      });
    });

    test('חריג באמצע — מדווח למארח, והזרימה משתחררת', () async {
      host.onRefresh = (_) async => throw StateError('boom');
      await flow.downloadAll();
      expect(log, ['refresh', 'crashed']);
      expect(host.crashed, isA<StateError>());
      expect(flow.isPreparing, isFalse);
      expect(flow.isDownloading, isFalse);
    });

    test('"ביטול" ב"מתכונן" — חוזרים אחרי הבדיקה ברשת בלי לשאול ולהוריד',
        () async {
      library.shouldOfferSemanticDownload = true;
      host.onRefresh = (_) async => flow.abandonPreparing();
      await flow.downloadAll();
      expect(log, ['refresh']);
      expect(flow.isPreparing, isFalse);

      // ההורדה הבאה אינה יורשת את הביטול.
      host.onRefresh = null;
      await flow.downloadAll();
      expect(log, contains('capture'));
    });

    test('runs every component in order and ends with one sweep', () async {
      await flow.downloadAll();

      expect(log, [
        'refresh',
        'changed downloading=true cancelling=false',
        'capture',
        'app',
        'library',
        'plugins',
        'store app',
        'changed downloading=false cancelling=false',
        'ended',
        'sweep',
        'finished',
      ]);
      expect(host.failed, isEmpty);
      expect(host.skipped, isEmpty);
      expect(flow.isDownloading, isFalse);
      expect(flow.isPreparing, isFalse);
      await pumpEventQueue();
      expect(flow.pendingSweep, isNull);
    });

    test('a component proven up to date does not run and is reported',
        () async {
      app.onlineProof = _proven;
      plugins.catalogOnlineProof = _proven;

      await flow.downloadAll();

      expect(componentsRun(), ['library', 'store app']);
      expect(host.skipped, [MirrorComponent.app, MirrorComponent.plugins]);
    });

    test('the store app runs on its own check even when plugins skip',
        () async {
      plugins.catalogOnlineProof = _proven;
      plugins.storeAppOnlineProof = _hasNew;
      await flow.downloadAll();
      expect(componentsRun(), contains('store app'));
      expect(componentsRun(), isNot(contains('plugins')));

      log.clear();
      plugins.catalogOnlineProof = _hasNew;
      plugins.storeAppOnlineProof = _proven;
      await flow.downloadAll();
      expect(componentsRun(), contains('plugins'));
      expect(componentsRun(), isNot(contains('store app')));
    });

    test('stale online checks are refreshed before the skips are decided',
        () async {
      app.onlineProof = _proven;
      library.libraryOnlineProof = _proven;
      host.onRefresh = (_) async {
        app.onlineProof = _hasNew;
        library.libraryOnlineProof = _hasNew;
      };

      await flow.downloadAll();

      expect(componentsRun(), containsAllInOrder(['app', 'library']));
      expect(host.skipped, isEmpty);
    });

    test('a stale full package keeps the app module running', () async {
      app.onlineProof = _proven;
      app.hasStaleFullPackage = true;
      await flow.downloadAll();
      expect(componentsRun(), contains('app'));
    });

    test('a declined smart search still skips an up-to-date library', () async {
      library.shouldOfferSemanticDownload = true;
      library.libraryOnlineProof = _proven;
      host.onConfirmSemantic = () async => _no;

      await flow.downloadAll();

      expect(log.where((e) => e == 'ask semantic'), hasLength(1));
      expect(componentsRun(), isNot(contains('library')));
      expect(host.skipped, [MirrorComponent.library]);
    });

    test('an accepted smart search runs the library with it', () async {
      library.shouldOfferSemanticDownload = true;
      library.libraryOnlineProof = _proven;
      host.onConfirmSemantic = () async => _yes;

      await flow.downloadAll();

      expect(componentsRun(), contains('library'));
      expect(library.includedSemanticSearch, isTrue);
    });

    // "חזרה" במסך השאלה: ההורדה לא מתחילה, ושום דבר לא נלכד או נוקה.
    test('backing out of the smart search question downloads nothing',
        () async {
      library.shouldOfferSemanticDownload = true;
      host.onConfirmSemantic = () async => null;

      await flow.downloadAll();

      expect(log, ['refresh', 'ask semantic']);
      expect(flow.isDownloading, isFalse);
      expect(flow.isPreparing, isFalse);
      expect(host.failed, isNull);
    });

    test('the active plan and the current component follow the run', () async {
      plugins.catalogOnlineProof = _proven;
      plugins.storeAppOnlineProof = _proven;
      MirrorComponent? during;
      List<MirrorComponent>? components;
      app.onDownload = () async {
        during = flow.currentComponent;
        components = flow.activeComponents;
        expect(flow.activePlan, isNotNull);
      };

      expect(flow.activePlan, isNull);
      await flow.downloadAll();

      expect(during, MirrorComponent.app);
      expect(components, [MirrorComponent.app, MirrorComponent.library]);
      expect(flow.currentComponent, isNull);
      expect(flow.activeComponents, isEmpty);
      expect(flow.activePlan, isNull);
    });

    test('smart search is not offered when the library is not selected',
        () async {
      library.shouldOfferSemanticDownload = true;
      host.settings = const AppSettings(syncLibrary: false);
      await flow.downloadAll();
      expect(log, isNot(contains('ask semantic')));
      expect(componentsRun(), isNot(contains('library')));
    });

    test('the library size is probed while the app downloads', () async {
      app.onDownload = () async => expect(library.probes, 1);
      await flow.downloadAll();
      expect(library.probes, 1);
    });

    test('no size probe without the library, first, or with smart search',
        () async {
      host.settings = const AppSettings(syncLibrary: false);
      await flow.downloadAll();
      host.settings = const AppSettings(syncApp: false);
      await flow.downloadAll();
      host.settings = const AppSettings();
      library.shouldOfferSemanticDownload = true;
      host.onConfirmSemantic = () async => _yes;
      await flow.downloadAll();

      expect(componentsRun().where((c) => c == 'library'), hasLength(2));
      expect(library.probes, 0);
    });

    test('personal update mode never skips the library', () async {
      library.libraryOnlineProof = _proven;
      library.personalUpdateMode = true;
      await flow.downloadAll();
      expect(componentsRun(), contains('library'));
    });

    test('unselected components neither run nor count as skipped', () async {
      host.settings = const AppSettings(syncApp: false, syncPlugins: false);
      app.onlineProof = _proven;
      plugins.catalogOnlineProof = _proven;
      await flow.downloadAll();
      expect(componentsRun(), ['library']);
      expect(host.skipped, isEmpty);
    });

    test('nothing starts without a selection or while blocked', () async {
      host.settings = const AppSettings(
        syncApp: false,
        syncLibrary: false,
        syncPlugins: false,
      );
      await flow.downloadAll();
      expect(log, isEmpty);

      host.settings = const AppSettings();
      host.isBlocked = true;
      await flow.downloadAll();
      expect(log, isEmpty);
    });

    test('blocked again after the smart-search dialog: nothing downloads',
        () async {
      library.shouldOfferSemanticDownload = true;
      host.onConfirmSemantic = () async {
        host.isBlocked = true;
        return _yes;
      };

      await flow.downloadAll();

      expect(log, ['refresh', 'ask semantic']);
      expect(flow.isDownloading, isFalse);
    });

    test('an unmounted shell after the refresh stops before any download',
        () async {
      host.onRefresh = (_) async => host.isActive = false;
      await flow.downloadAll();
      expect(log, ['refresh']);
    });

    test('cancel stops before the next component and rolls back', () async {
      app.onDownload = () async {
        expect(flow.isDownloading, isTrue);
        flow.requestCancel();
      };

      await flow.downloadAll();

      expect(componentsRun(), ['app']);
      expect(log.sublist(log.indexOf('app')), [
        'app',
        'changed downloading=true cancelling=true',
        'rollback',
        'changed downloading=false cancelling=false',
        'cancelled',
      ]);
      expect(host.sweeps, 0);
      expect(flow.pendingSweep, isNull);
      expect(log, isNot(contains('finished')));
    });

    test('cancel during the first component reverts it and keeps nothing',
        () async {
      app.onDownload = () async => flow.requestCancel();

      await flow.downloadAll();

      expect(host.rollback.reverted, MirrorComponent.app);
      expect(host.kept, isEmpty);
    });

    test('cancel during the second component keeps the first', () async {
      library.onDownload = () async => flow.requestCancel();

      await flow.downloadAll();

      expect(componentsRun(), ['app', 'library']);
      expect(host.rollback.reverted, MirrorComponent.library);
      expect(host.kept, [MirrorComponent.app]);
      expect(log.last, 'cancelled');
    });

    test('a component that failed before the cancel is not reported as kept',
        () async {
      app.onDownload = () async => app.downloadFailed = true;
      library.onDownload = () async => flow.requestCancel();

      await flow.downloadAll();

      expect(host.rollback.reverted, MirrorComponent.library);
      expect(host.kept, isEmpty);
    });

    test('a failed snapshot downloads nothing and is reported', () async {
      host.captureError = const FileSystemException('locked');

      await flow.downloadAll();

      expect(componentsRun(), isEmpty);
      expect(log.sublist(log.indexOf('capture')), [
        'capture',
        'changed downloading=false cancelling=false',
        'snapshot failed',
      ]);
      expect(flow.isDownloading, isFalse);
      expect(host.sweeps, 0);
    });

    test('a failed rollback after cancel is reported as such', () async {
      host.rollback.error = const FileSystemException('locked');
      app.onDownload = () async => flow.requestCancel();

      await flow.downloadAll();

      expect(log.last, 'cancelled revert failed');
      expect(flow.isDownloading, isFalse);
      expect(flow.isCancelling, isFalse);
    });

    test('a component that throws still releases the download state', () async {
      app.onDownload = () async => throw StateError('boom');

      // החריג מגיע למארח (מסך כשל), לא כחריג שאיש אינו מחכה לו.
      await flow.downloadAll();

      expect(flow.isDownloading, isFalse);
      expect(log.sublist(log.length - 2), [
        'changed downloading=false cancelling=false',
        'crashed',
      ]);
      expect(host.crashed, isA<StateError>());
      app.onDownload = null;
      await flow.downloadAll();
      expect(componentsRun().where((c) => c == 'app'), hasLength(2));
    });

    test('an unmounted shell after the rollback leaves no notification',
        () async {
      app.onDownload = () async => flow.requestCancel();
      host.rollback.gate = Completer<void>();
      final run = flow.downloadAll();
      await pumpEventQueue();
      host.isActive = false;
      host.rollback.gate!.complete();
      await run;
      expect(log, isNot(contains('cancelled')));
    });

    test('closing the window cancels and waits for the rollback', () async {
      final appGate = Completer<void>();
      app.onDownload = () => appGate.future;
      host.rollback.gate = Completer<void>();
      final run = flow.downloadAll();
      await pumpEventQueue();
      expect(flow.isDownloading, isTrue);

      var closed = false;
      final close = flow.cancelAndWait().then((_) => closed = true);
      expect(flow.isCancelling, isTrue);
      appGate.complete();
      await pumpEventQueue();
      expect(log, contains('rollback'));
      expect(closed, isFalse);

      host.rollback.gate!.complete();
      await close;
      await run;
      expect(closed, isTrue);
      expect(componentsRun(), ['app']);
    });

    test('closing the window with no download running does not cancel',
        () async {
      await flow.cancelAndWait();
      expect(flow.isCancelling, isFalse);
      expect(log, isEmpty);
    });

    group('smart search preference', () {
      setUp(() {
        app.onlineProof = _proven;
        library.libraryOnlineProof = _proven;
        plugins.catalogOnlineProof = _proven;
        plugins.storeAppOnlineProof = _proven;
        library.shouldOfferSemanticDownload = true;
      });

      AppSettings mode(SemanticDownloadPreference p) =>
          AppSettings(semanticDownload: p);

      test('"never": no question, no smart search, even unchecked', () async {
        host.settings = mode(SemanticDownloadPreference.never);
        app.onlineProof = _hasNew;
        await flow.downloadAll(forceSemantic: true);
        expect(log, isNot(contains('ask semantic')));
        expect(componentsRun(), ['app']);
      });

      test('"always": downloads it without asking, only when not proven',
          () async {
        host.settings = mode(SemanticDownloadPreference.always);
        await flow.downloadAll();
        expect(log, isNot(contains('ask semantic')));
        expect(componentsRun(), ['library']);
        expect(library.includedSemanticSearch, isTrue);

        log.clear();
        library.shouldOfferSemanticDownload = false;
        await flow.downloadAll();
        expect(componentsRun(), isEmpty);
        expect(log, contains('found nothing'));
      });

      test('"ask" + force: downloads it without asking', () async {
        await flow.downloadAll(forceSemantic: true);
        expect(log, isNot(contains('ask semantic')));
        expect(library.includedSemanticSearch, isTrue);
      });

      test('"ask" without force: asks only next to a real download', () async {
        await flow.downloadAll();
        expect(log, isNot(contains('ask semantic')));
        expect(log, contains('found nothing'));

        log.clear();
        app.onlineProof = _hasNew;
        host.onConfirmSemantic = () async => _yes;
        await flow.downloadAll();
        expect(log.where((e) => e == 'ask semantic'), hasLength(1));
        expect(componentsRun(), ['app', 'library']);
        expect(library.includedSemanticSearch, isTrue);
      });

      test('the decision follows the refresh: nothing left means no run',
          () async {
        host.onRefresh =
            (_) async => library.shouldOfferSemanticDownload = false;
        await flow.downloadAll(forceSemantic: true);
        expect(componentsRun(), isEmpty);
        expect(log, ['refresh', 'found nothing']);
        expect(flow.isDownloading, isFalse);
        expect(host.sweeps, 0);
      });

      test('re-entry after "cancel" keeps the force flag', () async {
        final refreshGate = Completer<void>();
        host.onRefresh = (_) => refreshGate.future;
        final abandoned = flow.downloadAll();
        flow.abandonPreparing();

        final again = flow.downloadAll(forceSemantic: true);
        host.onRefresh = null;
        refreshGate.complete();
        await abandoned;
        await again;
        expect(log, isNot(contains('ask semantic')));
        expect(library.includedSemanticSearch, isTrue);
      });
    });

    test('a refresh that finds nothing new opens no task and reports it',
        () async {
      host.onRefresh = (_) async {
        app.onlineProof = _proven;
        library.libraryOnlineProof = _proven;
        plugins.catalogOnlineProof = _proven;
        plugins.storeAppOnlineProof = _proven;
      };
      await flow.downloadAll();
      expect(log, ['refresh', 'found nothing']);
      expect(host.skipped, isNull);
      expect(flow.isPreparing, isFalse);

      // בלי רענון ברשת אין "בדקתי שוב".
      log.clear();
      host.refreshed = false;
      await flow.downloadAll();
      expect(log, ['refresh', 'found nothing unchecked']);
    });

    test('a failed component is reported and the mirror is not swept',
        () async {
      plugins.lastSyncFailed = true;
      await flow.downloadAll();
      expect(host.failed, [MirrorComponent.plugins]);
      expect(host.sweeps, 0);
    });

    test('a failure of a skipped component is not reported', () async {
      app.onlineProof = _proven;
      app.downloadFailed = true;
      await flow.downloadAll();
      expect(host.failed, isEmpty);
      expect(host.skipped, [MirrorComponent.app]);
      expect(host.sweeps, 1);
    });

    test('no sweep while the library still needs a retry', () async {
      library.downloadNeedsRetry = true;
      await flow.downloadAll();
      expect(host.failed, isEmpty);
      expect(host.sweeps, 0);
    });

    test('no sweep while a launcher download runs', () async {
      host.launcherDownloading = true;
      await flow.downloadAll();
      expect(host.sweeps, 0);
    });

    test('the next download waits for the sweep before it starts', () async {
      host.sweepGate = Completer<void>();
      await flow.downloadAll();
      expect(flow.pendingSweep, isNotNull);

      log.clear();
      final next = flow.downloadAll();
      await pumpEventQueue();
      expect(log, isEmpty);

      host.sweepGate!.complete();
      host.sweepGate = null;
      await next;
      expect(log.first, 'refresh');
    });

    test('a second press while preparing is ignored', () async {
      final refreshGate = Completer<void>();
      host.onRefresh = (_) => refreshGate.future;
      final first = flow.downloadAll();
      expect(flow.isPreparing, isTrue);

      await flow.downloadAll();
      expect(log.where((e) => e == 'refresh'), hasLength(1));

      refreshGate.complete();
      await first;
      expect(flow.isPreparing, isFalse);
      expect(componentsRun(), hasLength(4));
    });

    test('"ביטול" בזמן הניקוי הקודם — הזרימה עוצרת לפני הבדיקה ברשת', () async {
      host.sweepGate = Completer<void>();
      await flow.downloadAll();
      log.clear();

      final next = flow.downloadAll();
      flow.abandonPreparing();
      host.sweepGate!.complete();
      host.sweepGate = null;
      await next;
      expect(log, isEmpty);
    });

    test('"הורדה" מיד אחרי "ביטול" — מחכה לזרימה שבוטלה ומתחילה מחדש',
        () async {
      final refreshGate = Completer<void>();
      host.onRefresh = (_) => refreshGate.future;
      final abandoned = flow.downloadAll();
      flow.abandonPreparing();

      final again = flow.downloadAll();
      host.onRefresh = null;
      refreshGate.complete();
      await abandoned;
      await again;
      expect(log.where((e) => e == 'refresh'), hasLength(2));
      expect(componentsRun(), hasLength(4));
    });

    test('"ביטול", "הורדה" ו"ביטול" שוב לפני שהראשונה חזרה — נשאר מבוטל',
        () async {
      final refreshGate = Completer<void>();
      host.onRefresh = (_) => refreshGate.future;
      final abandoned = flow.downloadAll();
      flow.abandonPreparing();
      final again = flow.downloadAll();
      flow.abandonPreparing();

      host.onRefresh = null;
      refreshGate.complete();
      await abandoned;
      await again;
      expect(log, ['refresh']);
      expect(flow.isPreparing, isFalse);

      // הביטול אינו נשאר תלוי: ההורדה הבאה רצה.
      await flow.downloadAll();
      expect(componentsRun(), hasLength(4));
    });

    test('חריג בזרימה שבוטלה — מדווח כמבוטל, לא ככשל של הבקשה החדשה', () async {
      final refreshGate = Completer<void>();
      host.onRefresh = (_) async {
        await refreshGate.future;
        throw StateError('boom');
      };
      final abandoned = flow.downloadAll();
      flow.abandonPreparing();
      final again = flow.downloadAll();

      refreshGate.complete();
      await abandoned;
      expect(log, ['refresh', 'crashed abandoned']);
      host.onRefresh = null;
      await again;
      expect(componentsRun(), hasLength(4));
    });
  });

  group('AutoInstallFlow', () {
    late List<bool> otzariaOpen;
    late int processChecks;
    late bool downloading;
    late bool exitPending;
    late bool active;

    AutoInstallFlow autoInstall() => AutoInstallFlow(
          library: library,
          app: app,
          isOtzariaRunning: () async {
            processChecks++;
            log.add('process check');
            return otzariaOpen.isEmpty ? false : otzariaOpen.removeAt(0);
          },
          isDownloading: () => downloading,
          exitPending: () => exitPending,
          isActive: () => active,
        );

    setUp(() {
      otzariaOpen = [];
      processChecks = 0;
      downloading = false;
      exitPending = false;
      active = true;
    });

    test('the app is installed first and the library rechecked against it',
        () async {
      final skipped = await autoInstall().run(enabled: true);

      expect(skipped, isFalse);
      expect(log, [
        'process check',
        'install app',
        'recheck library',
        'process check',
        'update library',
      ]);
      expect(app.installedWithWizard, isFalse);
    });

    test('disabled: nothing is checked or installed', () async {
      expect(await autoInstall().run(enabled: false), isFalse);
      expect(log, isEmpty);
    });

    test('Otzaria open skips both and is reported', () async {
      otzariaOpen = [true, true];
      expect(await autoInstall().run(enabled: true), isTrue);
      expect(log, ['process check', 'process check']);
    });

    test('each path asks for a fresh process state', () async {
      otzariaOpen = [false, true];
      expect(await autoInstall().run(enabled: true), isTrue);
      expect(log, [
        'process check',
        'install app',
        'recheck library',
        'process check',
      ]);
      expect(processChecks, 2);
    });

    test('a fresh install does not get its database auto-updated', () async {
      library.isFreshInstall = true;
      await autoInstall().run(enabled: true);
      expect(log, isNot(contains('update library')));
      expect(log, contains('install app'));
    });

    test('the app is installed only where it is already installed', () async {
      app.isInstalled = false;
      await autoInstall().run(enabled: true);
      expect(log, isNot(contains('install app')));
      expect(log, contains('update library'));
    });

    test('nothing without an available update', () async {
      library.hasUpdateAvailable = false;
      app.hasUpdateAvailable = false;
      await autoInstall().run(enabled: true);
      expect(log, isEmpty);
    });

    test('a running download holds the library update only', () async {
      downloading = true;
      await autoInstall().run(enabled: true);
      expect(log, ['process check', 'install app']);
    });

    test('nothing starts while the exe is replaced or UAC is awaited',
        () async {
      exitPending = true;
      expect(await autoInstall().run(enabled: true), isFalse);
      expect(log, ['process check', 'process check']);
    });

    test('an unmounted shell after the app install stops there', () async {
      app.onInstall = () async => active = false;
      expect(await autoInstall().run(enabled: true), isFalse);
      expect(log, ['process check', 'install app']);
    });

    test('a library that needed the newer app is updated after the recheck',
        () async {
      library.hasUpdateAvailable = false;
      library.onRecheck = () async => library.hasUpdateAvailable = true;
      await autoInstall().run(enabled: true);
      expect(log, [
        'process check',
        'install app',
        'recheck library',
        'process check',
        'update library',
      ]);
    });
  });

  group('LauncherUpdateFlow', () {
    late _FakeLauncher launcher;
    late _FakeLauncherHost launcherHost;
    late LauncherUpdateFlow launcherFlow;

    setUp(() {
      launcher = _FakeLauncher(log);
      launcherHost = _FakeLauncherHost(log);
      launcherFlow = LauncherUpdateFlow(
        launcher: launcher,
        downloads: flow,
        host: launcherHost,
      );
    });

    test('install asks, announces and replaces the exe', () async {
      await launcherFlow.install();
      expect(log, ['confirm 2.0.0', 'installing', 'launcher install']);
    });

    test('install is refused before the dialog during a long task', () async {
      launcherHost.wouldInterrupt = true;
      await launcherFlow.install();
      expect(log, ['busy']);
    });

    test('background work that stops in order does not refuse the install',
        () async {
      launcherHost
        ..wouldInterrupt = true
        ..onSettle = () => launcherHost.wouldInterrupt = false;
      await launcherFlow.install();
      expect(log, ['confirm 2.0.0', 'installing', 'launcher install']);
      expect(launcherHost.settles, 2);
    });

    test('background work started during the dialog is stopped again',
        () async {
      launcherHost
        ..whileDialogOpen = (() => launcherHost.wouldInterrupt = true)
        ..onSettle = () => launcherHost.wouldInterrupt = false;
      await launcherFlow.install();
      expect(log, ['confirm 2.0.0', 'installing', 'launcher install']);
    });

    test('install checks again after the confirmation dialog', () async {
      launcherHost.whileDialogOpen = () => launcherHost.wouldInterrupt = true;
      await launcherFlow.install();
      expect(log, ['confirm 2.0.0', 'busy']);
    });

    test('install does nothing when declined, unmounted or read-only',
        () async {
      launcherHost.approve = false;
      await launcherFlow.install();
      expect(log, ['confirm 2.0.0']);

      log.clear();
      launcherHost
        ..approve = true
        ..whileDialogOpen = () => launcherHost.isActive = false;
      await launcherFlow.install();
      expect(log, ['confirm 2.0.0']);

      log.clear();
      launcherHost
        ..isActive = true
        ..whileDialogOpen = null
        ..isReadOnly = true;
      await launcherFlow.install();
      expect(log, isEmpty);
    });

    test('install needs a downloaded version it can install', () async {
      launcher.downloadedVersion = null;
      await launcherFlow.install();
      launcher
        ..downloadedVersion = '2.0.0'
        ..canInstall = false;
      await launcherFlow.install();
      expect(log, isEmpty);
    });

    test('install that did not restart reports the error or a restart',
        () async {
      launcher
        ..restarted = false
        ..errorMessage = 'denied';
      await launcherFlow.install();
      expect(log.last, 'installFailed denied');

      log.clear();
      launcher.errorMessage = null;
      await launcherFlow.install();
      expect(log.last, 'manualRestart');
    });

    test('download announces the version and offers the install', () async {
      await launcherFlow.download();
      expect(log, [
        'launcher download',
        'downloaded 2.0.0',
        'confirm 2.0.0',
        'installing',
        'launcher install',
      ]);
    });

    test('a failed or not-ready download offers nothing', () async {
      launcher.downloadResult = false;
      await launcherFlow.download();
      expect(log, ['launcher download']);

      log.clear();
      launcher
        ..downloadResult = true
        ..hasUpdateReady = false;
      await launcherFlow.download();
      expect(log, ['launcher download']);
    });

    test('download is refused on a read-only drive', () async {
      launcherHost.isReadOnly = true;
      await launcherFlow.download();
      expect(log, isEmpty);
    });

    test('download waits for the mirror sweep first', () async {
      host.sweepGate = Completer<void>();
      await flow.downloadAll();
      log.clear();

      final download = launcherFlow.download();
      await pumpEventQueue();
      expect(log, isEmpty);

      host.sweepGate!.complete();
      await download;
      expect(log.first, 'launcher download');
    });

    test('download waits for a running mirror check first', () async {
      launcher.checkGate = Completer<void>();
      unawaited(launcherFlow.checkMirror());
      final download = launcherFlow.download();
      await pumpEventQueue();
      expect(log, ['mirror check']);

      launcher.checkGate!.complete();
      await download;
      expect(log[1], 'launcher download');
    });

    test('download does not start while the mirror download prepares',
        () async {
      final refreshGate = Completer<void>();
      host.onRefresh = (_) => refreshGate.future;
      final mirror = flow.downloadAll();

      await launcherFlow.download();
      expect(log, isNot(contains('launcher download')));

      refreshGate.complete();
      await mirror;
    });

    test('download does not start while another launcher download runs',
        () async {
      launcher.isDownloading = true;
      await launcherFlow.download();
      expect(log, isEmpty);
    });

    test('the mirror check is shared, and skipped when it cannot apply',
        () async {
      launcher.checkGate = Completer<void>();
      final first = launcherFlow.checkMirror();
      final second = launcherFlow.checkMirror();
      expect(launcher.checks, 1);
      expect(launcherFlow.pendingMirrorCheck, isNotNull);
      launcher.checkGate!.complete();
      await Future.wait([first, second]);
      expect(launcherFlow.pendingMirrorCheck, isNull);

      launcher.checkGate = null;
      await launcherFlow.checkMirror();
      expect(launcher.checks, 2);

      launcherHost.isReadOnly = true;
      await launcherFlow.checkMirror();
      launcherHost.isReadOnly = false;
      launcher.isDownloading = true;
      await launcherFlow.checkMirror();
      launcher
        ..isDownloading = false
        ..isInstalling = true;
      await launcherFlow.checkMirror();
      expect(launcher.checks, 2);
    });
  });
}

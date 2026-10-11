import '../settings/app_settings.dart';
import 'download_plan.dart';

abstract interface class AppMirrorModule {
  bool get hasStaleFullPackage;
  OnlineProof get onlineProof;
  Future<void> download({required bool Function() isCancelled});
  bool get downloadFailed;
}

abstract interface class LibraryMirrorModule {
  bool get shouldOfferSemanticDownload;
  bool get personalUpdateMode;
  OnlineProof get libraryOnlineProof;
  Future<void> download({
    required bool includeSemanticSearch,
    required bool Function() isCancelled,
  });
  bool get downloadFailed;
  bool get downloadNeedsRetry;
}

abstract interface class PluginsMirrorModule {
  OnlineProof get catalogOnlineProof;
  OnlineProof get storeAppOnlineProof;
  Future<void> sync({required bool Function() isCancelled});
  Future<void> syncStoreApp();
  bool get lastSyncFailed;
}

abstract interface class DownloadRollback {
  Future<void> rollback();
}

abstract interface class MirrorDownloadHost {
  bool get isActive;
  bool get isBlocked;
  bool get launcherDownloading;
  AppSettings get settings;
  Future<void> refreshStaleOnlineChecks(AppSettings s);
  Future<bool> confirmSemanticSearch();
  Future<DownloadRollback> captureRollback();
  Future<void> sweepMirror();
  void stateChanged();
  void downloadCancelled();
  void downloadEnded();
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
  bool _isPreparing = false;
  Future<void>? _run;
  Future<void>? _sweep;

  bool get isDownloading => _isDownloading;
  bool get isCancelling => _cancelRequested;
  bool get isPreparing => _isPreparing;
  Future<void>? get pendingSweep => _sweep;

  Future<void> downloadAll() async {
    if (_isPreparing) return;
    _isPreparing = true;
    final run = _run = _downloadAll();
    try {
      await run;
    } finally {
      _isPreparing = false;
      _run = null;
    }
  }

  void requestCancel() {
    _cancelRequested = true;
    host.stateChanged();
  }

  Future<void> cancelAndWait() async {
    if (_run case final run? when _isDownloading) {
      requestCancel();
      await run;
    }
  }

  Future<void> _downloadAll() async {
    if (_sweep case final sweep?) {
      await sweep;
      if (!host.isActive) return;
    }
    final s = host.settings;
    if (!s.hasSyncSelection || host.isBlocked) return;

    await host.refreshStaleOnlineChecks(s);
    if (!host.isActive) return;

    final skipApp = DownloadPlan.shouldSkipApp(
      s,
      hasStaleFullPackage: app.hasStaleFullPackage,
      online: app.onlineProof,
    );
    final includeSemanticSearch = s.downloadsLibrary &&
        library.shouldOfferSemanticDownload &&
        await host.confirmSemanticSearch();
    if (!host.isActive || host.isBlocked) return;
    final plan = DownloadPlan(
      skipApp: skipApp,
      includeSemanticSearch: includeSemanticSearch,
      skipLibrary: DownloadPlan.shouldSkipLibrary(
        s,
        includeSemanticSearch: includeSemanticSearch,
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

    _isDownloading = true;
    _cancelRequested = false;
    host.stateChanged();

    final rollback = await host.captureRollback();
    bool cancelled() => _cancelRequested;

    if (plan.runsApp(s)) await app.download(isCancelled: cancelled);
    if (!cancelled() && plan.runsLibrary(s)) {
      await library.download(
        includeSemanticSearch: includeSemanticSearch,
        isCancelled: cancelled,
      );
    }
    if (!cancelled() && plan.runsPlugins(s)) {
      await plugins.sync(isCancelled: cancelled);
    }
    if (!cancelled() && plan.runsStoreApp(s)) {
      await plugins.syncStoreApp();
    }

    if (cancelled()) {
      await rollback.rollback();
      if (!host.isActive) return;
      _isDownloading = false;
      _cancelRequested = false;
      host.stateChanged();
      host.downloadCancelled();
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
    if (failed.isEmpty &&
        !library.downloadNeedsRetry &&
        !host.launcherDownloading) {
      _sweep = _sweepMirror();
    }
    host.downloadFinished(failed: failed, skipped: plan.skipped);
  }

  Future<void> _sweepMirror() async {
    try {
      await host.sweepMirror();
    } finally {
      _sweep = null;
    }
  }
}

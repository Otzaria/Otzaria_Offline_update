import 'mirror_download_flow.dart';

abstract interface class LauncherUpdateTarget {
  bool get isDownloading;
  bool get isInstalling;
  bool get hasUpdateReady;
  bool get canInstall;
  String? get downloadedVersion;
  String? get errorMessage;
  Future<void> checkForUpdate();
  Future<bool> download();
  Future<bool> install();
}

enum LauncherUpdateNotice {
  downloaded,
  busy,
  installing,
  installFailed,
  manualRestart
}

abstract interface class LauncherUpdateHost {
  bool get isActive;
  bool get isReadOnly;
  bool blockedByReadOnly();
  bool get wouldInterrupt;

  /// עוצר בסדר עבודת רקע שאינה מצדיקה סירוב (משוב החיפוש), לפני [wouldInterrupt].
  Future<void> settleBackgroundWork();
  Future<bool> confirmInstall(String version);
  void notify(LauncherUpdateNotice notice, {String? detail});
}

class LauncherUpdateFlow {
  LauncherUpdateFlow({
    required this.launcher,
    required this.downloads,
    required this.host,
  });

  final LauncherUpdateTarget launcher;
  final MirrorDownloadFlow downloads;
  final LauncherUpdateHost host;

  Future<void>? _mirrorCheck;

  Future<void>? get pendingMirrorCheck => _mirrorCheck;

  Future<void> checkMirror() {
    if (host.isReadOnly || launcher.isDownloading || launcher.isInstalling) {
      return Future.value();
    }
    return _mirrorCheck ??=
        launcher.checkForUpdate().whenComplete(() => _mirrorCheck = null);
  }

  Future<void> download() async {
    if (host.blockedByReadOnly()) return;
    // ניקוי עלול להתחיל בזמן ההמתנה לבדיקה; בין הבדיקה האחרונה להורדה אין await.
    for (Future<void>? wait;
        (wait = downloads.pendingSweep ?? _mirrorCheck) != null;) {
      await wait;
    }
    // מראה נפרדת ומחוץ לשחזור; הניקוי מדולג כל עוד היא יורדת (`mirrorInUse`).
    if (!host.isActive || launcher.isDownloading) return;

    final downloaded = await launcher.download();
    if (!downloaded || !host.isActive || !launcher.hasUpdateReady) return;

    host.notify(
      LauncherUpdateNotice.downloaded,
      detail: '${launcher.downloadedVersion}',
    );
    await install();
  }

  Future<void> install() async {
    if (host.blockedByReadOnly()) return;
    if (!host.isActive) return;
    await host.settleBackgroundWork();
    if (!host.isActive) return;
    if (host.wouldInterrupt) {
      host.notify(LauncherUpdateNotice.busy);
      return;
    }
    final version = launcher.downloadedVersion;
    if (version == null || !launcher.canInstall) return;

    final approved = await host.confirmInstall(version);
    if (!approved || !host.isActive) return;
    await host.settleBackgroundWork();
    if (!host.isActive) return;
    if (host.wouldInterrupt) {
      host.notify(LauncherUpdateNotice.busy);
      return;
    }

    host.notify(LauncherUpdateNotice.installing);
    final restarted = await launcher.install();
    if (restarted || !host.isActive) return;

    final error = launcher.errorMessage;
    if (error != null) {
      host.notify(LauncherUpdateNotice.installFailed, detail: error);
      return;
    }
    host.notify(LauncherUpdateNotice.manualRestart);
  }
}

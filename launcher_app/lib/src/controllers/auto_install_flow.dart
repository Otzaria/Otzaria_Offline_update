abstract interface class AutoInstallLibrary {
  bool get isFreshInstall;
  bool get hasUpdateAvailable;
  Future<void> update();
}

abstract interface class AutoInstallApp {
  bool get isInstalled;
  bool get hasUpdateAvailable;
  Future<void> install({required bool useWizard});
}

class AutoInstallFlow {
  const AutoInstallFlow({
    required this.library,
    required this.app,
    required this.isOtzariaRunning,
    required this.isDownloading,
    required this.exitPending,
    required this.isActive,
  });

  final AutoInstallLibrary library;
  final AutoInstallApp app;
  final Future<bool> Function() isOtzariaRunning;
  final bool Function() isDownloading;
  final bool Function() exitPending;
  final bool Function() isActive;

  Future<bool> run({required bool enabled}) async {
    var skippedWhileRunning = false;

    if (enabled &&
        !isDownloading() &&
        !library.isFreshInstall &&
        library.hasUpdateAvailable) {
      if (await isOtzariaRunning()) {
        skippedWhileRunning = true;
      } else if (!exitPending()) {
        await library.update();
        if (!isActive()) return false;
      }
    }

    if (enabled && app.isInstalled && app.hasUpdateAvailable) {
      if (await isOtzariaRunning()) {
        skippedWhileRunning = true;
      } else if (!exitPending()) {
        await app.install(useWizard: false);
      }
    }

    return skippedWhileRunning;
  }
}

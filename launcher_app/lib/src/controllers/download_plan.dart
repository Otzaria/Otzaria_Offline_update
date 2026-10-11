import '../settings/app_settings.dart';
import 'online_check.dart';

class OnlineCheckStamp {
  const OnlineCheckStamp({required this.checkedAt, required this.error});

  final DateTime? checkedAt;
  final String? error;

  bool needsRefresh({DateTime? now}) =>
      onlineCheckNeedsRefresh(checkedAt: checkedAt, error: error, now: now);
}

class OnlineProof {
  const OnlineProof({
    required this.checkedAt,
    required this.error,
    required this.hasUpdate,
  });

  final DateTime? checkedAt;
  final String? error;
  final bool hasUpdate;

  bool get provenUpToDate => provenUpToDateOnline(
        checkedAt: checkedAt,
        error: error,
        hasUpdate: hasUpdate,
      );
}

class StaleOnlineChecks {
  const StaleOnlineChecks({
    required this.app,
    required this.library,
    required this.plugins,
  });

  factory StaleOnlineChecks.of(
    AppSettings s, {
    required OnlineCheckStamp app,
    required OnlineCheckStamp library,
    required OnlineCheckStamp catalog,
    required OnlineCheckStamp storeApp,
    DateTime? now,
  }) =>
      StaleOnlineChecks(
        app: s.syncApp && app.needsRefresh(now: now),
        library: s.downloadsLibrary && library.needsRefresh(now: now),
        plugins: s.syncPlugins &&
            (catalog.needsRefresh(now: now) || storeApp.needsRefresh(now: now)),
      );

  final bool app;
  final bool library;
  final bool plugins;

  bool get any => app || library || plugins;
}

enum MirrorComponent { app, library, plugins }

class DownloadPlan {
  const DownloadPlan({
    required this.skipApp,
    required this.includeSemanticSearch,
    required this.skipLibrary,
    required this.skipPlugins,
    required this.skipStoreApp,
  });

  static bool shouldSkipApp(
    AppSettings s, {
    required bool hasStaleFullPackage,
    required OnlineProof online,
  }) =>
      s.syncApp && !hasStaleFullPackage && online.provenUpToDate;

  static bool shouldSkipLibrary(
    AppSettings s, {
    required bool includeSemanticSearch,
    required bool personalUpdateMode,
    required OnlineProof online,
  }) =>
      !includeSemanticSearch &&
      s.downloadsLibrary &&
      !personalUpdateMode &&
      online.provenUpToDate;

  static bool shouldSkipPlugins(
    AppSettings s, {
    required OnlineProof catalog,
  }) =>
      s.syncPlugins && catalog.provenUpToDate;

  static bool shouldSkipStoreApp(
    AppSettings s, {
    required OnlineProof storeApp,
  }) =>
      s.syncPlugins && storeApp.provenUpToDate;

  final bool skipApp;
  final bool includeSemanticSearch;
  final bool skipLibrary;
  final bool skipPlugins;
  final bool skipStoreApp;

  bool runsApp(AppSettings s) => s.syncApp && !skipApp;

  bool runsLibrary(AppSettings s) => s.downloadsLibrary && !skipLibrary;

  bool runsPlugins(AppSettings s) => s.syncPlugins && !skipPlugins;

  bool runsStoreApp(AppSettings s) => s.syncPlugins && !skipStoreApp;

  List<MirrorComponent> get skipped => [
        if (skipApp) MirrorComponent.app,
        if (skipLibrary) MirrorComponent.library,
        if (skipPlugins) MirrorComponent.plugins,
      ];

  List<MirrorComponent> failed(
    AppSettings s, {
    required bool appFailed,
    required bool libraryFailed,
    required bool pluginsFailed,
  }) =>
      [
        if (runsApp(s) && appFailed) MirrorComponent.app,
        if (runsLibrary(s) && libraryFailed) MirrorComponent.library,
        if (runsPlugins(s) && pluginsFailed) MirrorComponent.plugins,
      ];
}

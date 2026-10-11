import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/download_plan.dart';
import 'package:launcher_app/src/controllers/online_check.dart';
import 'package:launcher_app/src/settings/app_settings.dart';

void main() {
  final now = DateTime(2026, 10, 11, 12);
  final fresh = now.subtract(const Duration(minutes: 1));
  final old = now.subtract(onlineCheckMaxAge + const Duration(minutes: 1));

  final proven = OnlineProof(checkedAt: fresh, error: null, hasUpdate: false);
  final hasNew = OnlineProof(checkedAt: fresh, error: null, hasUpdate: true);
  final failedCheck =
      OnlineProof(checkedAt: fresh, error: 'offline', hasUpdate: false);
  const neverChecked =
      OnlineProof(checkedAt: null, error: null, hasUpdate: false);

  const all = AppSettings();

  group('OnlineProof', () {
    test('only a successful check with nothing new is proof', () {
      expect(proven.provenUpToDate, isTrue);
      expect(hasNew.provenUpToDate, isFalse);
      expect(failedCheck.provenUpToDate, isFalse);
      expect(neverChecked.provenUpToDate, isFalse);
    });
  });

  group('StaleOnlineChecks', () {
    final freshStamp = OnlineCheckStamp(checkedAt: fresh, error: null);
    final oldStamp = OnlineCheckStamp(checkedAt: old, error: null);
    final failedStamp = OnlineCheckStamp(checkedAt: fresh, error: 'offline');
    const neverStamp = OnlineCheckStamp(checkedAt: null, error: null);

    StaleOnlineChecks of(
      AppSettings s, {
      OnlineCheckStamp? app,
      OnlineCheckStamp? library,
      OnlineCheckStamp? catalog,
      OnlineCheckStamp? storeApp,
    }) =>
        StaleOnlineChecks.of(
          s,
          app: app ?? freshStamp,
          library: library ?? freshStamp,
          catalog: catalog ?? freshStamp,
          storeApp: storeApp ?? freshStamp,
          now: now,
        );

    test('fresh checks of every component need no refresh', () {
      final stale = of(all);
      expect(stale.any, isFalse);
    });

    test('an old, failed or missing check is refreshed', () {
      expect(of(all, app: oldStamp).app, isTrue);
      expect(of(all, library: failedStamp).library, isTrue);
      expect(of(all, catalog: neverStamp).plugins, isTrue);
    });

    test('a stale store-app check alone refreshes the plugins', () {
      final stale = of(all, storeApp: oldStamp);
      expect(stale.plugins, isTrue);
      expect(stale.app, isFalse);
      expect(stale.library, isFalse);
      expect(stale.any, isTrue);
    });

    test('a component that is not selected is never refreshed', () {
      const none = AppSettings(
        syncApp: false,
        syncLibrary: false,
        syncPlugins: false,
      );
      final stale = of(
        none,
        app: neverStamp,
        library: neverStamp,
        catalog: neverStamp,
        storeApp: neverStamp,
      );
      expect(stale.app, isFalse);
      expect(stale.library, isFalse);
      expect(stale.plugins, isFalse);
      expect(stale.any, isFalse);
    });

    test('personal update mode selects the library', () {
      const personal = AppSettings(
        syncLibrary: false,
        personalUpdateMode: true,
      );
      expect(of(personal, library: neverStamp).library, isTrue);
    });
  });

  group('DownloadPlan skip rules', () {
    test('the app is skipped only when proven and no stale full package', () {
      expect(
        DownloadPlan.shouldSkipApp(
          all,
          hasStaleFullPackage: false,
          online: proven,
        ),
        isTrue,
      );
      expect(
        DownloadPlan.shouldSkipApp(
          all,
          hasStaleFullPackage: true,
          online: proven,
        ),
        isFalse,
      );
      for (final proof in [hasNew, failedCheck, neverChecked]) {
        expect(
          DownloadPlan.shouldSkipApp(
            all,
            hasStaleFullPackage: false,
            online: proof,
          ),
          isFalse,
        );
      }
      expect(
        DownloadPlan.shouldSkipApp(
          const AppSettings(syncApp: false),
          hasStaleFullPackage: false,
          online: proven,
        ),
        isFalse,
      );
    });

    test('a declined smart search still lets an up-to-date library skip', () {
      expect(
        DownloadPlan.shouldSkipLibrary(
          all,
          includeSemanticSearch: false,
          personalUpdateMode: false,
          online: proven,
        ),
        isTrue,
      );
      expect(
        DownloadPlan.shouldSkipLibrary(
          all,
          includeSemanticSearch: true,
          personalUpdateMode: false,
          online: proven,
        ),
        isFalse,
      );
    });

    test('the library is never skipped in personal update mode', () {
      expect(
        DownloadPlan.shouldSkipLibrary(
          all,
          includeSemanticSearch: false,
          personalUpdateMode: true,
          online: proven,
        ),
        isFalse,
      );
    });

    test('catalog and store app are skipped independently', () {
      expect(DownloadPlan.shouldSkipPlugins(all, catalog: proven), isTrue);
      expect(DownloadPlan.shouldSkipPlugins(all, catalog: hasNew), isFalse);
      expect(DownloadPlan.shouldSkipStoreApp(all, storeApp: proven), isTrue);
      expect(
        DownloadPlan.shouldSkipStoreApp(all, storeApp: failedCheck),
        isFalse,
      );
      const noPlugins = AppSettings(syncPlugins: false);
      expect(
        DownloadPlan.shouldSkipPlugins(noPlugins, catalog: proven),
        isFalse,
      );
      expect(
        DownloadPlan.shouldSkipStoreApp(noPlugins, storeApp: proven),
        isFalse,
      );
    });
  });

  group('DownloadPlan outcome', () {
    const plan = DownloadPlan(
      skipApp: true,
      includeSemanticSearch: false,
      skipLibrary: false,
      skipPlugins: true,
      skipStoreApp: false,
    );

    test('skipped lists app, library, plugins in order, never the store', () {
      expect(plan.skipped, [MirrorComponent.app, MirrorComponent.plugins]);
      const everything = DownloadPlan(
        skipApp: true,
        includeSemanticSearch: false,
        skipLibrary: true,
        skipPlugins: true,
        skipStoreApp: true,
      );
      expect(everything.skipped, [
        MirrorComponent.app,
        MirrorComponent.library,
        MirrorComponent.plugins,
      ]);
    });

    test('runs only selected components that were not skipped', () {
      expect(plan.runsApp(all), isFalse);
      expect(plan.runsLibrary(all), isTrue);
      expect(plan.runsPlugins(all), isFalse);
      expect(plan.runsStoreApp(all), isTrue);
      expect(plan.runsLibrary(const AppSettings(syncLibrary: false)), isFalse);
      expect(plan.runsStoreApp(const AppSettings(syncPlugins: false)), isFalse);
    });

    test('a failure counts only for a component that actually ran', () {
      expect(
        plan.failed(
          all,
          appFailed: true,
          libraryFailed: true,
          pluginsFailed: true,
        ),
        [MirrorComponent.library],
      );
      const none = DownloadPlan(
        skipApp: false,
        includeSemanticSearch: false,
        skipLibrary: false,
        skipPlugins: false,
        skipStoreApp: false,
      );
      expect(
        none.failed(
          all,
          appFailed: true,
          libraryFailed: false,
          pluginsFailed: true,
        ),
        [MirrorComponent.app, MirrorComponent.plugins],
      );
      expect(
        none.failed(
          const AppSettings(syncApp: false),
          appFailed: true,
          libraryFailed: false,
          pluginsFailed: false,
        ),
        isEmpty,
      );
    });
  });
}

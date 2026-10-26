import 'dart:io';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

import '../models/plugin_catalog.dart';
import '../models/plugin_store_category.dart';
import '../models/plugin_store_home.dart';
import '../models/plugin_sync_outcome.dart';
import '../models/plugin_sync_progress.dart';
import '../models/plugin_version_entry.dart';
import '../models/store_plugin.dart';
import 'download_pool.dart';
import 'media_sniffer.dart';
import 'plugin_build_check.dart';
import 'plugin_manifest_reader.dart';
import 'plugin_mirror_store.dart';
import 'plugin_store_client.dart';

/// מסנכרן את הקטלוג מהאתר אל המראה המקומית — פורט של `syncNow` מחנות
/// ה-Electron. רץ **רק** על המחשב המקוון; משם הכול עובד אופליין.
class PluginMirrorSync {
  const PluginMirrorSync({
    required this.client,
    required this.store,
    this.maxConcurrentPlugins = defaultMaxConcurrentPlugins,
    this.maxConcurrentScreenshots = defaultMaxConcurrentScreenshots,
    this.catalogGuard,
  });

  static const int defaultMaxConcurrentScreenshots = 3;

  /// ארבעה תוספים בו-זמנית. ראו [runPooled]: הקבצים כאן קטנים והזמן הולך
  /// על סיבובי הלוך-חזור, ולכן זה בדיוק המקום שבו מקביליות משתלמת.
  static const int defaultMaxConcurrentPlugins = 4;

  static const Duration untargetedBuildRetention = Duration(days: 60);

  final PluginStoreClient client;
  final PluginMirrorStore store;
  final Future<T> Function<T>(Future<T> Function() action)? catalogGuard;

  final int maxConcurrentPlugins;
  final int maxConcurrentScreenshots;

  Future<bool> hasPendingMedia(
    StorePlugin plugin,
    StorePlugin? previous,
  ) async =>
      (plugin.remoteImageUrl.isEmpty && previous?.imagePath != null) ||
      (plugin.remoteScreenshotUrls.isEmpty &&
          (previous?.screenshotPaths.isNotEmpty ?? false)) ||
      (plugin.remoteImageUrl.isNotEmpty &&
          !await _imageUnchanged(plugin, previous)) ||
      (plugin.remoteScreenshotUrls.isNotEmpty &&
          !await _screenshotsUnchanged(plugin, previous));

  Future<PluginSyncOutcome> sync({
    List<String> appVersions = const [],
    void Function(PluginSyncProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    void report(PluginSyncProgress progress) => onProgress?.call(progress);
    bool cancelRequested() => isCancelled?.call() ?? false;

    final strings = AppL10n.strings.pluginsDomain;

    await store.ensureDirs();
    report(
      PluginSyncProgress(
        phase: PluginSyncPhase.start,
        message: strings.syncLoadingCatalog,
      ),
    );

    final remote = await client.fetchCatalog();
    final previousCatalog = await store.load();
    if (remote.isEmpty && previousCatalog.plugins.isNotEmpty) {
      throw StateError(strings.syncEmptyCatalogRejected);
    }
    final existing = {
      for (final plugin in previousCatalog.plugins) plugin.id: plugin,
    };

    final now = DateTime.now();
    final plans = [
      for (final raw in remote)
        if (StorePlugin.isValidId(
            raw['id'] is String ? raw['id'] as String : ''))
          await _plan(raw, existing, appVersions, now),
    ];
    final keptInvalid = <StorePlugin>[];
    for (final raw in remote) {
      final rawId = raw['id'] is String ? raw['id'] as String : '';
      final kept = StorePlugin.isValidId(rawId) ? null : existing[rawId];
      if (kept == null) continue;
      keptInvalid.add(kept);
      report(
        PluginSyncProgress(
          phase: PluginSyncPhase.warning,
          message: strings.syncPluginFileFailed(kept.name, rawId),
        ),
      );
    }
    final todo = [
      for (final plan in plans)
        if (plan.hasWork) plan,
    ];

    final fetched = <String, StorePlugin>{};
    final failed = <String>[];
    final versionMismatches = <String>[];
    final total = todo.where((plan) => plan.needsNetwork).length;
    var done = 0;

    await runPooled([
      for (final plan in todo)
        () async {
          if (isCancelled?.call() ?? false) return;

          var plugin = plan.plugin;
          if (plan.needsNetwork) {
            done++;
            report(
              PluginSyncProgress(
                phase: PluginSyncPhase.plugin,
                message: strings.syncPlugin(plugin.name, done, total),
                current: done,
                total: total,
              ),
            );
          }

          await Directory(store.pluginDir(plugin.id)).create(recursive: true);
          plugin = await _syncImages(plan, plugin, report, cancelRequested);
          final files = await _syncPluginFiles(
            plan,
            plugin,
            report,
            now,
            cancelRequested,
          );
          plugin = files.plugin;

          fetched[plugin.id] = plugin;
          if (!files.ok) failed.add(plugin.name);
          versionMismatches.addAll(files.versionMismatches);
        },
    ], maxConcurrent: maxConcurrentPlugins);

    final cancelled = isCancelled?.call() ?? false;

    final plugins = <StorePlugin>[
      for (final plan in plans)
        fetched[plan.plugin.id] ??
            (cancelled && plan.hasWork
                ? (plan.previous ?? plan.plugin)
                : plan.plugin),
      ...keptInvalid,
    ];
    final syncedIds = {for (final plugin in plugins) plugin.id};

    final structure = cancelled
        ? _StoreStructure(
            home: previousCatalog.home,
            categories: previousCatalog.categories,
          )
        : await _syncStructure(syncedIds, previousCatalog, report);

    final built = PluginCatalog(
      lastSync: DateTime.now(),
      plugins: [
        for (final plugin in plugins)
          plugin.copyWith(categorySlugs: structure.slugsOf(plugin.id)),
      ],
      categories: structure.categories,
      home: structure.home,
    );
    Future<PluginCatalog> saveMerged() async {
      final merged = _mergeConcurrentAdditions(
        built,
        previousCatalog,
        await store.load(),
      );
      await store.save(merged);
      return merged;
    }

    final guard = catalogGuard;
    final catalog =
        guard == null ? await saveMerged() : await guard(saveMerged);

    if (!cancelled) {
      for (final plugin in catalog.plugins) {
        if (!plugin.hasValidId) continue;
        await store.pruneUnusedFiles(plugin);
      }
    }

    final skipped = plans.length - done;
    report(
      PluginSyncProgress(
        phase: PluginSyncPhase.done,
        message: strings.syncDoneCounts(done, skipped),
        current: done,
        total: total,
      ),
    );
    return PluginSyncOutcome(
      catalog: catalog,
      fetched: done,
      skipped: skipped,
      failed: failed,
      versionMismatches: versionMismatches,
      cancelled: cancelled,
      incompatible: [
        for (final plan in plans)
          if (plan.isIncompatible)
            '${plan.plugin.name} (${plan.plugin.lowestSupportedApp ?? '?'})',
      ],
    );
  }

  static PluginCatalog _mergeConcurrentAdditions(
    PluginCatalog built,
    PluginCatalog started,
    PluginCatalog latest,
  ) {
    final startedById = {
      for (final plugin in started.plugins) plugin.id: plugin
    };
    final latestById = {for (final plugin in latest.plugins) plugin.id: plugin};
    return PluginCatalog(
      lastSync: built.lastSync,
      categories: built.categories,
      home: built.home,
      plugins: [
        for (final plugin in built.plugins)
          _withAddedFiles(
              plugin, startedById[plugin.id], latestById[plugin.id]),
      ],
    );
  }

  static StorePlugin _withAddedFiles(
    StorePlugin built,
    StorePlugin? started,
    StorePlugin? latest,
  ) {
    if (latest == null) return built;
    final added = {
      for (final entry in latest.localFiles.entries)
        if (!built.localFiles.containsKey(entry.key) &&
            started?.localFiles[entry.key] != entry.value)
          entry.key: entry.value,
    };
    if (added.isEmpty && built.manifestId != null) return built;
    return built.copyWith(
      localFiles: {...built.localFiles, ...added},
      manifestId: built.manifestId ?? latest.manifestId,
    );
  }

  Future<_PluginPlan> _plan(
    Map<String, dynamic> raw,
    Map<String, StorePlugin> existing,
    List<String> appVersions,
    DateTime now,
  ) async {
    final remote = StorePlugin.fromApi(raw, client.baseUrl);
    final previous = existing[remote.id];

    var plugin = remote.copyWith(
      imagePath: remote.remoteImageUrl.isEmpty ? null : previous?.imagePath,
      screenshotPaths: remote.remoteScreenshotUrls.isEmpty
          ? const []
          : previous?.screenshotPaths ?? const [],
      localFiles: previous?.localFiles,
      manifestId: remote.manifestId ?? previous?.manifestId,
    );

    final keep = <String, PluginLocalFile>{};
    final missing = <PluginVersionEntry>[];
    final targets = plugin.targetsFor(appVersions);
    for (final target in targets) {
      if (target.downloadUrl.isEmpty) continue;
      final unchanged = await _unchangedBuild(target, plugin, previous);
      if (unchanged != null) {
        keep[target.version] =
            unchanged.copyWith(sourceUrl: target.downloadUrl, targetedAt: now);
      } else {
        missing.add(target);
      }
    }
    if (targets.isEmpty && previous != null) {
      for (final entry in previous.localFiles.entries) {
        if (await store.hasAsset(entry.value.relativePath)) {
          keep[entry.key] = entry.value;
        }
      }
    } else if (previous != null) {
      final published = {for (final v in plugin.versionEntries) v.version};
      final wanted = {for (final t in targets) t.version};
      for (final entry in previous.localFiles.entries) {
        if (wanted.contains(entry.key) || !published.contains(entry.key)) {
          continue;
        }
        if (appVersions.isNotEmpty && !_recentlyTargeted(entry.value, now)) {
          continue;
        }
        if (await store.hasAsset(entry.value.relativePath)) {
          keep[entry.key] = entry.value;
        }
      }
    }
    plugin = plugin.copyWith(localFiles: keep);

    return _PluginPlan(
      plugin: plugin,
      previous: previous,
      needsImage: plugin.remoteImageUrl.isNotEmpty &&
          !await _imageUnchanged(plugin, previous),
      needsScreenshots: plugin.remoteScreenshotUrls.isNotEmpty &&
          !await _screenshotsUnchanged(plugin, previous),
      missingBuilds: missing,
      isIncompatible: targets.isEmpty && plugin.remoteDownloadUrl.isNotEmpty,
      needsManifestId: plugin.manifestId == null && keep.isNotEmpty,
    );
  }

  /// מסנכרן את **מבנה** החנות — הקטגוריות המנוהלות והטקסטים של דף הבית.
  ///
  /// כשל כאן אינו מפיל את הסנכרון: המראה שומרת את המבנה הקודם (כך שגם אתר
  /// ישן בלי הנתיבים האלה, או קריאה שנפלה, לא מוחקים קטגוריות שכבר ירדו).
  Future<_StoreStructure> _syncStructure(
    Set<String> syncedIds,
    PluginCatalog previous,
    void Function(PluginSyncProgress) report,
  ) async {
    final strings = AppL10n.strings.pluginsDomain;
    report(
      PluginSyncProgress(
        phase: PluginSyncPhase.plugin,
        message: strings.syncCategories,
      ),
    );

    late final Map<String, dynamic> home;
    try {
      home = await client.fetchStoreHome();
    } catch (e) {
      report(
        PluginSyncProgress(
          phase: PluginSyncPhase.warning,
          message: strings.syncStructureFailed(
            PluginStoreClient.describeError(e),
          ),
        ),
      );
      return _StoreStructure(
        home: previous.home,
        categories: previous.categories,
      );
    }

    final settings = home['settings'];
    final rawCategories = home['categories'];
    final categories = <PluginStoreCategory>[];
    if (rawCategories is List) {
      for (final raw in rawCategories) {
        if (raw is! Map) continue;
        final summary = PluginStoreCategory.fromApi(
          Map<String, dynamic>.from(raw),
        );
        if (summary.slug.isEmpty) continue;
        categories.add(
          await _categoryMembers(summary, syncedIds, previous, report),
        );
      }
    }

    // תשובה תקינה אך חסרת מבנה (אתר ישן, שדה שהשתנה) אינה עילה למחוק את מה
    // שכבר במראה — אותו כלל בדיוק כמו בכשל הבקשה עצמה, למעלה.
    if (categories.isEmpty && previous.categories.isNotEmpty) {
      report(
        PluginSyncProgress(
          phase: PluginSyncPhase.warning,
          message: strings.syncStructureFailed(strings.syncStructureEmpty),
        ),
      );
      return _StoreStructure(
        home: previous.home,
        categories: previous.categories,
      );
    }

    return _StoreStructure(
      home: PluginStoreHome.fromApi(
        settings is Map ? Map<String, dynamic>.from(settings) : const {},
      ),
      categories: categories,
    );
  }

  /// דף הבית מחזיר תוספים רק לקטגוריות שמסומנות להצגה בו, ולכן החברות
  /// המלאה נשלפת תמיד מדף הקטגוריה עצמו.
  Future<PluginStoreCategory> _categoryMembers(
    PluginStoreCategory summary,
    Set<String> syncedIds,
    PluginCatalog previous,
    void Function(PluginSyncProgress) report,
  ) async {
    var ids = summary.pluginIds;
    try {
      ids = PluginStoreCategory.fromApi(
        await client.fetchCategory(summary.slug),
      ).pluginIds;
    } catch (e) {
      report(
        PluginSyncProgress(
          phase: PluginSyncPhase.warning,
          message: AppL10n.strings.pluginsDomain.syncCategoryFailed(
            summary.name,
            PluginStoreClient.describeError(e),
          ),
        ),
      );
      final known = previous.categoryBySlug(summary.slug);
      if (known != null) ids = known.pluginIds;
    }

    // תוסף שאינו בקטלוג שירד עכשיו (הוסר מהחנות, או שהסנכרון לא הגיע
    // אליו) לא נספר ולא מוצג בקטגוריה.
    return summary.copyWith(
      pluginIds: [
        for (final id in ids)
          if (syncedIds.contains(id)) id,
      ],
    );
  }

  Future<StorePlugin> _syncImages(
    _PluginPlan plan,
    StorePlugin plugin,
    void Function(PluginSyncProgress) report,
    bool Function() cancelled,
  ) async {
    var result = plugin;
    final dir = store.pluginDir(plugin.id);

    if (plan.needsImage) {
      try {
        final asset = await client.downloadAsset(
          plugin.remoteImageUrl,
          p.join(dir, 'image'),
          checkCancelled: () => _throwIfCancelled(cancelled),
          rejection: _imageRejection,
        );
        result = result.copyWith(imagePath: store.relativePath(asset.path));
      } catch (e) {
        result = result.copyWith(
          mediaVersion: plan.previousMediaVersion,
          remoteImageUrl: plan.previous?.remoteImageUrl,
        );
        if (!cancelled()) {
          report(
            PluginSyncProgress(
              phase: PluginSyncPhase.warning,
              message: AppL10n.strings.pluginsDomain.syncImageFailed(
                plugin.name,
                PluginStoreClient.describeError(e),
              ),
            ),
          );
        }
      }
    }

    if (plan.needsScreenshots) {
      final shotUrls = plugin.remoteScreenshotUrls;
      final downloaded = List<String?>.filled(shotUrls.length, null);
      var interrupted = false;
      var failedAny = false;
      await runPooled([
        for (var i = 0; i < shotUrls.length; i++)
          () async {
            if (interrupted) return;
            try {
              final asset = await client.downloadAsset(
                shotUrls[i],
                p.join(dir, 'screenshot-$i'),
                checkCancelled: () => _throwIfCancelled(cancelled),
                rejection: _imageRejection,
              );
              downloaded[i] = store.relativePath(asset.path);
            } catch (e) {
              failedAny = true;
              if (cancelled()) {
                interrupted = true;
                return;
              }
              report(
                PluginSyncProgress(
                  phase: PluginSyncPhase.warning,
                  message: AppL10n.strings.pluginsDomain.syncScreenshotFailed(
                    plugin.name,
                    PluginStoreClient.describeError(e),
                  ),
                ),
              );
            }
          },
      ], maxConcurrent: maxConcurrentScreenshots);
      if (failedAny) {
        result = result.copyWith(
          screenshotsMediaVersion: plan.previousScreenshotsMediaVersion,
          remoteScreenshotUrls: plan.previous?.remoteScreenshotUrls,
        );
      }
      final shots = downloaded.whereType<String>().toList();
      if (shots.isNotEmpty && !interrupted) {
        result = result.copyWith(screenshotPaths: shots);
      }
    }

    return result;
  }

  static Future<String?> _imageRejection(String path) async =>
      await MediaSniffer.isImageFile(path)
          ? null
          : AppL10n.strings.pluginsDomain.downloadedFileNotImage;

  static bool _recentlyTargeted(PluginLocalFile file, DateTime now) {
    final targetedAt = file.targetedAt;
    return targetedAt != null &&
        now.difference(targetedAt).abs() <= untargetedBuildRetention;
  }

  /// אותה כתובת, אותה גרסת תוסף, והקובץ עדיין על הדיסק. הגרסה נדרשת כי האתר
  /// יכול להחליף את תוכן התמונה מתחת לאותה כתובת.
  Future<bool> _imageUnchanged(
    StorePlugin plugin,
    StorePlugin? previous,
  ) async =>
      previous != null &&
      _sameSource(previous.remoteImageUrl, plugin.remoteImageUrl) &&
      mediaStampOf(previous) == plugin.mediaVersion &&
      await store.hasAsset(previous.imagePath);

  /// הגרסה שהתמונות שבמראה שייכות לה. קטלוג ישן בלי השדה נופל לגרסת התוסף
  /// שבו — כך הסנכרון הראשון אחרי העדכון אינו מוריד את כל החנות מחדש.
  static String mediaStampOf(StorePlugin plugin) =>
      plugin.mediaVersion.isNotEmpty ? plugin.mediaVersion : plugin.version;

  static String screenshotsStampOf(StorePlugin plugin) =>
      plugin.screenshotsMediaVersion.isNotEmpty
          ? plugin.screenshotsMediaVersion
          : mediaStampOf(plugin);

  /// כתובת ריקה בצד הקודם היא **קטלוג ישן** שנכתב לפני שהשדה נוסף, לא
  /// כתובת שהשתנתה. בלי החריג הזה הסנכרון הראשון אחרי העדכון היה מוריד את
  /// כל תמונות החנות מחדש רק כדי למלא שדה; השדה נכתב לקטלוג גם בלי הורדה.
  static bool _sameSource(String previous, String current) =>
      previous.isEmpty || previous == current;

  Future<bool> _screenshotsUnchanged(
    StorePlugin plugin,
    StorePlugin? previous,
  ) async {
    if (previous == null ||
        screenshotsStampOf(previous) != plugin.screenshotsMediaVersion ||
        !(previous.remoteScreenshotUrls.isEmpty ||
            _sameUrls(
              previous.remoteScreenshotUrls,
              plugin.remoteScreenshotUrls,
            )) ||
        previous.screenshotPaths.length != plugin.remoteScreenshotUrls.length) {
      return false;
    }
    for (final path in previous.screenshotPaths) {
      if (!await store.hasAsset(path)) return false;
    }
    return true;
  }

  static bool _sameUrls(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<PluginLocalFile?> _unchangedBuild(
    PluginVersionEntry target,
    StorePlugin plugin,
    StorePlugin? previous,
  ) async {
    final local = plugin.localFileFor(target.version);
    if (local == null ||
        !await store.hasFileFor(plugin, target.version) ||
        !await store.hasBuild(local)) {
      return null;
    }
    final expected = target.sha256;
    if (expected != null && local.sha256 == null) {
      final actual = await PluginBuildCheck.sha256Of(
        store.absolutePath(local.relativePath),
      );
      return actual == expected ? local.copyWith(sha256: actual) : null;
    }
    final known = previous?.versionEntries
        .where((entry) => entry.version == target.version)
        .firstOrNull;
    return buildMatches(
      target,
      local.sourceUrl ?? known?.downloadUrl ?? '',
      local.size,
      recordedSha256: local.sha256,
    )
        ? local
        : null;
  }

  static bool buildMatches(
    PluginVersionEntry target,
    String recordedSource,
    int recordedSize, {
    String? recordedSha256,
  }) {
    final expected = target.sha256;
    if (expected != null && recordedSha256 != null) {
      return expected == recordedSha256;
    }
    return (target.fileSize <= 0 ||
            recordedSize <= 0 ||
            recordedSize == target.fileSize) &&
        _sameBuildSource(recordedSource, target.downloadUrl, target.version);
  }

  static bool _sameBuildSource(
    String recorded,
    String current,
    String version,
  ) =>
      _sameSource(recorded, current) ||
      _canonicalBuildSource(recorded, version) ==
          _canonicalBuildSource(current, version);

  static String _canonicalBuildSource(String url, String version) {
    var path = url;
    final queryStart = url.indexOf('?');
    if (queryStart >= 0) {
      final query = Uri.splitQueryString(url.substring(queryStart + 1));
      if (query.length != 1 || query['version'] != version) return url;
      path = url.substring(0, queryStart);
    }
    const suffix = '/download';
    if (!path.endsWith(suffix)) return url;
    final base = path.substring(0, path.length - suffix.length);
    return base.endsWith('@$version') ? path : '$base@$version$suffix';
  }

  static String? buildRejection(
    Map<String, dynamic>? manifest,
    PluginVersionEntry target,
    String? expectedId,
  ) {
    final strings = AppL10n.strings.pluginsDomain;
    return switch (PluginBuildCheck.match(
      manifest,
      version: target.version,
      expectedId: expectedId,
    )) {
      PluginBuildMatch.notPlugin => strings.downloadedFileNotPlugin,
      PluginBuildMatch.wrongId => strings.downloadedFileWrongBuild,
      PluginBuildMatch.matches || PluginBuildMatch.versionDiffers => null,
    };
  }

  static void _throwIfCancelled(bool Function() cancelled) {
    if (cancelled()) {
      throw PluginStoreException(AppL10n.strings.appDomain.downloadCancelled);
    }
  }

  Future<({StorePlugin plugin, bool ok, List<String> versionMismatches})>
      _syncPluginFiles(
    _PluginPlan plan,
    StorePlugin plugin,
    void Function(PluginSyncProgress) report,
    DateTime now,
    bool Function() cancelled,
  ) async {
    if (plan.missingBuilds.isEmpty) {
      final known = plugin.anyLocalFile;
      if (plan.needsManifestId && known != null) {
        final id = PluginManifestReader.readId(
          store.absolutePath(known.relativePath),
        );
        if (id != null) {
          return (
            plugin: plugin.copyWith(manifestId: id),
            ok: true,
            versionMismatches: const <String>[],
          );
        }
      }
      return (plugin: plugin, ok: true, versionMismatches: const <String>[]);
    }

    final files = Map.of(plugin.localFiles);
    var manifestId = plugin.manifestId;
    var ok = true;
    var interrupted = false;
    final versionMismatches = <String>[];

    for (final target in plan.missingBuilds) {
      Map<String, dynamic>? manifest;
      try {
        final asset = await client.downloadAsset(
          target.downloadUrl,
          store.pluginFilePathNoExt(plugin.id, target.version),
          preferredExt: PluginMirrorStore.pluginFileExt,
          requiredExt: PluginMirrorStore.pluginFileExt,
          expectedSize: target.fileSize,
          expectedSha256: target.sha256,
          checkCancelled: () => _throwIfCancelled(cancelled),
          rejection: (path) {
            manifest = PluginManifestReader.read(path);
            return buildRejection(manifest, target, manifestId);
          },
        );
        files[target.version] = PluginLocalFile(
          relativePath: store.relativePath(asset.path),
          fileName: asset.originalName ?? '${plugin.name}${asset.ext}',
          ext: asset.ext,
          size: asset.size,
          sourceUrl: target.downloadUrl,
          targetedAt: now,
          sha256: target.sha256,
        );
        manifestId ??= PluginManifestReader.idOf(manifest);
        final manifestVersion = manifest?['version'];
        if (PluginBuildCheck.match(manifest, version: target.version) ==
            PluginBuildMatch.versionDiffers) {
          versionMismatches
              .add('${plugin.name}: ${target.version} ≠ $manifestVersion');
        }
      } catch (e) {
        if (cancelled()) {
          interrupted = true;
          break;
        }
        ok = false;
        report(
          PluginSyncProgress(
            phase: PluginSyncPhase.warning,
            message: AppL10n.strings.pluginsDomain.syncPluginFileFailed(
              plugin.name,
              PluginStoreClient.describeError(e),
            ),
          ),
        );
      }
    }

    final previous = plan.previous;
    if ((!ok || interrupted) && previous != null) {
      for (final entry in previous.localFiles.entries) {
        if (files.containsKey(entry.key)) continue;
        if (await store.hasAsset(entry.value.relativePath)) {
          files[entry.key] = entry.value.copyWith(
            sourceUrl: entry.value.sourceUrl ??
                previous.versionEntries
                    .where((version) => version.version == entry.key)
                    .firstOrNull
                    ?.downloadUrl,
          );
        }
      }
    }

    return (
      plugin: plugin.copyWith(localFiles: files, manifestId: manifestId),
      ok: ok,
      versionMismatches: versionMismatches,
    );
  }
}

/// מה חסר לתוסף אחד במראה. נקבע פעם אחת, לפני שההורדות מתחילות — ראו
/// [PluginMirrorSync.sync].
class _PluginPlan {
  const _PluginPlan({
    required this.plugin,
    required this.previous,
    required this.needsImage,
    required this.needsScreenshots,
    required this.missingBuilds,
    required this.isIncompatible,
    required this.needsManifestId,
  });

  /// הרשומה המרוחקת אחרי מיזוג הנתיבים המקומיים שכבר במראה. ה-[localFiles]
  /// שלה מכילים כבר רק את הבילדים המבוקשים שנמצאו על הדיסק.
  final StorePlugin plugin;
  final StorePlugin? previous;

  String? get previousMediaVersion {
    final old = previous;
    return old == null ? null : PluginMirrorSync.mediaStampOf(old);
  }

  String? get previousScreenshotsMediaVersion {
    final old = previous;
    return old == null ? null : PluginMirrorSync.screenshotsStampOf(old);
  }

  final bool needsImage;
  final bool needsScreenshots;

  /// הבילדים שצריכים לרדת — אחד לכל גרסת אוצריא שהכונן נושא ושהבילד
  /// המתאים לה אינו במראה.
  final List<PluginVersionEntry> missingBuilds;

  /// אין אף בילד שירוץ על גרסת אוצריא שהכונן נושא — אין מה להוריד, וזה
  /// אינו כשל. ראו [PluginSyncOutcome.incompatible].
  final bool isIncompatible;

  /// חילוץ `manifestId` מקובץ שכבר במראה — עבודה מקומית, בלי רשת, אבל
  /// כן סיבה לא לדלג על התוסף לגמרי.
  final bool needsManifestId;

  /// עבודה שיש בה פנייה לרשת. רק היא נספרת ומדווחת — ראו [PluginMirrorSync.sync].
  bool get needsNetwork =>
      needsImage || needsScreenshots || missingBuilds.isNotEmpty;

  bool get hasWork => needsNetwork || needsManifestId;
}

/// תוצאת סנכרון המבנה — הקטגוריות והטקסטים, ומהן נגזרת גם השיוך ההפוך
/// (תוסף → ה-slugs שהוא משובץ בהם) שנשמר על כל תוסף בקטלוג.
class _StoreStructure {
  _StoreStructure({required this.home, required this.categories});

  final PluginStoreHome home;
  final List<PluginStoreCategory> categories;

  late final Map<String, List<String>> _slugsByPlugin = () {
    final map = <String, List<String>>{};
    for (final category in categories) {
      for (final id in category.pluginIds) {
        (map[id] ??= <String>[]).add(category.slug);
      }
    }
    return map;
  }();

  List<String> slugsOf(String pluginId) => _slugsByPlugin[pluginId] ?? const [];
}

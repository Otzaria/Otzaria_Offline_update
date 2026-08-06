import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/plugin_catalog.dart';
import '../models/plugin_sync_progress.dart';
import '../models/store_plugin.dart';
import 'plugin_manifest_reader.dart';
import 'plugin_mirror_store.dart';
import 'plugin_store_client.dart';

/// מסנכרן את הקטלוג מהאתר אל המראה המקומית — פורט של `syncNow` מחנות
/// ה-Electron. רץ **רק** על המחשב המקוון; משם הכול עובד אופליין.
class PluginMirrorSync {
  const PluginMirrorSync({required this.client, required this.store});

  final PluginStoreClient client;
  final PluginMirrorStore store;

  /// זורק [PluginStoreException] רק אם רשימת התוספים עצמה לא נטענה. כשל
  /// בנכס בודד מדווח כ-[PluginSyncPhase.warning] והסנכרון ממשיך.
  Future<PluginCatalog> sync({
    void Function(PluginSyncProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    void report(PluginSyncProgress progress) => onProgress?.call(progress);

    await store.ensureDirs();
    report(const PluginSyncProgress(
      phase: PluginSyncPhase.start,
      message: 'טוען את רשימת התוספים מהאתר...',
    ));

    final remote = await client.fetchCatalog();
    final existing = {
      for (final plugin in (await store.load()).plugins) plugin.id: plugin,
    };

    final synced = <StorePlugin>[];
    final total = remote.length;
    var done = 0;

    for (final raw in remote) {
      if (isCancelled?.call() ?? false) break;
      done++;

      var plugin = StorePlugin.fromApi(raw, client.baseUrl);
      final previous = existing[plugin.id];
      report(PluginSyncProgress(
        phase: PluginSyncPhase.plugin,
        message: 'מסנכרן: ${plugin.name} ($done/$total)',
        current: done,
        total: total,
      ));

      // שומרים על מה שכבר יש מקומית, ומעדכנים רק את מה שבאמת ירד עכשיו.
      plugin = plugin.copyWith(
        imagePath: previous?.imagePath,
        screenshotPaths: previous?.screenshotPaths ?? const [],
        localFile: previous?.localFile,
        manifestId: previous?.manifestId,
      );

      final dir = store.pluginDir(plugin.id);
      await Directory(dir).create(recursive: true);

      plugin = await _syncImages(plugin, raw, dir, report);
      plugin = await _syncPluginFile(plugin, raw, previous, dir, report);

      synced.add(plugin);
    }

    final catalog = PluginCatalog(lastSync: DateTime.now(), plugins: synced);
    await store.save(catalog);

    report(PluginSyncProgress(
      phase: PluginSyncPhase.done,
      message: 'הסנכרון הושלם',
      current: done,
      total: total,
    ));
    return catalog;
  }

  /// תמונת התוסף וצילומי המסך קטנים, ולכן יורדים בכל סנכרון.
  Future<StorePlugin> _syncImages(
    StorePlugin plugin,
    Map<String, dynamic> raw,
    String dir,
    void Function(PluginSyncProgress) report,
  ) async {
    var result = plugin;

    final image = raw['image'];
    if (image is String && image.isNotEmpty) {
      try {
        final asset = await client.downloadAsset(image, p.join(dir, 'image'));
        result = result.copyWith(imagePath: store.relativePath(asset.path));
      } catch (e) {
        report(PluginSyncProgress(
          phase: PluginSyncPhase.warning,
          message: 'לא ניתן להוריד תמונה עבור ${plugin.name}: $e',
        ));
      }
    }

    final rawShots = raw['screenshots'];
    if (rawShots is List && rawShots.isNotEmpty) {
      final shots = <String>[];
      for (var i = 0; i < rawShots.length; i++) {
        final url = rawShots[i];
        if (url is! String || url.isEmpty) continue;
        try {
          final asset =
              await client.downloadAsset(url, p.join(dir, 'screenshot-$i'));
          shots.add(store.relativePath(asset.path));
        } catch (e) {
          report(PluginSyncProgress(
            phase: PluginSyncPhase.warning,
            message: 'לא ניתן להוריד צילום מסך עבור ${plugin.name}: $e',
          ));
        }
      }
      if (shots.isNotEmpty) result = result.copyWith(screenshotPaths: shots);
    }

    return result;
  }

  /// קובץ התוסף עצמו עלול להיות גדול — מדלגים עליו אם הגרסה לא השתנתה
  /// והקובץ כבר קיים.
  Future<StorePlugin> _syncPluginFile(
    StorePlugin plugin,
    Map<String, dynamic> raw,
    StorePlugin? previous,
    String dir,
    void Function(PluginSyncProgress) report,
  ) async {
    final unchanged = previous != null &&
        previous.version == plugin.version &&
        previous.localFile != null &&
        await store.hasLocalFile(previous);

    if (unchanged) {
      // תוסף שסונכרן לפני שה-manifestId נכנס לקטלוג — מחלצים אותו מהקובץ
      // הקיים בלי להוריד מחדש.
      if (plugin.manifestId == null) {
        final id = PluginManifestReader.readId(
          store.absolutePath(previous.localFile!.relativePath),
        );
        if (id != null) return plugin.copyWith(manifestId: id);
      }
      return plugin;
    }

    final downloadUrl = raw['downloadUrl'];
    if (downloadUrl is! String || downloadUrl.isEmpty) return plugin;

    try {
      final asset = await client.downloadAsset(
        downloadUrl,
        p.join(dir, 'plugin'),
        preferredExt: '.otzplugin',
      );
      return plugin.copyWith(
        localFile: PluginLocalFile(
          relativePath: store.relativePath(asset.path),
          fileName: asset.originalName ?? '${plugin.name}${asset.ext}',
          ext: asset.ext,
          size: asset.size,
        ),
        manifestId: PluginManifestReader.readId(asset.path),
      );
    } catch (e) {
      report(PluginSyncProgress(
        phase: PluginSyncPhase.warning,
        message: 'לא ניתן להוריד את קובץ התוסף ${plugin.name}: $e',
      ));
      return plugin;
    }
  }
}

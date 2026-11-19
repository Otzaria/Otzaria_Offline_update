import '../models/plugin_catalog.dart';
import '../models/plugin_version_entry.dart';
import '../models/plugins_online_status.dart';
import '../models/store_plugin.dart';
import 'plugin_mirror_store.dart';
import 'plugin_mirror_sync.dart';
import 'plugin_store_client.dart';

typedef _PluginTargets = ({
  StorePlugin plugin,
  List<PluginVersionEntry> builds,
});

/// "יש משהו חדש בחנות?" — קריאת מטא-דאטה אחת מול הקטלוג שכבר במראה, בלי
/// להוריד נכס ובלי לכתוב דבר. המקבילה של `peekLatestOnlineVersion` בספרייה,
/// והיא זו שמזינה את הנדנוד "יש עדכונים ברשת" שבדף הבית.
class PluginOnlinePeek {
  const PluginOnlinePeek({required this.client, required this.store});

  final PluginStoreClient client;
  final PluginMirrorStore store;

  /// [appVersions] — אותן גרסאות אוצריא שהסנכרון יקבל. חובה שיהיו זהות:
  /// ההצצה אמורה לדווח בדיוק על מה שסנכרון היה מביא.
  Future<PluginsOnlineStatus> peek({
    List<String> appVersions = const [],
  }) async {
    final remote = _prepare(
      await client.fetchCatalog(),
      client.baseUrl,
      appVersions,
    );
    final local = await store.load();
    final present = <String, Set<String>>{};
    final checked = <(String, String)>{};
    final pendingMedia = <String>{};
    final mirrored = {for (final plugin in local.plugins) plugin.id: plugin};
    final sync = PluginMirrorSync(client: client, store: store);
    for (final entry in remote) {
      final plugin = entry.plugin;
      if (!plugin.hasValidId) continue;
      final known = mirrored[plugin.id];
      if (known != null) {
        final have = present.putIfAbsent(plugin.id, () => <String>{});
        for (final target in entry.builds) {
          if (checked.add((plugin.id, target.version)) &&
              await store.hasInstallableBuild(
                known.localFileFor(target.version),
              )) {
            have.add(target.version);
          }
        }
      }
      if (await sync.hasPendingMedia(plugin, known)) {
        pendingMedia.add(plugin.id);
      }
    }

    return _compare(
      remote: remote,
      local: local,
      presentBuilds: present,
      pendingMedia: pendingMedia,
    );
  }

  static List<_PluginTargets> _prepare(
    List<Map<String, dynamic>> remote,
    String baseUrl,
    List<String> appVersions,
  ) =>
      remote.map((raw) {
        final plugin = StorePlugin.fromApi(raw, baseUrl);
        return (
          plugin: plugin,
          builds: [
            if (plugin.hasValidId)
              for (final target in plugin.targetsFor(appVersions))
                if (target.downloadUrl.isNotEmpty) target,
          ],
        );
      }).toList(growable: false);

  /// ההשוואה עצמה, בלי רשת ובלי דיסק — [presentBuilds] הן, לכל מזהה תוסף,
  /// גרסאות הבילד שהקובץ שלהן נמצא בפועל במראה.
  ///
  /// השאלה הנשאלת כאן היא **בדיוק** זו של `PluginMirrorSync._plan`: לכל
  /// גרסת אוצריא שהכונן נושא נבחר הבילד התואם, ונבדק אם הוא כבר במראה.
  /// כל השוואה "חכמה" אחרת הייתה מדווחת עדכון שסנכרון לא מביא, או להפך.
  static PluginsOnlineStatus compare({
    required List<Map<String, dynamic>> remote,
    required PluginCatalog local,
    required String baseUrl,
    required Map<String, Set<String>> presentBuilds,
    List<String> appVersions = const [],
    Set<String> pendingMedia = const {},
  }) =>
      _compare(
        remote: _prepare(remote, baseUrl, appVersions),
        local: local,
        presentBuilds: presentBuilds,
        pendingMedia: pendingMedia,
      );

  static PluginsOnlineStatus _compare({
    required List<_PluginTargets> remote,
    required PluginCatalog local,
    required Map<String, Set<String>> presentBuilds,
    required Set<String> pendingMedia,
  }) {
    final mirrored = {for (final plugin in local.plugins) plugin.id: plugin};
    final fresh = <String>[];
    final updated = <String>[];
    final missing = <String>[];
    final remoteIds = <String>{};
    int? bytes = 0;
    void fetches(Iterable<PluginVersionEntry> builds) {
      for (final build in builds) {
        final size = build.fileSize;
        bytes = size > 0 && bytes != null ? bytes! + size : null;
      }
    }

    for (final entry in remote) {
      final plugin = entry.plugin;
      remoteIds.add(plugin.id);
      if (!plugin.hasValidId) continue;

      final targets = entry.builds;
      final known = mirrored[plugin.id];
      if (known == null) {
        // תוסף שאין לו אף בילד שירוץ על מה שבכונן אינו "חדש": סנכרון לא
        // יביא לו כלום, וההצצה חייבת לומר את מה שהסנכרון יעשה.
        if (targets.isNotEmpty ||
            plugin.remoteDownloadUrl.isEmpty ||
            pendingMedia.contains(plugin.id)) {
          fresh.add(plugin.name);
          fetches(targets);
        }
        continue;
      }

      final have = presentBuilds[plugin.id] ?? const <String>{};
      final stale = [
        for (final target in targets)
          if (_needsFetch(target, known, have)) target,
      ];
      if (stale.isEmpty && !pendingMedia.contains(plugin.id)) continue;
      fetches(stale);

      // **גרסה חדשה** באתר לעומת **קובץ שחסר** מהכונן. השניים נראים אחרת
      // למשתמש ולכן נספרים בנפרד: בילד שהמראה כבר מתארת כשלה (הגרסה שנרשמה
      // בקטלוג, או בילד שנרשם לו קובץ) ואינו על הדיסק הוא חוסר — נמחק, לא
      // הועתק, או הורדה שנכשלה. כל בילד אחר הוא גרסה חדשה.
      final describes = targets.any(
        (target) =>
            target.version == known.version ||
            known.localFiles.containsKey(target.version),
      );
      if (describes) {
        missing.add(plugin.name);
      } else {
        updated.add(plugin.name);
      }
    }

    final removed = [
      if (remote.isNotEmpty)
        for (final plugin in local.plugins)
          if (!remoteIds.contains(plugin.id)) plugin.name,
    ];

    return PluginsOnlineStatus(
      newPlugins: fresh,
      updatedPlugins: updated,
      missingPlugins: missing,
      removedPlugins: removed,
      totalOnline: remote.length,
      pendingBytes: bytes,
    );
  }

  static bool _needsFetch(
    PluginVersionEntry target,
    StorePlugin known,
    Set<String> have,
  ) {
    if (!have.contains(target.version)) return true;
    final local = known.localFileFor(target.version);
    return !PluginMirrorSync.buildMatches(
      target,
      local?.sourceUrl ?? _recorded(known, target.version)?.downloadUrl ?? '',
      local?.size ?? 0,
      recordedSha256: local?.sha256,
    );
  }

  static PluginVersionEntry? _recorded(StorePlugin known, String version) =>
      known.versionEntries
          .where((entry) => entry.version == version)
          .firstOrNull;
}

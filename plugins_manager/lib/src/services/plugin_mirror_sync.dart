import 'dart:io';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

import '../models/plugin_catalog.dart';
import '../models/plugin_store_category.dart';
import '../models/plugin_store_home.dart';
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

    final strings = AppL10n.strings.pluginsDomain;

    await store.ensureDirs();
    report(PluginSyncProgress(
      phase: PluginSyncPhase.start,
      message: strings.syncLoadingCatalog,
    ));

    final remote = await client.fetchCatalog();
    final previousCatalog = await store.load();
    // רשימה ריקה היא JSON תקין, ולכן `fetchCatalog` לא זורק עליה — אבל
    // לכתוב אותה על קטלוג קיים פירושו למחוק חנות שלמה ממחשב לא-מקוון בגלל
    // תקלה זמנית באתר. נכשלים במקום, והמראה נשארת כפי שהיא.
    if (remote.isEmpty && previousCatalog.plugins.isNotEmpty) {
      throw StateError(strings.syncEmptyCatalogRejected);
    }
    final existing = {
      for (final plugin in previousCatalog.plugins) plugin.id: plugin,
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
        message: strings.syncPlugin(plugin.name, done, total),
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

    final cancelled = isCancelled?.call() ?? false;

    // ביטול אינו מוחק מהקטלוג תוספים שכבר היו במראה: הקבצים שלהם עדיין על
    // הדיסק, ורשימה חלקית הייתה מעלימה אותם מהמחשב המנותק עד סנכרון מלא.
    final syncedIds = {for (final plugin in synced) plugin.id};
    final plugins = <StorePlugin>[
      ...synced,
      if (cancelled)
        for (final plugin in previousCatalog.plugins)
          if (!syncedIds.contains(plugin.id)) plugin,
    ];

    // סנכרון שבוטל באמצע לא מושך מבנה חדש — המבנה הקודם נשאר תואם למה
    // שכבר במראה יותר מרשימה חלקית שנבנתה על חצי קטלוג.
    final structure = cancelled
        ? _StoreStructure(
            home: previousCatalog.home,
            categories: previousCatalog.categories,
          )
        : await _syncStructure(syncedIds, previousCatalog, report);

    final catalog = PluginCatalog(
      lastSync: DateTime.now(),
      plugins: [
        for (final plugin in plugins)
          plugin.copyWith(categorySlugs: structure.slugsOf(plugin.id)),
      ],
      categories: structure.categories,
      home: structure.home,
    );
    await store.save(catalog);

    report(PluginSyncProgress(
      phase: PluginSyncPhase.done,
      message: strings.syncDone,
      current: done,
      total: total,
    ));
    return catalog;
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
    report(PluginSyncProgress(
      phase: PluginSyncPhase.plugin,
      message: strings.syncCategories,
    ));

    late final Map<String, dynamic> home;
    try {
      home = await client.fetchStoreHome();
    } catch (e) {
      report(PluginSyncProgress(
        phase: PluginSyncPhase.warning,
        message: strings.syncStructureFailed('$e'),
      ));
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
        final summary =
            PluginStoreCategory.fromApi(Map<String, dynamic>.from(raw));
        if (summary.slug.isEmpty) continue;
        categories
            .add(await _categoryMembers(summary, syncedIds, previous, report));
      }
    }

    // תשובה תקינה אך חסרת מבנה (אתר ישן, שדה שהשתנה) אינה עילה למחוק את מה
    // שכבר במראה — אותו כלל בדיוק כמו בכשל הבקשה עצמה, למעלה.
    if (categories.isEmpty && previous.categories.isNotEmpty) {
      report(PluginSyncProgress(
        phase: PluginSyncPhase.warning,
        message: strings.syncStructureFailed(strings.syncStructureEmpty),
      ));
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
      report(PluginSyncProgress(
        phase: PluginSyncPhase.warning,
        message: AppL10n.strings.pluginsDomain
            .syncCategoryFailed(summary.name, '$e'),
      ));
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
          message:
              AppL10n.strings.pluginsDomain.syncImageFailed(plugin.name, '$e'),
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
            message: AppL10n.strings.pluginsDomain
                .syncScreenshotFailed(plugin.name, '$e'),
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
        message: AppL10n.strings.pluginsDomain
            .syncPluginFileFailed(plugin.name, '$e'),
      ));
      // הקובץ שבמראה הוא עדיין הישן — הקטלוג חייב לומר את גרסתו. אחרת
      // בדיקת ה-unchanged למעלה תתאים בסנכרון הבא, הקובץ החדש לא יירד לעולם,
      // וההתקנה תגיש בשקט את הישן תחת מספר הגרסה החדש.
      if (previous?.localFile != null && await store.hasLocalFile(previous!)) {
        return plugin.copyWith(version: previous.version);
      }
      return plugin;
    }
  }
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

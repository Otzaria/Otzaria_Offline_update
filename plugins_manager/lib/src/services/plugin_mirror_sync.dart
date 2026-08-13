import 'dart:io';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

import '../models/plugin_catalog.dart';
import '../models/plugin_store_category.dart';
import '../models/plugin_store_home.dart';
import '../models/plugin_sync_outcome.dart';
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
  ///
  /// **הסנכרון מתוכנן לפני שהוא מתחיל**: קודם נקבע לכל תוסף מה בכלל חסר
  /// במראה (השוואת מטא-דאטה + בדיקת קיום קבצים, בלי רשת), ורק מי שחסר לו
  /// משהו נכנס ללולאה. תוסף שכבר מעודכן אינו נוגע ברשת, אינו מדווח
  /// התקדמות, ואינו נספר במונה — כך "3 מתוך 3" הוא באמת מה שיורד עכשיו,
  /// ולא "3 מתוך 40" שרובם רק נבדקים.
  Future<PluginSyncOutcome> sync({
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

    final plans = [
      for (final raw in remote) await _plan(raw, existing),
    ];
    final todo = [
      for (final plan in plans)
        if (plan.hasWork) plan,
    ];

    final fetched = <String, StorePlugin>{};
    final failed = <String>[];
    final total = todo.length;
    var done = 0;

    for (final plan in todo) {
      if (isCancelled?.call() ?? false) break;
      done++;

      var plugin = plan.plugin;
      report(PluginSyncProgress(
        phase: PluginSyncPhase.plugin,
        message: strings.syncPlugin(plugin.name, done, total),
        current: done,
        total: total,
      ));

      await Directory(store.pluginDir(plugin.id)).create(recursive: true);
      plugin = await _syncImages(plan, plugin, report);
      final file = await _syncPluginFile(plan, plugin, report);
      plugin = file.plugin;

      fetched[plugin.id] = plugin;
      if (!file.ok) failed.add(plugin.name);
    }

    final cancelled = isCancelled?.call() ?? false;

    // תוסף שלא הגיע תורו בביטול חייב להישאר על הרשומה הקודמת: הרשומה
    // החדשה מתארת גרסה שקובץ שלה לא ירד, וזה בדיוק מה שהיה גורם לסנכרון
    // הבא לדלג עליו לנצח.
    final plugins = <StorePlugin>[
      for (final plan in plans)
        fetched[plan.plugin.id] ??
            (cancelled && plan.hasWork
                ? (plan.previous ?? plan.plugin)
                : plan.plugin),
    ];
    final syncedIds = {for (final plugin in plugins) plugin.id};

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

    final skipped = plans.length - done;
    report(PluginSyncProgress(
      phase: PluginSyncPhase.done,
      message: strings.syncDoneCounts(done, skipped),
      current: done,
      total: total,
    ));
    return PluginSyncOutcome(
      catalog: catalog,
      fetched: done,
      skipped: skipped,
      failed: failed,
    );
  }

  /// מה חסר לתוסף הזה במראה — כל ההחלטות במקום אחד, ובלי רשת. השלבים
  /// שמורידים בפועל רק מבצעים את מה שנקבע כאן.
  Future<_PluginPlan> _plan(
    Map<String, dynamic> raw,
    Map<String, StorePlugin> existing,
  ) async {
    final remote = StorePlugin.fromApi(raw, client.baseUrl);
    final previous = existing[remote.id];

    // שומרים על מה שכבר יש מקומית, ומעדכנים רק את מה שבאמת ירד עכשיו.
    final plugin = remote.copyWith(
      imagePath: previous?.imagePath,
      screenshotPaths: previous?.screenshotPaths ?? const [],
      localFile: previous?.localFile,
      manifestId: previous?.manifestId,
    );

    return _PluginPlan(
      plugin: plugin,
      previous: previous,
      needsImage: plugin.remoteImageUrl.isNotEmpty &&
          !await _imageUnchanged(plugin, previous),
      needsScreenshots: plugin.remoteScreenshotUrls.isNotEmpty &&
          !await _screenshotsUnchanged(plugin, previous),
      needsFile: plugin.remoteDownloadUrl.isNotEmpty &&
          !await _fileUnchanged(plugin, previous),
      // תוסף שסונכרן לפני שה-manifestId נכנס לקטלוג — מחלצים אותו מהקובץ
      // הקיים בלי להוריד מחדש. קריאת ZIP מקומית, לא רשת.
      needsManifestId:
          plugin.manifestId == null && await store.hasLocalFile(plugin),
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
        message:
            strings.syncStructureFailed(PluginStoreClient.describeError(e)),
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
        message: AppL10n.strings.pluginsDomain.syncCategoryFailed(
            summary.name, PluginStoreClient.describeError(e)),
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

  /// מוריד את מה שהתכנון סימן — התמונה וצילומי המסך, כל אחד בנפרד.
  Future<StorePlugin> _syncImages(
    _PluginPlan plan,
    StorePlugin plugin,
    void Function(PluginSyncProgress) report,
  ) async {
    var result = plugin;
    final dir = store.pluginDir(plugin.id);

    if (plan.needsImage) {
      try {
        final asset = await client.downloadAsset(
          plugin.remoteImageUrl,
          p.join(dir, 'image'),
        );
        result = result.copyWith(imagePath: store.relativePath(asset.path));
      } catch (e) {
        report(PluginSyncProgress(
          phase: PluginSyncPhase.warning,
          message: AppL10n.strings.pluginsDomain
              .syncImageFailed(plugin.name, PluginStoreClient.describeError(e)),
        ));
      }
    }

    if (plan.needsScreenshots) {
      final shotUrls = plugin.remoteScreenshotUrls;
      final shots = <String>[];
      for (var i = 0; i < shotUrls.length; i++) {
        try {
          final asset = await client.downloadAsset(
            shotUrls[i],
            p.join(dir, 'screenshot-$i'),
          );
          shots.add(store.relativePath(asset.path));
        } catch (e) {
          report(PluginSyncProgress(
            phase: PluginSyncPhase.warning,
            message: AppL10n.strings.pluginsDomain.syncScreenshotFailed(
                plugin.name, PluginStoreClient.describeError(e)),
          ));
        }
      }
      if (shots.isNotEmpty) result = result.copyWith(screenshotPaths: shots);
    }

    return result;
  }

  /// אותה כתובת, אותו `updatedAt`, והקובץ עדיין על הדיסק. `updatedAt` נדרש
  /// כי האתר יכול להחליף את תוכן התמונה מתחת לאותה כתובת.
  Future<bool> _imageUnchanged(
          StorePlugin plugin, StorePlugin? previous) async =>
      previous != null &&
      _sameSource(previous.remoteImageUrl, plugin.remoteImageUrl) &&
      previous.updatedAt == plugin.updatedAt &&
      await store.hasAsset(previous.imagePath);

  /// כתובת ריקה בצד הקודם היא **קטלוג ישן** שנכתב לפני שהשדה נוסף, לא
  /// כתובת שהשתנתה. בלי החריג הזה הסנכרון הראשון אחרי העדכון היה מוריד את
  /// כל תמונות החנות מחדש רק כדי למלא שדה — בדיוק ההתנהגות שבאנו לבטל.
  /// `updatedAt` הוא מה שמכריע שם, והשדה נכתב לקטלוג גם בלי הורדה.
  static bool _sameSource(String previous, String current) =>
      previous.isEmpty || previous == current;

  Future<bool> _screenshotsUnchanged(
    StorePlugin plugin,
    StorePlugin? previous,
  ) async {
    if (previous == null ||
        previous.updatedAt != plugin.updatedAt ||
        !(previous.remoteScreenshotUrls.isEmpty ||
            _sameUrls(
                previous.remoteScreenshotUrls, plugin.remoteScreenshotUrls)) ||
        previous.screenshotPaths.length != plugin.remoteScreenshotUrls.length) {
      return false;
    }
    // כולם או כלום: צילום אחד שנעלם מהדיסק מחזיר את כל הסדרה להורדה, כי
    // השמות נגזרים מהאינדקס ברשימה.
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

  /// אותה גרסה, אותה כתובת, והקובץ עדיין על הדיסק — ראו [_sameSource].
  Future<bool> _fileUnchanged(
    StorePlugin plugin,
    StorePlugin? previous,
  ) async =>
      previous != null &&
      _sameSource(previous.remoteDownloadUrl, plugin.remoteDownloadUrl) &&
      previous.version == plugin.version &&
      previous.localFile != null &&
      await store.hasLocalFile(previous);

  /// קובץ התוסף עצמו עלול להיות גדול — יורד רק כשהתכנון סימן שהוא חסר או
  /// השתנה. `ok: false` = התכנון ביקש להוריד וההורדה נכשלה; המתקשר סופר.
  Future<({StorePlugin plugin, bool ok})> _syncPluginFile(
    _PluginPlan plan,
    StorePlugin plugin,
    void Function(PluginSyncProgress) report,
  ) async {
    final previous = plan.previous;

    if (!plan.needsFile) {
      // קטלוג ישן בלי manifestId — מחלצים מהקובץ שכבר במראה, בלי רשת.
      if (plan.needsManifestId && plugin.localFile != null) {
        final id = PluginManifestReader.readId(
          store.absolutePath(plugin.localFile!.relativePath),
        );
        if (id != null) {
          return (plugin: plugin.copyWith(manifestId: id), ok: true);
        }
      }
      return (plugin: plugin, ok: true);
    }

    try {
      final asset = await client.downloadAsset(
        plugin.remoteDownloadUrl,
        p.join(store.pluginDir(plugin.id), 'plugin'),
        preferredExt: '.otzplugin',
      );
      return (
        plugin: plugin.copyWith(
          localFile: PluginLocalFile(
            relativePath: store.relativePath(asset.path),
            fileName: asset.originalName ?? '${plugin.name}${asset.ext}',
            ext: asset.ext,
            size: asset.size,
          ),
          manifestId: PluginManifestReader.readId(asset.path),
        ),
        ok: true,
      );
    } catch (e) {
      report(PluginSyncProgress(
        phase: PluginSyncPhase.warning,
        message: AppL10n.strings.pluginsDomain.syncPluginFileFailed(
            plugin.name, PluginStoreClient.describeError(e)),
      ));
      // הקובץ שבמראה הוא עדיין הישן — הקטלוג חייב לומר את גרסתו. אחרת
      // התכנון היה מדלג עליו בסנכרון הבא, הקובץ החדש לא יירד לעולם,
      // וההתקנה תגיש בשקט את הישן תחת מספר הגרסה החדש.
      if (previous?.localFile != null && await store.hasLocalFile(previous!)) {
        return (plugin: plugin.copyWith(version: previous.version), ok: false);
      }
      return (plugin: plugin, ok: false);
    }
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
    required this.needsFile,
    required this.needsManifestId,
  });

  /// הרשומה המרוחקת אחרי מיזוג הנתיבים המקומיים שכבר במראה.
  final StorePlugin plugin;
  final StorePlugin? previous;

  final bool needsImage;
  final bool needsScreenshots;
  final bool needsFile;

  /// חילוץ `manifestId` מקובץ שכבר במראה — עבודה מקומית, בלי רשת, אבל
  /// כן סיבה לא לדלג על התוסף לגמרי.
  final bool needsManifestId;

  bool get hasWork =>
      needsImage || needsScreenshots || needsFile || needsManifestId;
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

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
  });

  /// ארבעה תוספים בו-זמנית. ראו [runPooled]: הקבצים כאן קטנים והזמן הולך
  /// על סיבובי הלוך-חזור, ולכן זה בדיוק המקום שבו מקביליות משתלמת.
  static const int defaultMaxConcurrentPlugins = 4;

  final PluginStoreClient client;
  final PluginMirrorStore store;

  /// כמה תוספים מסונכרנים בו-זמנית. כל אחד מהם עדיין מוריד את הנכסים שלו
  /// בטור, כך שהתקרה חוסמת גם את מספר החיבורים בפועל.
  final int maxConcurrentPlugins;

  /// זורק [PluginStoreException] רק אם רשימת התוספים עצמה לא נטענה. כשל
  /// בנכס בודד מדווח כ-[PluginSyncPhase.warning] והסנכרון ממשיך.
  ///
  /// **הסנכרון מתוכנן לפני שהוא מתחיל**: קודם נקבע לכל תוסף מה בכלל חסר
  /// במראה (השוואת מטא-דאטה + בדיקת קיום קבצים, בלי רשת), ורק מי שחסר לו
  /// משהו נכנס ללולאה. תוסף שכבר מעודכן אינו נוגע ברשת, אינו מדווח
  /// התקדמות, ואינו נספר במונה — כך "3 מתוך 3" הוא באמת מה שיורד עכשיו,
  /// ולא "3 מתוך 40" שרובם רק נבדקים.
  ///
  /// [appVersions] הן גרסאות אוצריא שהכונן נושא (היציבה, ואיתה הלא-יציבה
  /// כשהיא חדשה ממנה). לכל אחת יורד הבילד שתואם לה — ראו
  /// `plugin_compatibility.dart`. רשימה ריקה = אין מול מה לסנן, ואז יורד
  /// הבילד החי, כמו לפני שהתאימות נכנסה.
  Future<PluginSyncOutcome> sync({
    List<String> appVersions = const [],
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
      for (final raw in remote) await _plan(raw, existing, appVersions),
    ];
    final todo = [
      for (final plan in plans)
        if (plan.hasWork) plan,
    ];

    final fetched = <String, StorePlugin>{};
    final failed = <String>[];
    final total = todo.length;
    var done = 0;

    // התוספים מסונכרנים במקביל: כל אחד הוא כמה קבצים קטנים שרובם המתנה
    // לשרת, ובטור ההמתנות האלה מצטברות לרוב זמן הסנכרון. בדיקת הביטול
    // עברה לתוך המשימה — משימה שממתינה בתור בזמן שבוטלה פשוט לא מתחילה.
    await runPooled(
      [
        for (final plan in todo)
          () async {
            if (isCancelled?.call() ?? false) return;
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
            final files = await _syncPluginFiles(plan, plugin, report);
            plugin = files.plugin;

            fetched[plugin.id] = plugin;
            if (!files.ok) failed.add(plugin.name);
          },
      ],
      maxConcurrent: maxConcurrentPlugins,
    );

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

    // בילד שכבר אינו בקטלוג (גרסת אוצריא שבכונן זזה) נמחק מהדיסק — אחרת
    // כל עדכון של אוצריא היה מוסיף שכבת בילדים ישנים על הכונן הנייד.
    // **לא בביטול**: שם הקטלוג הוא הישן, והניקוי היה מוחק את מה שכן ירד.
    if (!cancelled) {
      for (final plugin in catalog.plugins) {
        await store.pruneUnusedFiles(plugin);
      }
    }

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
      // ליומן בלבד — ראו [PluginSyncOutcome.incompatible].
      incompatible: [
        for (final plan in plans)
          if (plan.isIncompatible)
            '${plan.plugin.name} (${plan.plugin.lowestSupportedApp ?? '?'})',
      ],
    );
  }

  /// מה חסר לתוסף הזה במראה — כל ההחלטות במקום אחד, ובלי רשת. השלבים
  /// שמורידים בפועל רק מבצעים את מה שנקבע כאן.
  Future<_PluginPlan> _plan(
    Map<String, dynamic> raw,
    Map<String, StorePlugin> existing,
    List<String> appVersions,
  ) async {
    final remote = StorePlugin.fromApi(raw, client.baseUrl);
    final previous = existing[remote.id];

    // שומרים על מה שכבר יש מקומית, ומעדכנים רק את מה שבאמת ירד עכשיו.
    var plugin = remote.copyWith(
      imagePath: previous?.imagePath,
      screenshotPaths: previous?.screenshotPaths ?? const [],
      localFiles: previous?.localFiles,
      manifestId: previous?.manifestId,
    );

    // בילד לכל גרסת אוצריא שהכונן נושא. בילד שכבר במראה נשמר, וזה שאינו
    // מבוקש עוד נושר מהקטלוג — הקובץ שלו נמחק בסוף הסנכרון.
    final keep = <String, PluginLocalFile>{};
    final missing = <PluginVersionEntry>[];
    final targets = plugin.targetsFor(appVersions);
    for (final target in targets) {
      if (target.downloadUrl.isEmpty) continue;
      if (await _buildUnchanged(target, plugin, previous)) {
        keep[target.version] = plugin.localFileFor(target.version)!;
      } else {
        missing.add(target);
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
      // אין אף בילד תואם — לא כשל, אבל כן דבר שכדאי שיהיה ביומן.
      isIncompatible: targets.isEmpty && plugin.remoteDownloadUrl.isNotEmpty,
      // תוסף שסונכרן לפני שה-manifestId נכנס לקטלוג — מחלצים אותו מהקובץ
      // הקיים בלי להוריד מחדש. קריאת ZIP מקומית, לא רשת.
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

  /// הבילד הזה כבר במראה: קובץ רשום לגרסה שלו, הקובץ עדיין על הדיסק,
  /// והכתובת שממנה הוא ירד לא השתנתה מתחתיו — ראו [_sameSource].
  Future<bool> _buildUnchanged(
    PluginVersionEntry target,
    StorePlugin plugin,
    StorePlugin? previous,
  ) async {
    if (!await store.hasFileFor(plugin, target.version)) return false;
    final known = previous?.versionEntries
        .where((entry) => entry.version == target.version)
        .firstOrNull;
    return known == null || _sameSource(known.downloadUrl, target.downloadUrl);
  }

  /// מוריד את הבילדים שהתכנון סימן — אחד לכל גרסת אוצריא שהכונן נושא
  /// ושהבילד שלה עוד לא במראה. `ok: false` = לפחות אחד מהם נכשל.
  Future<({StorePlugin plugin, bool ok})> _syncPluginFiles(
    _PluginPlan plan,
    StorePlugin plugin,
    void Function(PluginSyncProgress) report,
  ) async {
    if (plan.missingBuilds.isEmpty) {
      // קטלוג ישן בלי manifestId — מחלצים מקובץ שכבר במראה, בלי רשת.
      final known = plugin.anyLocalFile;
      if (plan.needsManifestId && known != null) {
        final id =
            PluginManifestReader.readId(store.absolutePath(known.relativePath));
        if (id != null) {
          return (plugin: plugin.copyWith(manifestId: id), ok: true);
        }
      }
      return (plugin: plugin, ok: true);
    }

    final files = Map.of(plugin.localFiles);
    var manifestId = plugin.manifestId;
    var ok = true;

    for (final target in plan.missingBuilds) {
      try {
        final asset = await client.downloadAsset(
          target.downloadUrl,
          store.pluginFilePathNoExt(plugin.id, target.version),
          preferredExt: '.otzplugin',
        );
        files[target.version] = PluginLocalFile(
          relativePath: store.relativePath(asset.path),
          fileName: asset.originalName ?? '${plugin.name}${asset.ext}',
          ext: asset.ext,
          size: asset.size,
        );
        manifestId ??= PluginManifestReader.readId(asset.path);
      } catch (e) {
        ok = false;
        report(PluginSyncProgress(
          phase: PluginSyncPhase.warning,
          message: AppL10n.strings.pluginsDomain.syncPluginFileFailed(
              plugin.name, PluginStoreClient.describeError(e)),
        ));
      }
    }

    // בילד שנכשל אינו נרשם, ולכן הסנכרון הבא ינסה אותו שוב. אבל אז גם אין
    // מה להתקין — ולכן בילד ישן שכבר יושב במראה נשאר בקטלוג במקום להימחק
    // ב-[PluginMirrorStore.pruneUnusedFiles]. עדיף בילד ישן שרץ מכלום.
    final previous = plan.previous;
    if (!ok && previous != null) {
      for (final entry in previous.localFiles.entries) {
        if (files.containsKey(entry.key)) continue;
        if (await store.hasAsset(entry.value.relativePath)) {
          files[entry.key] = entry.value;
        }
      }
    }

    return (
      plugin: plugin.copyWith(localFiles: files, manifestId: manifestId),
      ok: ok,
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

  bool get hasWork =>
      needsImage ||
      needsScreenshots ||
      missingBuilds.isNotEmpty ||
      needsManifestId;
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

import 'package:flutter/foundation.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:plugins_manager/plugins_manager.dart';

import '../services/app_logger.dart';
import 'progress_notifier.dart';

enum PluginsModuleStatus { idle, loading, ready, syncing, error }

/// סינון לפי סטטוס התוסף בחנות (`stable` / `beta` / `experimental`).
enum PluginStatusFilter { all, stable, beta, experimental }

/// שלושת המסכים של החנות באתר, במקום שלושת ה-routes שלה:
/// `/plugins` (דף בית אצור), `/plugins/all` ו-`/plugins/category/<slug>`.
enum PluginStorePage { home, all, category }

/// עוטף את [PluginsManager] כמצב הניתן לצפייה עבור מסך החנות — טעינת
/// הקטלוג המקומי, הורדה יזומה מהאתר, סינון, שמירת קובץ והתקנה ישירה.
///
/// [load] בלבד נקרא בפתיחה: הוא קורא מהתיקייה המקומית וסורק את ההתקנה של
/// אוצריא, ולא נוגע ברשת. [sync] היא הפעולה היחידה שדורשת אינטרנט.
class PluginsModuleController extends ChangeNotifier with ProgressNotifier {
  PluginsModuleController({
    required String mirrorRootDir,
    Future<String?> Function()? otzariaLaunchPath,
  })
  // תיקיית התוספים של אוצריא נגזרת מההתקנה שהלאנצ'ר זיהה ואינה ניתנת
  // להגדרה — ראו AppPaths: אין נתיבים בהגדרות.
  : _manager = PluginsManager(
          resolveMirrorDir: () async => mirrorRootDir,
          otzariaLaunchPath: otzariaLaunchPath,
        );

  final PluginsManager _manager;

  PluginsModuleStatus status = PluginsModuleStatus.idle;
  String? errorMessage;

  List<StorePlugin> plugins = const [];

  /// קטגוריות החנות כפי שנאצרו באתר, בסדר שלו. ריק במראה ישנה.
  List<PluginStoreCategory> categories = const [];

  /// הכותרת והתקציר של דף הבית של החנות, כפי שירדו מהאתר.
  PluginStoreHome home = PluginStoreHome.empty;

  /// `manifestId -> גרסה מותקנת`. setter ולא שדה: התוצרים הממוזנים למטה
  /// ([filtered], [featured], [homeCategories]…) נגזרים ממנו, והצבה ישירה
  /// הייתה משאירה אותם על התשובה הקודמת.
  Map<String, String> get installed => _installed;
  set installed(Map<String, String> value) {
    _installed = value;
    _invalidateDerived();
  }

  Map<String, String> _installed = const {};
  DateTime? lastSync;

  /// שורש קובצי החנות במראה — ממנו נבנים נתיבי התמונות המוחלטים.
  String? pluginsDir;

  // ── ניווט ─────────────────────────────────────────────────────────────────

  /// המסך המוצג. החנות נפתחת בדף הבית האצור, בדיוק כמו באתר; מראה בלי
  /// קטגוריות (סנכרון ישן) נופלת ל"כל התוספים" — אין לה דף בית להציג.
  PluginStorePage view = PluginStorePage.home;

  /// ה-slug של הקטגוריה הפתוחה, כשה-[view] הוא [PluginStorePage.category].
  String? openCategorySlug;

  // ── סינון (מסך "כל התוספים" בלבד, כמו באתר) ───────────────────────────────
  String search = '';

  /// החנות נפתחת על "הכול" — המשתמש בא לראות מה קיים, לא רק את היציב.
  PluginStatusFilter statusFilter = PluginStatusFilter.all;
  String? tagFilter;

  /// הצג רק מה שלא מותקן או שיש לו עדכון — פועל כברירת מחדל, כמו בחנות
  /// המקורית: המשתמש בא לעדכן, לא לגלול על מה שכבר מותקן.
  bool hideInstalled = true;

  // ── בדיקה קלה ברשת ────────────────────────────────────────────────────────

  /// מה נמצא בחנות שברשת לעומת המראה, או `null` כשטרם נבדק בהרצה הזו.
  PluginsOnlineStatus? onlineStatus;
  String? onlineCheckError;
  DateTime? onlineCheckedAt;

  /// `true` כשיש בחנות תוסף חדש או גרסה חדשה שאינם במראה המקומית.
  bool get hasOnlineUpdate => onlineStatus?.hasUpdates ?? false;

  // ── סנכרון ────────────────────────────────────────────────────────────────

  /// מה הסנכרון האחרון באמת עשה (כמה ירדו, כמה דולגו), או `null` לפני
  /// שרץ אחד בהרצה הזו.
  PluginSyncOutcome? lastSyncOutcome;

  String? syncMessage;
  double? syncProgress;
  final List<String> syncWarnings = [];

  /// הטעינה שרצה כרגע, אם רצה — [refreshInstalled] ממתינה לה במקום לדלג
  /// עליה: בעלייה שתיהן יוצאות לדרך כמעט יחד.
  Future<void>? _loading;

  /// טוען את הקטלוג המקומי וסורק את התוספים המותקנים. ללא רשת.
  Future<void> load() => _loading = _load();

  Future<void> _load() async {
    status = PluginsModuleStatus.loading;
    errorMessage = null;
    notifyListeners();

    try {
      final snapshot = await _manager.load();
      plugins = snapshot.catalog.plugins;
      categories = snapshot.catalog.categories;
      home = snapshot.catalog.home;
      lastSync = snapshot.catalog.lastSync;
      installed = snapshot.installed;
      pluginsDir = snapshot.pluginsDir;
      _invalidateDerived();
      _settleView();
      status = PluginsModuleStatus.ready;
    } catch (e, st) {
      status = PluginsModuleStatus.error;
      errorMessage = e.toString();
      AppLogger.instance.error('טעינת קטלוג התוספים נכשלה', e, st);
    }
    notifyListeners();
  }

  /// סורק מחדש **רק** את התוספים המותקנים, בלי לטעון את הקטלוג ובלי להעביר
  /// את המסך למצב טעינה. נקרא אחרי שזיהוי אוצריא התעדכן: תיקיית התוספים
  /// נגזרת מנתיב ההתקנה, וסריקה שרצה לפניו הסתכלה במקום אחר.
  Future<void> refreshInstalled() async {
    await _loading;
    if (status != PluginsModuleStatus.ready) return;

    try {
      final scanned = await _manager.scanInstalled();
      if (mapEquals(installed, scanned)) return;
      installed = scanned;
      _invalidateDerived();
      notifyListeners();
    } catch (e, st) {
      // כישלון כאן אינו הופך את החנות לשגויה — היא כבר טעונה ומוצגת.
      AppLogger.instance.error('סריקת התוספים המותקנים נכשלה', e, st);
    }
  }

  /// שואל את האתר אם יש תוסף חדש או גרסה חדשה — **בקשה קלה אחת**, בלי
  /// להוריד קובץ. כשל (בעיקר "אין רשת") הוא מצב תקין ונשמר ב-
  /// [onlineCheckError], בדיוק כמו בשאר המודולים.
  Future<void> checkOnline() async {
    onlineCheckError = null;
    notifyListeners();

    try {
      onlineStatus = await _manager.peekOnlineUpdates();
    } catch (e) {
      onlineStatus = null;
      onlineCheckError = e.toString();
      // ראו `LibraryModuleController.checkOnline` — בלי stack trace בכוונה.
      AppLogger.instance.info('בדיקת עדכונים ברשת (תוספים) לא הצליחה: $e');
    }
    onlineCheckedAt = DateTime.now();
    notifyListeners();
  }

  /// מסנכרן את הקטלוג והקבצים מהאתר אל המראה. דורש אינטרנט.
  ///
  /// [isCancelled] נבדק בין תוסף לתוסף (הקבצים עצמם קטנים) — ראו
  /// `PluginMirrorSync.sync`.
  Future<void> sync({bool Function()? isCancelled}) async {
    status = PluginsModuleStatus.syncing;
    errorMessage = null;
    syncMessage = AppL10n.strings.plugins.syncingOverlayStarting;
    syncProgress = null;
    syncWarnings.clear();
    notifyListeners();

    try {
      final outcome = await _manager.sync(
          isCancelled: isCancelled,
          onProgress: (progress) {
            syncMessage = progress.message;
            if (progress.phase == PluginSyncPhase.warning) {
              syncWarnings.add(progress.message);
            } else if (progress.fraction != null) {
              syncProgress = progress.fraction;
            }
            // הסנכרון מדווח פעמים רבות בשנייה (נכס אחר נכס) — מדולל, כמו
            // שאר מדי ההתקדמות.
            notifyProgress();
          });
      lastSyncOutcome = outcome;
      AppLogger.instance.info('סנכרון התוספים: ${outcome.fetched} ירדו, '
          '${outcome.skipped} דולגו, ${syncWarnings.length} אזהרות'
          '${syncWarnings.isEmpty ? '' : ':\n${syncWarnings.join('\n')}'}');
      // המראה זה עתה נמשכה מהאתר — התשובה הישנה של הבדיקה הקלה כבר לא
      // מתארת אותה, והשארתה הייתה מציגה "יש עדכונים" אחרי שהם כבר ירדו.
      // כשקובץ תוסף לא ירד המראה עדיין חסרה אותו, ולכן התשובה נשארת — וכך
      // גם בסנכרון שבוטל, שהשאיר בדיוק את אותו חוסר.
      if (!outcome.hasFailures && !(isCancelled?.call() ?? false)) {
        onlineStatus = PluginsOnlineStatus.empty;
        onlineCheckedAt = DateTime.now();
        onlineCheckError = null;
      }
      await load();
    } catch (e, st) {
      status = PluginsModuleStatus.error;
      errorMessage = e.toString();
      AppLogger.instance.error('סנכרון חנות התוספים נכשל', e, st);
      notifyListeners();
    }
  }

  // ── פעולות על תוסף בודד ───────────────────────────────────────────────────

  StorePlugin? byId(String id) {
    for (final plugin in plugins) {
      if (plugin.id == id) return plugin;
    }
    return null;
  }

  PluginInstallStatus statusOf(StorePlugin plugin) =>
      plugin.statusAgainst(installed);

  /// הגרסה המותקנת של התוסף, או null אם אינו מותקן.
  String? installedVersionOf(StorePlugin plugin) =>
      plugin.manifestId == null ? null : installed[plugin.manifestId];

  String suggestedFileName(StorePlugin plugin) =>
      _manager.suggestedFileName(plugin);

  /// נתיב מוחלט לנכס (תמונה / צילום מסך) שנשמר בקטלוג כנתיב יחסי.
  String? assetPath(String? relativePath) {
    final root = pluginsDir;
    if (root == null || relativePath == null || relativePath.isEmpty) {
      return null;
    }
    return PluginMirrorStore.resolveAgainst(root, relativePath);
  }

  Future<PluginInstallResult> saveCopy(StorePlugin plugin, String destPath) =>
      _manager.saveCopy(plugin, destPath);

  Future<PluginInstallResult> directInstall(StorePlugin plugin) async {
    final result = await _manager.directInstall(plugin);
    if (!result.success) {
      AppLogger.instance.error(
        'התקנה ישירה של ${plugin.name} נכשלה: ${result.error}',
      );
    }
    return result;
  }

  Future<PluginInstallResult> openHomepage(String url) =>
      _manager.openExternalUrl(url);

  // ── סינון ─────────────────────────────────────────────────────────────────

  void setSearch(String value) {
    if (search == value) return;
    search = value;
    _invalidateDerived();
    notifyListeners();
  }

  void setStatusFilter(PluginStatusFilter value) {
    if (statusFilter == value) return;
    statusFilter = value;
    _invalidateDerived();
    notifyListeners();
  }

  // ── ניווט בין מסכי החנות ──────────────────────────────────────────────────

  void showHome() => _goTo(PluginStorePage.home);

  /// "כל התוספים" — הרשימה השטוחה עם הסינון. [query] מגיע מתיבת החיפוש
  /// שבדף הבית: באתר היא מובילה לדף חיפוש צד-שרת, וכאן לסינון המקומי.
  void showAllPlugins({String? query}) {
    if (query != null) search = query;
    _goTo(PluginStorePage.all);
  }

  void showCategory(String slug) {
    openCategorySlug = slug;
    _goTo(PluginStorePage.category);
  }

  void _goTo(PluginStorePage target) {
    if (target != PluginStorePage.category) openCategorySlug = null;
    view = target;
    _invalidateDerived();
    notifyListeners();
  }

  /// מיישר את המסך המוצג מול הקטלוג שנטען זה עתה: בלי קטגוריות אין דף בית,
  /// וקטגוריה שנעלמה מהחנות לא נשארת פתוחה.
  void _settleView() {
    if (view == PluginStorePage.category && openCategory == null) {
      openCategorySlug = null;
      view = PluginStorePage.all;
    }
    if (view == PluginStorePage.home && !hasCuratedHome) {
      view = PluginStorePage.all;
    }
  }

  void setTagFilter(String? value) {
    if (tagFilter == value) return;
    tagFilter = value;
    _invalidateDerived();
    notifyListeners();
  }

  void setHideInstalled(bool value) {
    if (hideInstalled == value) return;
    hideInstalled = value;
    _invalidateDerived();
    notifyListeners();
  }

  // ── תוצרים מחושבים, ממוזנים ───────────────────────────────────────────────
  // כל אלה נקראו ישירות מ-`build`, ולכן חושבו מחדש בכל בנייה של המסך — כולל
  // בכל דיווח התקדמות של הורדה. `filtered` לבדו הוא `statusOf` לכל תוסף
  // ו-`allTags` הוא מיון. הם משתנים רק כשהקטלוג או הסינון משתנים, ולכן
  // נשמרים עד ל-[_invalidateDerived].
  List<StorePlugin>? _filtered;
  List<String>? _allTags;
  List<StorePlugin>? _updatable;
  List<StorePlugin>? _featured;
  Map<String, StorePlugin>? _byId;
  List<PluginStoreCategory>? _homeCategories;
  bool? _hasCuratedHome;

  void _invalidateDerived() {
    _filtered = null;
    _allTags = null;
    _updatable = null;
    _featured = null;
    _byId = null;
    _homeCategories = null;
    _hasCuratedHome = null;
  }

  /// האם התוסף עובר את מתג "רק מה שלא מותקן" שבשורה העליונה. המתג הוא
  /// תוספת של הלאנצ'ר ולכן חל על **כל** המסכים, גם על האצירה.
  bool _passesInstalledFilter(StorePlugin plugin) =>
      !hideInstalled || statusOf(plugin) != PluginInstallStatus.upToDate;

  /// "כל התוספים" — חיפוש, סטטוס ותגית, מעל מתג ההתקנה.
  List<StorePlugin> get filtered => _filtered ??= plugins.where((plugin) {
        if (!plugin.matchesQuery(search)) return false;
        if (statusFilter != PluginStatusFilter.all &&
            plugin.status != statusFilter.name) {
          return false;
        }
        if (tagFilter != null && !plugin.tags.contains(tagFilter)) return false;
        return _passesInstalledFilter(plugin);
      }).toList(growable: false);

  Map<String, StorePlugin> get _pluginsById =>
      _byId ??= {for (final plugin in plugins) plugin.id: plugin};

  /// התוספים הנבחרים, בסדר האצירה של האתר — `/api/plugins` מחזיר אותם
  /// ראשונים, ולכן סדר הקטלוג הוא סדר האצירה.
  List<StorePlugin> get featured => _featured ??= plugins
      .where((p) => p.isFeatured && _passesInstalledFilter(p))
      .toList(growable: false);

  /// הקטגוריות שמקבלות שורה בדף הבית ונשאר בהן מה להציג אחרי מתג ההתקנה.
  /// ממוזן כמו שאר התוצרים: הוא מריץ [pluginsIn] לכל קטגוריה, ודף הבית קורא
  /// לו מ-`build` — כלומר גם בכל דיווח התקדמות של סנכרון.
  List<PluginStoreCategory> get homeCategories => _homeCategories ??= [
        for (final category in categories)
          if (category.showOnHome && pluginsIn(category).isNotEmpty) category,
      ];

  /// האם **קיים** דף בית אצור. נמדד על המבנה עצמו ולא על מה שנשאר אחרי
  /// הסינון — אחרת כיבוי כל הכרטיסים ע"י המתג היה נראה כמו חנות ריקה.
  bool get hasCuratedHome =>
      _hasCuratedHome ??= plugins.any((p) => p.isFeatured) ||
          categories.any((c) => c.showOnHome && c.pluginIds.isNotEmpty);

  PluginStoreCategory? get openCategory {
    final slug = openCategorySlug;
    if (slug == null) return null;
    return categoryBySlug(slug);
  }

  PluginStoreCategory? categoryBySlug(String slug) {
    for (final category in categories) {
      if (category.slug == slug) return category;
    }
    return null;
  }

  /// תוספי הקטגוריה בסדר הידני שנקבע באתר, אחרי מתג ההתקנה. [limit] הוא
  /// `homeLimit` של שורת דף-הבית. מזהה שאין לו תוסף בקטלוג מדולג.
  List<StorePlugin> pluginsIn(PluginStoreCategory category, {int? limit}) {
    final result = <StorePlugin>[];
    for (final id in category.pluginIds) {
      final plugin = _pluginsById[id];
      if (plugin == null || !_passesInstalledFilter(plugin)) continue;
      result.add(plugin);
      if (limit != null && result.length >= limit) break;
    }
    return result;
  }

  /// שם התצוגה של קטגוריה לפי ה-slug שנשמר על התוסף.
  String categoryName(String slug) => categoryBySlug(slug)?.name ?? slug;

  /// כותרת החנות. ברירת המחדל זהה לזו שבאתר, למראה שסונכרנה לפני
  /// שהטקסטים האלה נכנסו — או כשמנהלי האתר השאירו אותם ריקים.
  String get homeTitle => home.title.isEmpty
      ? AppL10n.strings.plugins.catalogTitleFallback
      : home.title;

  String get homeSubtitle => home.subtitle.isEmpty
      ? AppL10n.strings.plugins.catalogSubtitleFallback
      : home.subtitle;

  List<String> get allTags => _allTags ??= () {
        final tags = <String>{};
        for (final plugin in plugins) {
          tags.addAll(plugin.tags);
        }
        return tags.toList()..sort();
      }();

  /// תוספים שמותקנים אצל המשתמש בגרסה ישנה מזו שבחנות.
  List<StorePlugin> get updatablePlugins => _updatable ??= plugins
      .where((p) => statusOf(p) == PluginInstallStatus.updateAvailable)
      .toList(growable: false);

  int get installedCount => installed.length;

  @override
  void dispose() {
    _manager.dispose();
    super.dispose();
  }
}

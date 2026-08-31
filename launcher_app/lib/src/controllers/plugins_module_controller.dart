import 'dart:async';

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
    this.mirroredAppVersions,
    this.installedAppVersion,
    this.ensureAppVersionsKnown,
    this.installWatchInterval = const Duration(seconds: 1),
    this.installWatchTimeout = const Duration(minutes: 5),
  })
  // תיקיית התוספים של אוצריא נגזרת מההתקנה שהלאנצ'ר זיהה ואינה ניתנת
  // להגדרה — ראו AppPaths: אין נתיבים בהגדרות.
  : _manager = PluginsManager(
          resolveMirrorDir: () async => mirrorRootDir,
          otzariaLaunchPath: otzariaLaunchPath,
        );

  final PluginsManager _manager;

  /// גרסאות אוצריא שהכונן נושא — היציבה, ואיתה הלא-יציבה כשהיא חדשה ממנה.
  /// **ההורדה** מביאה בילד תוסף לכל אחת מהן, כדי שהמחשב המנותק ימצא בילד
  /// שירוץ אצלו בכל אחד משני המקרים.
  final Future<List<String>> Function()? mirroredAppVersions;

  /// גרסת אוצריא שבמחשב **הזה**, ולפיה נבחר איזה בילד יוצג ויותקן.
  final Future<String?> Function()? installedAppVersion;

  /// ממתין לכך ששתי הקריאות שמעליי יידעו לענות. הן נשענות על הבדיקה
  /// המקומית של מודול התוכנה, שרצה בעלייה **במקביל** להצצה ברשת —
  /// ראו [_appVersions].
  final Future<void> Function()? ensureAppVersionsKnown;

  /// כל כמה זמן נסרקת תיקיית התוספים אחרי מסירה לאוצריא, ועד מתי. מוזרקים
  /// רק כדי שבדיקות לא יחכו בזמן אמת.
  final Duration installWatchInterval;
  final Duration installWatchTimeout;

  /// התשובה האחרונה של [installedAppVersion]. `null` = לא ידוע (אוצריא לא
  /// זוהתה), ואז אין מול מה לסנן והבילד החי הוא שנבחר.
  String? appVersion;

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
      // לפני הקטלוג: הגרסה היא שקובעת איזה בילד כל תוסף מציג, והנגזרות
      // למטה מחושבות מיד אחרי ההצבה של `installed`.
      appVersion = await installedAppVersion?.call();
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
      // גם הגרסה מתעדכנת כאן: היא נקראת מאותה התקנה שזה עתה זוהתה, ובלעדיה
      // החנות הייתה ממשיכה להציג בילדים לפי גרסה שכבר לא נכונה.
      final version = await installedAppVersion?.call();
      if (!mapEquals(installed, scanned) || version != appVersion) {
        appVersion = version;
        installed = scanned;
        _invalidateDerived();
        notifyListeners();
      }
      // אחרי ההצבה, לא לפניה: מי שמאזין להודעת הסיום קורא מיד את המפה
      // החדשה. גם סריקה שלא שינתה כלום מגיעה לכאן — פסק הזמן נסגר בה.
      _settleInstallWatch(scanned);
    } catch (e, st) {
      // כישלון כאן אינו הופך את החנות לשגויה — היא כבר טעונה ומוצגת.
      AppLogger.instance.error('סריקת התוספים המותקנים נכשלה', e, st);
    }
  }

  // ── המתנה להתקנה שנמסרה לאוצריא ───────────────────────────────────────────
  // ההתקנה עצמה קורית בחלון של אוצריא, ולכן הרגע שבו היא נגמרה מגיע אלינו
  // רק מהדיסק: תיקיית ההתקנה נסרקת שוב ושוב עד שהגרסה שם משתנה. בלי זה
  // המשתמש היה צריך ללחוץ "בדיקה מחדש" כדי לראות מה כבר עודכן.

  /// תוספים שנמסרו לאוצריא וטרם אושרו בסריקה, לפי `id` של התוסף בחנות.
  final Map<String, _PendingInstall> _pendingInstalls = {};
  Timer? _installWatch;

  /// שמות התוספים שאוצריא סיימה להתקין. `AppShell` מאזין ומציג הודעה —
  /// גם כשהמשתמש כבר עבר ממסך החנות למסך אחר.
  final StreamController<String> _installDone =
      StreamController<String>.broadcast();
  Stream<String> get installCompletions => _installDone.stream;

  /// האם ממתינים כרגע לאוצריא שתסיים התקנה כלשהי.
  bool get isAwaitingInstall => _pendingInstalls.isNotEmpty;

  bool isAwaitingInstallOf(StorePlugin plugin) =>
      _pendingInstalls.containsKey(plugin.id);

  /// מתחיל להמתין להתקנה של [plugin] באוצריא. ציבורי כדי שבדיקות יוכלו
  /// להריץ את ההמתנה בלי למסור URL למערכת ההפעלה.
  void watchForInstall(StorePlugin plugin) {
    final manifestId = plugin.manifestId;
    // בלי מזהה מניפסט אין מה לזהות בסריקה — התוסף לא ייספר כמותקן ממילא.
    if (manifestId == null) return;

    _pendingInstalls[plugin.id] = _PendingInstall(
      name: plugin.name,
      manifestId: manifestId,
      versionBefore: installed[manifestId],
      deadline: DateTime.now().add(installWatchTimeout),
    );
    _installWatch ??= Timer.periodic(installWatchInterval, _tick);
    notifyListeners();
  }

  void _tick(Timer _) {
    // חנות שאינה מוכנה (טעינה / סנכרון / שגיאה) לא נסרקת, אבל המועד שעבר
    // חייב לסגור את ההמתנה גם אז — אחרת הטיימר רץ עד סוף ההרצה.
    if (status == PluginsModuleStatus.ready) {
      unawaited(refreshInstalled());
    } else {
      _settleInstallWatch(installed);
    }
  }

  /// סוגר את מה שהסריקה הוכיחה: גרסה שהשתנתה = ההתקנה הסתיימה, ומועד
  /// שעבר = הפסקנו לחכות (המשתמש ביטל בחלון של אוצריא, או שלא סיים).
  void _settleInstallWatch(Map<String, String> scanned) {
    if (_pendingInstalls.isEmpty) return;

    final now = DateTime.now();
    final countBefore = _pendingInstalls.length;
    final done = <String>[];
    _pendingInstalls.removeWhere((id, pending) {
      if (scanned[pending.manifestId] != pending.versionBefore) {
        done.add(pending.name);
        return true;
      }
      return now.isAfter(pending.deadline);
    });

    if (_pendingInstalls.length == countBefore) return; // עוד מחכים

    if (_pendingInstalls.isEmpty) {
      _installWatch?.cancel();
      _installWatch = null;
    }
    // גם פסק זמן משנה את מצב השורה בדיאלוג, והסריקה עצמה לא בהכרח תודיע.
    notifyListeners();
    for (final name in done) {
      AppLogger.instance.info('אוצריא סיימה להתקין את $name');
      if (!_installDone.isClosed) _installDone.add(name);
    }
  }

  /// שואל את האתר אם יש תוסף חדש או גרסה חדשה — **בקשה קלה אחת**, בלי
  /// להוריד קובץ. כשל (בעיקר "אין רשת") הוא מצב תקין ונשמר ב-
  /// [onlineCheckError], בדיוק כמו בשאר המודולים.
  Future<void> checkOnline() async {
    onlineCheckError = null;
    notifyListeners();

    try {
      // אותן גרסאות שהסנכרון יקבל — אחרת ההצצה מדווחת על עדכון שההורדה
      // לא תביא, או שותקת על אחד שכן.
      onlineStatus = await _manager.peekOnlineUpdates(
        appVersions: await _appVersions(),
      );
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
          appVersions: await _appVersions(),
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
      // ליומן בלבד: הבחירה עצמה שקופה למשתמש, אבל "למה התוסף הזה לא על
      // הכונן" חייב להיות ניתן לענות עליו.
      if (outcome.incompatible.isNotEmpty) {
        AppLogger.instance.info(
          'תוספים בלי גרסה שתואמת לאוצריא שבכונן: '
          '${outcome.incompatible.join(', ')}',
        );
      }
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

  /// הגרסאות שההורדה וההצצה מסננות לפיהן: מה שיושב במראת התוכנה, ואיתן
  /// הגרסה שמותקנת כאן בפועל — מחשב שנשאר על גרסה ישנה יותר מזו שבכונן
  /// צריך גם הוא בילד שירוץ אצלו. רשימה ריקה = אין מול מה לסנן.
  ///
  /// **ממתין תחילה לבדיקה המקומית**: רשימה ריקה מפני שהיא עוד לא הספיקה
  /// אינה "אין מול מה לסנן" אלא תשובה שגויה — ההצצה הייתה שואלת על הבילד
  /// החי, מדווחת "חסר" על מה שאינו תואם לכונן, וההורדה שאחריה לא הייתה
  /// מביאה דבר. כך הנדנוד חוזר אחרי כל הורדה.
  Future<List<String>> _appVersions() async {
    await ensureAppVersionsKnown?.call();
    final installedVersion = await installedAppVersion?.call();
    final versions = <String>{
      ...?await mirroredAppVersions?.call(),
      if (installedVersion != null) installedVersion,
    };
    return versions.where((v) => v.isNotEmpty).toList(growable: false);
  }

  // ── פעולות על תוסף בודד ───────────────────────────────────────────────────

  StorePlugin? byId(String id) {
    for (final plugin in plugins) {
      if (plugin.id == id) return plugin;
    }
    return null;
  }

  PluginInstallStatus statusOf(StorePlugin plugin) =>
      plugin.statusAgainst(installed, appVersion: appVersion);

  /// הגרסה המותקנת של התוסף, או null אם אינו מותקן.
  String? installedVersionOf(StorePlugin plugin) =>
      plugin.manifestId == null ? null : installed[plugin.manifestId];

  /// הבילד שיותקן במחשב הזה — לא בהכרח האחרון שפורסם. `null` = אין בילד
  /// שתואם לגרסת אוצריא שכאן.
  PluginVersionEntry? targetOf(StorePlugin plugin) =>
      plugin.installTarget(appVersion);

  /// מספר הגרסה להצגה: של הבילד שיותקן, ובחוסר — של החי בקטלוג.
  String versionOf(StorePlugin plugin) =>
      targetOf(plugin)?.version ?? plugin.version;

  /// האם הקובץ של הבילד שיותקן בכלל ירד למראה.
  bool hasFileFor(StorePlugin plugin) =>
      plugin.localFileFor(targetOf(plugin)?.version) != null;

  String suggestedFileName(StorePlugin plugin) =>
      _manager.suggestedFileName(plugin, appVersion: appVersion);

  /// נתיב מוחלט לנכס (תמונה / צילום מסך) שנשמר בקטלוג כנתיב יחסי.
  String? assetPath(String? relativePath) {
    final root = pluginsDir;
    if (root == null || relativePath == null || relativePath.isEmpty) {
      return null;
    }
    return PluginMirrorStore.resolveAgainst(root, relativePath);
  }

  Future<PluginInstallResult> saveCopy(StorePlugin plugin, String destPath) =>
      _manager.saveCopy(plugin, destPath, appVersion: appVersion);

  /// מוסר את התוסף לאוצריא. ההצלחה כאן היא של ה**מסירה** בלבד — ההתקנה
  /// נגמרת בחלון של אוצריא, ולכן מתחילים מיד להמתין לה על הדיסק.
  Future<PluginInstallResult> directInstall(StorePlugin plugin) async {
    final result = await _manager.directInstall(plugin, appVersion: appVersion);
    if (result.success) {
      watchForInstall(plugin);
    } else {
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
    _installWatch?.cancel();
    unawaited(_installDone.close());
    _manager.dispose();
    super.dispose();
  }
}

/// תוסף שנמסר לאוצריא וממתין לאישור מהדיסק. [versionBefore] הוא מה שהיה
/// מותקן ברגע המסירה — כל שינוי ממנו הוא ההוכחה שההתקנה הסתיימה.
class _PendingInstall {
  const _PendingInstall({
    required this.name,
    required this.manifestId,
    required this.versionBefore,
    required this.deadline,
  });

  final String name;
  final String manifestId;
  final String? versionBefore;
  final DateTime deadline;
}

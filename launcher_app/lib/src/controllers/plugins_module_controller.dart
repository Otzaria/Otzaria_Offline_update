import 'dart:async';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:library_manager/library_manager.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart' show OtzariaCapabilities;
import 'package:plugins_manager/plugins_manager.dart';

import '../services/app_logger.dart';
import '../services/coalescing_loader.dart';
import '../services/known_plugins_store.dart';
import '../services/storage_failure.dart';
import '../services/store_app_destination_store.dart';
import '../services/store_search.dart';
import 'dispose_guard.dart';
import 'progress_notifier.dart';

enum PluginsModuleStatus { idle, loading, ready, syncing, error }

typedef PluginsCatalogOnlineAnswers = ({
  PluginsOnlineStatus? status,
  String? checkError,
  DateTime? checkedAt,
  bool closedForShabbat,
});

typedef StoreAppOnlineAnswers = ({
  StoreAppRelease? release,
  String? checkError,
  DateTime? checkedAt,
});

/// סינון לפי יציבות: "ניסיוני" כולל גם את מה שהאתר מסמן כבטא.
enum PluginStatusFilter { all, stable, experimental }

/// סטטוס של גרסה שעוד לא יציבה. האתר שולח `beta`/`experimental`; השאר —
/// לחומרה. סטטוס לא מוכר אינו נספר כאן וגם לא כיציב: מופיע רק תחת "הכול".
bool isExperimentalPluginStatus(String status) => const {
      'beta',
      'experimental',
      'alpha',
      'rc',
      'preview',
    }.contains(status.toLowerCase());

/// סיכום "עדכון הכול": מה נשלח, מה נכשל ולמה, והאם נעצר באמצע.
typedef PluginUpdateAllOutcome = ({
  List<StorePlugin> sent,
  List<({StorePlugin plugin, String? error})> failed,
  bool stopped,
});

/// הבורר שליד החיפוש: הכול / מותקנים / לא מותקנים.
enum PluginInstallFilter { all, installed, notInstalled }

enum PluginSortMode { recommended, newest, updated }

/// המרווח בין שתי מסירות רצופות של עדכוני תוספים.
///
/// כל מסירה היא `otzaria://plugin/install-local`. כשאוצריא סגורה, הראשונה
/// מפעילה אותה, ושנייה מוקדמת מדי הייתה פותחת מופע נוסף.
const Duration pluginUpdateDeliverySpacing = Duration(milliseconds: 1500);

class PluginsModuleController extends ChangeNotifier
    with DisposeGuard, ProgressNotifier {
  PluginsModuleController({
    required String mirrorRootDir,
    String? stateDir,
    Future<String?> Function()? otzariaLaunchPath,
    Future<String?> Function(String dataRoot)? locatePluginsDb,
    this.mirroredAppVersions,
    this.installedAppVersion,
    this.ensureAppVersionsKnown,
    this.installWatchInterval = const Duration(seconds: 1),
    this.installWatchTimeout = const Duration(minutes: 5),
    http.Client? httpClient,
    PluginsManager? manager,
  })  : _manager = manager ??
            PluginsManager(
              resolveMirrorDir: () async => mirrorRootDir,
              otzariaLaunchPath: otzariaLaunchPath,
              locatePluginsDb: locatePluginsDb,
              httpClient: httpClient,
            ),
        mirrorDirs = PluginsManager.mirrorDirsIn(mirrorRootDir),
        _known = stateDir == null ? null : KnownPluginsStore(stateDir),
        _destination =
            stateDir == null ? null : StoreAppDestinationStore(stateDir);

  static Future<String?> locateOtzariaPluginsDb(String dataRoot) async {
    final settings = await const OtzariaSettingsReader().read(dataRoot);
    return locateUserStateDb(
      dataRoot: dataRoot,
      databasesPathSetting: settings?.databasesPath,
      libraryPathSetting: settings?.libraryPath,
      fileName: pluginsRegistryFileName,
    );
  }

  final PluginsManager _manager;

  final List<String> mirrorDirs;

  /// זיכרון "אילו תוספים כבר נראו כאן". `null` כשאין תיקיית כתיבה — אז אין
  /// הודעות על תוספים חדשים בכלל, ולא הודעה שחוזרת בכל הרצה.
  final KnownPluginsStore? _known;
  final StoreAppDestinationStore? _destination;

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

  List<StorePlugin> get plugins => _plugins;
  set plugins(List<StorePlugin> value) {
    _plugins = value;
    _searchTexts.clear();
    _invalidateDerived();
  }

  List<StorePlugin> _plugins = const [];

  /// קטגוריות החנות כפי שנאצרו באתר, בסדר שלו. ריק במראה ישנה.
  List<PluginStoreCategory> categories = const [];

  /// `manifestId -> גרסה מותקנת`. setter ולא שדה: הוא מאפס את מה שנגזר
  /// ממנו ([filtered], [updatablePlugins]…).
  Map<String, String> get installed => _installed;
  set installed(Map<String, String> value) {
    _installed = value;
    _invalidateDerived();
  }

  Map<String, String> _installed = const {};

  Set<String> get disabledInOtzaria => _disabled;
  Set<String> get developmentInOtzaria => _development;
  Set<String> _disabled = const {};
  Set<String> _development = const {};

  void _applyInstalledState(InstalledPluginsState state) {
    _disabled = state.disabled;
    _development = state.development;
    installed = state.versions;
  }

  DateTime? lastSync;

  /// שורש קובצי החנות במראה — ממנו נבנים נתיבי התמונות המוחלטים.
  String? pluginsDir;

  // ── תוכנת החנות העצמאית ───────────────────────────────────────────────────

  /// קובץ ההרצה של תוכנת החנות שיושב במראה, או `null` כשעדיין לא הורד.
  /// נטען ב-[load] יחד עם הקטלוג, כדי שהכפתור יידע אם יש מה להעתיק.
  MirroredStoreApp? storeApp;

  /// יש גם תוכנה וגם תוספים — רק אז יש מה להעתיק.
  bool get canExportStoreApp => storeApp != null && plugins.isNotEmpty;

  /// התיקייה שאליה הועתקה החנות במחשב הזה, כל עוד החנות עדיין יושבת בה.
  String? rememberedStoreDir;
  String? _rememberedStoreTag;

  /// החנות שהועתקה קודם ישנה מזו שבמראה — אפשר לעדכן אותה במקום.
  bool get storeAppUpdatePending =>
      canExportStoreApp &&
      rememberedStoreDir != null &&
      _rememberedStoreTag != storeApp!.release.tagName;

  Future<void> _loadStoreDestination() async {
    rememberedStoreDir = null;
    final saved = await _destination?.load();
    // כונן רשת או נייד שנרדם לא יתקע את הטעינה.
    if (saved == null ||
        !await StoreAppExporter.hasExistingStore(saved.dir)
            .timeout(const Duration(seconds: 2), onTimeout: () => false)) {
      return;
    }
    rememberedStoreDir = saved.dir;
    _rememberedStoreTag = saved.tag;
  }

  /// הגרסה החדשה שהבדיקה הקלה מצאה, או `null` כשאין חדש. **היא לבדה
  /// מרשה להוריד** — ראו [syncStoreApp].
  StoreAppRelease? storeAppOnline;
  DateTime? storeAppCheckedAt;
  String? storeAppCheckError;

  /// `true` כשיש ברשת גרסה של תוכנת החנות שאינה במראה.
  bool get hasStoreAppOnlineUpdate => storeAppOnline != null;

  /// ההעתקה שרצה כרגע, לתצוגת ההתקדמות.
  String? exportMessage;
  double? exportProgress;
  bool isExporting = false;

  // ── סינון ─────────────────────────────────────────────────────────────────
  String search = '';

  /// ה-slug של שבב הקטגוריה שנבחר, או `null` ל"הכול".
  String? categoryFilter;

  /// החנות נפתחת על "הכול" — המשתמש בא לראות מה קיים, לא רק את היציב.
  PluginStatusFilter statusFilter = PluginStatusFilter.all;
  String? tagFilter;
  PluginInstallFilter installFilter = PluginInstallFilter.all;
  PluginSortMode sortMode = PluginSortMode.recommended;

  // ── בדיקה קלה ברשת ────────────────────────────────────────────────────────

  /// מה נמצא בחנות שברשת לעומת המראה, או `null` כשטרם נבדק בהרצה הזו.
  PluginsOnlineStatus? onlineStatus;
  String? onlineCheckError;
  DateTime? onlineCheckedAt;

  /// [onlineCheckError] הוא סגירת האתר בשבת — לא נבדק, אבל גם לא כשל.
  bool onlineClosedForShabbat = false;

  /// `true` כשיש בחנות תוסף חדש או גרסה חדשה שאינם במראה המקומית.
  ///
  /// **הקטלוג בלבד** — [hasOnlineUpdate] מוסיף לו את תוכנת החנות. השניים
  /// נפרדים כי הם מדלגים בנפרד ב-`downloadAll`: סנכרון הקטלוג הוא עשרות
  /// קריאות לאתר, והורדת התוכנה היא קובץ אחד מגיטהאב.
  bool get hasCatalogOnlineUpdate => onlineStatus?.hasUpdates ?? false;

  /// `true` כשמשהו בחנות התחדש ברשת — הקטלוג או תוכנת החנות. זה מה שדף
  /// הבית קורא: בלי תוכנת החנות כאן, גרסה חדשה שלה לא הייתה מציגה בכלל
  /// את כפתור ההורדה.
  bool get hasOnlineUpdate => hasCatalogOnlineUpdate || hasStoreAppOnlineUpdate;

  PluginsCatalogOnlineAnswers get catalogOnlineAnswers => (
        status: onlineStatus,
        checkError: onlineCheckError,
        checkedAt: onlineCheckedAt,
        closedForShabbat: onlineClosedForShabbat,
      );

  void restoreCatalogOnlineAnswers(PluginsCatalogOnlineAnswers answers) {
    onlineStatus = answers.status;
    onlineCheckError = answers.checkError;
    onlineCheckedAt = answers.checkedAt;
    onlineClosedForShabbat = answers.closedForShabbat;
    notifyListeners();
  }

  StoreAppOnlineAnswers get storeAppOnlineAnswers => (
        release: storeAppOnline,
        checkError: storeAppCheckError,
        checkedAt: storeAppCheckedAt,
      );

  void restoreStoreAppOnlineAnswers(StoreAppOnlineAnswers answers) {
    storeAppOnline = answers.release;
    storeAppCheckError = answers.checkError;
    storeAppCheckedAt = answers.checkedAt;
    notifyListeners();
  }

  // ── סנכרון ────────────────────────────────────────────────────────────────

  /// מה הסנכרון האחרון באמת עשה (כמה ירדו, כמה דולגו), או `null` לפני
  /// שרץ אחד בהרצה הזו.
  PluginSyncOutcome? lastSyncOutcome;

  String? shabbatNotice;

  /// סנכרון שההורדה ביקשה ונדחה — כשל של הרכיב, לא שגיאה בכרטיס של החנות.
  String? syncRefusal;

  bool get lastSyncFailed =>
      errorMessage != null ||
      syncRefusal != null ||
      shabbatNotice != null ||
      storageFull ||
      (lastSyncOutcome?.hasFailures ?? false);

  /// החריג שהפיל את הסנכרון האחרון, או כשל הכתיבה של תוכנת החנות (שאינו קטלני
  /// אבל אומר שהכונן מלא). מתאפסים בתחילת כל אחד מהם.
  Object? syncCause;
  Object? storeAppCause;
  StorageFullException? get storageFailure =>
      findStorageFull(syncCause) ?? findStorageFull(storeAppCause);
  bool get storageFull => storageFailure != null;

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
      // ההמתנה לבדיקה המקומית קודמת לכול: לפניה נתיב ההתקנה אינו ידוע והסריקה
      // מסתכלת בתיקיית ברירת המחדל, וגרסת אוצריא ריקה מכשירה **כל** בילד
      // שבמראה — כולל זה שירד עבור הגרסה השנייה שהכונן נושא. משם "יש עדכון"
      // על תוסף שכבר עדכני, ורשימה שמתהפכת כשהזיהוי מגיע. ראו [_appVersions].
      await ensureAppVersionsKnown?.call();
      // לפני הקטלוג: הגרסה היא שקובעת איזה בילד כל תוסף מציג, והנגזרות
      // למטה מחושבות מיד אחרי ההצבה של `installed`.
      appVersion = await installedAppVersion?.call();
      final snapshot = await _manager.load();
      plugins = snapshot.catalog.plugins;
      categories = snapshot.catalog.categories;
      lastSync = snapshot.catalog.lastSync;
      _applyInstalledState(
        InstalledPluginsState(
          versions: snapshot.installed,
          disabled: snapshot.disabled,
          development: snapshot.development,
        ),
      );
      pluginsDir = snapshot.pluginsDir;
      storeApp = await _manager.loadStoreApp();
      await _loadStoreDestination();
      await _loadKnown();
      // קטגוריה או תגית שנעלמו מהחנות לא נשארות בחורה.
      if (categoryFilter case final slug? when categoryBySlug(slug) == null) {
        categoryFilter = null;
      }
      _invalidateDerived();
      if (tagFilter case final tag? when !allTags.contains(tag)) {
        tagFilter = null;
        _invalidateDerived();
      }
      status = PluginsModuleStatus.ready;
    } catch (e, st) {
      status = PluginsModuleStatus.error;
      errorMessage = e.toString();
      AppLogger.instance.error('טעינת קטלוג התוספים נכשלה', e, st);
    }
    notifyListeners();
  }

  late final CoalescingLoader _installedScan = CoalescingLoader(
    _refreshInstalled,
    isActive: () => !_installDone.isClosed,
  );

  Future<void> refreshInstalled() => _installedScan.run();

  Future<void> refreshAppVersion() async {
    final resolve = installedAppVersion;
    if (resolve == null) return;
    final version = await resolve();
    if (isDisposed || version == appVersion) return;
    appVersion = version;
    _invalidateDerived();
    notifyListeners();
  }

  Future<void> _refreshInstalled() async {
    await _loading;
    if (status != PluginsModuleStatus.ready) return;

    try {
      await refreshAppVersion();
      final scanned = await _manager.scanInstalled();
      if (!mapEquals(installed, scanned.versions) ||
          !setEquals(_disabled, scanned.disabled) ||
          !setEquals(_development, scanned.development)) {
        _applyInstalledState(scanned);
        _invalidateDerived();
        notifyListeners();
      }
      _settleInstallWatch(scanned.versions, reports: await _installReports());
    } catch (e, st) {
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

  /// שמות התוספים שאוצריא סיימה להתקין. `AppSession` מאזין ומציג הודעה —
  /// גם כשהמשתמש כבר עבר ממסך החנות למסך אחר.
  final StreamController<String> _installDone =
      StreamController<String>.broadcast();
  Stream<String> get installCompletions => _installDone.stream;

  final StreamController<({String name, PluginInstallReport report})>
      _installRejected = StreamController.broadcast();
  Stream<({String name, PluginInstallReport report})> get installRejections =>
      _installRejected.stream;

  /// האם ממתינים כרגע לאוצריא שתסיים התקנה כלשהי.
  bool get isAwaitingInstall => _pendingInstalls.isNotEmpty;

  bool isAwaitingInstallOf(StorePlugin plugin) =>
      _pendingInstalls.containsKey(plugin.id);

  /// מתחיל להמתין להתקנה של [plugin] באוצריא. ציבורי כדי שבדיקות יוכלו
  /// להריץ את ההמתנה בלי למסור URL למערכת ההפעלה.
  void watchForInstall(
    StorePlugin plugin, {
    String? deliveredPath,
    DateTime? handedOffAt,
  }) {
    final manifestId = plugin.manifestId;
    // בלי מזהה מניפסט אין מה לזהות בסריקה — התוסף לא ייספר כמותקן ממילא.
    if (manifestId == null) return;

    _pendingInstalls[plugin.id] = _PendingInstall(
      name: plugin.name,
      manifestId: manifestId,
      versionBefore: installed[manifestId],
      deadline: DateTime.now().add(installWatchTimeout),
      deliveredPath: deliveredPath,
      handedOffAt: handedOffAt ?? DateTime.now(),
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
  Future<Map<String, PluginInstallReport>> _installReports() async {
    final watched = {
      for (final entry in _pendingInstalls.entries)
        if (entry.value.deliveredPath != null) entry.key: entry.value,
    };
    if (watched.isEmpty) return const {};
    final root = await _manager.otzariaDataRoot();
    if (root == null) return const {};
    final capabilities = await OtzariaCapabilities.read(root);
    if ((capabilities?.pluginInstallResults ?? 0) < 1) return const {};
    final reports = await PluginInstallResults.read(root);
    return {
      for (final entry in watched.entries)
        if (PluginInstallResults.latestFor(
          reports,
          entry.value.deliveredPath!,
          entry.value.handedOffAt,
        )
            case final report?)
          entry.key: report,
    };
  }

  void _settleInstallWatch(
    Map<String, String> scanned, {
    Map<String, PluginInstallReport> reports = const {},
  }) {
    if (_pendingInstalls.isEmpty) return;

    final now = DateTime.now();
    final countBefore = _pendingInstalls.length;
    final done = <String>[];
    final rejected = <({String name, PluginInstallReport report})>[];
    _pendingInstalls.removeWhere((id, pending) {
      final report = reports[id];
      if (report != null) {
        if (report.succeeded) {
          done.add(pending.name);
        } else {
          rejected.add((name: pending.name, report: report));
        }
        return true;
      }
      if (scanned[pending.manifestId] != pending.versionBefore) {
        done.add(pending.name);
        return true;
      }
      return !now.isBefore(pending.deadline);
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
    for (final entry in rejected) {
      AppLogger.instance.info(
        'אוצריא לא התקינה את ${entry.name}: ${entry.report.outcome}'
        '${entry.report.message == null ? '' : ' (${entry.report.message})'}',
      );
      if (!_installRejected.isClosed) _installRejected.add(entry);
    }
  }

  /// שואל את האתר אם יש תוסף חדש או גרסה חדשה — **בקשה קלה אחת**, בלי
  /// להוריד קובץ. כשל (בעיקר "אין רשת") הוא מצב תקין ונשמר ב-
  /// [onlineCheckError], בדיוק כמו בשאר המודולים.
  /// שתי בקשות קלות לשני שרתים שונים — הקטלוג מ-otzaria.org ותוכנת החנות
  /// מגיטהאב. במקביל, ועם דיווח כשל נפרד: אתר שאינו עונה אינו אומר דבר על
  /// הזמינות של השני, ודגל כשל משותף היה מבטל את הדילוג של שניהם.
  Future<void> checkOnline() async {
    // הכשל הקודם נשאר עד התשובה החדשה — ראו `LibraryModuleController.checkOnline`.
    notifyListeners();

    // אותן גרסאות שהסנכרון יקבל — אחרת ההצצה מדווחת על עדכון שההורדה
    // לא תביא, או שותקת על אחד שכן.
    final appVersions = await _appVersions();
    await Future.wait([_peekCatalog(appVersions), _peekStoreApp()]);
    notifyListeners();
  }

  Future<void> _peekCatalog(List<String> appVersions) async {
    try {
      onlineStatus = await _manager.peekOnlineUpdates(appVersions: appVersions);
      onlineCheckError = null;
      onlineClosedForShabbat = false;
    } on PluginStoreShabbatException catch (e) {
      onlineStatus = null;
      onlineCheckError = e.message;
      onlineClosedForShabbat = true;
      AppLogger.instance.info('בדיקת עדכונים ברשת (תוספים): האתר סגור בשבת');
    } catch (e) {
      onlineStatus = null;
      onlineCheckError = e.toString();
      onlineClosedForShabbat = false;
      // ראו `LibraryModuleController.checkOnline` — בלי stack trace בכוונה.
      AppLogger.instance.info('בדיקת עדכונים ברשת (תוספים) לא הצליחה: $e');
    }
    onlineCheckedAt = DateTime.now();
  }

  Future<void> _peekStoreApp() async {
    try {
      storeAppOnline = await _manager.peekStoreApp();
      storeAppCheckError = null;
    } catch (e) {
      storeAppOnline = null;
      storeAppCheckError = e.toString();
      AppLogger.instance.info('בדיקת גרסת תוכנת החנות לא הצליחה: $e');
    }
    storeAppCheckedAt = DateTime.now();
  }

  /// מסנכרן את הקטלוג והקבצים מהאתר אל המראה. דורש אינטרנט. `false` —
  /// נדחה, ראו [syncBlockedReason]; סנכרון שכבר רץ מצורף ואינו נדחה.
  ///
  /// [isCancelled] נבדק בין תוסף לתוסף (הקבצים עצמם קטנים) — ראו
  /// `PluginMirrorSync.sync`.
  Future<bool> sync({
    bool Function()? isCancelled,
    bool forDownload = false,
  }) {
    if (_syncRun case final running?) return running;
    if (syncBlockedReason(forDownload: forDownload) case final reason?) {
      // בהורדה — כשל רגיל של הרכיב (`lastSyncFailed`), לא חריג שמפיל את הזרימה.
      if (forDownload) {
        syncRefusal = reason;
        notifyListeners();
      }
      return Future.value(false);
    }
    return _syncRun =
        _sync(isCancelled: isCancelled).then((_) => true).whenComplete(() {
      _syncRun = null;
      if (!_installDone.isClosed) notifyListeners();
    });
  }

  /// למה סנכרון לא יתחיל עכשיו, או `null`. [forDownload] — ההורדה הכוללת
  /// מבקשת, והמראה כבר שמורה לה.
  String? syncBlockedReason({bool forDownload = false}) {
    // "עדכון הכול" משחרר את המראה בין מסירה למסירה, אבל עוד לא סיים.
    final busy = isReadingMirror ||
        isUpdatingAll ||
        (!forDownload && (syncBlockedElsewhere?.call() ?? false));
    return busy ? AppL10n.strings.plugins.syncBlockedSnack : null;
  }

  /// הסנכרון העצמאי מחליף קבצים במראה ובוחר גרסאות לפי המתקין שבה —
  /// `AppSession` עונה כאן אם הורדה או "עדכון כאן" אוחזים בהם.
  bool Function()? syncBlockedElsewhere;

  /// הורדה, ניקוי או החזרה לאחור כותבים עכשיו את מראה התוספים.
  bool Function()? mirrorWrittenElsewhere;
  Future<bool>? _syncRun;

  bool get isSyncing => _syncRun != null;

  Future<void> _sync({bool Function()? isCancelled}) async {
    status = PluginsModuleStatus.syncing;
    syncRefusal = null;
    errorMessage = null;
    shabbatNotice = null;
    lastSyncOutcome = null;
    syncCause = null;
    storeAppCause = null;
    syncMessage = AppL10n.strings.plugins.syncingOverlayStarting;
    syncProgress = null;
    syncWarnings.clear();
    await Future<void>.value();
    notifyListeners();

    try {
      final outcome = await _manager.sync(
        appVersions: await _appVersions(),
        isCancelled: isCancelled,
        onProgress: (progress) {
          syncMessage = progress.message;
          if (progress.phase == PluginSyncPhase.plugin &&
              progress.current != null) {
            AppLogger.instance.info(progress.message);
          }
          if (progress.phase == PluginSyncPhase.warning) {
            syncWarnings.add(progress.message);
          } else if (progress.fraction != null) {
            syncProgress = progress.fraction;
          }
          // הסנכרון מדווח פעמים רבות בשנייה (נכס אחר נכס) — מדולל, כמו
          // שאר מדי ההתקדמות.
          notifyProgress();
        },
      );
      lastSyncOutcome = outcome;
      syncCause = outcome.storageFailure;
      AppLogger.instance.info(
        'סנכרון התוספים: ${outcome.fetched} ירדו, '
        '${outcome.skipped} דולגו, ${syncWarnings.length} אזהרות'
        '${syncWarnings.isEmpty ? '' : ':\n${syncWarnings.join('\n')}'}',
      );
      // ליומן בלבד: הבחירה עצמה שקופה למשתמש, אבל "למה התוסף הזה לא על
      // הכונן" חייב להיות ניתן לענות עליו.
      if (outcome.versionMismatches.isNotEmpty) {
        AppLogger.instance.warn(
          'גרסת המניפסט שונה מזו שבאתר: '
          '${outcome.versionMismatches.join(', ')}',
        );
      }
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
      if (!outcome.provesMissingContent && !(isCancelled?.call() ?? false)) {
        onlineStatus = PluginsOnlineStatus.empty;
        onlineCheckedAt = DateTime.now();
        onlineCheckError = null;
        onlineClosedForShabbat = false;
      } else if (!hasCatalogOnlineUpdate) {
        // "אין שינוי" מלפני הסנכרון כבר אינו נכון: חסרה מדיה או קובץ.
        onlineStatus = null;
        onlineCheckedAt = null;
      }
      await load();
    } on PluginStoreShabbatException catch (e) {
      shabbatNotice = e.message;
      AppLogger.instance.info('סנכרון חנות התוספים נדחה: האתר סגור בשבת');
      await load();
    } catch (e, st) {
      status = PluginsModuleStatus.error;
      errorMessage = e.toString();
      syncCause = e;
      if (!hasCatalogOnlineUpdate) {
        onlineStatus = null;
        onlineCheckedAt = null;
      }
      AppLogger.instance.error('סנכרון חנות התוספים נכשל', e, st);
      notifyListeners();
    }
  }

  /// מוריד את תוכנת החנות — **אך ורק** כשהבדיקה הקלה מצאה גרסה חדשה. בלי
  /// [storeAppOnline] אין כאן שום פנייה לרשת: הורדה שלא התחדש בה דבר אינה
  /// נוגעת בגיטהאב בכלל.
  ///
  /// **לעולם אינו קטלני** — הוא נוסע בצד של הורדת התוספים, וכשל שלו אינו
  /// סיבה לסמן הורדה שהצליחה ככושלת: הכפתור פשוט יישאר על הגרסה הקודמת עד
  /// ההורדה הבאה. כמו מבנה החנות (`syncStructureFailed`), האזהרה ליומן.
  Future<void> syncStoreApp() async {
    syncCause = null;
    storeAppCause = null;
    final release = storeAppOnline;
    if (release == null) return;

    try {
      storeApp = await _manager.syncStoreApp(release);
      AppLogger.instance.info('תוכנת החנות ירדה: ${release.tagName}');
      // ירדה — ולכן התשובה הישנה של הבדיקה כבר אינה מתארת את המראה.
      storeAppOnline = null;
      storeAppCheckedAt = DateTime.now();
      storeAppCheckError = null;
    } catch (e) {
      if (isStorageFull(e)) storeAppCause = e;
      AppLogger.instance.info('הורדת תוכנת החנות לא הצליחה: $e');
    }
    notifyListeners();
  }

  /// מעתיק את תוכנת החנות ואת כל התוספים שבמראה ליעד שהמשתמש בחר. **בלי
  /// רשת.** זורק בכישלון; המסך הוא שמציג את ההודעה.
  Future<StoreAppExportOutcome> exportStoreApp(String destinationDir) {
    if (_exportRun == null) {
      // מסירה ברקע ("עדכון כאן" שהסתיים מוקדם) הייתה נכשלת מכאן והלאה.
      final reason = mirrorReadBlockedReason ??
          (_delivering.isNotEmpty || isDeliveryRunActive
              ? AppL10n.strings.plugins.actionsBlockedDelivering
              : null);
      if (reason != null) return Future.error(PluginMirrorBusy(reason));
    }
    return _exportRun ??=
        _exportStoreApp(destinationDir).whenComplete(() => _exportRun = null);
  }

  Future<StoreAppExportOutcome>? _exportRun;

  Future<StoreAppExportOutcome> _exportStoreApp(String destinationDir) async {
    isExporting = true;
    exportMessage = AppL10n.strings.pluginsDomain.exportPreparing;
    exportProgress = null;
    notifyListeners();

    try {
      final outcome = await _manager.exportStoreApp(
        destinationDir,
        onProgress: (progress) {
          exportMessage = progress.message;
          exportProgress = progress.fraction;
          // תוסף אחר תוסף — מדולל כמו שאר מדי ההתקדמות.
          notifyProgress();
        },
      );
      final tag = storeApp?.release.tagName;
      if (tag != null) {
        await _destination?.record(dir: destinationDir, tag: tag);
        rememberedStoreDir = destinationDir;
        _rememberedStoreTag = tag;
      }
      return outcome;
    } finally {
      isExporting = false;
      exportMessage = null;
      exportProgress = null;
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

  StorePlugin? byId(String id) => _pluginsById[id];

  PluginInstallStatus statusOf(StorePlugin plugin) => plugin.statusAgainst(
        installed,
        appVersion: appVersion,
        development: _development,
      );

  bool isDisabledInOtzaria(StorePlugin plugin) =>
      _disabled.contains(plugin.manifestId);

  bool isDevelopmentInOtzaria(StorePlugin plugin) =>
      _development.contains(plugin.manifestId);

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

  Map<String, dynamic> get diagnostics => {
        'appVersion': appVersion,
        'installed': Map<String, String>.of(installed),
        'lastSync': lastSync?.toIso8601String(),
        'inventory': [
          for (final plugin in plugins)
            {
              'id': plugin.id,
              'name': plugin.name,
              'manifestId': plugin.manifestId,
              'catalogVersion': plugin.version,
              'compatibleWith': plugin.compatibleWith,
              'maxAppVersion': plugin.maxAppVersion,
              'mirroredVersions': plugin.localFiles.keys.toList(),
              'targetVersion': targetOf(plugin)?.version,
              'status': statusOf(plugin).name,
              'directInstall': canDirectInstall(plugin),
              'development': isDevelopmentInOtzaria(plugin),
            },
        ],
      };

  bool canDirectInstall(StorePlugin plugin) =>
      targetOf(plugin)?.supportsDirectInstall ?? plugin.supportsDirectInstall;

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

  Future<PluginInstallResult> saveCopy(
    StorePlugin plugin,
    String destPath,
  ) async {
    if (mirrorReadBlockedReason case final reason?) {
      return PluginInstallResult.failure(reason);
    }
    _savingCopies++;
    notifyListeners();
    try {
      return await _manager.saveCopy(plugin, destPath, appVersion: appVersion);
    } finally {
      _savingCopies--;
      if (!isDisposed) notifyListeners();
    }
  }

  int _savingCopies = 0;

  /// למה אי אפשר לקרוא מהמראה עכשיו, או `null`: סנכרון או הורדה כותבים בה.
  String? get mirrorReadBlockedReason {
    final t = AppL10n.strings.plugins;
    if (isSyncing) return t.actionsBlockedSyncing;
    if (mirrorWrittenElsewhere?.call() ?? false) {
      return t.actionsBlockedElsewhere;
    }
    return null;
  }

  /// מסירה, שמירת עותק או העתקת החנות קוראות עכשיו מהמראה.
  bool get isReadingMirror =>
      _delivering.isNotEmpty ||
      _deliveryRuns > 0 ||
      _savingCopies > 0 ||
      _exportRun != null;

  Future<PluginInstallResult> directInstall(StorePlugin plugin) async {
    final handedOffAt = DateTime.now();
    var current = plugin;
    final result = await _manager.directInstall(
      plugin,
      appVersion: appVersion,
      onPluginUpdated: (updated) {
        current = updated;
        _replacePlugin(updated);
      },
    );
    if (result.success) {
      watchForInstall(
        current,
        deliveredPath: result.deliveredPath,
        handedOffAt: handedOffAt,
      );
    } else {
      AppLogger.instance.error(
        'התקנה ישירה של ${plugin.name} נכשלה: ${result.error}',
      );
    }
    return result;
  }

  final Map<String, Future<PluginInstallResult>> _delivering = {};

  /// התוסף נמסר לאוצריא ברגע זה — לכל תוסף בנפרד.
  bool isDelivering(StorePlugin plugin) => _delivering.containsKey(plugin.id);

  /// מסירה כלשהי רצה — קוראת קובץ מהמראה.
  bool get isDeliveringAny => _delivering.isNotEmpty;

  /// [directInstall] עם סימון "בשליחה" עד שהמסירה חוזרת; חריגה היא כישלון של
  /// התוסף הזה. מסירה של תוסף שכבר בשליחה מצטרפת אליה.
  Future<PluginInstallResult> deliver(StorePlugin plugin) {
    if (_delivering[plugin.id] case final running?) return running;
    if (_closing) return Future.value(const PluginInstallResult.failure(null));
    // מסירה עשויה גם להוריד קובץ חסר אל המראה — ולכן לא באמצע העתקה.
    final blocked = mirrorReadBlockedReason ??
        (isExporting ? AppL10n.strings.plugins.actionsBlockedExporting : null);
    if (blocked != null) {
      return Future.value(PluginInstallResult.failure(blocked));
    }
    final run = _delivering[plugin.id] = _deliver(plugin).whenComplete(() {
      _delivering.remove(plugin.id);
      _signalIdle();
      if (!isDisposed) notifyListeners();
    });
    notifyListeners();
    return run;
  }

  Future<PluginInstallResult> _deliver(StorePlugin plugin) async {
    try {
      return await directInstall(plugin);
    } catch (error, stackTrace) {
      AppLogger.instance.error(
        'מסירת ${plugin.name} לאוצריא נכשלה',
        error,
        stackTrace,
      );
      return const PluginInstallResult.failure(null);
    }
  }

  /// "עדכון הכול" שרץ: כמה נשלחו מתוך כמה. `null` כשאינו רץ.
  ({int done, int total})? updateAllRun;
  bool get isUpdatingAll => updateAllRun != null;
  bool _stopUpdateAll = false;
  bool get updateAllStopRequested => _stopUpdateAll;

  void stopUpdateAll() {
    if (!isUpdatingAll || _stopUpdateAll) return;
    _stopUpdateAll = true;
    notifyListeners();
  }

  /// "עדכון הכול" מהחנות. רץ בקונטרולר ולא במסך: הוא משימה ארוכה שממשיכה
  /// גם כשעוברים מסך, ונעצר רק ב-[stopUpdateAll]. `null` — כבר רץ.
  Future<PluginUpdateAllOutcome?> updateAll(List<StorePlugin> targets) async {
    if (isUpdatingAll || targets.isEmpty) return null;
    _stopUpdateAll = false;
    updateAllRun = (done: 0, total: targets.length);
    notifyListeners();
    final failed = <({StorePlugin plugin, String? error})>[];
    try {
      final sent = await deliverUpdates(
        plugins: targets,
        isCancelled: () => _stopUpdateAll,
        onDelivered: (plugin, result) {
          if (!result.success) {
            failed.add((plugin: plugin, error: result.error));
          }
          final run = updateAllRun;
          if (run != null) {
            updateAllRun = (done: run.done + 1, total: run.total);
          }
        },
      );
      final stopped =
          _stopUpdateAll && sent.length + failed.length < targets.length;
      return (sent: sent, failed: failed, stopped: stopped);
    } finally {
      // אחרת longTaskRunning נשאר תקוע עד סוף ההרצה.
      updateAllRun = null;
      _stopUpdateAll = false;
      if (!isDisposed) notifyListeners();
    }
  }

  /// מוסר לאוצריא, אחד אחרי השני, את העדכונים שאפשר להתקין ישירות
  /// ([plugins], וכברירת מחדל [deliverableUpdates]). מחזיר מה נשלח בהצלחה.
  Future<List<StorePlugin>> deliverUpdates({
    List<StorePlugin>? plugins,
    void Function(StorePlugin plugin)? onDelivering,
    void Function(StorePlugin plugin, PluginInstallResult result)? onDelivered,
    bool Function()? isCancelled,
  }) async {
    final sent = <StorePlugin>[];
    var first = true;
    // אוחז במראה לכל הרצף: גם ברווח שבין מסירה למסירה (ראו [isReadingMirror]).
    _deliveryRuns++;
    try {
      for (final plugin in plugins ?? deliverableUpdates) {
        if (isDisposed || _closing || (isCancelled?.call() ?? false)) break;
        if (!first) await Future<void>.delayed(pluginUpdateDeliverySpacing);
        first = false;
        if (isDisposed || _closing || (isCancelled?.call() ?? false)) break;
        onDelivering?.call(plugin);
        final result = await deliver(plugin);
        if (result.success) sent.add(plugin);
        onDelivered?.call(plugin, result);
      }
    } finally {
      _deliveryRuns--;
      _signalIdle();
      // הבית, היציאה והחנות קוראים אותו מהמאזינים.
      if (!isDisposed) notifyListeners();
    }
    return sent;
  }

  int _deliveryRuns = 0;

  /// רצף מסירות ("עדכון הכול", שלב התוספים של "עדכון כאן") עוד לא הסתיים.
  bool get isDeliveryRunActive => _deliveryRuns > 0;

  bool _closing = false;
  Completer<void>? _idle;

  /// סגירה אושרה: שום מסירה חדשה לא מתחילה, וממתינים לאלה שבשליחה (וברצף —
  /// לכל היותר עוד מרווח אחד). אין כאן מגבלת זמן; ראו [resumeDeliveries].
  Future<void> stopDeliveriesAndWait() {
    _closing = true;
    if (_delivering.isEmpty && _deliveryRuns == 0) return Future.value();
    return (_idle ??= Completer<void>()).future;
  }

  /// "חזרה לכלי" מהמתנת הסגירה: מסירות מותרות שוב. רצף שכבר יצא מהלולאה
  /// (נעצר ברווח) אינו חוזר; רצף שעוד במסירה ממשיך כרגיל.
  void resumeDeliveries() => _closing = false;

  void _signalIdle() {
    if (_delivering.isNotEmpty || _deliveryRuns > 0) return;
    _idle?.complete();
    _idle = null;
  }

  /// עדכונים שאוצריא יכולה לקבל ישירות.
  List<StorePlugin> get deliverableUpdates =>
      updatablePlugins.where(canDirectInstall).toList(growable: false);

  void _replacePlugin(StorePlugin updated) {
    plugins = [
      for (final entry in plugins) entry.id == updated.id ? updated : entry,
    ];
    _invalidateDerived();
    notifyListeners();
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

  void setCategory(String? slug) {
    if (categoryFilter == slug) return;
    categoryFilter = slug;
    _invalidateDerived();
    notifyListeners();
  }

  void setTagFilter(String? value) {
    if (tagFilter == value) return;
    tagFilter = value;
    _invalidateDerived();
    notifyListeners();
  }

  void setSortMode(PluginSortMode value) {
    if (sortMode == value) return;
    sortMode = value;
    _invalidateDerived();
    notifyListeners();
  }

  void setInstallFilter(PluginInstallFilter value) {
    if (installFilter == value) return;
    installFilter = value;
    _invalidateDerived();
    notifyListeners();
  }

  /// כמה מסננים פעילים מתחת ל"עוד סינון" (יציבות ותגית).
  int get moreFiltersCount =>
      (statusFilter == PluginStatusFilter.all ? 0 : 1) +
      (tagFilter == null ? 0 : 1);

  /// "ניקוי החיפוש והסינון" — כל מה שמצמצם את הרשימה, בבת אחת.
  void clearFilters() {
    search = '';
    categoryFilter = null;
    statusFilter = PluginStatusFilter.all;
    tagFilter = null;
    installFilter = PluginInstallFilter.all;
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
  List<StorePlugin>? _newPlugins;
  Map<String, StorePlugin>? _byId;
  List<PluginStoreCategory>? _shownCategories;

  void _invalidateDerived() {
    _filtered = null;
    _allTags = null;
    _updatable = null;
    _newPlugins = null;
    _byId = null;
    _shownCategories = null;
  }

  bool _passesInstallFilter(StorePlugin plugin) => switch (installFilter) {
        PluginInstallFilter.all => true,
        PluginInstallFilter.installed => installedVersionOf(plugin) != null,
        PluginInstallFilter.notInstalled => installedVersionOf(plugin) == null,
      };

  final Map<StorePlugin, List<String>> _searchTexts = Map.identity();

  bool _matchesQuery(StorePlugin plugin, String query) => _searchTexts
      .putIfAbsent(
          plugin,
          () => [
                for (final text in [
                  plugin.name,
                  plugin.shortDescription,
                  plugin.description,
                  plugin.author,
                  ...plugin.tags,
                ])
                  normalizeStoreText(text),
              ])
      .any((text) => text.contains(query));

  /// הרשימה המוצגת: חיפוש, קטגוריה, מותקנים, יציבות ותגית — יחד.
  List<StorePlugin> get filtered => _filtered ??= () {
        final query = normalizeStoreQuery(search);
        final category =
            categoryFilter == null ? null : categoryBySlug(categoryFilter!);
        final members = category?.pluginIds.toSet();
        return _sorted(plugins.where((plugin) {
          if (members != null && !members.contains(plugin.id)) return false;
          if (!_passesInstallFilter(plugin)) return false;
          if (statusFilter == PluginStatusFilter.stable &&
              plugin.status != 'stable') {
            return false;
          }
          if (statusFilter == PluginStatusFilter.experimental &&
              !isExperimentalPluginStatus(plugin.status)) {
            return false;
          }
          if (tagFilter != null && !plugin.tags.contains(tagFilter)) {
            return false;
          }
          return query.isEmpty || _matchesQuery(plugin, query);
        }).toList(growable: false));
      }();

  /// מיון יורד לפי תאריך; תוסף בלי תאריך (קטלוג ישן) בסוף. שוויון שומר על
  /// סדר הקטלוג — `sort` של Dart אינו יציב, ולכן האינדקס משמש שובר שוויון.
  List<StorePlugin> _sorted(List<StorePlugin> list) {
    final String Function(StorePlugin)? key = switch (sortMode) {
      PluginSortMode.recommended => null,
      PluginSortMode.newest => (p) => p.publishedAt,
      PluginSortMode.updated => (p) => p.displayUpdatedDate,
    };
    if (key == null) return list;
    final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])]
      ..sort((a, b) {
        final byDate = key(b.$2).compareTo(key(a.$2));
        return byDate != 0 ? byDate : a.$1.compareTo(b.$1);
      });
    return [for (final entry in indexed) entry.$2];
  }

  Map<String, StorePlugin> get _pluginsById =>
      _byId ??= {for (final plugin in plugins.reversed) plugin.id: plugin};

  /// הקטגוריות שיש בהן תוסף אחד לפחות — שבב ריק אינו מוביל לשום מקום.
  List<PluginStoreCategory> get shownCategories => _shownCategories ??= [
        for (final category in categories)
          if (pluginsIn(category).isNotEmpty) category,
      ];

  PluginStoreCategory? categoryBySlug(String slug) {
    for (final category in categories) {
      if (category.slug == slug) return category;
    }
    return null;
  }

  /// תוספי הקטגוריה בסדר הידני שנקבע באתר. מזהה שאין לו תוסף בקטלוג מדולג.
  List<StorePlugin> pluginsIn(PluginStoreCategory category) => [
        for (final id in category.pluginIds)
          if (_pluginsById[id] case final plugin?) plugin,
      ];

  /// שם התצוגה של קטגוריה לפי ה-slug שנשמר על התוסף.
  String categoryName(String slug) => categoryBySlug(slug)?.name ?? slug;

  List<String> get allTags => _allTags ??= () {
        final tags = <String>{};
        for (final plugin in plugins) {
          tags.addAll(plugin.tags);
        }
        return tags.toList()..sort();
      }();

  // ── תוספים חדשים ──────────────────────────────────────────────────────────

  /// מה שהטוסט של החנות והחלון שבמסך הראשי כבר הכירו במחשב הזה. `null` =
  /// אין נקודת התחלה (אין תיקיית כתיבה, או שהקטלוג עוד ריק) — ואז אין הודעות.
  Set<String>? _seenIds;
  Set<String>? _notifiedIds;

  /// הרגע שבו קטלוג לא ריק נטען לראשונה במחשב הזה רק **קובע נקודת התחלה**:
  /// בלי זה מחשב חדש היה מכריז על כל החנות כחדשה. קטלוג ריק אינו נקודת
  /// התחלה — אחרת הסנכרון הראשון היה מכריז על כולו.
  Future<void> _loadKnown() async {
    final known = _known;
    if (known == null) return;
    var seen = await known.loadSeen();
    var notified = await known.loadNotified();
    if (seen == null && plugins.isNotEmpty) {
      final ids = plugins.map((plugin) => plugin.id).toList();
      await known.recordSeen(ids);
      await known.recordNotified(ids);
      seen = ids.toSet();
      notified = ids.toSet();
    }
    _seenIds = seen;
    _notifiedIds = notified ?? seen;
  }

  /// תוסף חדש לפי המדד של החנות הרשמית: לא מותקן כאן, ויש לו בילד שרץ.
  bool _isNewCandidate(StorePlugin plugin) {
    final status = statusOf(plugin);
    return status == PluginInstallStatus.notInstalled ||
        status == PluginInstallStatus.unknown;
  }

  /// תוספים שעוד לא הוצגו בטוסט של החנות במחשב הזה.
  List<StorePlugin> get newPlugins {
    final seen = _seenIds;
    if (seen == null) return const [];
    return _newPlugins ??= plugins
        .where((p) => !seen.contains(p.id) && _isNewCandidate(p))
        .toList(growable: false);
  }

  /// תוספים שהחלון שבמסך הראשי עוד לא הזכיר. מי שכבר נראה בחנות אינו חדש.
  List<StorePlugin> get newPluginsForHome {
    final seen = _seenIds;
    final notified = _notifiedIds;
    if (seen == null || notified == null) return const [];
    return plugins
        .where(
          (p) =>
              !seen.contains(p.id) &&
              !notified.contains(p.id) &&
              _isNewCandidate(p),
        )
        .toList(growable: false);
  }

  /// מה שסומן "חדש" בהרצה הזו — השבב נשאר עד סוף ההרצה, גם אחרי הרישום.
  final Set<String> _newThisRun = {};
  bool isNewThisRun(StorePlugin plugin) => _newThisRun.contains(plugin.id);

  /// רושם שהחנות הציגה את התוספים האלה כחדשים.
  Future<void> markNewSeen(Iterable<StorePlugin> shown) async {
    final ids = shown.map((plugin) => plugin.id).toList();
    if (ids.isEmpty) return;
    _newThisRun.addAll(ids);
    _seenIds = {...?_seenIds, ...ids};
    _newPlugins = null;
    await _known?.recordSeen(ids);
  }

  /// רושם שהחלון שבמסך הראשי הזכיר את התוספים האלה.
  Future<void> markHomeNotified(Iterable<StorePlugin> shown) async {
    final ids = shown.map((plugin) => plugin.id).toList();
    if (ids.isEmpty) return;
    _notifiedIds = {...?_notifiedIds, ...ids};
    await _known?.recordNotified(ids);
  }

  /// תוספים שמותקנים אצל המשתמש בגרסה ישנה מזו שבחנות.
  List<StorePlugin> get updatablePlugins => _updatable ??= plugins
      .where((p) => statusOf(p) == PluginInstallStatus.updateAvailable)
      .toList(growable: false);

  int get installedCount => installed.length;

  @override
  void dispose() {
    _installWatch?.cancel();
    unawaited(_installDone.close());
    unawaited(_installRejected.close());
    _manager.dispose();
    super.dispose();
  }
}

/// פעולה על מראה התוספים נדחתה כי פעולה מתנגשת רצה. [message] מוכן להצגה.
class PluginMirrorBusy implements Exception {
  const PluginMirrorBusy(this.message);

  final String message;

  @override
  String toString() => message;
}

/// תוסף שנמסר לאוצריא וממתין לאישור מהדיסק. [versionBefore] הוא מה שהיה
/// מותקן ברגע המסירה — כל שינוי ממנו הוא ההוכחה שההתקנה הסתיימה.
class _PendingInstall {
  const _PendingInstall({
    required this.name,
    required this.manifestId,
    required this.versionBefore,
    required this.deadline,
    required this.handedOffAt,
    this.deliveredPath,
  });

  final String name;
  final String manifestId;
  final String? versionBefore;
  final DateTime deadline;
  final DateTime handedOffAt;
  final String? deliveredPath;
}

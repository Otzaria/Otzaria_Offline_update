import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';

import 'models/library_update_check_result.dart';
import 'services/library_db_locator.dart';
import 'services/library_state_store.dart';
import 'services/library_update_applier.dart';

export 'services/library_update_applier.dart'
    show
        LibraryUpdateApplier,
        LibraryApplyStage,
        LibraryApplyProgress,
        LibraryApplyException;

/// נזרק כשאין עדיין מראה מקומית להיבדק מולה — כלומר עוד לא בוצעה הורדה
/// אף פעם. זה מצב תקין לחלוטין בהרצה ראשונה, ולא שגיאה אמיתית: ה-UI אמור
/// לתרגם אותו ל"יש להוריד עדכונים קודם".
class LibraryMirrorMissingException implements Exception {
  const LibraryMirrorMissingException(this.mirrorDir);

  final String mirrorDir;

  @override
  String toString() =>
      'עדיין לא הורדו עדכוני ספרייה לתיקייה המקומית — יש להריץ הורדה '
      'במחשב עם חיבור לאינטרנט.';
}

/// נקודת הכניסה היחידה שמודול ה-UI אמור להשתמש בה כדי **לבדוק** גרסת מסד
/// (ה-DB) של אוצריא ו**להחיל** בפועל את העדכון (דלתא או DB מלא) על ה-DB
/// החי — מחווט את שרשרת ה-discovery/planner/downloader/applier של
/// `seforim_library_updater`.
///
/// **מקור אחד בלבד: המראה המקומית** ([mirrorDir]) שיושבת לצד התוכנה.
/// בדיקה והחלה *תמיד* קוראות משם ולעולם לא מהרשת — גם כשיש חיבור. הרשת
/// נוגעת בדבר יחיד: [downloadToMirror], שממלא את התיקייה הזו.
///
/// דוגמת שימוש:
/// ```dart
/// final manager = LibraryManager(dataDir: appPaths.dataDir);
///
/// // במחשב עם אינטרנט — פעם אחת, ממלא את התיקייה שלצד התוכנה:
/// await manager.downloadToMirror(onStage: print);
///
/// // בכל מחשב, כולל בלי רשת בכלל:
/// final check = await manager.checkForUpdate();
/// if (check.updateAvailable) {
///   await manager.applyUpdate(check, onProgress: (p) => print(p.stage));
/// }
/// ```
class LibraryManager {
  LibraryManager({
    required this.dataDir,
    this.allowPrerelease = false,
  })  : _stateStore = LibraryStateStore(p.join(dataDir, 'library_state.json')),
        _planner = const LibraryUpdatePlanner(),
        _versionReader = const LocalDbVersionReader(),
        _recovery = const LibraryDbRecoveryService(),
        _cloudClient = GithubLibraryReleaseClient(),
        _applier = LibraryUpdateApplier() {
    _locator = LibraryDbLocator(stateStore: _stateStore);
  }

  /// תיקיית הנתונים של הלאנצ'ר (state, ונתיב ברירת המחדל להתקנה טרייה של
  /// ה-DB תחת `<dataDir>/library/seforim.db`).
  final String dataDir;

  /// `true` = הערוץ "כולל pre-release". ברירת המחדל `false` — release רגיל
  /// ב-GitHub נחשב יציב, pre-release נחשב לא יציב. ניתן לשינוי בזמן ריצה
  /// כדי שהחלפת ערוץ בהגדרות תיכנס לתוקף בבדיקה/הורדה הבאה.
  bool allowPrerelease;

  final LibraryStateStore _stateStore;
  late final LibraryDbLocator _locator;
  final LibraryUpdatePlanner _planner;
  final LocalDbVersionReader _versionReader;

  /// נשאר לצורך [checkForUpdate] בלבד — מזהה ומנקה שרידי-קריסה מהתקנות
  /// ישנות של הלאנצ'ר (מגרסאות קודמות שכן ביצעו patch/apply בפועל). לא
  /// כותב/מחיל דבר בעצמו.
  final LibraryDbRecoveryService _recovery;

  /// לקוח ה-cloud (GitHub) — משמש **רק** את [downloadToMirror]. בדיקה והחלה
  /// לא נוגעות בו לעולם; ראו [_resolveSource].
  final GithubLibraryReleaseClient _cloudClient;

  /// מבצע את ההחלה בפועל של תוכנית עדכון (delta/fullDownload) על ה-DB החי —
  /// ראו [applyUpdate].
  final LibraryUpdateApplier _applier;

  Future<void> setCustomDbPath(String dbPath) =>
      _stateStore.saveCustomDbPath(dbPath);

  /// נתיב ה-`seforim.db` שזוהה בפועל, או `null` אם לא נמצא — לתצוגה בממשק.
  /// המיקום מתגלה בכל קריאה מחדש; אין להניח נתיב קבוע.
  Future<String?> currentDbPath() => _locator.resolveDbPath();

  /// תיקיית המראה המקומית — קבועה, לצד התוכנה (בתוך [dataDir]). זה **המקור
  /// היחיד** שממנו [checkForUpdate] ו-[applyUpdate] קוראים, תמיד; היא נמלאת
  /// אך ורק על ידי [downloadToMirror], וכשהתוכנה על כונן נייד היא נוסעת
  /// יחד איתה למחשב הלא־מקוון בלי שום צעד העתקה נוסף.
  String get mirrorDir => p.join(dataDir, 'mirror', 'library');

  /// `true` אם כבר בוצעה הורדה מוצלחת אחת לפחות. בודק ספציפית את
  /// `releases.json`, שנכתב רק בסוף הורדה מוצלחת — התיקייה עצמה נוצרת מיד
  /// בתחילתה, ולכן קיומה לבדו לא מבטיח תוכן שלם.
  Future<bool> get hasMirror => File(p.join(
        mirrorDir,
        LocalMirrorLibraryReleaseClient.manifestFileName,
      )).exists();

  /// מוריד את עדכוני הספרייה מ-GitHub אל [mirrorDir] — **הפעולה הכבדה**
  /// שנוגעת ברשת (המסד המלא ~1GB + קובצי העדכון). מביא את ה-release
  /// האחרון בערוץ הנבחר.
  Future<void> downloadToMirror({
    void Function(String stage)? onStage,
    void Function(int doneAssets, int totalAssets)? onAssetProgress,
    void Function(int downloaded, int? total)? onBytesProgress,
    bool Function()? isCancelled,
  }) async {
    final exporter = LibraryMirrorExporter(client: _cloudClient);
    await exporter.export(
      destDir: mirrorDir,
      allowPrerelease: allowPrerelease,
      onStage: onStage,
      onAssetProgress: onAssetProgress,
      onBytesProgress: onBytesProgress,
      isCancelled: isCancelled,
    );
  }

  /// בודק מה הגרסה העדכנית ביותר הזמינה ב-GitHub — **פעולת רשת קלה**:
  /// קריאת API יחידה ל-`/releases`, בלי הורדת manifest או asset כלשהו
  /// (בשונה מ-[LibraryUpdateDiscovery.discover], שמוריד גם manifest לכל
  /// release כדי לבנות את גרף ה-patches — יקר יותר ממה שצריך כאן).
  /// מחזיר `null` אם אין release כשיר בערוץ הנבחר. מיועדת לבדיקה צדדית
  /// ("יש עדכון חדש ברשת?"); זורקת חריג רשת/HTTP רגיל בכשל — הקורא אמור
  /// להתייחס לכשל כ"אין חיבור כרגע", לא כשגיאה חוסמת.
  Future<int?> peekLatestOnlineVersion() async {
    final releases = LibraryUpdateDiscovery.eligibleReleases(
      await _cloudClient.fetchReleases(),
      allowPrerelease: allowPrerelease,
    );
    if (releases.isEmpty) return null;

    var latest = 0;
    for (final release in releases) {
      final version = LibraryUpdateDiscovery.releaseVersionOf(release);
      if (version > latest) latest = version;
    }
    return latest;
  }

  /// המראה המקומית כמקור releases. זורק [LibraryMirrorMissingException] אם
  /// עדיין לא הורד דבר — במקום ליפול לרשת בשקט, כפי שהיה בעבר.
  Future<LibraryReleaseSource> _resolveSource() async {
    if (!await hasMirror) throw LibraryMirrorMissingException(mirrorDir);
    return LocalMirrorLibraryReleaseClient(mirrorDir: mirrorDir);
  }

  /// בודק אם יש עדכון זמין.
  ///
  /// אם לא נמצא DB בכלל (לא בנתיב מותאם אישית ולא בברירת המחדל של
  /// אוצריא) — **לא** חוסם ומבקש בחירה ידנית; במקום זה מצביע אוטומטית על
  /// נתיב ברירת מחדל משלו (`<dataDir>/library/seforim.db`) וממשיך לתוכנית
  /// הורדה מלאה, בדיוק כמו שהתקנה ראשונה של אוצריא עצמה עובדת. ראו
  /// [LibraryUpdateCheckResult.isFreshInstall]. בחירה ידנית של קובץ DB
  /// קיים עדיין אפשרית מרצון דרך [setCustomDbPath].
  Future<LibraryUpdateCheckResult> checkForUpdate() async {
    var dbPath = await _locator.resolveDbPath();
    final isFreshInstall = dbPath == null;
    dbPath ??= p.join(dataDir, 'library', LibraryDbLocator.databaseFileName);

    LocalDbVersion local;
    if (isFreshInstall) {
      // אין DB בכלל עדיין — אין מה לקרוא ואין מה לשחזר. localVersion=0 +
      // hasVersionMeta=false גורמים ל-planner לבחור fullDownload, בדיוק
      // כמו DB ישן-מדי-לפאץ' (ראו LibraryUpdatePlanner._fullOrBlocked).
      local = const LocalDbVersion(
          dbVersion: 0, schemaVersion: null, hasVersionMeta: false);
    } else {
      // התאוששות מעדכון שנקטע באמצע, לפני שקוראים גרסה מקומית או פותחים
      // DB בכל דרך אחרת.
      final recovery = await _recovery.recoverIfNeeded(dbPath);
      if (recovery.action == RecoveryAction.blockedMissingBackup) {
        // מסלול דלתא (ה-apply עצמו אטומי): בודקים תקינות בפועל, לא רק
        // מניחים תקלה בגלל שהסימון נשאר.
        if (!_recovery.checkDbHealthAfterCrash(dbPath)) {
          throw StateError(
            '${recovery.detail ?? "עדכון DB שנקטע"} — quick_check נכשל בפועל, '
            'נדרשת התערבות ידנית (שחזור מגיבוי חיצוני).',
          );
        }
        _recovery.clearStaleArtifacts(dbPath);
      }
      local = _versionReader.read(dbPath);
    }

    final source = await _resolveSource();
    final discoverer = LibraryUpdateDiscovery(client: source);
    final discoveryResult =
        await discoverer.discover(allowPrerelease: allowPrerelease);

    final plan = _planner.plan(
      localVersion: local.dbVersion,
      hasLocalVersionMeta: local.hasVersionMeta,
      latestVersion: discoveryResult.latestVersion,
      edges: discoveryResult.edges,
      latestFullDbAsset: discoveryResult.latestFullDbAsset,
      latestReleaseTag: discoveryResult.latestReleaseTag,
      // בלי זה, release שמפרסם מסד מתוקן באותו db_version נראה כ"מעודכן".
      localReleaseTag: await _stateStore.loadAppliedReleaseTag(),
    );

    return LibraryUpdateCheckResult(
      dbPath: dbPath,
      localVersion: local,
      plan: plan,
      isFreshInstall: isFreshInstall,
      latestReleaseTag: discoveryResult.latestReleaseTag,
    );
  }

  /// מחיל בפועל את [check.plan] על ה-DB **החי** — זה הצעד שחסר עד עכשיו:
  /// [checkForUpdate] רק בודק ותכנן, הפונקציה הזו בפועל מורידה ומתקינה.
  ///
  /// זורק [OtzariaIsRunningException] אם אוצריא פתוחה (בווינדוס בלבד —
  /// הבדיקה מדולגת בפלטפורמות אחרות). זורק [LibraryApplyException] על
  /// כשלים אחרים (חיבור/אימות/גרסה לא תואמת) — במקרה כזה ה-DB משוחזר
  /// אוטומטית לגרסה הקודמת כשהתוכנית לא הייתה delta.
  ///
  /// לא עושה כלום אם `check.updateAvailable == false`.
  Future<void> applyUpdate(
    LibraryUpdateCheckResult check, {
    void Function(LibraryApplyProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final plan = check.plan;
    final dbPath = check.dbPath;
    if (plan == null || dbPath == null || !check.updateAvailable) return;

    switch (plan.kind) {
      case LibraryUpdatePlanKind.delta:
        await _applier.applyDelta(
          plan: plan,
          dbPath: dbPath,
          onProgress: onProgress,
          isCancelled: isCancelled,
        );
        break;
      case LibraryUpdatePlanKind.fullDownload:
        await _applier.applyFullDownload(
          plan: plan,
          dbPath: dbPath,
          onProgress: onProgress,
          isCancelled: isCancelled,
        );
        break;
      case LibraryUpdatePlanKind.none:
        return;
      case LibraryUpdatePlanKind.blocked:
        throw LibraryApplyException(
          plan.reason ?? 'מצב חסום — נדרשת פעולה ידנית',
        );
    }

    // התקנה טרייה: ה-dbPath שכתבנו אליו הופך מעכשיו לנתיב הקבוע שנבדוק
    // מולו (כמו בחירה ידנית של המשתמש) — כדי ש-checkForUpdate הבא ימצא
    // אותו במקום לחשוב שוב שזו התקנה טרייה.
    if (check.isFreshInstall) {
      await _stateStore.saveCustomDbPath(dbPath);
    }

    // רושמים מאיזה release התוכן הנוכחי הגיע — זה מה שמאפשר לזהות בהמשך
    // מסד מתוקן שפורסם באותו db_version (ראו LibraryUpdatePlanner).
    final appliedTag = plan.fullDbReleaseTag ?? check.latestReleaseTag;
    if (appliedTag != null) {
      await _stateStore.saveAppliedReleaseTag(appliedTag);
    }
  }

  /// סוגר את חיבורי ה-HTTP הפנימיים. יש לקרוא כשמסיימים להשתמש
  /// ב-[LibraryManager] (לא הכרחי בין קריאות בודדות — רק בסגירת האפליקציה).
  void dispose() {
    _cloudClient.dispose();
    _applier.dispose();
  }
}

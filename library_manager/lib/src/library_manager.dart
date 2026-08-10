import 'dart:io';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';

import 'models/library_update_check_result.dart';
import 'services/companion_assets_installer.dart';
import 'services/companion_assets_mirror.dart';
import 'services/external_update_notice.dart';
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
  String toString() => AppL10n.strings.libraryDomain.mirrorMissing;
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
    Future<String?> Function()? otzariaLaunchPath,
  })  : _stateStore = LibraryStateStore(p.join(dataDir, 'library_state.json')),
        _planner = const LibraryUpdatePlanner(),
        _versionReader = const LocalDbVersionReader(),
        _recovery = const LibraryDbRecoveryService(),
        _cloudClient = GithubLibraryReleaseClient(),
        _applier = LibraryUpdateApplier() {
    _locator = LibraryDbLocator(
      stateStore: _stateStore,
      otzariaLaunchPath: otzariaLaunchPath,
    );
  }

  /// תיקיית הנתונים של הלאנצ'ר (state, ונתיב ברירת המחדל להתקנה טרייה של
  /// ה-DB תחת `<dataDir>/library/seforim.db`).
  final String dataDir;

  /// `true` = הערוץ "כולל pre-release". ברירת המחדל `false` — release רגיל
  /// ב-GitHub נחשב יציב, pre-release נחשב לא יציב. ניתן לשינוי בזמן ריצה
  /// כדי שהחלפת ערוץ בהגדרות תיכנס לתוקף בבדיקה/הורדה הבאה.
  bool allowPrerelease;

  /// הזמן הקצוב לפעולות הרשת של המודול — נכנס לתוקף בבקשה הבאה.
  set networkTimeout(Duration value) {
    _cloudClient.timeout = value;
    _applier.connectTimeout = value;
  }

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

  /// הקבצים הנלווים לספרייה (תלמוד, קטלוג, מילון). אוצריא מרעננת אותם
  /// **מהרשת** בכל עדכון ספרייה; כאן הם נוסעים במראה ומותקנים אופליין.
  final CompanionAssetsMirror _companionsMirror = CompanionAssetsMirror();
  final CompanionAssetsInstaller _companionsInstaller =
      const CompanionAssetsInstaller();

  /// תיקיית המראה של הקבצים הנלווים — לצד מראת הספרייה, תחת אותו שורש.
  String get companionsMirrorDir => p.join(dataDir, 'mirror', 'companions');

  Future<void> setCustomDbPath(String dbPath) =>
      _stateStore.saveCustomDbPath(dbPath);

  /// נתיב ה-`seforim.db` שזוהה בפועל, או `null` אם לא נמצא — לתצוגה בממשק.
  /// המיקום מתגלה בכל קריאה מחדש; אין להניח נתיב קבוע.
  Future<String?> currentDbPath() => _locator.resolveDbPath();

  String? _lastResolvedDbPath;

  /// הנתיב ש-[checkForUpdate] האחרון איתר (`null` = לא נמצא DB, או שטרם
  /// רצה בדיקה). קיים כדי שהממשק יציג את הנתיב בלי לקרוא ל-[currentDbPath]
  /// בנוסף: האיתור עצמו קורא את קופסת ההגדרות של אוצריא מעותק, וריצה כפולה
  /// שלו בכל בדיקה הייתה עלות מיותרת בעלייה.
  String? get lastResolvedDbPath => _lastResolvedDbPath;

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
  ///
  /// [onCompanionWarning] מקבל כשל בקובץ נלווה בודד — פעולה best-effort
  /// שאינה מפילה את ההורדה, אך גם אינה אמורה להיעלם בשקט: בלעדיה המשתמש
  /// היה מגלה רק במחשב הלא-מקוון שהתלמוד לא נסע איתו.
  Future<void> downloadToMirror({
    void Function(String stage)? onStage,
    void Function(int doneAssets, int totalAssets)? onAssetProgress,
    void Function(int downloaded, int? total)? onBytesProgress,
    void Function(String assetName, Object error)? onCompanionWarning,
    bool Function()? isCancelled,
  }) async {
    final exporter = LibraryMirrorExporter(client: _cloudClient);
    try {
      await exporter.export(
        destDir: mirrorDir,
        allowPrerelease: allowPrerelease,
        onStage: onStage,
        onAssetProgress: onAssetProgress,
        onBytesProgress: onBytesProgress,
        isCancelled: isCancelled,
      );
    } finally {
      // ה-exporter נוצר כאן בכל הורדה ומחזיק HttpClient משלו; בלי הסגירה
      // הזו כל לחיצה על "הורדה" משאירה connection pool פתוח.
      exporter.dispose();
    }
    // הקבצים הנלווים הם חלק מאותה הורדה: באוצריא הם מתרעננים מהרשת בכל
    // עדכון ספרייה, ובלעדיהם המחשב הלא-מקוון מקבל מסד חדש עם תלמוד/קטלוג/
    // מילון ישנים. כשל בהם אינו מפיל את ההורדה — ראו [CompanionAssetsMirror].
    await _companionsMirror.sync(
      destDir: companionsMirrorDir,
      onStage: onStage,
      onBytesProgress: onBytesProgress,
      onWarning: onCompanionWarning,
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
    var latest = 0;
    for (final release in releases) {
      // רק release שנושא תוכן מסד יורד בפועל למראה (ראו
      // `LibraryMirrorExporter._latestOnly`), ורק הוא נספר גם ב-`discover`.
      // ספירת release אחר כאן הציגה "יש עדכון ברשת" שאף הורדה לא מסלקת.
      if (release.deltaManifestAssets.isEmpty && release.fullDbAsset == null) {
        continue;
      }
      final version = LibraryUpdateDiscovery.releaseVersionOf(release);
      if (version > latest) latest = version;
    }
    return latest == 0 ? null : latest;
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
    _lastResolvedDbPath = dbPath;
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
      if (recovery.action == RecoveryAction.interrupted) {
        // אין גיבוי לשחזר ממנו: בודקים תקינות בפועל, לא מניחים תקלה רק
        // בגלל שהסימון נשאר.
        if (!_recovery.checkDbHealthAfterCrash(dbPath)) {
          final strings = AppL10n.strings.libraryDomain;
          throw StateError(
            strings.interruptedUpdateNeedsManualFix(
              recovery.detail ?? strings.interruptedUpdateDefaultDetail,
            ),
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
      latestFullDbVersion: discoveryResult.latestFullDbVersion,
      // בלי זה, release שמפרסם מסד מתוקן באותו db_version נראה כ"מעודכן".
      localReleaseTag: await _stateStore.loadAppliedReleaseTag(),
    );

    return LibraryUpdateCheckResult(
      dbPath: dbPath,
      localVersion: local,
      plan: plan,
      isFreshInstall: isFreshInstall,
      latestReleaseTag: discoveryResult.latestReleaseTag,
      companionsPending: await _companionsInstaller.hasPendingWork(
        mirrorDir: companionsMirrorDir,
        dbPath: dbPath,
      ),
    );
  }

  /// מחיל בפועל את [check.plan] על ה-DB **החי** — זה הצעד שחסר עד עכשיו:
  /// [checkForUpdate] רק בודק ותכנן, הפונקציה הזו בפועל מורידה ומתקינה.
  ///
  /// זורק [OtzariaIsRunningException] אם אוצריא פתוחה — `tasklist` בווינדוס,
  /// `pgrep -x` ב-macOS/לינוקס. זורק [LibraryApplyException] על
  /// כשלים אחרים (חיבור/אימות/גרסה לא תואמת) — בכל אחד מהם ה-DB הקיים נשאר
  /// כמו שהיה: מסלול delta אטומי, ומסלול המסד המלא מאמת את הקובץ החדש לפני
  /// שהוא מחליף.
  ///
  /// לא עושה כלום אם `check.updateAvailable == false`.
  ///
  /// מחזיר את מזהי הספרים שתוכנם השתנה (מסלול דלתא בלבד; ריק בהורדה מלאה,
  /// שבה אין דיווח כזה) — אוצריא משתמשת בהם כדי לאנדקס מחדש בדיוק את הספרים
  /// האלה. ראו `library_manager/README.md`, "אינדקס החיפוש".
  ///
  /// [onCompanionWarning] מקבל כשל בהתקנת קובץ נלווה בודד — כמו בהורדה, זה
  /// best-effort שאסור לו להיעלם בשקט.
  Future<Set<int>> applyUpdate(
    LibraryUpdateCheckResult check, {
    void Function(LibraryApplyProgress progress)? onProgress,
    void Function(String assetName, Object error)? onCompanionWarning,
    bool Function()? isCancelled,
  }) async {
    final plan = check.plan;
    final dbPath = check.dbPath;
    if (dbPath == null || !check.updateAvailable) {
      return const <int>{};
    }

    var booksTouched = const <int>{};
    if (plan != null && check.dbUpdateAvailable) {
      switch (plan.kind) {
        case LibraryUpdatePlanKind.delta:
          // שלב בשרשרת שנכשל אינו מבטל את השלבים שכבר בוצעו והוחלו על ה-DB
          // החי. בלי הרישום הזה הספרים שהשתנו בהם היו נשארים מאונדקסים
          // בגרסתם הישנה אצל אוצריא — בדיוק מה ש-[ExternalUpdateNotice] מונע.
          final partial = <int>{};
          try {
            booksTouched = await _applier.applyDelta(
              plan: plan,
              dbPath: dbPath,
              onProgress: onProgress,
              isCancelled: isCancelled,
              onStepApplied: partial.addAll,
            );
          } catch (_) {
            if (partial.isNotEmpty) {
              await const ExternalUpdateNotice().write(
                dbPath: dbPath,
                route: ExternalUpdateNotice.routeDelta,
                booksTouched: partial,
              );
            }
            rethrow;
          }
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
          break;
        case LibraryUpdatePlanKind.blocked:
          throw LibraryApplyException(
            plan.reason ??
                AppL10n.strings.libraryDomain.blockedNeedsManualAction,
          );
      }

      // רישומי ה-state הם קבצי JSON זעירים, אבל הם נכתבים **אחרי** שהמסד
      // כבר הוחלף. כשל שלהם (כונן מלא, USB שנשלף) אינו הופך עדכון שהצליח
      // לכישלון — לכל היותר הבדיקה הבאה תציע שוב את מה שכבר מותקן.
      try {
        // התקנה טרייה: ה-dbPath שכתבנו אליו הופך מעכשיו לנתיב הקבוע שנבדוק
        // מולו (כמו בחירה ידנית של המשתמש) — כדי ש-checkForUpdate הבא ימצא
        // אותו במקום לחשוב שוב שזו התקנה טרייה.
        if (check.isFreshInstall) {
          await _stateStore.saveCustomDbPath(dbPath);
        }
        await _saveAppliedTag(check, plan);
      } catch (_) {}
      // מה השתנה, לטובת אינדקס החיפוש של אוצריא — ראו [ExternalUpdateNotice].
      await const ExternalUpdateNotice().write(
        dbPath: dbPath,
        route: plan.kind == LibraryUpdatePlanKind.delta
            ? ExternalUpdateNotice.routeDelta
            : ExternalUpdateNotice.routeFull,
        booksTouched: booksTouched,
        dbVersion: plan.targetVersion,
        releaseTag: plan.fullDbReleaseTag ?? check.latestReleaseTag,
      );
    }

    // הקבצים הנלווים אחרי המסד — אותו סדר כמו ב-`LibraryUpdateBloc` באוצריא,
    // ובאותה רוח: כשל בהם אינו מבטל עדכון מסד שכבר הצליח.
    await _companionsInstaller.install(
      mirrorDir: companionsMirrorDir,
      dbPath: dbPath,
      onStage: (stage) => onProgress?.call(LibraryApplyProgress(
        stage: LibraryApplyStage.installingCompanions,
        statusText: stage,
      )),
      onWarning: onCompanionWarning,
      isCancelled: isCancelled,
    );

    onProgress?.call(const LibraryApplyProgress(stage: LibraryApplyStage.done));
    return booksTouched;
  }

  Future<void> _saveAppliedTag(
    LibraryUpdateCheckResult check,
    LibraryUpdatePlan plan,
  ) async {
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

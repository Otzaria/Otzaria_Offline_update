import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';

import 'models/library_update_check_result.dart';
import 'services/library_db_locator.dart';
import 'services/library_state_store.dart';

/// נקודת הכניסה היחידה שמודול ה-UI אמור להשתמש בה כדי **לבדוק** גרסת מסד
/// (ה-DB) של אוצריא ול**הוריד** את הקבצים העדכניים לתיקייה מקומית — מחווט
/// את שרשרת ה-discovery/planner/downloader של `seforim_library_updater`.
///
/// **חשוב:** ה-manager הזה **לא** מחיל (patch/apply) שום דבר על ה-DB
/// החי בפועל, ולא ניגש אליו לכתיבה. תפקידו היחיד מול הענן הוא לבדוק אילו
/// גרסאות קיימות ([checkForUpdate]) ולהוריד קבצים לתיקייה מקומית
/// ([exportOfflineMirror]/[refreshOfflineMirrorCache]). התקנה/עדכון בפועל
/// של קובץ ה-DB עצמו היא צעד נפרד ומכוון-ידית מחוץ למחלקה הזו.
///
/// **מקור הבדיקה** ניתן להחלפה בזמן ריצה בין הענן (GitHub, ברירת מחדל)
/// לבין מראה מקומית (offline) — ראו [useLocalMirror]/[useCloud]. המראה
/// המקומית עצמה נבנית פעם אחת, במחשב עם אינטרנט, דרך [exportOfflineMirror].
///
/// דוגמת שימוש (בדיקה + הורדה לתיקייה מקומית):
/// ```dart
/// final manager = LibraryManager(dataDir: r'C:\Users\me\AppData\Roaming\OurLauncher');
///
/// final check = await manager.checkForUpdate();
/// if (check.updateAvailable) {
///   await manager.refreshOfflineMirrorCache(
///     onStage: (stage) => print(stage),
///   );
///   // הקבצים המעודכנים נמצאים עכשיו ב-manager.offlineMirrorCacheDir —
///   // התקנתם בפועל היא צעד נפרד ומכוון-ידית.
/// }
/// ```
///
/// דוגמת שימוש (הכנת מראה offline למחשב אחר, ואז בדיקה מולה):
/// ```dart
/// // במחשב עם אינטרנט:
/// await manager.exportOfflineMirror(destDir: r'D:\seforim-mirror');
/// // מעתיקים את D:\seforim-mirror\ ל-USB, פותחים במחשב היעד:
///
/// // במחשב היעד (בלי אינטרנט):
/// await manager.useLocalMirror(r'E:\seforim-mirror'); // E: = כונן ה-USB שם
/// final check = await manager.checkForUpdate(); // קורא מהתיקייה המקומית בלבד
/// ```
class LibraryManager {
  LibraryManager({
    required this.dataDir,
    bool allowPrerelease = true,
  })  : _allowPrerelease = allowPrerelease,
        _stateStore = LibraryStateStore(p.join(dataDir, 'library_state.json')),
        _planner = const LibraryUpdatePlanner(),
        _versionReader = const LocalDbVersionReader(),
        _recovery = const LibraryDbRecoveryService(),
        _cloudClient = GithubLibraryReleaseClient() {
    _locator = LibraryDbLocator(stateStore: _stateStore);
  }

  /// תיקיית הנתונים של הלאנצ'ר (state, ונתיב ברירת המחדל להתקנה טרייה של
  /// ה-DB תחת `<dataDir>/library/seforim.db`).
  final String dataDir;

  /// אם `true` (ברירת מחדל), בדיקת עדכון עוקבת אחר releases prerelease של
  /// SeforimLibrary גם כן.
  final bool _allowPrerelease;

  final LibraryStateStore _stateStore;
  late final LibraryDbLocator _locator;
  final LibraryUpdatePlanner _planner;
  final LocalDbVersionReader _versionReader;

  /// נשאר לצורך [checkForUpdate] בלבד — מזהה ומנקה שרידי-קריסה מהתקנות
  /// ישנות של הלאנצ'ר (מגרסאות קודמות שכן ביצעו patch/apply בפועל). לא
  /// כותב/מחיל דבר בעצמו.
  final LibraryDbRecoveryService _recovery;

  /// לקוח ה-cloud (GitHub) — נשמר לאורך חיי ה-manager (מחזיק חיבור HTTP
  /// אחד) בין אם מצב ה-cloud פעיל ובין אם לא, כי [exportOfflineMirror]
  /// תמיד צריך אותו גם כשהמשתמש כרגע במצב מראה מקומית.
  final GithubLibraryReleaseClient _cloudClient;

  Future<void> setCustomDbPath(String dbPath) => _stateStore.saveCustomDbPath(dbPath);

  /// עובר לעדכון ממראה מקומית (offline) בתיקייה [mirrorDir] — במקום
  /// מהענן. התיקייה חייבת להיבנות מראש דרך [exportOfflineMirror] (או
  /// שהועתקה מתיקייה כזו, למשל מ-USB). הבחירה נשמרת בין הרצות.
  Future<void> useLocalMirror(String mirrorDir) =>
      _stateStore.saveLocalMirrorPath(mirrorDir);

  /// חוזר לעדכון מהענן (GitHub) — ברירת המחדל.
  Future<void> useCloud() => _stateStore.saveLocalMirrorPath(null);

  /// נתיב המראה המקומית הפעילה כרגע, או `null` אם מצב ה-cloud פעיל.
  Future<String?> currentLocalMirrorPath() => _stateStore.loadLocalMirrorPath();

  /// תיקיית ה"מראה המקומית האוטומטית" — קבועה, בתוך [dataDir], ומתוחזקת
  /// לבד על ידי [refreshOfflineMirrorCache] (נקרא ברקע בכל פתיחת האפליקציה
  /// — ראו הקורא ב-launcher_app). שני תפקידים בו-זמנית:
  ///  1. מקור ברירת המחדל ש-[checkForUpdate] קורא ממנו בפועל (ראו
  ///     [_resolveSource]) — כך שהבדיקה תמיד עובדת מול נתונים מקומיים
  ///     בלבד, בלי תלות ברשת בזמן הבדיקה עצמה.
  ///  2. תוכן מוכן-מראש להעברה למחשב אחר (USB / תיקייה משותפת): פשוט
  ///     מעתיקים את התיקייה הזו כמות שהיא.
  String get offlineMirrorCacheDir => p.join(dataDir, 'offline-mirror');

  /// מרענן את [offlineMirrorCacheDir] מהענן. best-effort ומיועד לרוץ ברקע
  /// בלי לחסום את הבדיקה/החלה בפועל של עדכון — אם הוא נכשל (למשל אין
  /// אינטרנט) ה-cache פשוט נשאר כפי שהיה מהרענון הקודם, וזה תקין לגמרי.
  Future<void> refreshOfflineMirrorCache({
    void Function(String stage)? onStage,
    void Function(int doneAssets, int totalAssets)? onAssetProgress,
    void Function(int downloaded, int? total)? onBytesProgress,
    bool Function()? isCancelled,
  }) =>
      exportOfflineMirror(
        destDir: offlineMirrorCacheDir,
        onStage: onStage,
        onAssetProgress: onAssetProgress,
        onBytesProgress: onBytesProgress,
        isCancelled: isCancelled,
      );

  /// בונה מראה מקומית מלאה (כל עדכוני ה-DB, כולל היסטוריה) מהענן לתיקייה
  /// [destDir] — כדי להעביר למחשב בלי אינטרנט (USB / תיקייה משותפת). תמיד
  /// פונה ל-GitHub בפועל (דורש אינטרנט), ללא קשר למצב המקור הפעיל כרגע.
  Future<void> exportOfflineMirror({
    required String destDir,
    void Function(String stage)? onStage,
    void Function(int doneAssets, int totalAssets)? onAssetProgress,
    void Function(int downloaded, int? total)? onBytesProgress,
    bool Function()? isCancelled,
  }) async {
    final exporter = LibraryMirrorExporter(client: _cloudClient);
    await exporter.export(
      destDir: destDir,
      allowPrerelease: _allowPrerelease,
      onStage: onStage,
      onAssetProgress: onAssetProgress,
      onBytesProgress: onBytesProgress,
      isCancelled: isCancelled,
    );
  }

  /// מקור ה-releases הפעיל כרגע, בסדר עדיפות:
  ///  1. מראה מקומית שהמשתמש בחר במפורש (דרך [useLocalMirror]) — למשל
  ///     כונן USB חיצוני. גוברת על הכול כל עוד היא פעילה.
  ///  2. [offlineMirrorCacheDir] האוטומטי, אם כבר נבנה פעם אחת (על ידי
  ///     [refreshOfflineMirrorCache]) — כך שבדיקה/החלה של עדכון עובדת מול
  ///     נתונים מקומיים בלבד, בלי תלות ברשת בזמן הבדיקה עצמה, וללא קשר
  ///     לחיבור אינטרנט הנוכחי של המחשב.
  ///  3. הענן, כ-fallback יחיד למקרה שעדיין אין שום cache מקומי בכלל
  ///     (למשל הרצה ראשונה אי-פעם, לפני שהרענון האוטומטי הראשון הספיק
  ///     לרוץ) — בדיוק כמו ההתנהגות המקורית לפני שנוסף ה-cache.
  ///
  /// נבדק מחדש בכל [checkForUpdate] כדי שמעבר בין המקורות ייכנס לתוקף
  /// מיד, בלי לדרוש הפעלה מחדש של האפליקציה.
  Future<LibraryReleaseSource> _resolveSource() async {
    final mirrorPath = await _stateStore.loadLocalMirrorPath();
    if (mirrorPath != null && mirrorPath.isNotEmpty) {
      return LocalMirrorLibraryReleaseClient(mirrorDir: mirrorPath);
    }
    // בודקים ספציפית את releases.json (לא רק שהתיקייה קיימת) — היא נוצרת
    // רק בסוף export מוצלח; התיקייה עצמה נוצרת מיד בתחילתו, אז אם רענון
    // ראשון-אי-פעם רץ ברקע ממש עכשיו, הדבר הזה מונע קריאה מ-cache חלקי.
    final cachedManifest = File(p.join(
      offlineMirrorCacheDir,
      LocalMirrorLibraryReleaseClient.manifestFileName,
    ));
    if (await cachedManifest.exists()) {
      return LocalMirrorLibraryReleaseClient(mirrorDir: offlineMirrorCacheDir);
    }
    return _cloudClient;
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
      local = const LocalDbVersion(dbVersion: 0, schemaVersion: null, hasVersionMeta: false);
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
    final discoveryResult = await discoverer.discover(allowPrerelease: _allowPrerelease);

    final plan = _planner.plan(
      localVersion: local.dbVersion,
      hasLocalVersionMeta: local.hasVersionMeta,
      latestVersion: discoveryResult.latestVersion,
      edges: discoveryResult.edges,
      latestFullDbAsset: discoveryResult.latestFullDbAsset,
      latestReleaseTag: discoveryResult.latestReleaseTag,
    );

    return LibraryUpdateCheckResult(
      dbPath: dbPath,
      localVersion: local,
      plan: plan,
      isFreshInstall: isFreshInstall,
    );
  }

  /// סוגר את חיבורי ה-HTTP הפנימיים. יש לקרוא כשמסיימים להשתמש
  /// ב-[LibraryManager] (לא הכרחי בין קריאות בודדות — רק בסגירת האפליקציה).
  void dispose() {
    _cloudClient.dispose();
  }
}

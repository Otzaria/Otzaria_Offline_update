import 'dart:io';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';

import 'models/library_update_check_result.dart';
import 'services/companion_assets.dart';
import 'services/companion_assets_installer.dart';
import 'services/companion_assets_mirror.dart';
import 'services/external_update_notice.dart';
import 'services/library_db_locator.dart';
import 'services/library_state_store.dart';
import 'services/library_update_applier.dart';
import 'services/otzaria_process_guard.dart';
import 'services/otzaria_settings_reader.dart';
import 'services/otzaria_settings_writer.dart';
import 'services/recent_library_releases_client.dart';
import 'services/semantic_search_assets.dart';

export 'services/library_update_applier.dart'
    show
        LibraryUpdateApplier,
        LibraryApplyStage,
        LibraryApplyProgress,
        LibraryApplyException,
        ExtractedDbVerifier;

/// נזרק כשאין עדיין מראה מקומית להיבדק מולה — כלומר עוד לא בוצעה הורדה
/// אף פעם. זה מצב תקין לחלוטין בהרצה ראשונה, ולא שגיאה אמיתית: ה-UI אמור
/// לתרגם אותו ל"יש להוריד עדכונים קודם".
class LibraryMirrorMissingException implements Exception {
  const LibraryMirrorMissingException(this.mirrorDir);

  final String mirrorDir;

  @override
  String toString() => AppL10n.strings.libraryDomain.mirrorMissing;
}

/// מה [LibraryManager.downloadToMirror] הביא בפועל — קיים כדי שמצב "עדכון
/// אישי" לא יהיה שקוף: משתמש שהפעיל אותו וגרסתו לא זוהתה מקבל בכל זאת מסד
/// מלא, וזה צריך להיאמר.
class MirrorDownloadOutcome {
  const MirrorDownloadOutcome({
    this.personalFromVersion,
    this.upToDate = false,
  });

  /// הגרסה שממנה ירדו קובצי העדכון במצב אישי. `null` = ירד המסד המלא —
  /// מצב ציבורי, או מצב אישי שלא זוהתה בו גרסה מקומית.
  final int? personalFromVersion;

  /// מצב אישי שבו אין במקור גרסה חדשה מזו שמותקנת — המראה לא נגעה.
  final bool upToDate;
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
    String? stateDir,
    this.allowPrerelease = false,
    this.personalUpdateMode = false,
    Future<String?> Function()? otzariaLaunchPath,
    String? operatingSystem,
    Map<String, String>? environment,
    LocalDbVersionReader versionReader = const LocalDbVersionReader(),
    OtzariaSettingsReader settingsReader = const OtzariaSettingsReader(),
    LibraryUpdateApplier? applier,
  }) : _stateStore = LibraryStateStore(
         p.join(stateDir ?? dataDir, LibraryStateStore.fileName),
         dataDir: dataDir,
       ),
       _planner = const LibraryUpdatePlanner(),
       _versionReader = versionReader,
       _recovery = const LibraryDbRecoveryService(),
       _cloudClient = RecentLibraryReleasesClient(),
       _applier = applier ?? LibraryUpdateApplier() {
    _locator = LibraryDbLocator(
      stateStore: _stateStore,
      settingsReader: settingsReader,
      otzariaLaunchPath: otzariaLaunchPath,
      operatingSystem: operatingSystem,
      environment: environment,
    );
  }

  /// תיקיית הנתונים של הלאנצ'ר (state ומראה). **לא** מיקום ההתקנה של המסד —
  /// ראו [installDbPath].
  ///
  /// `stateDir` שבבנאי מפריד את **קובץ המצב** ממנה, לכונן מוגן-כתיבה שממנו
  /// אפשר רק להתקין (`AppPaths.readOnly` בלאנצ'ר). ברירת המחדל היא [dataDir]
  /// עצמה, כלומר ההתנהגות שהייתה כאן תמיד.
  final String dataDir;

  /// `true` = הערוץ "כולל pre-release". ברירת המחדל `false` — release רגיל
  /// ב-GitHub נחשב יציב, pre-release נחשב לא יציב. ניתן לשינוי בזמן ריצה
  /// כדי שהחלפת ערוץ בהגדרות תיכנס לתוקף בבדיקה/הורדה הבאה.
  bool allowPrerelease;

  /// `true` = "עדכון אישי": [downloadToMirror] מביא רק קובצי עדכון מהגרסה
  /// המותקנת ומעלה, בלי המסד המלא (~1.5GB). ברירת המחדל `false` — התוכנה היא
  /// כלי הפצה, והמסד המלא הוא מה שמאפשר לכונן לשרת מחשב שאין בו אוצריא בכלל.
  /// משפיע על ההורדה בלבד; הבדיקה וההחלה זהות בשני המצבים.
  bool personalUpdateMode;

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

  final RecentLibraryReleasesClient _cloudClient;

  /// מבצע את ההחלה בפועל של תוכנית עדכון (delta/fullDownload) על ה-DB החי —
  /// ראו [applyUpdate].
  final LibraryUpdateApplier _applier;

  /// הקבצים הנלווים לספרייה (תלמוד, קטלוג, מילון). אוצריא מרעננת אותם
  /// **מהרשת** בכל עדכון ספרייה; כאן הם נוסעים במראה ומותקנים אופליין.
  /// תקרת החיבורים המקבילים של כל ההורדה — נכסי הספרייה **והקבצים הנלווים
  /// יחד**. ראו [DownloadScheduler]: מול GitHub אי אפשר לפצל קובץ בודד לכמה
  /// חיבורים, אבל אפשר להוריד קבצים שונים בו-זמנית, וזה מה שמאיץ בפועל.
  final DownloadScheduler _scheduler = DownloadScheduler();

  late final CompanionAssetsMirror _companionsMirror = CompanionAssetsMirror(
    scheduler: _scheduler,
  );
  final CompanionAssetsInstaller _companionsInstaller =
      const CompanionAssetsInstaller();

  /// מכוון את ההגדרה של אוצריא לספרייה שהרגע הותקנה — ראו
  /// [_pointOtzariaAtFreshDb].
  final OtzariaSettingsWriter _settingsWriter = const OtzariaSettingsWriter();

  /// תיקיית המראה של הקבצים הנלווים — לצד מראת הספרייה, תחת אותו שורש.
  String get companionsMirrorDir => p.join(dataDir, 'mirror', 'companions');

  String get semanticMirrorDir => p.join(dataDir, 'mirror', 'semantic');

  LibraryDbLocator _snapshotLocator() => _locator.withSettingsReader(
    OtzariaSettingsSnapshot(_locator.settingsReader),
  );

  Future<OtzariaSettings?> _semanticSettings([
    LibraryDbLocator? locator,
  ]) async {
    final source = locator ?? _locator;
    final launch = await source.otzariaLaunchPath?.call();
    final root = await source.otzariaSettingsRoot(launch);
    return root == null ? null : source.settingsReader.read(root);
  }

  static String _semanticVectorsRoot(OtzariaSettings? settings, String dbPath) {
    final library = settings?.libraryPath;
    return library != null && library.isNotEmpty
        ? p.dirname(library)
        : p.dirname(p.dirname(dbPath));
  }

  Future<String> resolveSemanticVectorsRoot(String dbPath) async =>
      _semanticVectorsRoot(await _semanticSettings(), dbPath);

  Future<bool> semanticConsentGranted() async =>
      (await _semanticSettings())?.searchFeedbackGranted ?? false;

  Future<void> setCustomDbPath(String dbPath) =>
      _stateStore.saveCustomDbPath(dbPath);

  /// נתיב המסד בתוך תיקייה שהמשתמש בחר — לבחירת מיקום להתקנה טרייה, לפני
  /// שיש שם קובץ להצביע עליו.
  String dbPathIn(String dir) => p.join(dir, LibraryDbLocator.databaseFileName);

  Future<String> installDbPath() => _installDbPath(_locator);

  Future<String> _installDbPath(LibraryDbLocator locator) async =>
      await locator.resolveInstallDbPath() ??
      p.join(dataDir, 'library', LibraryDbLocator.databaseFileName);

  /// האם אוצריא תמצא את המסד הזה בעצמה. `false` = המשתמש יצטרך להצביע על
  /// המיקום מתוך אוצריא — ראו [LibraryDbLocator.isKnownToOtzaria].
  Future<bool> isDbPathKnownToOtzaria(String dbPath) =>
      _locator.isKnownToOtzaria(dbPath);

  /// נתיב ה-`seforim.db` שזוהה בפועל, או `null` אם לא נמצא — לתצוגה בממשק.
  /// המיקום מתגלה בכל קריאה מחדש; אין להניח נתיב קבוע.
  Future<String?> currentDbPath() => _locator.resolveDbPath();

  /// גרסת המסד המקומי בלבד, בלי לגעת במראה. `null` כשלא נמצא מסד או שהקובץ
  /// שנבחר אינו נפתח.
  ///
  /// קיימת כי [checkForUpdate] קורא את הגרסה ואז זורק `LibraryMirrorMissingException`
  /// כשעוד לא הורידו כלום — והממשק נשאר עם "לא ידוע" למסד שנקרא בהצלחה,
  /// בדיוק אחרי שהמשתמש בחר אותו ידנית.
  Future<LocalDbVersion?> readLocalVersion() async {
    final path = _lastResolvedDbPath ?? await _locator.resolveDbPath();
    if (path == null) return null;
    try {
      return await _versionReader.readInIsolate(path);
    } catch (_) {
      return null;
    }
  }

  String? _lastResolvedDbPath;

  /// הנתיב ש-[checkForUpdate] האחרון איתר (`null` = לא נמצא DB, או שטרם
  /// רצה בדיקה). קיים כדי שהממשק יציג את הנתיב בלי לקרוא ל-[currentDbPath]
  /// בנוסף: האיתור עצמו קורא את קופסת ההגדרות של אוצריא מעותק, וריצה כפולה
  /// שלו בכל בדיקה הייתה עלות מיותרת בעלייה.
  String? get lastResolvedDbPath => _lastResolvedDbPath;

  String? _lastInstallDbPath;

  /// לאן [checkForUpdate] האחרון היה מתקין ספרייה חדשה — כדי שהממשק יציג את
  /// היעד **לפני** ההתקנה, בלי להריץ את כל האיתור (כולל קריאת ההגדרות של
  /// אוצריא) פעם נוספת.
  String? get lastInstallDbPath => _lastInstallDbPath;

  /// בקשת עדכון האינדקס שממתינה לאוצריא, או `null` כשאין. נכתבת אחרי כל
  /// עדכון מסד מוצלח ושורדת הפעלות מחדש של הלאנצ'ר — ראו
  /// [ExternalUpdateNotice].
  ///
  /// [dbPath] מיותר כשכבר רצה [checkForUpdate]; אחרת המסד מאותר כאן.
  Future<ExternalUpdateNoticeData?> pendingReindexRequest({
    String? dbPath,
  }) async {
    final path = dbPath ?? _lastResolvedDbPath ?? await currentDbPath();
    if (path == null) return null;
    return const ExternalUpdateNotice().read(dbPath: path);
  }

  /// מסמן שהבקשה נמסרה לאוצריא. **רק אחרי מסירה בפועל** — ראו
  /// [ExternalUpdateNotice.clear].
  Future<void> clearReindexRequest({String? dbPath}) async {
    final path = dbPath ?? _lastResolvedDbPath ?? await currentDbPath();
    if (path == null) return;
    await const ExternalUpdateNotice().clear(dbPath: path);
  }

  /// תיקיית המראה המקומית — קבועה, לצד התוכנה (בתוך [dataDir]). זה **המקור
  /// היחיד** שממנו [checkForUpdate] ו-[applyUpdate] קוראים, תמיד; היא נמלאת
  /// אך ורק על ידי [downloadToMirror], וכשהתוכנה על כונן נייד היא נוסעת
  /// יחד איתה למחשב הלא־מקוון בלי שום צעד העתקה נוסף.
  String get mirrorDir => p.join(dataDir, 'mirror', 'library');

  /// `true` אם כבר בוצעה הורדה מוצלחת אחת לפחות. בודק ספציפית את
  /// `releases.json`, שנכתב רק בסוף הורדה מוצלחת — התיקייה עצמה נוצרת מיד
  /// בתחילתה, ולכן קיומה לבדו לא מבטיח תוכן שלם.
  Future<bool> get hasMirror =>
      File(p.join(mirrorDir, LocalMirrorLibraryReleaseClient.manifestFileName))
          .exists();

  /// מוריד את עדכוני הספרייה מ-GitHub אל [mirrorDir] — **הפעולה הכבדה**
  /// שנוגעת ברשת (המסד המלא ~1GB + קובצי העדכון). מביא את ה-release
  /// האחרון בערוץ הנבחר.
  ///
  /// [onCompanionWarning] מקבל כשל בקובץ נלווה בודד — פעולה best-effort
  /// שאינה מפילה את ההורדה, אך גם אינה אמורה להיעלם בשקט: בלעדיה המשתמש
  /// היה מגלה רק במחשב הלא-מקוון שהתלמוד לא נסע איתו.
  ///
  /// [onWarning] מקבל אזהרה מהייצוא עצמו — למשל manifest שאינו קריא ולכן
  /// ה-edge שלו דולג. כשל **רשת** אינו אזהרה אלא זריקה, ראו `export`.
  ///
  /// [onCompanionStage] הוא ערוץ נפרד בכוונה: שני השלבים רצים במקביל, וכשהם
  /// כתבו לאותה שורת מצב היא קפצה בין "מוריד תלמוד" ל"מוריד מסד" בזמן שהמד
  /// מתאר את שניהם יחד. בלעדיו הם חוזרים לערוץ אחד, כמקודם.
  Future<MirrorDownloadOutcome> downloadToMirror({
    bool includeSemanticSearch = false,
    void Function(String stage)? onStage,
    void Function(String? stage)? onCompanionStage,
    void Function(int doneAssets, int totalAssets)? onAssetProgress,
    void Function(int downloaded, int? total)? onBytesProgress,
    void Function(String assetName, Object error)? onCompanionWarning,
    void Function(String warning)? onWarning,
    bool Function()? isCancelled,
  }) async {
    final fromVersion = personalUpdateMode
        ? await recordedPersonalDbVersion()
        : null;
    // מצב אישי בלי גרסה מזוהה נופל להורדה הרגילה במקום להיכשל — מוטב מסד
    // מלא מכונן שאין בו כלום. ה-stage אומר זאת, וגם ה-[MirrorDownloadOutcome].
    if (personalUpdateMode && fromVersion == null) {
      onStage?.call(AppL10n.strings.libraryDomain.exportPersonalVersionUnknown);
    }

    // מונה בייטים אחד לשני השלבים, כי הם רצים יחד — ראו למטה. בלעדיו
    // הייצוא והקבצים הנלווים היו כותבים לסירוגין למד ההתקדמות.
    final bytes = ByteProgressAggregator(onProgress: onBytesProgress);
    final exportBytes = bytes.slot();
    final companionBytes = bytes.slot();

    var exported = true;
    final exporter = LibraryMirrorExporter(
      client: _cloudClient,
      scheduler: _scheduler,
    );

    // **שני השלבים רצים בו-זמנית.** הקבצים הנלווים הם ~509MB שלא היה להם
    // שום קשר לנכסי הספרייה, והם המתינו בתור להורדת המסד (~1.5GB) שסיימה
    // אותם. הם חולקים את אותה תקרת חיבורים ([_scheduler]), ולכן זה לא מוסיף
    // עומס — רק ממלא את הזמן שבו רק המסד הגדול רץ.
    final exportFuture = () async {
      try {
        exported = await exporter.export(
          destDir: mirrorDir,
          allowPrerelease: allowPrerelease,
          fromVersion: fromVersion,
          onStage: onStage,
          onAssetProgress: onAssetProgress,
          onBytesProgress: exportBytes.report,
          onWarning: onWarning,
          isCancelled: isCancelled,
        );
      } catch (_) {
        _cloudClient.forgetReleases();
        rethrow;
      } finally {
        exporter.dispose();
      }
    }();

    // הקבצים הנלווים הם חלק מאותה הורדה: באוצריא הם מתרעננים מהרשת בכל
    // עדכון ספרייה, ובלעדיהם המחשב הלא-מקוון מקבל מסד חדש עם תלמוד/קטלוג/
    // מילון ישנים. כשל בהם אינו מפיל את ההורדה — ראו [CompanionAssetsMirror].
    final companionsFuture = _companionsMirror.sync(
      destDir: companionsMirrorDir,
      onStage: (stage) {
        if (onCompanionStage != null) {
          onCompanionStage(stage);
        } else if (stage != null) {
          onStage?.call(stage);
        }
      },
      onBytesProgress: companionBytes.report,
      onWarning: onCompanionWarning,
      isCancelled: isCancelled,
    );

    // `Future.wait` ממתין לשניהם גם כשאחד נכשל, ואז מפיץ את השגיאה הראשונה.
    // ההמתנה חשובה: שלב שנשאר רץ ברקע ממשיך לכתוב אל המראה אחרי שהמבטל כבר
    // ניקה אותה (ראו `MirrorDownloadUndo`).
    await Future.wait<void>([exportFuture, companionsFuture]);

    if (includeSemanticSearch) {
      final semantic = SemanticSearchAssets(scheduler: _scheduler);
      if (!exported) exportBytes.report(0, 0);
      final semanticBytes = bytes.slot();
      try {
        String? tag;
        if (exported) {
          final discovery = await LibraryUpdateDiscovery(
            client: await _resolveSource(),
          ).discover(allowPrerelease: allowPrerelease);
          tag = discovery.newestReleaseTag;
        } else {
          await peekLatestOnlineVersion();
          tag = _onlineLibraryTag;
        }
        if (tag == null) {
          throw StateError(
            AppL10n.strings.libraryDomain.companionsMirrorMissing,
          );
        }
        await semantic.sync(
          mirrorDir: semanticMirrorDir,
          libraryTag: tag,
          onStage: onStage,
          onBytesProgress: semanticBytes.report,
          isCancelled: isCancelled,
        );
      } catch (e) {
        if (e is PatchDownloadCancelled || (isCancelled?.call() ?? false)) {
          rethrow;
        }
        onCompanionWarning?.call(
          AppL10n.strings.libraryDomain.companionSemanticName,
          e,
        );
      } finally {
        semantic.dispose();
      }
    }

    return MirrorDownloadOutcome(
      personalFromVersion: fromVersion,
      upToDate: !exported,
    );
  }

  /// הגרסה שממנה תצא הורדה במצב אישי: **הנמוכה** מבין הגרסאות שנרשמו
  /// ב-[captureLocalDbVersion]. `null` = טרם נרשמה אף גרסה.
  ///
  /// **אינה קוראת שום מסד.** הקריאה קורית רק בלחיצה מפורשת, ובכוונה: הכונן
  /// מגיע גם למחשב המקוון, ואם *הוא* מחזיק אוצריא — קריאה אוטומטית שם הייתה
  /// דורסת את הגרסה של המחשב שבשבילו מורידים ומשאירה אותו בלי מסלול patches.
  ///
  /// ומדוע הנמוכה: מי שלחץ בכמה מחשבים מקבל הורדה שמשרתת את כולם.
  Future<int?> recordedPersonalDbVersion() =>
      _stateStore.lowestKnownDbVersion();

  Future<bool> isRegisteredForPersonalUpdate() =>
      _stateStore.hasOwnKnownDbVersion();

  Future<int?> captureLocalDbVersion() async {
    final path = await currentDbPath();
    if (path == null) return null;
    _lastResolvedDbPath = path;
    final local = await _versionReader.readInIsolate(path);
    if (!local.hasVersionMeta || local.dbVersion <= 0) return null;
    await _stateStore.recordOwnDbVersion(local.dbVersion);
    return local.dbVersion;
  }

  /// הקבצים הנלווים שהורדה למראה הייתה מביאה עכשיו — הבדיקה הקלה שלהם. הם
  /// מתעדכנים בנפרד מהמסד, ולכן [peekLatestOnlineVersion] אינו רואה אותם.
  Future<Set<CompanionAsset>> peekPendingCompanions() =>
      _companionsMirror.peekPending(destDir: companionsMirrorDir);

  String? _onlineLibraryTag;

  Future<bool> peekPendingSemanticSearch() async {
    if (_onlineLibraryTag == null) await peekLatestOnlineVersion();
    final tag = _onlineLibraryTag;
    if (tag == null) return false;
    final semantic = SemanticSearchAssets();
    try {
      return await semantic.peekPending(
        mirrorDir: semanticMirrorDir,
        libraryTag: tag,
      );
    } finally {
      semantic.dispose();
    }
  }

  Future<int?> peekLatestOnlineVersion() async {
    _onlineLibraryTag = null;
    final latest = _latestOnline(await _cloudClient.fetchFreshReleases());
    _onlineLibraryTag = latest.tag;
    return latest.version;
  }

  ({int? version, String? tag}) _latestOnline(List<LibraryRelease> all) {
    final releases = LibraryUpdateDiscovery.eligibleReleases(
      all,
      allowPrerelease: allowPrerelease,
    );
    var latest = 0;
    String? tag;
    for (final release in releases) {
      if (release.deltaManifestAssets.isEmpty && release.fullDbAsset == null) {
        continue;
      }
      final version = LibraryUpdateDiscovery.releaseVersionOf(release);
      if (version > latest) {
        latest = version;
        tag = release.tag;
      }
    }
    return (version: latest == 0 ? null : latest, tag: tag);
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
  /// אוצריא) — **לא** חוסם ומבקש בחירה ידנית; במקום זה מצביע על מיקום
  /// ההתקנה ([installDbPath]) וממשיך לתוכנית הורדה מלאה, בדיוק כמו שהתקנה
  /// ראשונה של אוצריא עצמה עובדת. ראו
  /// [LibraryUpdateCheckResult.isFreshInstall]. בחירה ידנית של קובץ DB
  /// קיים עדיין אפשרית מרצון דרך [setCustomDbPath].
  Future<LibraryUpdateCheckResult> checkForUpdate() async {
    final locator = _snapshotLocator();
    var dbPath = await locator.resolveDbPath();
    final applying = _appliesInFlight > 0;
    if (dbPath == null && !applying) {
      for (final candidate in {
        ...await locator.dbCandidates(),
        await _installDbPath(locator),
      }) {
        _recovery.restoreRetiredDbIfOrphaned(candidate);
      }
      dbPath = await locator.resolveDbPath();
    }
    _lastResolvedDbPath = dbPath;
    final isFreshInstall = dbPath == null;
    dbPath ??= await _installDbPath(locator);
    _lastInstallDbPath = dbPath;

    const unknownVersion = LocalDbVersion(
      dbVersion: 0,
      schemaVersion: null,
      hasVersionMeta: false,
    );
    LocalDbVersion local;
    String? corruptAfterCrashReason;
    if (isFreshInstall) {
      local = unknownVersion;
    } else {
      final recovery = applying
          ? null
          : await _recovery.recoverIfNeeded(dbPath);
      final interrupted = recovery?.action == RecoveryAction.interrupted;
      if (interrupted &&
          !await _recovery.checkDbHealthAfterCrashAsync(dbPath)) {
        final strings = AppL10n.strings.libraryDomain;
        corruptAfterCrashReason = strings.interruptedUpdateCorruptDb(
          recovery!.detail ?? strings.interruptedUpdateDefaultDetail,
        );
        local = unknownVersion;
      } else {
        if (interrupted) _recovery.clearStaleArtifacts(dbPath);
        local = await _versionReader.readInIsolate(dbPath);
      }
    }

    final source = await _resolveSource();
    final releases = await source.fetchReleases();
    final discoverer = LibraryUpdateDiscovery(
      client: _FetchedReleasesSource(source, releases),
    );
    final discoveryResult = await discoverer.discover(
      allowPrerelease: allowPrerelease,
    );
    final mirrorDownloadIncomplete = await _mirrorDownloadIncomplete(releases);

    // מאיזה release התוכן שעל **המחשב הזה** הגיע, ובאיזו גרסה — בלי זה,
    // release שמפרסם מסד מתוקן באותו db_version נראה כ"מעודכן".
    final applied = await _stateStore.loadAppliedRelease();

    // מה שכבר נמסר למחשב הזה מהמראה — בלעדיו קובץ נלווה שאוצריא עצמה רעננה
    // מהרשת נראה כישן, וההצעה חוזרת בכל פתיחה. ראו
    // `CompanionAssetsInstaller.pendingWork`.
    final companions = await _companionsInstaller.pendingWork(
      mirrorDir: companionsMirrorDir,
      dbPath: dbPath,
      delivered: _deliveredCompanions(
        await _stateStore.loadDeliveredCompanions(),
      ),
    );

    final plan = _planner.plan(
      localVersion: local.dbVersion,
      hasLocalVersionMeta: local.hasVersionMeta,
      latestVersion: discoveryResult.latestVersion,
      edges: discoveryResult.edges,
      latestFullDbAsset: discoveryResult.latestFullDbAsset,
      fullDbReleaseTag: discoveryResult.fullDbReleaseTag,
      latestFullDbVersion: discoveryResult.latestFullDbVersion,
      latestContentTag: discoveryResult.latestContentTag,
      localReleaseTag: applied?.tag,
      localReleaseTagVersion: applied?.dbVersion,
      blockingSchemaVersion: discoveryResult.blockingSchemaVersion,
      blockingPatchFormatVersion: discoveryResult.blockingPatchFormatVersion,
      localVersionUnknownReason: corruptAfterCrashReason,
    );

    final settings = await _semanticSettings(locator);
    final semantic = SemanticSearchAssets();
    final bool semanticPending;
    try {
      semanticPending = await semantic.pending(
        mirrorDir: semanticMirrorDir,
        dbPath: dbPath,
        libraryVersion: plan.kind == LibraryUpdatePlanKind.blocked
            ? local.dbVersion
            : plan.finalTargetVersion ?? local.dbVersion,
        vectorsRootPath: _semanticVectorsRoot(settings, dbPath),
        preferencesReady: settings?.semanticSearchReadyPreferences ?? false,
      );
    } finally {
      semantic.dispose();
    }
    return LibraryUpdateCheckResult(
      dbPath: dbPath,
      localVersion: local,
      plan: plan,
      isFreshInstall: isFreshInstall,
      latestVersion: discoveryResult.latestVersion,
      latestContentTag: discoveryResult.latestContentTag,
      pendingCompanions: companions.pending,
      unavailableCompanions: companions.unavailable,
      mirroredCompanions: companions.mirrored,
      semanticPending: semanticPending,
      semanticConsentGranted: await semanticConsentGranted(),
      mirrorDownloadIncomplete: mirrorDownloadIncomplete,
    );
  }

  Future<bool> _mirrorDownloadIncomplete(List<LibraryRelease> releases) async {
    try {
      final knownSidecars = <String>{};
      for (final release in releases) {
        for (final asset in release.assets) {
          final file = File(asset.downloadUrl);
          if (!await file.exists() ||
              (asset.size > 0 && await file.length() != asset.size)) {
            return true;
          }
          knownSidecars.add(PatchDownloader.resumeSidecarPath(file.path));
        }
      }
      final assets = Directory(p.join(mirrorDir, 'assets'));
      if (!await assets.exists()) return false;
      final sidecarSuffix = PatchDownloader.resumeSidecarPath('');
      await for (final entry in assets.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entry is File &&
            entry.path.endsWith(sidecarSuffix) &&
            !knownSidecars.contains(entry.path)) {
          return true;
        }
      }
      return false;
    } on FileSystemException {
      return true;
    }
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
  /// שבה אין דיווח כזה). בסוף עדכון מוצלח נכתב גם סימון שבקשת עדכון אינדקס
  /// ממתינה לאוצריא — ראו [pendingReindexRequest] ו-
  /// `library_manager/README.md`, "אינדקס החיפוש".
  ///
  /// [onCompanionWarning] מקבל כשל בהתקנת קובץ נלווה בודד — כמו בהורדה, זה
  /// best-effort שאסור לו להיעלם בשקט.
  ///
  /// [onStateWarning] מקבל כשל ברישומי ה-state שאחרי החלה שהצליחה. הם אינם
  /// הופכים אותה לכישלון, אבל בלעדיהם הבדיקה הבאה מציעה שוב את מה שכבר
  /// מותקן — ולכן הכשל חייב להגיע ללוג.
  ///
  /// [useFullDownloadFallback] מריץ את **אותה בדיקה** דרך המסד המלא שבמראה
  /// במקום ה-patches ([LibraryUpdatePlan.fullDownloadFallback]) — מסלול
  /// ההתאוששות אחרי שמסלול הדלתא נכשל, למשל בגלל patch שאינו מתאים למסד
  /// שעל המחשב. אינו קורה מאליו: זו הורדה גדולה, ולכן החלטה של המשתמש.
  ///
  /// [onLibraryLocationNotSet] נקרא אחרי **התקנה טרייה** שלא הצלחנו לכוון
  /// אליה את ההגדרה של אוצריא — ראו [_pointOtzariaAtFreshDb]. בלי להציג
  /// זאת, אוצריא תיפתח על ספרייה ריקה בלי שום רמז למה.
  Future<Set<int>> applyUpdate(
    LibraryUpdateCheckResult check, {
    void Function(LibraryApplyProgress progress)? onProgress,
    void Function(String assetName, Object error)? onCompanionWarning,
    void Function(Object error)? onStateWarning,
    void Function(String dbPath)? onLibraryLocationNotSet,
    bool Function()? isCancelled,
    bool useFullDownloadFallback = false,
  }) async {
    _appliesInFlight++;
    try {
      return await _applyUpdate(
        check,
        onProgress: onProgress,
        onCompanionWarning: onCompanionWarning,
        onStateWarning: onStateWarning,
        onLibraryLocationNotSet: onLibraryLocationNotSet,
        isCancelled: isCancelled,
        useFullDownloadFallback: useFullDownloadFallback,
      );
    } finally {
      _appliesInFlight--;
    }
  }

  int _appliesInFlight = 0;

  Future<Set<int>> _applyUpdate(
    LibraryUpdateCheckResult check, {
    void Function(LibraryApplyProgress progress)? onProgress,
    void Function(String assetName, Object error)? onCompanionWarning,
    void Function(Object error)? onStateWarning,
    void Function(String dbPath)? onLibraryLocationNotSet,
    bool Function()? isCancelled,
    bool useFullDownloadFallback = false,
  }) async {
    // מסלול ההתאוששות: אותה בדיקה, אבל עם המסד המלא במקום ה-patches. לא
    // קורה מעצמו — הורדה של ~1.5GB וחילוץ של ~5.5GB היא החלטה של המשתמש.
    final plan = useFullDownloadFallback
        ? check.plan?.fullDownloadFallback
        : check.plan;
    final dbPath = check.dbPath;
    if (useFullDownloadFallback && plan == null) {
      throw LibraryApplyException(
        AppL10n.strings.libraryDomain.fullDbAssetMissingFromPlan,
      );
    }
    if (dbPath == null || !check.updateAvailable) {
      return const <int>{};
    }

    var booksTouched = const <int>{};
    var appliedVersion = plan?.targetVersion;
    var appliedTag = _contentTagFor(check, plan, appliedVersion);
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
              onStepApplied: (books, _) => partial.addAll(books),
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
          appliedTag = plan.fullDbReleaseTag;
          final followUp = plan.followUpDelta;
          if (followUp != null) {
            try {
              booksTouched = await _applier.applyDelta(
                plan: followUp,
                dbPath: dbPath,
                onProgress: onProgress,
                isCancelled: isCancelled,
                onStepApplied: (_, version) {
                  appliedVersion = version;
                  appliedTag = _contentTagFor(check, plan, version);
                },
              );
              appliedVersion = followUp.targetVersion;
              appliedTag = _contentTagFor(check, plan, appliedVersion);
            } catch (_) {
              await _finishDbUpdate(
                check: check,
                dbPath: dbPath,
                route: ExternalUpdateNotice.routeFull,
                booksTouched: const <int>{},
                version: appliedVersion,
                tag: appliedTag,
                onStateWarning: onStateWarning,
                onLibraryLocationNotSet: onLibraryLocationNotSet,
              );
              rethrow;
            }
          }
          break;
        case LibraryUpdatePlanKind.none:
          break;
        case LibraryUpdatePlanKind.blocked:
          throw LibraryApplyException(
            plan.reason ??
                AppL10n.strings.libraryDomain.blockedNeedsManualAction,
          );
      }

      await _finishDbUpdate(
        check: check,
        dbPath: dbPath,
        route: plan.kind == LibraryUpdatePlanKind.delta
            ? ExternalUpdateNotice.routeDelta
            : ExternalUpdateNotice.routeFull,
        booksTouched: booksTouched,
        version: appliedVersion,
        tag: appliedTag,
        onStateWarning: onStateWarning,
        onLibraryLocationNotSet: onLibraryLocationNotSet,
      );
    }

    // הקבצים הנלווים אחרי המסד — אותו סדר כמו ב-`LibraryUpdateBloc` באוצריא,
    // ובאותה רוח: כשל בהם אינו מבטל עדכון מסד שכבר הצליח.
    final companions = await _companionsInstaller.install(
      mirrorDir: companionsMirrorDir,
      dbPath: dbPath,
      delivered: _deliveredCompanions(
        await _stateStore.loadDeliveredCompanions(),
      ),
      onStage: (stage) => onProgress?.call(
        LibraryApplyProgress(
          stage: LibraryApplyStage.installingCompanions,
          statusText: stage,
        ),
      ),
      onWarning: onCompanionWarning,
      isCancelled: isCancelled,
    );
    // **הראיה שהמראה הזו נמסרה כאן.** בלעדיה הבדיקה הבאה אינה יודעת להבדיל
    // בין קובץ ישן לבין קובץ שאוצריא החליפה אחרינו, ומציעה שוב את מה שכבר
    // מותקן — ולכן כשל ברישום מדווח ואינו נבלע.
    try {
      await _stateStore.saveDeliveredCompanions({
        for (final e in companions.delivered.entries) e.key.name: e.value,
      });
    } catch (e) {
      onStateWarning?.call(e);
    }

    if (check.semanticPending && check.semanticConsentGranted) {
      final name = AppL10n.strings.libraryDomain.companionSemanticName;
      try {
        final settings = await _semanticSettings();
        if (!(settings?.searchFeedbackGranted ?? false)) {
          throw StateError(
            AppL10n.strings.libraryDomain.semanticConsentRequired,
          );
        }
        if (await const OtzariaProcessGuard().isAnyRunning(
          OtzariaProcessGuard.processNamesFor(Platform.operatingSystem),
        )) {
          throw const OtzariaIsRunningException();
        }
        final semantic = SemanticSearchAssets();
        try {
          final version = await _versionReader.readInIsolate(dbPath);
          await semantic.install(
            mirrorDir: semanticMirrorDir,
            dbPath: dbPath,
            libraryVersion: version.dbVersion,
            vectorsRootPath: _semanticVectorsRoot(settings, dbPath),
            beforeActivate: () async {
              if (await const OtzariaProcessGuard().isAnyRunning(
                OtzariaProcessGuard.processNamesFor(Platform.operatingSystem),
              )) {
                throw const OtzariaIsRunningException();
              }
            },
            onStage: (stage) => onProgress?.call(
              LibraryApplyProgress(
                stage: LibraryApplyStage.installingCompanions,
                statusText: stage,
              ),
            ),
            isCancelled: isCancelled,
          );
          if (await const OtzariaProcessGuard().isAnyRunning(
            OtzariaProcessGuard.processNamesFor(Platform.operatingSystem),
          )) {
            throw const OtzariaIsRunningException();
          }
          final launch = await _locator.otzariaLaunchPath?.call();
          final root = await _locator.otzariaSettingsRoot(launch);
          if (root == null ||
              !await const OtzariaSettingsWriter().finishSemanticInstall(
                dataRootPath: root,
              )) {
            throw StateError(
              AppL10n.strings.libraryDomain.companionsInstallFailed(name),
            );
          }
        } finally {
          semantic.dispose();
        }
      } catch (error) {
        onCompanionWarning?.call(name, error);
      }
    }
    onProgress?.call(const LibraryApplyProgress(stage: LibraryApplyStage.done));
    return booksTouched;
  }

  /// הרשומה שנשמרה לפי שם הפריט, מומרת חזרה ל-enum. שם שאינו מוכר (רשומה
  /// מגרסה עתידית) פשוט נופל — הוא ייחשב "לא נמסר", ולכל היותר יוצע שוב.
  Map<CompanionAsset, String> _deliveredCompanions(Map<String, String> raw) {
    final byAsset = <CompanionAsset, String>{};
    for (final asset in CompanionAsset.values) {
      final marker = raw[asset.name];
      if (marker != null) byAsset[asset] = marker;
    }
    return byAsset;
  }

  String? _contentTagFor(
    LibraryUpdateCheckResult check,
    LibraryUpdatePlan? plan,
    int? version,
  ) {
    final latest = check.latestVersion;
    if (version != null && latest != null && version >= latest) {
      return check.latestContentTag ?? plan?.fullDbReleaseTag;
    }
    return plan?.fullDbReleaseTag;
  }

  /// רישומי הסיום של עדכון מסד שהצליח: state מקומי + הסימון לאוצריא.
  /// [version] ו-[tag] הם מה שהמסד באמת הגיע אליו — לא בהכרח יעד התוכנית.
  Future<void> _finishDbUpdate({
    required LibraryUpdateCheckResult check,
    required String dbPath,
    required String route,
    required Set<int> booksTouched,
    required int? version,
    required String? tag,
    void Function(Object error)? onStateWarning,
    void Function(String dbPath)? onLibraryLocationNotSet,
  }) async {
    // רישומי ה-state הם קבצי JSON זעירים, אבל הם נכתבים **אחרי** שהמסד כבר
    // הוחלף. כשל שלהם (כונן מלא, USB שנשלף) אינו הופך עדכון שהצליח לכישלון —
    // אבל הוא כן מחזיר את ההצעה בבדיקה הבאה, ולכן הוא **מדווח ולא נבלע**:
    // בלי זה "מציע לעדכן בכל פתיחה" הוא תקלה בלי שום עקבה בלוג.
    //
    // **כל כתיבה ב-try משלה.** כששלושתן חלקו אחד, כשל בראשונה דילג על השתיים
    // שאחריה — ודווקא הן אלה שמונעות את ההצעה החוזרת.
    Future<void> record(Future<void> Function() write) async {
      try {
        await write();
      } catch (e) {
        onStateWarning?.call(e);
      }
    }

    final locator = _snapshotLocator();
    await record(() async {
      if (check.isFreshInstall && !await locator.isKnownToOtzaria(dbPath)) {
        await _stateStore.saveCustomDbPath(dbPath);
      }
    });
    if (check.isFreshInstall) {
      final pointed = await _pointOtzariaAtFreshDb(dbPath, locator);
      if (!pointed) onLibraryLocationNotSet?.call(dbPath);
    }
    // רושמים מאיזה release התוכן הנוכחי הגיע, **יחד עם הגרסה** — זה מה
    // שמאפשר לזהות בהמשך מסד מתוקן שפורסם באותו db_version, ומונע השוואה
    // מול רישום שנעשה בגרסה אחרת (ראו LibraryUpdatePlanner).
    if (tag != null && version != null && version > 0) {
      await record(
        () => _stateStore.saveAppliedRelease(tag: tag, dbVersion: version),
      );
    }
    if (version != null && version > 0) {
      await record(() => _stateStore.recordOwnDbVersion(version));
    }
    // מה השתנה, לטובת אינדקס החיפוש של אוצריא — ראו [ExternalUpdateNotice].
    await const ExternalUpdateNotice().write(
      dbPath: dbPath,
      route: route,
      booksTouched: booksTouched,
      dbVersion: version,
      releaseTag: tag,
    );
  }

  Future<bool> _pointOtzariaAtFreshDb(
    String dbPath,
    LibraryDbLocator locator,
  ) async {
    try {
      final launchPath = await locator.otzariaLaunchPath?.call();
      final root = await locator.otzariaSettingsRoot(launchPath);
      if (root == null) return false;

      final current = await locator.settingsReader.read(root);
      if (current != null && !current.isEmpty) {
        final resolved = current.resolveDbPath(
          path: p.context,
          fileName: LibraryDbLocator.databaseFileName,
        );
        return resolved != null && p.equals(resolved, dbPath);
      }

      // קופסה שקיימת אך לא נקראה (פגומה, מוצפנת, פורמט אחר) מוחזרת
      // כ-`null` בדיוק כמו קופסה שאינה קיימת — והכתיבה לתוכה עלולה
      // להחמיר. כותבים רק כשאין קובץ בכלל, או כשהוא נקרא והתברר כריק.
      final boxFile = File(p.join(root, OtzariaSettingsReader.boxFileName));
      if (current == null && await boxFile.exists()) return false;

      // פתיחת הקופסה במקומה לוקחת נעילה בתיקייה של אוצריא. אוצריא רצה
      // מחזיקה אותה, וניסיון כזה נוגע בקובץ הנעילה שלה — ולכן פשוט לא
      // מנסים. ההחלה עצמה כבר חסומה כשהיא פתוחה; זו הבדיקה לתהליך שעלה
      // באמצע העדכון הארוך.
      if (await const OtzariaProcessGuard().isAnyRunning(
        OtzariaProcessGuard.processNamesFor(Platform.operatingSystem),
      )) {
        return false;
      }

      return await _settingsWriter.pointLibraryAt(
        dataRootPath: root,
        dbPath: dbPath,
        // אוצריא מותקנת אך מעולם לא רצה — אין עדיין שורש נתונים, ואנחנו
        // יוצרים אותו. בלי נתיב הפעלה ידוע לא ניצור תיקיות מיותרות.
        allowCreate: launchPath != null,
      );
    } catch (_) {
      return false;
    }
  }

  /// סוגר את חיבורי ה-HTTP הפנימיים. יש לקרוא כשמסיימים להשתמש
  /// ב-[LibraryManager] (לא הכרחי בין קריאות בודדות — רק בסגירת האפליקציה).
  void dispose() {
    _cloudClient.dispose();
    _applier.dispose();
  }
}

class _FetchedReleasesSource implements LibraryReleaseSource {
  _FetchedReleasesSource(this._source, this._releases);

  final LibraryReleaseSource _source;
  final List<LibraryRelease> _releases;

  @override
  Future<List<LibraryRelease>> fetchReleases() async => _releases;

  @override
  Future<DeltaManifest> fetchManifest(String url) => _source.fetchManifest(url);

  @override
  void dispose() => _source.dispose();
}

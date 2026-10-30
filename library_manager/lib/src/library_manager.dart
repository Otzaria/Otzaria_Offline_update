import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:http/http.dart' as http;
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart' show OtzariaCapabilities;
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';

import 'models/library_update_check_result.dart';
import 'services/companion_assets.dart';
import 'services/companion_assets_installer.dart';
import 'services/companion_assets_mirror.dart';
import 'services/external_update_notice.dart';
import 'services/library_changes_notes.dart';
import 'services/library_db_locator.dart';
import 'services/library_state_store.dart';
import 'services/library_update_applier.dart';
import 'services/library_updater_l10n.dart';
import 'services/mirror_download_bound.dart';
import 'services/otzaria_instance_lock.dart';
import 'services/otzaria_process_guard.dart';
import 'services/otzaria_settings_reader.dart';
import 'services/otzaria_settings_writer.dart';
import 'services/readable_releases_client.dart';
import 'services/readable_schema_limit.dart';
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

/// `releases.json` קיים אך אינו קריא — כונן שמערכת הקבצים שלו נפגמה (issue
/// #127). רק הורדה מחדש במחשב המקוון כותבת אותו מחדש; [detail] הולך ללוג.
class LibraryMirrorDamagedException implements Exception {
  const LibraryMirrorDamagedException(this.mirrorDir, this.detail);

  final String mirrorDir;
  final String detail;

  @override
  String toString() => AppL10n.strings.libraryDomain.mirrorDamaged;
}

/// מה [LibraryManager.downloadToMirror] הביא בפועל — קיים כדי שמצב "עדכון
/// אישי" לא יהיה שקוף: משתמש שהפעיל אותו וגרסתו לא זוהתה מקבל בכל זאת מסד
/// מלא, וזה צריך להיאמר.
class MirrorDownloadOutcome {
  const MirrorDownloadOutcome({
    this.personalFromVersion,
    this.upToDate = false,
    this.repairedDamagedMirror = false,
    this.newerNeedsOtzaria,
    this.keptNewerMirror = false,
    this.libraryLeftAsIs = false,
    this.unreadableManifests = const {},
  });

  /// הגרסה שממנה ירדו קובצי העדכון במצב אישי. `null` = ירד המסד המלא —
  /// מצב ציבורי, או מצב אישי שלא זוהתה בו גרסה מקומית.
  final int? personalFromVersion;

  /// מצב אישי שבו אין במקור גרסה חדשה מזו שמותקנת — המראה לא נגעה.
  final bool upToDate;

  /// מצב אישי "מעודכן" עם `releases.json` פגום — המראה נבנתה מחדש במסלול המלא.
  final bool repairedDamagedMirror;

  /// The newest library left out because the Otzaria installers on the drive
  /// cannot read its schema; `null` when nothing was left out.
  final int? newerNeedsOtzaria;

  /// The mirror already held a newer library than those installers read, so
  /// it was left as it was rather than replaced with an older one.
  final bool keptNewerMirror;

  /// The export did not run because of that limit — [keptNewerMirror], or
  /// nothing online is readable — so the mirror was not touched.
  final bool libraryLeftAsIs;

  /// Update manifests that could not be read: whether a newer readable library
  /// exists is unknown, so nothing here may be read as "up to date".
  final Set<String> unreadableManifests;
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
    Future<String?> Function()? otzariaAppVersion,
    Future<int?> Function()? mirroredReadableDbSchema,
    OtzariaInstanceLock? instanceLock,
    String? operatingSystem,
    Map<String, String>? environment,
    LocalDbVersionReader versionReader = const LocalDbVersionReader(),
    OtzariaSettingsReader settingsReader = const OtzariaSettingsReader(),
    OtzariaProcessGuard processGuard = const OtzariaProcessGuard(),
    RecentLibraryReleasesClient? releaseClient,
    LibraryUpdateApplier? applier,
    this.semanticEngineFactory,
    @visibleForTesting this.semanticAssetsFactory,
  }) : _stateStore = LibraryStateStore(
         p.join(stateDir ?? dataDir, LibraryStateStore.fileName),
         dataDir: dataDir,
       ),
       _planner = const OfflineLibraryUpdatePlanner(),
       _versionReader = versionReader,
       _recovery = const OfflineLibraryDbRecoveryService(),
       _processGuard = processGuard,
       _otzariaAppVersion = otzariaAppVersion,
       _mirroredReadableDbSchema = mirroredReadableDbSchema,
       _instanceLock = instanceLock,
       _cloudClient = releaseClient ?? RecentLibraryReleasesClient(),
       _applier = applier ?? LibraryUpdateApplier(processGuard: processGuard) {
    useLibraryUpdaterL10n();
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

  set networkTimeout(Duration value) {
    _cloudClient.timeout = value;
    _applier.connectTimeout = value;
  }

  final LibraryStateStore _stateStore;
  late final LibraryDbLocator _locator;
  final OfflineLibraryUpdatePlanner _planner;
  final LocalDbVersionReader _versionReader;

  /// נשאר לצורך [checkForUpdate] בלבד — מזהה ומנקה שרידי-קריסה מהתקנות
  /// ישנות של הלאנצ'ר (מגרסאות קודמות שכן ביצעו patch/apply בפועל). לא
  /// כותב/מחיל דבר בעצמו.
  final OfflineLibraryDbRecoveryService _recovery;

  final OtzariaProcessGuard _processGuard;

  final Future<String?> Function()? _otzariaAppVersion;

  /// The schema the drive's Otzaria installers read, for the semantic peek.
  final Future<int?> Function()? _mirroredReadableDbSchema;

  final OtzariaInstanceLock? _instanceLock;

  final RecentLibraryReleasesClient _cloudClient;

  final LibraryUpdateApplier _applier;

  /// Replaces the native engine of the smart-search install, for tests.
  final SemanticEngineFactory? semanticEngineFactory;

  /// Replaces the smart-search download and light check, for tests.
  final SemanticSearchAssets Function(DownloadScheduler scheduler)?
  semanticAssetsFactory;

  /// הקבצים הנלווים לספרייה (תלמוד, קטלוג, מילון). אוצריא מרעננת אותם
  /// **מהרשת** בכל עדכון ספרייה; כאן הם נוסעים במראה ומותקנים אופליין.
  /// תקרת הקבצים המקבילים של כל ההורדה — נכסי הספרייה **והקבצים הנלווים
  /// יחד**. ראו [DownloadScheduler] ו-`connectionsPerFile`.
  final DownloadScheduler _scheduler = DownloadScheduler();

  CompanionAssetsMirror? _companionsMirrorInstance;

  CompanionAssetsMirror get _companionsMirror => _companionsMirrorInstance ??=
      CompanionAssetsMirror(scheduler: _scheduler);
  final CompanionAssetsInstaller _companionsInstaller =
      const CompanionAssetsInstaller();

  final OtzariaSettingsWriter _settingsWriter = const OtzariaSettingsWriter();

  /// The one boundary for `seforim_library_updater`, whose full-drive
  /// failures arrive as text: a recognised one crosses as [StorageFullException].
  Future<T> _storageAware<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (error, stack) {
      final full = storageFullFromUpstream(error);
      if (full == null) rethrow;
      Error.throwWithStackTrace(full, stack);
    }
  }

  Future<bool> _isOtzariaRunning() => _processGuard.isAnyRunning(
    OtzariaProcessGuard.processNamesFor(Platform.operatingSystem),
  );

  Future<void> _throwIfOtzariaRunning() async {
    if (await _isOtzariaRunning()) throw const OtzariaIsRunningException();
  }

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

  Future<void> setCustomDbPath(String dbPath, {bool explicit = false}) =>
      _stateStore.saveCustomDbPath(dbPath, explicit: explicit);

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
  Future<bool> get hasMirror => File(
    p.join(mirrorDir, LocalMirrorLibraryReleaseClient.manifestFileName),
  ).exists();

  Future<bool> _mirrorManifestDamaged() async {
    if (!await hasMirror) return false;
    try {
      await LocalMirrorLibraryReleaseClient(
        mirrorDir: mirrorDir,
      ).fetchReleases();
      return false;
    } catch (e) {
      if (_isDamagedManifestError(e)) return true;
      rethrow;
    }
  }

  // שדה מסוג שגוי בתוך JSON תקין נופל ב-cast, לא ב-LocalMirrorException.
  static bool _isDamagedManifestError(Object e) =>
      e is LocalMirrorException || e is TypeError || e is FormatException;

  /// [readableDbSchema] is the highest schema an Otzaria installer on the
  /// drive reads; nothing above it is downloaded. `null` = no such limit.
  Future<MirrorDownloadOutcome> downloadToMirror({
    bool includeSemanticSearch = false,
    int? readableDbSchema,
    void Function(String stage)? onStage,
    void Function(String? stage)? onCompanionStage,
    void Function(int doneAssets, int totalAssets)? onAssetProgress,
    void Function(int downloaded, int? total)? onBytesProgress,
    void Function(String assetName, Object error)? onCompanionWarning,
    void Function(String warning)? onWarning,
    bool Function()? isCancelled,
  }) async {
    // שני מייצאים על אותה מראה היו מתנגשים; הבדיקה המוקדמת נעצרת ומתפנה קודם.
    if (_sizeProbe case final probe?) {
      probe.stop();
      await probe.done;
    }
    final fromVersion = personalUpdateMode
        ? await recordedPersonalDbVersion()
        : null;
    if (personalUpdateMode && fromVersion == null) {
      onStage?.call(AppL10n.strings.libraryDomain.exportPersonalVersionUnknown);
    }

    final bytes = ByteProgressAggregator(onProgress: onBytesProgress);
    final exportBytes = bytes.slot();
    final companionBytes = bytes.slot();

    var exported = true;
    var exportFailed = false;
    var repaired = false;
    var keptNewer = false;
    var leftAsIs = false;
    int? mirroredLatest;
    // A full drive found by one branch stops the other from starting assets;
    // it is not a user cancel and surfaces as the storage failure itself.
    (StorageFullException, StackTrace)? gateFailure;
    var exportStoppedByGate = false;
    bool stopRequested() =>
        gateFailure != null || (isCancelled?.call() ?? false);

    final readable =
        readableDbSchema != null && readableDbSchema < kSupportedDbSchemaVersion
        ? ReadableReleasesClient(
            _cloudClient,
            readableSchema: readableDbSchema,
            allowPrerelease: allowPrerelease,
            fromVersion: fromVersion,
            scheduler: _scheduler,
            isCancelled: stopRequested,
          )
        : null;

    Future<bool> runExport(int? from) async {
      final exporter = LibraryMirrorExporter(
        supportedDbSchemaVersion: kSupportedDbSchemaVersion,
        client: readable ?? _cloudClient,
        scheduler: _scheduler,
      );
      try {
        return await _storageAware(
          () => exporter.export(
            destDir: mirrorDir,
            allowPrerelease: allowPrerelease,
            fromVersion: from,
            onStage: onStage,
            onAssetProgress: onAssetProgress,
            onBytesProgress: exportBytes.report,
            onWarning: onWarning,
            isCancelled: stopRequested,
          ),
        );
      } finally {
        exporter.dispose();
      }
    }

    final exportFuture = () async {
      try {
        if (readable != null) {
          await readable.fetchReleases();
          final online = readable.newestReadableVersion;
          final mirrored = await _mirroredReach(
            readable.readableSchema,
            fromVersion: fromVersion,
          );
          mirroredLatest = mirrored?.latest;
          // Reaching the same number is not holding the same content: a
          // re-publish or a replaced asset must still reach the drive.
          final servesOnline =
              mirrored != null &&
              (mirrored.readable > (online ?? 0) ||
                  // A personal machine already holds its own version.
                  (fromVersion != null && (online ?? 0) <= fromVersion) ||
                  (mirrored.readable == online &&
                      _holdsOnline(
                        mirrored.present,
                        mirrored.route,
                        await readable.fetchReleases(),
                        online!,
                        schema: readable.readableSchema,
                        fromVersion: fromVersion,
                      )));
          if (mirrored != null &&
              (online ?? 0) < mirrored.latest &&
              servesOnline) {
            onStage?.call(AppL10n.strings.libraryDomain.exportKeptNewerMirror);
            exported = false;
            keptNewer = leftAsIs = true;
            return;
          }
          // Nothing readable to gain, and what cannot be read decides nothing:
          // rewriting would only cost the drive what it already serves.
          if (online == null ||
              (readable.unreadableManifests.isNotEmpty && servesOnline)) {
            exported = false;
            leftAsIs = true;
            return;
          }
        }
        exported = await runExport(fromVersion);
        // ייצוא אישי "מעודכן" אינו כותב את releases.json, ולכן מראה פגומה
        // מתוקנת אז רק בייצוא מלא.
        if (!exported && await _mirrorManifestDamaged()) {
          onStage?.call(
            AppL10n.strings.libraryDomain.exportPersonalMirrorDamaged,
          );
          exported = await runExport(null);
          repaired = true;
        }
      } catch (e) {
        _cloudClient.forgetReleases();
        final gate = gateFailure;
        if (gate != null &&
            (e is PatchDownloadCancelled ||
                e is StateError &&
                    e.message ==
                        AppL10n.strings.libraryDomain.exportCancelled) &&
            !(isCancelled?.call() ?? false)) {
          exportStoppedByGate = true;
          Error.throwWithStackTrace(gate.$1, gate.$2);
        }
        exportFailed = true;
        rethrow;
      }
    }();

    final companionsFuture = () async {
      try {
        await _companionsMirror.sync(
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
          onStorageFailure: (error, stack) => gateFailure ??= (error, stack),
          isCancelled: () => exportFailed || (isCancelled?.call() ?? false),
        );
      } catch (error, stack) {
        final full = storageFullFromUpstream(error);
        if (full == null) rethrow;
        gateFailure ??= (full, stack);
        Error.throwWithStackTrace(full, stack);
      }
    }();

    (StorageFullException, StackTrace)? storageFailure;
    try {
      await Future.wait<void>([exportFuture, companionsFuture]);
    } on StorageFullException catch (error, stack) {
      // A full drive in the companions leaves the finished DB export valid.
      if (exportFailed && !exportStoppedByGate) rethrow;
      storageFailure = (error, stack);
    }
    if (storageFailure == null && !(isCancelled?.call() ?? false)) {
      await _syncChangesNotes(
        onWarning: onCompanionWarning,
        isCancelled: isCancelled,
      );
    }

    // Under a limit the vectors follow the library the drive now reaches, not
    // the base full DB; the light check then reads the same answer back.
    String? readableTag;
    // A library is reached but which release's content it is stays unproven —
    // never the same as "nothing to fetch".
    var targetUnknown = false;
    if (readable != null && !(isCancelled?.call() ?? false)) {
      final schema = readable.readableSchema;
      final reach = readable.newestReadableVersion == null
          ? null
          : await _mirroredReach(schema, fromVersion: fromVersion);
      if (reach != null && reach.readable > 0) {
        // Personal mode at its own version knows the number only: a release
        // is named only when no re-publish leaves the content in doubt.
        final candidates =
            OfflineLibraryUpdateDiscovery.eligibleReleases(
              await readable.fetchReleases(),
              allowPrerelease: allowPrerelease,
            ).where(
              (r) =>
                  OfflineLibraryUpdateDiscovery.releaseVersionOf(r) ==
                      reach.readable &&
                  (r.fullDbAssetFor(maxSchemaVersion: schema) != null ||
                      r.deltaManifestAssets.isNotEmpty),
            );
        readableTag = reach.uncertain
            ? null
            : reach.tag ??
                  (candidates.length == 1 ? candidates.single.tag : null);
        targetUnknown = readableTag == null;
      }
    }
    // Nothing readable online means no library for vectors to match.
    if (storageFailure == null &&
        includeSemanticSearch &&
        (readable == null || readableTag != null)) {
      final semantic =
          semanticAssetsFactory?.call(_scheduler) ??
          SemanticSearchAssets(scheduler: _scheduler);
      if (!exported) exportBytes.report(0, 0);
      final semanticBytes = bytes.slot();
      try {
        String? tag;
        if (readable != null) {
          tag = readableTag;
        } else if (exported) {
          final discovery = await OfflineLibraryUpdateDiscovery(
            supportedDbSchemaVersion: kSupportedDbSchemaVersion,
            client: await _resolveSource(),
          ).discover(allowPrerelease: allowPrerelease);
          tag = discovery.newestReleaseTag;
        } else {
          final latest = _latestOnline(await _cloudClient.fetchReleases());
          _onlineLibraryTag = latest?.tag;
          tag = latest?.tag;
        }
        if (tag == null) {
          throw StateError(
            AppL10n.strings.libraryDomain.companionsMirrorMissing,
          );
        }
        final releases = _cloudClient.lastFetchedReleases ?? const [];
        await semantic.sync(
          mirrorDir: semanticMirrorDir,
          libraryTag: tag,
          // The online machine's Otzaria fetches its vectors itself.
          fleet: SemanticFleet(
            await _stateStore.liveSemanticStates(excludeOwn: true),
          ),
          libraryTagFor: (version) => _libraryTagFor(releases, version),
          onStage: onStage,
          onBytesProgress: semanticBytes.report,
          isCancelled: stopRequested,
        );
      } catch (e, stack) {
        if (e is PatchDownloadCancelled || (isCancelled?.call() ?? false)) {
          rethrow;
        }
        final full = storageFullFromUpstream(e);
        if (full != null) {
          storageFailure = (
            !identical(full, e) && full.dir == null && full.message == null
                ? StorageFullException(
                    dir: semanticMirrorDir,
                    cause: full.cause,
                  )
                : full,
            stack,
          );
        } else {
          onCompanionWarning?.call(
            AppL10n.strings.libraryDomain.companionSemanticName,
            e,
          );
        }
      } finally {
        semantic.dispose();
      }
    }
    // Saved last: a cancel restores the mirror but not this file.
    if (readable != null &&
        readable.unreadableManifests.isEmpty &&
        !exportStoppedByGate &&
        !(isCancelled?.call() ?? false)) {
      await _saveReadableTarget(
        readable.readableSchema,
        readableTag,
        unknown: targetUnknown,
        online: readable.onlineReleases,
        fromVersion: fromVersion,
      );
    }
    // The finished components are on the drive; a full drive stops the rest.
    if (storageFailure != null) {
      Error.throwWithStackTrace(storageFailure.$1, storageFailure.$2);
    }
    return MirrorDownloadOutcome(
      personalFromVersion: repaired ? null : fromVersion,
      upToDate:
          !exported &&
          !leftAsIs &&
          (readable?.unreadableManifests.isEmpty ?? true),
      repairedDamagedMirror: repaired,
      newerNeedsOtzaria: switch (readable?.newerUnreadableVersion) {
        final newer? when !keptNewer || newer > (mirroredLatest ?? 0) => newer,
        _ => null,
      },
      keptNewerMirror: keptNewer,
      libraryLeftAsIs: leftAsIs,
      unreadableManifests: readable?.unreadableManifests ?? const {},
    );
  }

  ({void Function() stop, Future<void> done})? _sizeProbe;

  /// כמה [downloadToMirror] יביא בפועל, בלי להוריד דבר: מריץ את התכנון של המנוע
  /// (קובצי התיאור בלבד) ועוצר כשהוא מכריז על היעד. null בכשל או אחרי [timeout].
  Future<int?> probeMirrorDownloadBytes({
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (_mirroredReadableDbSchema != null) return null;
    // שתי בדיקות במקביל מתחרות על אותה מראה; השאלה החדשה גוברת.
    _sizeProbe?.stop();
    var stopped = false;
    int? exportBytes;
    Future<int?> run() async {
      final fromVersion = personalUpdateMode
          ? await recordedPersonalDbVersion()
          : null;
      final exporter = LibraryMirrorExporter(
        supportedDbSchemaVersion: kSupportedDbSchemaVersion,
        client: _cloudClient,
      );
      final export = () async {
        try {
          final exported = await exporter.export(
            destDir: mirrorDir,
            allowPrerelease: allowPrerelease,
            fromVersion: fromVersion,
            onBytesProgress: (_, total) {
              exportBytes ??= total ?? -1;
              stopped = true;
            },
            isCancelled: () => stopped,
          );
          if (!exported) exportBytes ??= 0;
        } on StateError {
          if (exportBytes == null) rethrow;
        } finally {
          exporter.dispose();
        }
      }();
      final companions = _companionsMirror
          .peekPending(destDir: companionsMirrorDir)
          .then((_) => _companionsMirror.peekedPendingBytes);
      final results = await Future.wait<int?>([
        export.then((_) => exportBytes),
        companions,
      ]);
      if (results.any((bytes) => bytes == null || bytes < 0)) return null;
      return results[0]! + results[1]!;
    }

    final work = run();
    final probe = (
      stop: () => stopped = true,
      done: work.then<void>((_) {}, onError: (_) {}),
    );
    _sizeProbe = probe;
    try {
      return await work.timeout(timeout);
    } on TimeoutException {
      stopped = true;
      return null;
    } finally {
      unawaited(
        probe.done.whenComplete(() {
          if (identical(_sizeProbe, probe)) _sizeProbe = null;
        }),
      );
    }
  }

  Future<void> _saveReadableTarget(
    int schema,
    String? tag, {
    required bool unknown,
    required List<LibraryRelease> online,
    required int? fromVersion,
  }) async {
    try {
      await _stateStore.saveReadableSemanticTarget({
        'schema': schema,
        'allowPrerelease': allowPrerelease,
        'online': _lightReadable(online, schema).online,
        'fromVersion': fromVersion,
        'mirror': await _mirrorIdentity(),
        'tag': tag,
        'unknown': unknown,
      });
    } on Exception {
      // Without it the light check reports "unknown", which is still true.
    }
  }

  /// The verdict describes this mirror only: a deleted, rebuilt or rolled
  /// back `releases.json` voids it.
  Future<String?> _mirrorIdentity() async {
    final file = File(
      p.join(mirrorDir, LocalMirrorLibraryReleaseClient.manifestFileName),
    );
    try {
      return '${sha256.convert(await file.readAsBytes())}';
    } on FileSystemException {
      return null;
    }
  }

  /// How far [schema] reads along readable patches from the mirror's full DB or
  /// [fromVersion] — counting only assets complete on the drive.
  Future<
    ({
      int latest,
      int readable,
      String? tag,
      bool uncertain,
      List<LibraryRelease> present,
      ReadableSchemaRoute route,
    })?
  >
  _mirroredReach(int schema, {int? fromVersion}) async {
    if (!await hasMirror) return null;
    try {
      final source = LocalMirrorLibraryReleaseClient(mirrorDir: mirrorDir);
      final named = await source.fetchReleases();
      Future<OfflineLibraryDiscoveryResult> discover(
        List<LibraryRelease> releases,
      ) => OfflineLibraryUpdateDiscovery(
        supportedDbSchemaVersion: kSupportedDbSchemaVersion,
        client: _FetchedReleasesSource(source, releases),
      ).discover(allowPrerelease: allowPrerelease);

      final present = [
        for (final release in named)
          LibraryRelease(
            tag: release.tag,
            isPrerelease: release.isPrerelease,
            isDraft: release.isDraft,
            publishedAt: release.publishedAt,
            assets: [
              for (final asset in release.assets)
                if (asset.size <= 0 || await _completeOnDisk(asset)) asset,
            ],
          ),
      ];
      final route = ReadableSchemaRoute.limit(
        discovery: await discover(present),
        releases: present,
        allowPrerelease: allowPrerelease,
        readableSchema: schema,
      );
      final reached = {?route.latestFullDbVersion, ?fromVersion};
      for (var grew = true; grew;) {
        grew = false;
        for (final edge in route.edges) {
          if (reached.contains(edge.fromVersion) &&
              reached.add(edge.toVersion)) {
            grew = true;
          }
        }
      }
      final reach = reached.fold(0, (a, b) => a > b ? a : b);
      final contents = _plannedContents(
        present,
        route,
        reach,
        // A lagging machine plans from patches below the base too.
        starts: fromVersion != null
            ? [if (fromVersion < reach) fromVersion]
            : [
                null,
                ...{
                  ...reached,
                  for (final edge in route.edges) edge.fromVersion,
                }.where((v) => v < reach),
              ],
        reached: reached,
      );
      return (
        latest: (await discover(named)).latestVersion,
        readable: reach,
        tag: contents.length == 1
            ? _tagForVersion(contents.values.single.toList(), reach)
            : null,
        uncertain: contents.length > 1,
        present: present,
        route: route,
      );
    } catch (e) {
      if (_isDamagedManifestError(e)) return null;
      rethrow;
    }
  }

  /// The content the offline planner itself installs into [reach] from each of
  /// [starts] (`null` = an empty machine), keyed by content hash, with every
  /// release on the drive delivering that same content. Reachability alone
  /// proves nothing: two re-publishes of one patch may lead to different DBs.
  Map<String, Set<LibraryRelease>> _plannedContents(
    List<LibraryRelease> present,
    ReadableSchemaRoute route,
    int reach, {
    required List<int?> starts,
    required Set<int> reached,
  }) {
    Iterable<LibraryRelease> releasesOf(PatchEdge edge) => present.where(
      (r) => r.assets.any((a) => a.downloadUrl == edge.manifestUrl),
    );
    final contents = <String, Set<LibraryRelease>>{};
    for (final local in starts) {
      final plan = _planner.plan(
        localVersion: local ?? 0,
        hasLocalVersionMeta: local != null,
        latestVersion: reach,
        edges: route.edges,
        latestFullDbAsset: route.latestFullDbAsset,
        fullDbReleaseTag: route.fullDbReleaseTag,
        latestFullDbVersion: route.latestFullDbVersion,
      );
      if (plan.finalTargetVersion != reach) continue;
      final steps = switch (plan.kind) {
        LibraryUpdatePlanKind.delta => plan.deltaSteps,
        LibraryUpdatePlanKind.fullDownload =>
          plan.followUpDelta?.deltaSteps ?? const <PatchEdge>[],
        _ => null,
      };
      if (steps == null) continue;
      if (steps.isEmpty) {
        contents
            .putIfAbsent('full:${plan.fullDbReleaseTag}', () => {})
            .addAll(present.where((r) => r.tag == plan.fullDbReleaseTag));
        continue;
      }
      contents
          .putIfAbsent(steps.last.manifest.toContentHash, () => {})
          .addAll(releasesOf(steps.last));
    }
    // Other re-publishes that lead to the very same content name it too.
    for (final edge in route.edges) {
      if (edge.toVersion == reach && reached.contains(edge.fromVersion)) {
        contents[edge.manifest.toContentHash]?.addAll(releasesOf(edge));
      }
    }
    // A full DB and a patch of one release are one content.
    for (final key
        in contents.keys.where((k) => k.startsWith('full:')).toList()) {
      final tag = key.substring('full:'.length);
      final same = contents.entries
          .where((e) => !e.key.startsWith('full:'))
          .where((e) => e.value.any((r) => r.tag == tag))
          .firstOrNull;
      if (same != null) same.value.addAll(contents.remove(key)!);
    }
    return contents;
  }

  /// Whether the mirror's own route (full DB, then patches) reaches [version]
  /// on assets [online] still serves: same release, GitHub id and `updatedAt`.
  bool _holdsOnline(
    List<LibraryRelease> present,
    ReadableSchemaRoute route,
    List<LibraryRelease> online,
    int version, {
    required int schema,
    int? fromVersion,
  }) {
    final eligible = OfflineLibraryUpdateDiscovery.eligibleReleases(
      online,
      allowPrerelease: allowPrerelease,
    ).toList();
    // [online] lists the newest re-publish of each version first; with
    // [newest], only that carrier of the asset kind counts.
    bool same(
      LibraryRelease held,
      Iterable<ReleaseAsset> assets, {
      required bool Function(LibraryRelease release) carries,
      bool newest = true,
    }) {
      final version = OfflineLibraryUpdateDiscovery.releaseVersionOf(held);
      final source = eligible
          .where(
            (r) =>
                OfflineLibraryUpdateDiscovery.releaseVersionOf(r) == version &&
                carries(r) &&
                (newest || r.tag == held.tag),
          )
          .firstOrNull;
      if (source == null || source.tag != held.tag) return false;
      return assets.every(
        (asset) => source.assets.any(
          (s) =>
              // The drive holds a split full DB as its assembled archive.
              (s.isSplitFullDbManifest ? s.splitArchiveName : s.name) ==
                  asset.name &&
              (s.id == null
                  ? s.size == asset.size
                  : s.id == asset.id && s.updatedAt == asset.updatedAt),
        ),
      );
    }

    final reached = <int>{?fromVersion};
    final base = present
        .where((r) => r.tag == route.fullDbReleaseTag)
        .firstOrNull;
    final full = route.latestFullDbAsset;
    if (base != null &&
        full != null &&
        same(
          base,
          [full],
          carries: (r) => r.fullDbAssetFor(maxSchemaVersion: schema) != null,
          // The exporter keeps an older base on the drive and only drops one
          // whose version is the latest and was re-published.
          newest: route.latestFullDbVersion == version,
        )) {
      reached.add(route.latestFullDbVersion!);
    }
    for (var grew = true; grew;) {
      grew = false;
      for (final edge in route.edges) {
        if (!reached.contains(edge.fromVersion) ||
            reached.contains(edge.toVersion)) {
          continue;
        }
        final urls = {edge.manifestUrl, ...edge.patchFileUrls.values};
        final held = present
            .where(
              (r) => r.assets.any((a) => a.downloadUrl == edge.manifestUrl),
            )
            .firstOrNull;
        final manifest = held?.assets
            .firstWhere((a) => a.downloadUrl == edge.manifestUrl)
            .name;
        if (held != null &&
            same(
              held,
              held.assets.where((a) => urls.contains(a.downloadUrl)),
              carries: (r) =>
                  r.deltaManifestAssets.any((a) => a.name == manifest),
            )) {
          grew = reached.add(edge.toVersion) || grew;
        }
      }
    }
    return reached.contains(version);
  }

  // The same size rule as [_mirrorDownloadIncomplete]; hashing stays with the
  // exporter, which re-verifies whatever it keeps.
  static Future<bool> _completeOnDisk(ReleaseAsset asset) async {
    final file = File(asset.downloadUrl);
    return await file.exists() && await file.length() == asset.size;
  }

  /// The release of [version]; of a re-publish, the latest one.
  String? _tagForVersion(
    List<LibraryRelease> releases,
    int version, {
    bool Function(LibraryRelease release)? carries,
  }) {
    LibraryRelease? best;
    for (final release in OfflineLibraryUpdateDiscovery.eligibleReleases(
      releases,
      allowPrerelease: allowPrerelease,
    )) {
      if (OfflineLibraryUpdateDiscovery.releaseVersionOf(release) != version ||
          !(carries?.call(release) ?? true)) {
        continue;
      }
      final at = release.publishedAt;
      final bestAt = best?.publishedAt;
      if (best == null ||
          (at != null && (bestAt == null || at.isAfter(bestAt)))) {
        best = release;
      }
    }
    return best?.tag;
  }

  /// "מה חדש" של כל release שהמראה מכסה. קובץ שעוד לא הועלה יובא בהורדה
  /// הבאה, וכשל כאן לעולם אינו מכשיל את ההורדה — רק מדווח.
  Future<void> _syncChangesNotes({
    void Function(String assetName, Object error)? onWarning,
    bool Function()? isCancelled,
  }) async {
    final name = AppL10n.strings.libraryDomain.libraryChangesNotesName;
    try {
      final online = _cloudClient.lastFetchedReleases;
      if (online == null || !await hasMirror) return;
      final covered = LibraryChangesNotes.coveredReleases(
        online: online,
        mirrored: await LocalMirrorLibraryReleaseClient(
          mirrorDir: mirrorDir,
        ).fetchReleases(),
        allowPrerelease: allowPrerelease,
      );
      final client = http.Client();
      try {
        await LibraryChangesNotes.syncMirror(
          mirrorDir: mirrorDir,
          covered: covered,
          client: client,
          isCancelled: isCancelled,
          onWarning: (tag, error) => onWarning?.call('$name ($tag)', error),
        );
      } finally {
        client.close();
      }
    } catch (error) {
      onWarning?.call(name, error);
    }
  }

  /// "מה חדש" שבמראה לגרסאות ([fromVersion], [toVersion]], החדשה קודם.
  Future<List<LibraryChangesNote>> changesNotesBetween(
    int fromVersion,
    int toVersion,
  ) => LibraryChangesNotes.inMirror(
    mirrorDir,
    fromVersion: fromVersion,
    toVersion: toVersion,
  );

  /// "מה חדש" בעדכון ש-[check] מציע — ריק כשאין עדכון מסד, או כשאין גרסה
  /// מקומית להשוות אליה (התקנה טרייה).
  Future<List<LibraryChangesNote>> pendingChangesNotes(
    LibraryUpdateCheckResult check,
  ) async {
    final local = check.localVersion;
    final plan = check.plan;
    final target = plan?.finalTargetVersion;
    if (plan == null ||
        plan.kind == LibraryUpdatePlanKind.none ||
        plan.kind == LibraryUpdatePlanKind.blocked ||
        local == null ||
        !local.hasVersionMeta ||
        target == null) {
      return const [];
    }
    return changesNotesBetween(local.dbVersion, target);
  }

  /// מוסר לאוצריא את "מה חדש" של הגרסאות שהוחלו — ראו
  /// [LibraryChangesNotes.handOff]. שורש הנתונים כמו בהגדרות (גם נייד).
  Future<void> _handOffChangesNotes(int fromVersion, int toVersion) async {
    final notes = await changesNotesBetween(fromVersion, toVersion);
    if (notes.isEmpty) return;
    final launch = await _locator.otzariaLaunchPath?.call();
    final root = await _locator.otzariaSettingsRoot(launch);
    if (root == null) return;
    // בלי אוצריא מותקנת אין ליצור את תיקיית הנתונים שלה.
    if (launch == null && !await Directory(root).exists()) return;
    await LibraryChangesNotes.handOff(dataRoot: root, notes: notes);
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

  /// המחשבים שנרשמו ושרשומתם בתוקף, מהגרסה הנמוכה — נקודת ההתחלה.
  Future<List<RegisteredMachine>> registeredMachines() =>
      _stateStore.liveRegisteredMachines();

  Future<void> forgetRegisteredMachine(String machineKey) =>
      _stateStore.forgetKnownDbVersion(machineKey);

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

  /// ה-releases של [peekLatestOnlineVersion] האחרון שהצליח; `null` אחרי כשל.
  List<LibraryRelease>? _peekedReleases;

  /// חסם עליון לחיפוש החכם לפי [peekPendingSemanticSearch] האחרון.
  int? get peekedSemanticBytes => _peekedSemanticBytes;
  int? _peekedSemanticBytes;

  /// Why the last light check offered nothing: the published vectors are
  /// unreadable by the bundled engine.
  SemanticEngineIncompatibleException? get peekedSemanticIncompatibility =>
      _peekedSemanticIncompatibility;
  SemanticEngineIncompatibleException? _peekedSemanticIncompatibility;

  Future<bool> peekPendingSemanticSearch() async {
    _peekedSemanticBytes = null;
    _peekedSemanticIncompatibility = null;
    if (_onlineLibraryTag == null) await peekLatestOnlineVersion();
    final readable = await _readableOnlineTag();
    final tag = readable.limited ? readable.tag : _onlineLibraryTag;
    if (tag == null) {
      _peekedSemanticBytes = 0;
      return false;
    }
    final semantic =
        semanticAssetsFactory?.call(_scheduler) ?? SemanticSearchAssets();
    try {
      final pending = await semantic.peekPending(
        mirrorDir: semanticMirrorDir,
        libraryTag: tag,
        // The online machine's Otzaria fetches its vectors itself.
        fleet: SemanticFleet(
          await _stateStore.liveSemanticStates(excludeOwn: true),
        ),
      );
      _peekedSemanticBytes = semantic.peekedPendingBytes;
      _peekedSemanticIncompatibility = semantic.peekedIncompatibility;
      return pending;
    } finally {
      semantic.dispose();
    }
  }

  /// The vectors' tag under the drive's limit (no installer passes nothing).
  /// Throws when only a manifest, which a peek never reads, could tell.
  Future<({bool limited, String? tag})> _readableOnlineTag() async {
    final read = _mirroredReadableDbSchema;
    if (read == null) return (limited: false, tag: null);
    final schema = await read();
    if (schema != null && schema >= kSupportedDbSchemaVersion) {
      return (limited: false, tag: null);
    }
    if (schema == null) return (limited: true, tag: null);
    final light = _lightReadable(
      _cloudClient.lastFetchedReleases ?? const [],
      schema,
    );
    // The last download's answer first: it saw which route the drive kept,
    // which names alone cannot tell.
    final decided = await _stateStore.loadReadableSemanticTarget();
    final fromVersion = personalUpdateMode
        ? await recordedPersonalDbVersion()
        : null;
    if (decided != null &&
        decided['schema'] == schema &&
        decided['allowPrerelease'] == allowPrerelease &&
        decided['online'] == light.online &&
        decided['fromVersion'] == fromVersion &&
        decided['mirror'] == await _mirrorIdentity()) {
      if (decided['unknown'] != false) {
        throw StateError(AppL10n.strings.libraryDomain.semanticTargetUnknown);
      }
      final tag = decided['tag'];
      return (limited: true, tag: tag is String ? tag : null);
    }
    if (light.certain) return (limited: true, tag: light.tag);
    throw StateError(AppL10n.strings.libraryDomain.semanticTargetUnknown);
  }

  /// A completed limited export still describes this drive and online list.
  Future<bool> isReadableMirrorCurrent() async {
    final schema = await _mirroredReadableDbSchema?.call();
    if (schema == null) return false;
    final decided = await _stateStore.loadReadableSemanticTarget();
    if (decided == null || decided['unknown'] != false) return false;
    return decided['schema'] == schema &&
        decided['allowPrerelease'] == allowPrerelease &&
        decided['online'] ==
            _lightReadable(
              _cloudClient.lastFetchedReleases ?? const [],
              schema,
            ).online &&
        decided['fromVersion'] ==
            (personalUpdateMode ? await recordedPersonalDbVersion() : null) &&
        decided['mirror'] == await _mirrorIdentity();
  }

  /// What names alone settle: the newest release with a full DB [schema]
  /// reads, whether no newer patch needs a manifest to judge, and a
  /// fingerprint of every eligible release's content identity.
  ({String? tag, bool certain, String online}) _lightReadable(
    List<LibraryRelease> releases,
    int schema,
  ) {
    final eligible = OfflineLibraryUpdateDiscovery.eligibleReleases(
      releases,
      allowPrerelease: allowPrerelease,
    );
    var newest = 0;
    for (final release in eligible) {
      if (release.fullDbAssetFor(maxSchemaVersion: schema) == null) continue;
      final version = OfflineLibraryUpdateDiscovery.releaseVersionOf(release);
      if (version > newest) newest = version;
    }
    // A re-publish the installer cannot read is not what the drive gets.
    final tag = newest == 0
        ? null
        : _tagForVersion(
            releases,
            newest,
            carries: (r) => r.fullDbAssetFor(maxSchemaVersion: schema) != null,
          );
    // Any re-publish or replaced asset may change which content the drive
    // serves, so a saved verdict must not outlive one.
    final online = [
      for (final release in eligible)
        for (final asset in release.assets)
          if (asset.isFullDbArchive ||
              asset.isSplitFullDbManifest ||
              asset.isDeltaManifest)
            '${release.tag}/${asset.name}/${asset.id}/${asset.updatedAt}',
    ]..sort();
    return (
      tag: tag,
      // Re-publishes of the newest version leave to the route which one the
      // drive serves, and names cannot see the route.
      certain:
          !eligible.any(
            (r) =>
                OfflineLibraryUpdateDiscovery.releaseVersionOf(r) > newest &&
                r.deltaManifestAssets.isNotEmpty,
          ) &&
          eligible
                  .where(
                    (r) =>
                        OfflineLibraryUpdateDiscovery.releaseVersionOf(r) ==
                            newest &&
                        (r.fullDbAssetFor(maxSchemaVersion: schema) != null ||
                            r.deltaManifestAssets.isNotEmpty),
                  )
                  .length <=
              1,
      online: online.join(';'),
    );
  }

  static final _libraryTagPattern = RegExp(r'^v(\d+)-');

  static String? _libraryTagFor(List<LibraryRelease> releases, int version) {
    for (final release in releases) {
      if (release.isDraft) continue;
      final match = _libraryTagPattern.firstMatch(release.tag);
      if (match != null && int.parse(match.group(1)!) == version) {
        return release.tag;
      }
    }
    return null;
  }

  Future<int?> peekLatestOnlineVersion() async {
    _onlineLibraryTag = null;
    _peekedReleases = null;
    final releases = await _cloudClient.fetchFreshReleases();
    final latest = _latestOnline(releases);
    _peekedReleases = releases;
    _onlineLibraryTag = latest?.tag;
    return latest?.version;
  }

  /// חסם עליון ל-[downloadToMirror] (בלי חיפוש חכם) מההצצות, בלי רשת ובלי כתיבה —
  /// [mirrorDownloadBytesBound] או [personalDownloadBytesBound]; `null` = אין חסם.
  Future<int?> peekedDownloadBytesBound() async {
    if (_mirroredReadableDbSchema != null) return null;
    final releases = _peekedReleases;
    final companions = _companionsMirror.peekedPendingBytes;
    if (releases == null || companions == null) return null;
    final fromVersion = personalUpdateMode
        ? await recordedPersonalDbVersion()
        : null;
    final exporter = LibraryMirrorExporter(
      supportedDbSchemaVersion: kSupportedDbSchemaVersion,
      client: _cloudClient,
    );
    final List<LibraryRelease> eligible;
    final List<LibraryRelease> relevant;
    final ApplyTimeEstimate applyTime;
    try {
      eligible = LibraryUpdateDiscovery.eligibleReleases(
        releases,
        allowPrerelease: allowPrerelease,
      );
      relevant = fromVersion == null
          ? exporter.recentReleases(eligible)
          : exporter.personalReleases(eligible, fromVersion);
      applyTime = exporter.applyTime;
    } finally {
      exporter.dispose();
    }

    final held = <(String, String)>{};
    final manifests = <(String, String), DeltaManifest>{};
    // במצב אישי גם נשא המסד המלא, שאינו בין ה-releases של קובצי העדכון.
    final scanned = {
      ...relevant,
      if (fromVersion != null)
        ...eligible.where(
          (r) =>
              r.fullDbAssetFor(maxSchemaVersion: kSupportedDbSchemaVersion) !=
              null,
        ),
    };
    for (final release in scanned) {
      for (final asset in release.assets) {
        // מסד מפוצל נשמר בשם הארכיון המורכב, וגודלו רק במניפסט שברשת: קיומו
        // מספיק כדי שהמייצא עשוי לבחור בו.
        final archive = asset.isSplitFullDbManifest
            ? asset.splitArchiveName!
            : null;
        if (archive != null) {
          if (await File(_mirrorAssetPath(release.tag, archive)).exists()) {
            held.add((release.tag, asset.name));
          }
          continue;
        }
        final file = File(_mirrorAssetPath(release.tag, asset.name));
        if (!await file.exists() || await file.length() != asset.size) {
          continue;
        }
        held.add((release.tag, asset.name));
        if (!asset.isDeltaManifest) continue;
        try {
          manifests[(release.tag, asset.name)] = DeltaManifest.fromJson(
            jsonDecode(await file.readAsString()) as Map<String, dynamic>,
          );
        } catch (_) {
          // manifest שאינו נקרא — הקשת נחשבת תקפה, כמו בלי manifest.
        }
      }
    }
    if (fromVersion != null) {
      final bytes = personalDownloadBytesBound(
        eligible: eligible,
        relevant: relevant,
        fromVersion: fromVersion,
        supportedDbSchemaVersion: kSupportedDbSchemaVersion,
        applyTime: applyTime,
        complete: (release, asset) => held.contains((release.tag, asset.name)),
        heldManifest: (release, asset) => manifests[(release.tag, asset.name)],
      );
      return bytes == null ? null : bytes + companions;
    }
    final bytes = mirrorDownloadBytesBound(
      relevant: relevant,
      supportedDbSchemaVersion: kSupportedDbSchemaVersion,
      applyTime: applyTime,
      complete: (release, asset) => held.contains((release.tag, asset.name)),
      heldManifest: (release, asset) => manifests[(release.tag, asset.name)],
    );
    return bytes == null ? null : bytes + companions;
  }

  /// בכונן יש ספרייה מלאה — שהייצוא האישי הבא ימחק. קריאה בלבד.
  Future<bool> mirrorHoldsFullDb() async {
    try {
      if (!await hasMirror) return false;
      final releases = await LocalMirrorLibraryReleaseClient(
        mirrorDir: mirrorDir,
      ).fetchReleases();
      for (final release in releases) {
        final full = release.fullDbAssetFor(
          maxSchemaVersion: kSupportedDbSchemaVersion,
        );
        if (full == null) continue;
        final name = full.isSplitFullDbManifest
            ? full.splitArchiveName!
            : full.name;
        if (await File(_mirrorAssetPath(release.tag, name)).exists()) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  /// הנתיב שבו [LibraryMirrorExporter] שומר נכס — כמו `_safeDirName` שלו.
  String _mirrorAssetPath(String tag, String name) => p.join(
    mirrorDir,
    'assets',
    tag.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_'),
    name,
  );

  ({String tag, int version})? _latestOnline(List<LibraryRelease> all) =>
      OfflineLibraryUpdateDiscovery.latestOnlineRelease(
        supportedDbSchemaVersion: kSupportedDbSchemaVersion,
        all,
        allowPrerelease: allowPrerelease,
      );

  /// המראה המקומית כמקור releases. זורק [LibraryMirrorMissingException] אם
  /// עדיין לא הורד דבר — במקום ליפול לרשת בשקט, כפי שהיה בעבר.
  Future<LibraryReleaseSource> _resolveSource() async {
    if (!await hasMirror) throw LibraryMirrorMissingException(mirrorDir);
    return LocalMirrorLibraryReleaseClient(mirrorDir: mirrorDir);
  }

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
    final List<LibraryRelease> releases;
    try {
      releases = await source.fetchReleases();
    } catch (e) {
      if (!_isDamagedManifestError(e)) rethrow;
      throw LibraryMirrorDamagedException(mirrorDir, '$e');
    }
    final discoverer = OfflineLibraryUpdateDiscovery(
      supportedDbSchemaVersion: kSupportedDbSchemaVersion,
      client: _FetchedReleasesSource(source, releases),
    );
    final discoveryResult = await discoverer.discover(
      allowPrerelease: allowPrerelease,
    );
    final mirrorDownloadIncomplete = await _mirrorDownloadIncomplete(releases);
    final readableSchema = await _readableDbSchema(locator);
    final route = ReadableSchemaRoute.limit(
      discovery: discoveryResult,
      releases: releases,
      allowPrerelease: allowPrerelease,
      readableSchema: readableSchema,
    );

    final applied = await _stateStore.loadAppliedRelease();

    final companions = await _companionsInstaller.pendingWork(
      mirrorDir: companionsMirrorDir,
      dbPath: dbPath,
      delivered: _deliveredCompanions(
        await _stateStore.loadDeliveredCompanions(),
      ),
    );

    LibraryUpdatePlan planFor(ReadableSchemaRoute route) => _planner.plan(
      localVersion: local.dbVersion,
      hasLocalVersionMeta: local.hasVersionMeta,
      latestVersion: discoveryResult.latestVersion,
      edges: route.edges,
      latestFullDbAsset: route.latestFullDbAsset,
      fullDbReleaseTag: route.fullDbReleaseTag,
      latestFullDbVersion: route.latestFullDbVersion,
      latestContentTag: discoveryResult.latestContentTag,
      localReleaseTag: applied?.tag,
      localReleaseTagVersion: applied?.dbVersion,
      blockingSchemaVersion: discoveryResult.blockingSchemaVersion,
      blockingPatchFormatVersion: discoveryResult.blockingPatchFormatVersion,
      localVersionUnknownReason: corruptAfterCrashReason,
    );

    final limitedPlan = planFor(route);
    final plan = route.limited
        ? _limitToReadableSchema(
            limitedPlan,
            unlimited: planFor(ReadableSchemaRoute.unlimited(discoveryResult)),
            route: route,
            localVersion: local.dbVersion,
            latestVersion: discoveryResult.latestVersion,
          )
        : limitedPlan;

    final settings = await _semanticSettings(locator);
    final supportsWindows = await _supportsWindowsVectors(locator);
    final semantic =
        semanticAssetsFactory?.call(_scheduler) ?? SemanticSearchAssets();
    var semanticPending = false;
    var semanticRecovered = false;
    SemanticEngineIncompatibleException? semanticIncompatibility;
    try {
      final semanticVersion = switch (plan.kind) {
        LibraryUpdatePlanKind.none ||
        LibraryUpdatePlanKind.blocked => local.dbVersion,
        _ => plan.finalTargetVersion ?? local.dbVersion,
      };
      semanticPending = await semantic.pending(
        mirrorDir: semanticMirrorDir,
        dbPath: dbPath,
        libraryVersion: semanticVersion,
        vectorsRootPath: _semanticVectorsRoot(settings, dbPath),
        preferencesReady: settings?.semanticSearchReadyPreferences ?? false,
        supportsWindows: supportsWindows,
        needsBase: await _ownNeedsBase(),
        onRecoveryVerified: () => semanticRecovered = true,
      );
      semanticIncompatibility = await semantic.incompatibility(
        mirrorDir: semanticMirrorDir,
        libraryVersion: semanticVersion,
        supportsWindows: supportsWindows,
        dbPath: dbPath,
        vectorsRootPath: _semanticVectorsRoot(settings, dbPath),
      );
      if (semanticIncompatibility == null && semanticPending) {
        final reads = await _semanticTargetReadsText4(locator);
        if (reads != true) {
          semanticIncompatibility = SemanticEngineIncompatibleException(
            lineTextVersion: kSemanticEngineText.lineTextVersion,
            keyVersion: kSemanticEngineText.keyVersion,
            reason: reads == null
                ? SemanticIncompatibilityReason.otzariaUnproven
                : SemanticIncompatibilityReason.updateOtzaria,
          );
        }
      }
      if (semanticIncompatibility != null) semanticPending = false;
    } finally {
      semantic.dispose();
    }
    if (!isFreshInstall) {
      await _recordSemanticState(
        dbPath: dbPath,
        settings: settings,
        supportsWindows: supportsWindows,
        baseInstalled: semanticRecovered,
      );
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
      semanticConsentGranted: settings?.searchFeedbackGranted ?? false,
      semanticIncompatibility: semanticIncompatibility,
      mirrorDownloadIncomplete: mirrorDownloadIncomplete,
      readableDbSchemaVersion: readableSchema,
      needsNewerOtzaria: !identical(plan, limitedPlan),
    );
  }

  /// A failed chain sets it; only a base install or a changed set clears it.
  @visibleForTesting
  static bool nextNeedsBase({
    required SemanticMachineState? previous,
    required int libraryVersion,
    required String identityDigest,
    bool chainFailed = false,
    bool baseInstalled = false,
  }) =>
      chainFailed ||
      (!baseInstalled &&
          previous != null &&
          previous.needsBase &&
          previous.libraryVersion == libraryVersion &&
          previous.identityDigest == identityDigest);

  Future<bool> _ownNeedsBase() async =>
      (await _stateStore.loadOwnSemanticState())?.needsBase ?? false;

  /// Whether the target Otzaria reads text-4 vectors; `null` = version unknown.
  Future<bool?> _semanticTargetReadsText4(LibraryDbLocator locator) async {
    final launch = await locator.otzariaLaunchPath?.call();
    final root = await locator.otzariaSettingsRoot(launch);
    return OtzariaCapabilities.readsSemanticLineText4(
      capabilities: root == null ? null : await OtzariaCapabilities.read(root),
      launchPath: launch,
      installedVersion: await _otzariaAppVersion?.call(),
    );
  }

  Future<bool> _supportsWindowsVectors(LibraryDbLocator locator) async {
    final launch = await locator.otzariaLaunchPath?.call();
    final root = await locator.otzariaSettingsRoot(launch);
    return OtzariaCapabilities.supportsWindowsVectors(
      capabilities: root == null ? null : await OtzariaCapabilities.read(root),
      launchPath: launch,
      installedVersion: await _otzariaAppVersion?.call(),
    );
  }

  /// Records this machine's smart-search set for the next download's plan;
  /// only a machine that installs it from the drive (consent given) counts.
  Future<void> _recordSemanticState({
    required String dbPath,
    required OtzariaSettings? settings,
    required bool supportsWindows,
    bool chainFailed = false,
    bool baseInstalled = false,
  }) async {
    try {
      if (settings == null) return;
      if (!settings.searchFeedbackGranted) {
        await _stateStore.recordOwnSemanticState(null);
        return;
      }
      final live = (await SemanticSearchAssets.readInstalledSets(
        p.join(_semanticVectorsRoot(settings, dbPath), 'vectors'),
      )).firstOrNull;
      final family = live == null
          ? null
          : live.windows
          ? SemanticVectorsFamily.windows
          : SemanticVectorsFamily.legacy;
      final version = live?.libraryVersion ?? 0;
      final identity = live?.identityDigest ?? '';
      final previous = await _stateStore.loadOwnSemanticState();
      final needsBase = nextNeedsBase(
        previous: previous,
        libraryVersion: version,
        identityDigest: identity,
        chainFailed: chainFailed,
        baseInstalled: baseInstalled,
      );
      await _stateStore.recordOwnSemanticState(
        SemanticMachineState(
          supportsWindows: supportsWindows,
          family: family,
          libraryVersion: version,
          identityDigest: identity,
          needsBase: needsBase,
        ),
      );
    } on Exception {
      // Best effort: a failed record must not fail the check or the install.
    }
  }

  Future<int?> _readableDbSchema(LibraryDbLocator locator) async {
    final launch = await locator.otzariaLaunchPath?.call();
    final root = await locator.otzariaSettingsRoot(launch);
    return OtzariaCapabilities.resolveReadableDbSchema(
      capabilities: root == null ? null : await OtzariaCapabilities.read(root),
      installedVersion: await _otzariaAppVersion?.call(),
      launchPath: launch,
    );
  }

  LibraryUpdatePlan _limitToReadableSchema(
    LibraryUpdatePlan plan, {
    required LibraryUpdatePlan unlimited,
    required ReadableSchemaRoute route,
    required int localVersion,
    required int latestVersion,
  }) {
    final readable = route.readableSchema;
    if (!route.limited || readable == null) return plan;
    final strings = AppL10n.strings.libraryDomain;
    int reachedBy(LibraryUpdatePlan p) =>
        p.kind == LibraryUpdatePlanKind.blocked
        ? localVersion
        : p.finalTargetVersion ?? localVersion;
    final reached = reachedBy(plan);
    if (reached >= latestVersion || reachedBy(unlimited) <= reached) {
      return plan;
    }
    switch (plan.kind) {
      case LibraryUpdatePlanKind.none:
        return plan;
      case LibraryUpdatePlanKind.blocked:
        return LibraryUpdatePlan.blocked(
          localVersion: plan.localVersion,
          targetVersion: latestVersion,
          reason: strings.planOtzariaTooOldForLibrary(readable, latestVersion),
        );
      case LibraryUpdatePlanKind.delta:
        return LibraryUpdatePlan.delta(
          localVersion: plan.localVersion,
          targetVersion: plan.targetVersion ?? reached,
          steps: plan.deltaSteps,
          reason: strings.planStopsBeforeOtzariaSchema(reached, latestVersion),
          fullDownloadFallback: plan.fullDownloadFallback,
        );
      case LibraryUpdatePlanKind.fullDownload:
        return LibraryUpdatePlan.fullDownload(
          localVersion: plan.localVersion,
          targetVersion: plan.targetVersion,
          asset: plan.fullDbAsset!,
          releaseTag: plan.fullDbReleaseTag!,
          reason: strings.planStopsBeforeOtzariaSchema(reached, latestVersion),
          followUpDelta: plan.followUpDelta,
        );
    }
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
  /// זורק [OtzariaIsRunningException] אם אוצריא פתוחה — [OtzariaProcessGuard].
  /// זורק [LibraryApplyException] על
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
    void Function(String reason)? onLibraryLocationFailure,
    bool Function()? isCancelled,
    bool useFullDownloadFallback = false,
  }) async {
    _appliesInFlight++;
    OtzariaInstanceLease? lease;
    try {
      final lock = _instanceLock;
      if (lock != null) {
        final launch = await _locator.otzariaLaunchPath?.call();
        lease = await lock.acquire(
          portableDataRoot: await _locator.portableDataRoot(launch),
        );
      }
      return await _applyUpdate(
        check,
        onProgress: onProgress,
        onCompanionWarning: onCompanionWarning,
        onStateWarning: onStateWarning,
        onLibraryLocationNotSet: onLibraryLocationNotSet,
        onLibraryLocationFailure: onLibraryLocationFailure,
        isCancelled: isCancelled,
        useFullDownloadFallback: useFullDownloadFallback,
      );
    } finally {
      lease?.release();
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
    void Function(String reason)? onLibraryLocationFailure,
    bool Function()? isCancelled,
    bool useFullDownloadFallback = false,
  }) async {
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
          final partial = <int>{};
          try {
            booksTouched = await _storageAware(
              () => _applier.applyDelta(
                plan: plan,
                dbPath: dbPath,
                onProgress: onProgress,
                isCancelled: isCancelled,
                onStepApplied: (books, _) => partial.addAll(books),
              ),
            );
          } catch (_) {
            if (partial.isNotEmpty) {
              await const ExternalUpdateNotice().write(
                dbPath: dbPath,
                route: ExternalUpdateNotice.routeDelta,
                booksTouched: partial,
                onError: onStateWarning,
              );
            }
            rethrow;
          }
          break;
        case LibraryUpdatePlanKind.fullDownload:
          await _storageAware(
            () => _applier.applyFullDownload(
              plan: plan,
              dbPath: dbPath,
              onProgress: onProgress,
              isCancelled: isCancelled,
            ),
          );
          appliedTag = plan.fullDbReleaseTag;
          final followUp = plan.followUpDelta;
          if (followUp != null) {
            try {
              booksTouched = await _storageAware(
                () => _applier.applyDelta(
                  plan: followUp,
                  dbPath: dbPath,
                  onProgress: onProgress,
                  isCancelled: isCancelled,
                  onStepApplied: (_, version) {
                    appliedVersion = version;
                    appliedTag = _contentTagFor(check, plan, version);
                  },
                ),
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
                onLibraryLocationFailure: onLibraryLocationFailure,
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
        onLibraryLocationFailure: onLibraryLocationFailure,
      );
    }

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
    try {
      await _stateStore.saveDeliveredCompanions({
        for (final e in companions.delivered.entries) e.key.name: e.value,
      });
    } catch (e) {
      onStateWarning?.call(e);
    }

    if (companions.storageFailure == null &&
        check.semanticPending &&
        check.semanticConsentGranted) {
      final name = AppL10n.strings.libraryDomain.companionSemanticName;
      try {
        final settings = await _semanticSettings();
        if (!(settings?.searchFeedbackGranted ?? false)) {
          throw StateError(
            AppL10n.strings.libraryDomain.semanticConsentRequired,
          );
        }
        await _throwIfOtzariaRunning();
        final semantic =
            semanticAssetsFactory?.call(_scheduler) ??
            SemanticSearchAssets(engineFactory: semanticEngineFactory);
        final supportsWindows = await _supportsWindowsVectors(_locator);
        var chainFailed = false;
        var baseInstalled = false;
        try {
          final version = await _versionReader.readInIsolate(dbPath);
          try {
            baseInstalled = await semantic.install(
              mirrorDir: semanticMirrorDir,
              dbPath: dbPath,
              libraryVersion: version.dbVersion,
              vectorsRootPath: _semanticVectorsRoot(settings, dbPath),
              supportsWindows: supportsWindows,
              targetReadsLineText4: await _semanticTargetReadsText4(_locator),
              beforeActivate: _throwIfOtzariaRunning,
              onStage: (stage) => onProgress?.call(
                LibraryApplyProgress(
                  stage: LibraryApplyStage.installingCompanions,
                  statusText: stage,
                ),
              ),
              isCancelled: isCancelled,
            );
          } on SemanticChainNotApplicableException {
            chainFailed = true;
            rethrow;
          } finally {
            await _recordSemanticState(
              dbPath: dbPath,
              settings: settings,
              supportsWindows: supportsWindows,
              chainFailed: chainFailed,
              baseInstalled: baseInstalled,
            );
          }
          await _throwIfOtzariaRunning();
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
    void Function(String reason)? onLibraryLocationFailure,
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
      final failure = await _pointOtzariaAtFreshDb(dbPath, locator);
      if (failure != null) {
        onLibraryLocationFailure?.call(failure);
        onLibraryLocationNotSet?.call(dbPath);
      }
    }
    if (tag != null && version != null && version > 0) {
      await record(
        () => _stateStore.saveAppliedRelease(tag: tag, dbVersion: version),
      );
    }
    if (version != null && version > 0) {
      await record(() => _stateStore.recordOwnDbVersion(version));
    }
    final local = check.localVersion;
    if (local != null && local.hasVersionMeta && version != null) {
      await record(() => _handOffChangesNotes(local.dbVersion, version));
    }
    // מה השתנה, לטובת אינדקס החיפוש של אוצריא — ראו [ExternalUpdateNotice].
    await const ExternalUpdateNotice().write(
      dbPath: dbPath,
      route: route,
      booksTouched: booksTouched,
      dbVersion: version,
      releaseTag: tag,
      onError: onStateWarning,
    );
  }

  Future<String?> _pointOtzariaAtFreshDb(
    String dbPath,
    LibraryDbLocator locator,
  ) async {
    try {
      final launchPath = await locator.otzariaLaunchPath?.call();
      final root = await locator.otzariaSettingsRoot(launchPath);
      if (root == null) {
        return 'No known Otzaria settings root (launch path: $launchPath)';
      }

      final current = await locator.settingsReader.read(root);
      if (current != null && !current.isEmpty) {
        final resolved = current.resolveDbPath(
          path: p.context,
          fileName: LibraryDbLocator.databaseFileName,
        );
        if (resolved != null && p.equals(resolved, dbPath)) return null;
        if (resolved != null) {
          if (await File(resolved).exists()) {
            return 'Otzaria settings point at $resolved, which already holds '
                'a database, so they were not overwritten';
          }
          if (!p.isAbsolute(resolved) ||
              !await Directory(p.dirname(resolved)).exists()) {
            return 'Otzaria settings point at $resolved, which is unavailable '
                '(unplugged drive?), so they were not overwritten';
          }
        }
      }

      final boxFile = File(p.join(root, OtzariaSettingsReader.boxFileName));
      if (current == null && await boxFile.exists()) {
        return 'Settings file ${boxFile.path} exists but could not be read '
            '(corrupt, encrypted or another format)';
      }

      if (await _isOtzariaRunning()) {
        return 'Otzaria is running, so the settings were not written';
      }

      final written = await _settingsWriter.pointLibraryAt(
        dataRootPath: root,
        dbPath: dbPath,
        allowCreate: launchPath != null,
      );
      if (written) return null;
      return 'Writing the settings to $root failed (root creation allowed: '
          '${launchPath != null})';
    } catch (e) {
      return 'Writing the settings threw: $e';
    }
  }

  void dispose() {
    _cloudClient.dispose();
    _applier.dispose();
    _companionsMirrorInstance?.dispose();
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

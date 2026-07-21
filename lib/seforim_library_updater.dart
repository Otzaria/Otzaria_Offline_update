/// לקוח Dart לצריכת הפצות הדלתא של `Otzaria/SeforimLibrary`.
///
/// מייצא את ה-API הציבורי בלבד: מודלים של פורמט ההפצה, גילוי ותכנון מסלול,
/// הורדה ואימות, חישוב hash לוגי, והחלת patch אטומית.
///
/// **פעולות חוסמות:** `LogicalContentHasher.compute` ו-`PatchApplier.apply`
/// סינכרוניות וכבדות (ה-hash עד עשרות שניות על DB מלא). אל תריץ אותן על ה-UI
/// isolate — עטוף ב-`Isolate.run`.
library;

export 'src/models/delta_manifest.dart' show DeltaManifest, PatchFileEntry;
export 'src/models/library_release.dart' show LibraryRelease, ReleaseAsset;
export 'src/models/library_update_plan.dart'
    show LibraryUpdatePlan, LibraryUpdatePlanKind, PatchEdge;
export 'src/models/patch_table_spec.dart'
    show PatchTableSpec, kPatchTablesInFkOrder, kHashTableOrder;
export 'src/services/github_library_release_client.dart'
    show GithubLibraryReleaseClient;
export 'src/services/library_db_recovery_service.dart'
    show
        LibraryDbRecoveryService,
        RecoveryResult,
        RecoveryAction,
        BackupIntegrityException;
export 'src/services/library_update_discovery.dart'
    show LibraryUpdateDiscovery, LibraryDiscoveryResult;
export 'src/services/library_update_planner.dart' show LibraryUpdatePlanner;
export 'src/services/local_db_version_reader.dart'
    show LocalDbVersionReader, LocalDbVersion;
export 'src/services/logical_content_hasher.dart' show LogicalContentHasher;
export 'src/services/patch_applier.dart'
    show
        PatchApplier,
        PatchApplyResult,
        PatchApplyException,
        kBooksTouchedTables;
export 'src/services/patch_downloader.dart'
    show PatchDownloader, PatchDownloadException, PatchDownloadCancelled;

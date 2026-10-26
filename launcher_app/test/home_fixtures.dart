// מצבי הבית של המוקאפ (`#scn=<name>`) כמודלים — לבדיקות הבית ולצילומי
// הסקירה. העובדות עוברות ב-`deriveHomeGuidance`, כך שהגיבור הוא מה שהמוצר
// היה מחליט, ולא מה שהבדיקה מניחה. אחרי מצבי המוקאפ — מצבים נוספים שאין
// להם מקבילה במוקאפ (בדיקה, הורדה בלבד, כונן ריק עם תוכנות נוספות).

import 'package:flutter/widgets.dart';
import 'package:launcher_app/src/controllers/library_module_controller.dart';
import 'package:launcher_app/src/controllers/otzaria_module_controller.dart';
import 'package:launcher_app/src/controllers/plugins_module_controller.dart';
import 'package:launcher_app/src/screens/home/home_progress.dart';
import 'package:launcher_app/src/screens/home/home_view_model.dart';
import 'package:launcher_app/src/shell/home_guidance.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

const homeScenarios = [
  'offline',
  'online',
  'uptodate',
  'newer',
  'first',
  'firstOffline',
  'open',
  'readonly',
  'drivefull',
  'checking',
  'downloadOnly',
  'firstWithApps',
  'uptodateOnline',
  'checkFailed',
  'othersPending',
  'openIdle',
  'installingApp',
  'appError',
  'libraryNotices',
  'libraryNotFound',
  'libraryElsewhere',
  'personalOnline',
  'personalOnlineNoSize',
  'personalNoneRegistered',
  'personalPreparedHere',
  'downloadV32',
  'syncOff',
  'taskPluginsSync',
  'semanticOnly',
];

final _checkedAt = DateTime(2026, 10, 23, 23, 14);
const _newPlugins = ['דף יומי', 'מילון ארמית'];
const _mb = 1 << 20;

HomeViewModel _model(
  GuidanceFacts f, {
  String? installed = '0.10.3',
  String? drive = '0.10.4',
  String? onlineApp,
  int? onlineLibrary,
  int onlinePlugins = 0,
  int pluginUpdates = 0,
  int customApps = 0,
  int customAppsPending = 0,
  int reportsToSend = 0,
  int reportsToCollect = 0,
  int toolReportsPending = 0,
  List<String> newPlugins = const [],
  bool autoInstallSkipped = false,
  bool onlineStoreApp = false,
  bool offersElevation = false,
  LauncherLine? launcher,
  bool canLaunch = true,
  bool semanticOffer = false,
  String? failedDownloads,
  FoundNothing? foundNothing,
  int? appDownloadBytes,
  int? libraryDownloadBytes,
  int? driveFreeBytes,
  String? appError,
  bool whatsNew = false,
  String? libraryMissingNames,
  bool libraryNotFound = false,
  String? libraryElsewhereFrom,
  bool semanticConsent = false,
  String? driveCompanionNames,
  HomeTask? task,
  bool personalMode = false,
  int personalMachines = 0,
  int? personalFloor,
  bool personalPreparedHere = false,
}) {
  final guidance = deriveHomeGuidance(f);
  TileStatus tile(GuidanceItem item) => deriveTileStatus(
        item,
        f,
        download: guidance.downloadItems,
        unchecked: guidance.uncheckedItems,
      );
  bool checked(GuidanceItem item) => f.proofOf(item).succeeded;
  return HomeViewModel(
    guidance: guidance,
    online: f.online,
    installedVersion: installed,
    driveAppVersion: drive,
    onlineAppVersion: onlineApp,
    onlineAppLatest: checked(GuidanceItem.app) ? onlineApp ?? drive : null,
    libraryHereVersion: installed == null
        ? null
        : f.libraryStatus == LibraryStatusFact.updateAvailable
            ? 145
            : 146,
    libraryFreshInstall: installed == null,
    driveLibraryVersion: 146,
    driveCompanionNames: driveCompanionNames,
    onlineLibraryVersion: onlineLibrary,
    onlineLibraryLatest:
        checked(GuidanceItem.library) ? onlineLibrary ?? 146 : null,
    pluginUpdatesOnDrive: pluginUpdates,
    onlinePluginChanges: onlinePlugins,
    onlineStoreApp: onlineStoreApp,
    appDownloadBytes: appDownloadBytes,
    libraryDownloadBytes: libraryDownloadBytes,
    driveFreeBytes: driveFreeBytes,
    syncApp: f.syncApp,
    syncLibrary: f.syncLibrary,
    syncPlugins: f.syncPlugins,
    semanticOffer: semanticOffer,
    failedDownloads: failedDownloads,
    foundNothing: foundNothing,
    onlineCheckedAt: f.online == true ? _checkedAt : null,
    appError: appError,
    whatsNew: whatsNew,
    libraryMissingNames: libraryMissingNames,
    libraryNotFound: libraryNotFound,
    libraryElsewhereFrom: libraryElsewhereFrom,
    personalMode: personalMode,
    personalMachines: personalMachines,
    personalFloor: personalFloor,
    personalPreparedHere: personalPreparedHere,
    semanticConsent: semanticConsent,
    task: task ?? (f.installing ? HomeTask.installingApp : HomeTask.other),
    appTile: tile(GuidanceItem.app),
    libraryTile: tile(GuidanceItem.library),
    pluginsTile: tile(GuidanceItem.plugins),
    pluginsOnDrive: 11,
    pluginsInstalled: installed == null ? 0 : 6,
    customApps: customApps,
    customAppsPending: customAppsPending,
    customAppsUnannounced: customAppsPending > 0,
    reportsToSend: reportsToSend,
    reportsToCollect: reportsToCollect,
    toolReportsPending: toolReportsPending,
    autoInstallSkipped: autoInstallSkipped,
    offersElevation: offersElevation,
    newPlugins: newPlugins,
    canLaunch: canLaunch && installed != null,
    launcher: launcher,
    driveName: 'E:',
  );
}

const _driveUpdate = GuidanceFacts(
  otzariaStatus: AppStatusFact.updateAvailable,
  libraryStatus: LibraryStatusFact.updateAvailable,
  pluginUpdatesOnDrive: 3,
  online: false,
);

HomeViewModel homeScenario(String name) => switch (name) {
      'offline' => _model(
          _driveUpdate,
          pluginUpdates: 3,
          customApps: 3,
          customAppsPending: 2,
          reportsToCollect: 3,
          newPlugins: _newPlugins,
          launcher: const LauncherLine(
            LauncherLineKind.ready,
            version: '3.3.0',
          ),
        ),
      'online' => _model(
          const GuidanceFacts(
            otzariaStatus: AppStatusFact.updateAvailable,
            libraryStatus: LibraryStatusFact.updateAvailable,
            pluginUpdatesOnDrive: 3,
            online: true,
            onlineApp: true,
            onlineLibrary: true,
            onlinePlugins: true,
          ),
          // גרסה גולמית כמו שהאתר מחזיר — המסך מציג "0.10.5".
          onlineApp: 'v0.10.5+812',
          onlineLibrary: 147,
          onlinePlugins: 3,
          onlineStoreApp: true,
          appDownloadBytes: 96 * _mb,
          libraryDownloadBytes: 1229 * _mb,
          driveFreeBytes: 29082 * _mb,
          pluginUpdates: 3,
          customApps: 3,
          customAppsPending: 2,
          reportsToSend: 12,
          newPlugins: _newPlugins,
          launcher: const LauncherLine(
            LauncherLineKind.online,
            version: '3.3.0',
          ),
        ),
      'uptodate' => _model(
          const GuidanceFacts(online: false),
          installed: '0.10.4',
          customApps: 3,
          newPlugins: _newPlugins,
        ),
      'newer' => _model(
          const GuidanceFacts(
            otzariaStatus: AppStatusFact.installedIsNewer,
            online: false,
          ),
          installed: '0.10.5',
        ),
      'first' || 'firstOffline' => _model(
          GuidanceFacts(
            otzariaInstalled: false,
            otzariaStatus: AppStatusFact.needsDownload,
            libraryStatus: LibraryStatusFact.needsDownload,
            online: name == 'first',
            onlineApp: name == 'first',
            onlineLibrary: name == 'first',
          ),
          installed: null,
          drive: null,
          onlineApp: '0.10.5',
        ),
      'open' => _model(
          const GuidanceFacts(
            otzariaStatus: AppStatusFact.updateAvailable,
            libraryStatus: LibraryStatusFact.updateAvailable,
            pluginUpdatesOnDrive: 3,
            online: false,
            otzariaRunning: true,
          ),
          pluginUpdates: 3,
          customApps: 3,
          customAppsPending: 2,
          reportsToCollect: 3,
          newPlugins: _newPlugins,
          autoInstallSkipped: true,
          launcher: const LauncherLine(
            LauncherLineKind.ready,
            version: '3.3.0',
          ),
        ),
      // בכונן מוגן אין בדיקה ברשת (`AppSession.checkOnline`), ולכן online נשאר
      // null; הדיווחים שבו נספרים, אבל אין לשלוח אותם מכאן.
      'readonly' => _model(
          const GuidanceFacts(
            readOnly: true,
            otzariaStatus: AppStatusFact.updateAvailable,
            libraryStatus: LibraryStatusFact.updateAvailable,
            pluginUpdatesOnDrive: 3,
          ),
          pluginUpdates: 3,
          customApps: 3,
          customAppsPending: 1,
          reportsToSend: 12,
          newPlugins: _newPlugins,
        ),
      'drivefull' => _model(
          const GuidanceFacts(readOnly: true, driveFull: true),
          installed: '0.10.4',
          customApps: 3,
          reportsToSend: 4,
          newPlugins: _newPlugins,
        ),
      'checking' => _model(
          const GuidanceFacts(otzariaStatus: AppStatusFact.checking),
          customApps: 3,
        ),
      // הכול מותקן ומעודכן מהכונן, ובאתר יש חדש — האריחים אומרים מה יירד.
      'downloadOnly' => _model(
          const GuidanceFacts(
            online: true,
            onlineApp: true,
            onlineLibrary: true,
            onlinePlugins: true,
          ),
          installed: '0.10.4',
          onlineApp: '0.10.5',
          onlineLibrary: 147,
          onlinePlugins: 5,
          appDownloadBytes: 96 * _mb,
          libraryDownloadBytes: 1229 * _mb,
          driveFreeBytes: 29082 * _mb,
          customApps: 2,
          reportsToSend: 3,
          offersElevation: true,
          launcher: const LauncherLine(
            LauncherLineKind.online,
            version: 'v3.3.0',
          ),
        ),
      // הספרייה v32 לכונן ריק: החסם שהבית מציג לפני הלחיצה.
      // "רק המחשב שלי" במחשב המחובר: הגודל מהמייצא עצמו, והערה עם "שינוי".
      'personalOnline' => _model(
          const GuidanceFacts(
              online: true, onlineApp: true, onlineLibrary: true),
          onlineApp: '0.10.5',
          onlineLibrary: 147,
          appDownloadBytes: 96 * _mb,
          libraryDownloadBytes: 90 * _mb,
          driveFreeBytes: 29082 * _mb,
          personalMode: true,
          personalMachines: 1,
          personalFloor: 145,
        ),
      // המייצא לא ענה (או עוד לא) — בלי מספר, לא 90 MB שמטעה.
      'personalOnlineNoSize' => _model(
          const GuidanceFacts(online: true, onlineLibrary: true),
          installed: '0.10.4',
          onlineLibrary: 147,
          personalMode: true,
          personalMachines: 2,
          personalFloor: 145,
        ),
      'personalNoneRegistered' => _model(
          const GuidanceFacts(online: true, onlineLibrary: true),
          installed: null,
          onlineLibrary: 147,
          personalMode: true,
        ),
      // המחשב הלא מחובר נרשם מעצמו בהרצה הזו.
      'personalPreparedHere' => _model(
          const GuidanceFacts(online: false),
          installed: '0.10.4',
          drive: '0.10.4',
          personalMode: true,
          personalMachines: 1,
          personalFloor: 146,
          personalPreparedHere: true,
        ),
      'downloadV32' => _model(
          const GuidanceFacts(online: true, onlineLibrary: true),
          installed: '0.10.4',
          onlineLibrary: 32,
          libraryDownloadBytes: 2955264720,
          driveFreeBytes: 29082 * _mb,
        ),
      // באתר ספרייה חדשה, וההורדה שלה כבויה; השאר מסומן.
      'syncOff' => _model(
          const GuidanceFacts(
            online: true,
            onlineLibrary: true,
            syncLibrary: false,
          ),
          installed: '0.10.4',
          onlineLibrary: 147,
        ),
      'taskPluginsSync' => _model(
          const GuidanceFacts(online: true, longTaskRunning: true),
          installed: '0.10.4',
          task: HomeTask.syncingPlugins,
        ),
      // כונן ריק מאוצריא, אבל יש בו תוכנות נוספות ודיווחים, והוא מוגן.
      'firstWithApps' => _model(
          const GuidanceFacts(
            readOnly: true,
            otzariaInstalled: false,
            otzariaStatus: AppStatusFact.needsDownload,
            libraryStatus: LibraryStatusFact.needsDownload,
          ),
          installed: null,
          drive: null,
          customApps: 2,
          customAppsPending: 2,
          reportsToSend: 3,
        ),
      // "לשאול כל פעם": חיפוש חכם לבדו — שורה משנית, ונלווה שלא ירד.
      'semanticOffer' => _model(
          const GuidanceFacts(online: true),
          installed: '0.10.4',
          semanticOffer: true,
          failedDownloads: 'תלמוד בבלי',
        ),
      // "הורדה" על בדיקה ישנה, והבדיקה המחודשת לא מצאה דבר.
      'recheckNothing' => _model(
          const GuidanceFacts(online: true),
          installed: '0.10.4',
          foundNothing: FoundNothing.rechecked,
        ),
      // אותו דבר כשהבדיקות היו טריות — לפי הבדיקה הקודמת, עם השעה שלה.
      'nothingNew' => _model(
          const GuidanceFacts(online: true),
          installed: '0.10.4',
          foundNothing: FoundNothing.earlierCheck,
        ),
      'nothingNewAttention' => _model(
          const GuidanceFacts(
            libraryStatus: LibraryStatusFact.error,
            online: true,
          ),
          foundNothing: FoundNothing.earlierCheck,
        ),
      'nothingNewWelcome' => _model(
          const GuidanceFacts(
            otzariaInstalled: false,
            otzariaStatus: AppStatusFact.needsDownload,
            libraryStatus: LibraryStatusFact.needsDownload,
            online: true,
          ),
          installed: null,
          drive: null,
          foundNothing: FoundNothing.earlierCheck,
        ),
      'recheckNothingHere' => _model(
          const GuidanceFacts(
            otzariaStatus: AppStatusFact.updateAvailable,
            online: true,
          ),
          foundNothing: FoundNothing.rechecked,
          failedDownloads: 'תלמוד בבלי',
        ),
      // מחובר, וכל רכיב שנבחר נבדק בלי חדש — "הכול מעודכן".
      'uptodateOnline' => _model(
          const GuidanceFacts(online: true),
          installed: '0.10.4',
          customApps: 3,
          semanticOffer: true,
        ),
      // מחובר, ובדיקת הספרייה לבדה נכשלה — "לא הצלחתי לבדוק".
      'checkFailed' => _model(
          const GuidanceFacts(
            online: true,
            libraryProof: OnlineProof.failed,
          ),
          installed: '0.10.4',
          customApps: 3,
        ),
      // אוצריא מעודכנת, אבל הכלי ותוכנות נוספות מחכים — לא "הכול מעודכן".
      'othersPending' => _model(
          const GuidanceFacts(
            online: true,
            launcherUpdate: true,
            customAppsPending: true,
          ),
          installed: '0.10.4',
          customApps: 3,
          customAppsPending: 2,
          launcher: const LauncherLine(
            LauncherLineKind.online,
            version: '3.3.0',
          ),
        ),
      // אוצריא פתוחה, ואין מה להתקין — הפס עם "סגירת אוצריא".
      'openIdle' => _model(
          const GuidanceFacts(online: false, otzariaRunning: true),
          installed: '0.10.4',
          whatsNew: true,
          customApps: 3,
        ),
      // התקנה שרצה מחוץ למסך משימה; המד מ-[homeScenarioProgress].
      'installingApp' => _model(
          const GuidanceFacts(
            otzariaStatus: AppStatusFact.installing,
            installing: true,
            online: false,
          ),
        ),
      'appError' => _model(
          const GuidanceFacts(
              otzariaStatus: AppStatusFact.error, online: false),
          installed: '0.10.4',
          appError: 'לא הצלחנו לקרוא את התיקייה שבכונן\n'
              'FileSystemException: Access is denied',
        ),
      // הספרייה מעודכנת, ורק החיפוש החכם מחכה לתשובה — בגיבור, בלי הודעה.
      'semanticOnly' => _model(
          const GuidanceFacts(online: false, semanticConsentRequired: true),
          installed: '0.10.4',
          driveCompanionNames:
              AppL10n.strings.libraryDomain.companionSemanticName,
        ),
      // יש מה להתקין, ובספרייה קבצים חסרים והסכמה לחיפוש חכם.
      'libraryNotices' => _model(
          _driveUpdate,
          pluginUpdates: 3,
          whatsNew: true,
          libraryMissingNames: 'מילון החיפוש המקורב',
          semanticConsent: true,
        ),
      // הגיבור עצמו מציע את הפעולה — בלי הודעה כפולה מעליו.
      'libraryNotFound' => _model(
          const GuidanceFacts(
            libraryStatus: LibraryStatusFact.needsManualPath,
            online: false,
          ),
          installed: '0.10.4',
          libraryNotFound: true,
        ),
      // התוכנה מחכה כאן, והכונן הוכן למחשב אחר — ההודעה מעל הגיבור.
      'libraryElsewhere' => _model(
          const GuidanceFacts(
            otzariaStatus: AppStatusFact.updateAvailable,
            libraryStatus: LibraryStatusFact.personalTargetElsewhere,
            online: false,
          ),
          libraryElsewhereFrom: '145',
        ),
      _ => throw ArgumentError.value(name, 'name'),
    };

/// מד ההתקדמות של [homeScenario] — רק להתקנה, עם אשף שממשיך בחלון משלו.
Widget? homeScenarioProgress(String name, String dataDir) {
  if (name != 'installingApp') return null;
  final otzaria = OtzariaModuleController(dataDir: dataDir)
    ..status = OtzariaModuleStatus.installing
    ..installStage = AppL10n.strings.appDomain.setupContinuesElsewhere;
  return HomeTaskProgress(
    task: HomeTask.installingApp,
    otzaria: otzaria,
    library: LibraryModuleController(dataDir: dataDir),
    plugins: PluginsModuleController(mirrorRootDir: dataDir),
  );
}

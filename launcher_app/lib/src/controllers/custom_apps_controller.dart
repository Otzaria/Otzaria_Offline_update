import 'dart:async';
import 'dart:io';

import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;

import '../services/announced_apps_store.dart';
import '../services/app_logger.dart';
import '../services/coalescing_loader.dart';
import '../services/custom_app_detection_snapshot.dart';
import '../services/exe_icon_extractor.dart';
import 'progress_notifier.dart';

/// הגרסה המוטבעת בקובץ הרצה, או `null`. ציבורי כי הבונה משתמש בו כדי
/// להציע גרסה מתוך קובץ ההתקנה עצמו — ב-Inno ובדומיו זו בדרך כלל הגרסה
/// של התוכנה, וזה חוסך מהמשתמש להקליד אותה.
String? readInstallerVersion(String path) =>
    CustomAppsController._readInstalledVersion(path);

bool customAppOnlineIsNewer(String online, String? stored) {
  if (stored == null) return true;
  if (online == stored) return false;
  final left = OtzariaUpdateCheckResult.normalizeVersion(online);
  final right = OtzariaUpdateCheckResult.normalizeVersion(stored);
  if (!_hasNumericBase(left) || !_hasNumericBase(right)) return true;
  final order = OtzariaUpdateCheckResult.compareVersions(left, right);
  if (order != 0) return order > 0;
  return left.contains('-') && right.contains('-') && left != right;
}

bool _hasNumericBase(String version) {
  final dash = version.indexOf('-');
  final base = dash < 0 ? version : version.substring(0, dash);
  return base
      .split('.')
      .every((part) => part.isNotEmpty && int.tryParse(part) != null);
}

/// תוכנה מותאמת אחת, כפי שהמסך צריך אותה: התיאור, מה שמור על הכונן, ומה
/// מותקן על המחשב הזה.
class CustomAppView {
  const CustomAppView({required this.entry, this.installed});

  final CustomAppEntry entry;

  /// מה שנמצא על **המחשב הזה**. `null` = לא נמצאה התקנה, וזה מצב תקין.
  final CustomAppInstallState? installed;

  AppDescriptor get descriptor => entry.descriptor;
  StoredInstaller? get storedInstaller => entry.installer;

  bool get canInstall => entry.hasInstaller;
  bool get canLaunch => installed != null;

  /// האם התוסף בכלל הגדיר כיצד לזהות. בלי זה אסור להציג "אינה מותקנת" —
  /// התשובה הנכונה היא "לא ניתן לדעת".
  bool get canDetect => (descriptor.detect.exeName ?? '').isNotEmpty;

  /// מה שהכונן מציע למחשב הזה — עליו נפתחת הודעת הכניסה למסך.
  ///
  /// **הכול נקרא מהדיסק ולא מהרשת.** שתי שתיקות מכוונות: בלי כללי זיהוי
  /// אנחנו לא יודעים אם התוכנה מותקנת, ובהתקנה שגרסתה אינה נקראית אין מה
  /// להשוות — "לא ידוע" אינו "יש עדכון", ולנדנד עליו בכל כניסה זה רעש.
  CustomAppPending get pending {
    final stored = storedInstaller;
    if (stored == null || !canDetect) return CustomAppPending.none;

    final current = installed;
    if (current == null) return CustomAppPending.notInstalled;

    final version = current.version;
    if (version == null) return CustomAppPending.none;
    return OtzariaUpdateCheckResult.compareVersions(version, stored.version) < 0
        ? CustomAppPending.newerOnDrive
        : CustomAppPending.none;
  }
}

/// מה ממתין לתוכנה על הכונן. שני המצבים אינם זהים למשתמש: האחד הוא תוכנה
/// שעוד לא הגיעה למחשב הזה, והשני עדכון לתוכנה שכבר יושבת בו.
enum CustomAppPending { none, notInstalled, newerOnDrive }

/// איזו רשימה מוצגת במסך — כמו `PluginStorePage` של חנות התוספים, פחות
/// דף הבית האצור: אין כאן אתר שאוצר משהו.
enum CustomAppsPage {
  /// כל התוכנות, בלי סינון. זה המצב ההתחלתי, וגם היחיד למי שלא הגדיר
  /// קטגוריות בכלל.
  all,

  /// קטגוריה אחת — ראו [CustomAppsController.openCategorySlug].
  category,

  /// מה שלא שויך לשום קטגוריה. מוצג רק כשיש בכלל קטגוריות.
  uncategorized,
}

/// מצב התוכנות המותאמות עבור הממשק.
///
/// **ריק הוא המצב הרגיל.** רוב המשתמשים לא יוסיפו אף תוכנה, והממשק חייב
/// להיעלם לגמרי כש-[apps] ריקה — ראו [hasApps].
class CustomAppsController extends ChangeNotifier with ProgressNotifier {
  CustomAppsController({
    required String mirrorRootDir,
    String? stateDir,
    CustomAppsManager? manager,
    ExeIconExtraction? extractIcon,
    CustomAppDetectionSnapshot Function()? detectionSnapshot,
  }) {
    _mirrorRootDir = mirrorRootDir;
    _extractIcon = extractIcon ?? ExeIconExtractor.extract;
    _announced = stateDir == null ? null : AnnouncedAppsStore(stateDir);
    _newDetectionSnapshot =
        detectionSnapshot ?? CustomAppDetectionSnapshot.live;
    _manager = manager ??
        CustomAppsManager(
          resolveMirrorDir: () async => mirrorRootDir,
          readVersion: _readInstalledVersion,
          lookupUninstallDirs: _lookupUninstallDirs,
          lookupRunningProcess: _findRunningProcess,
          lookupUninstallEntries: _uninstallEntries,
          lookupInstalledExe: findInstalledExe,
          onLearningStarted: _markLearning,
          onLearnedRulesNotSaved: logLearnedRulesNotSaved,
        );
  }

  @visibleForTesting
  static void logLearnedRulesNotSaved(String id, FileSystemException error) =>
      AppLogger.maybeInstance
          ?.warn('שמירת כללי הזיהוי שנלמדו עבור $id נכשלה: $error');

  void _markLearning() {
    isLearning = true;
    notifyListeners();
  }

  late final CustomAppsManager _manager;

  late final CustomAppDetectionSnapshot Function() _newDetectionSnapshot;

  static const Symbol _detectionSnapshotKey = #customAppDetectionSnapshot;

  /// שורש המראה. נשמר גם כאן ולא רק בתוך ה-manager, כי נתיבי המדיה
  /// נדרשים **סינכרונית** בזמן `build` — התיקייה עצמה קבועה כל ההרצה.
  late final String _mirrorRootDir;

  /// לאן נרשם "כבר הוצגה הודעה על התוכנה הזו במחשב הזה". `null` כשאין
  /// תיקיית כתיבה — אז הזיכרון הוא של ההרצה הנוכחית בלבד.
  late final AnnouncedAppsStore? _announced;

  /// המזהים שההודעה עליהם כבר נאמרה כאן. נטענים יחד עם הרשימה, ולכן הם
  /// מוכנים עוד לפני שהמסך מספיק לפתוח את ההודעה.
  Set<String> _announcedIds = {};

  List<CustomAppView> apps = const [];

  /// הקטגוריות שהמשתמש הגדיר, בסדר שנקבע. ריק הוא המצב הרגיל — קטגוריות
  /// הן תוספת, והמסך מסתדר בלעדיהן לגמרי.
  List<CustomAppCategory> categories = const [];

  bool isBusy = false;
  String? errorMessage;

  /// דולק כל זמן שממתינים לרישום ההסרה אחרי התקנה — עד דקה, כי קוד יציאה 0
  /// של מתקין אינו אומר שהרישום שלו כבר נכתב. המתנה בלי הודעה נראית כתקיעה.
  bool isLearning = false;

  /// הדגל היחיד שהממשק צריך כדי להחליט אם להציג משהו בכלל.
  bool get hasApps => apps.isNotEmpty;

  /// התוכנות שיש להן מה להציע למחשב הזה — ראו [CustomAppView.pending].
  List<CustomAppView> get pendingApps => [
        for (final app in apps)
          if (app.pending != CustomAppPending.none) app,
      ];

  /// מתוכן — אלה שההודעה עליהן **עוד לא נאמרה במחשב הזה**, והן היחידות
  /// שפותחות אותה. תוכנה שכבר הוכרזה כאן שותקת מכאן ואילך: הכרטיס שבמסך
  /// ממילא אומר את אותו הדבר בכל כניסה, וחלון קופץ שחוזר הוא נדנוד.
  List<CustomAppView> get unannouncedApps => [
        for (final app in pendingApps)
          if (!_announcedIds.contains(app.descriptor.id)) app,
      ];

  /// רושם שההודעה על [shown] נאמרה במחשב הזה, כדי שלא תיאמר בו שוב.
  Future<void> markAnnounced(Iterable<CustomAppView> shown) async {
    final ids = [for (final app in shown) app.descriptor.id];
    if (ids.isEmpty) return;
    _announcedIds = {..._announcedIds, ...ids};
    await _announced?.record(ids);
  }

  /// נפתר בעצלתיים ובתוך `try`: פלטפורמה שאין לה קורא זורקת, וזה לא אמור
  /// למנוע מהרשימה להיטען — היא פשוט לא תדע גרסאות.
  static InstalledVersionReader? _versionReader;
  static bool _versionReaderResolved = false;

  static String? _readInstalledVersion(String exePath) {
    if (!_versionReaderResolved) {
      _versionReaderResolved = true;
      try {
        _versionReader = currentInstalledVersionReader();
      } catch (_) {
        _versionReader = null;
      }
    }
    try {
      return _versionReader?.readVersion(exePath);
    } catch (_) {
      // קובץ בלי שדה גרסה — "לא ידוע", לא כשל.
      return null;
    }
  }

  CustomAppDetectionSnapshot get _detectionSnapshot =>
      Zone.current[_detectionSnapshotKey] as CustomAppDetectionSnapshot? ??
      _newDetectionSnapshot();

  Future<String?> _findRunningProcess(String exeName) =>
      _detectionSnapshot.runningProcess(exeName);

  List<String> _lookupUninstallDirs(RegExp displayName) =>
      _detectionSnapshot.uninstallDirs(displayName);

  /// **כל** רישומי ההסרה, בלי סינון — זה מה שהופך צילום לפני/אחרי לאפשרי.
  ///
  /// הסריקה סינכרונית ועולה ~200ms, ולכן ההשוואה החוזרת ב-`InstallLearner`
  /// מאטה בהדרגה: לולאה צמודה הייתה נועצת את הממשק שוב ושוב לאורך דקה.
  static Future<List<UninstallEntry>> _uninstallEntries() async {
    try {
      return [
        for (final entry
            in const WindowsInstallRegistry().entries(matchesDisplayName: _any))
          UninstallEntry(
            keyName: entry.keyName,
            displayName: entry.displayName,
            installDir: entry.installDir,
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  static bool _any(String _) => true;

  static Future<String?> findInstalledExe(
    String dir,
    List<String> nameHints, {
    OtzariaTargetPlatform? platform,
  }) =>
      OtzariaAppLocator(platform: platform).findIn(
        dir,
        nameMatches: (candidate) => _nameMatchesHint(candidate, nameHints),
      );

  static bool _nameMatchesHint(String candidatePath, List<String> hints) {
    final name = InstallLearner.normalize(p.basenameWithoutExtension(
      candidatePath,
    ));
    for (final hint in hints) {
      if (name.contains(hint)) return true;
    }
    return false;
  }

  final Set<String> _pendingRedetectIds = {};
  late final CoalescingLoader _loader = CoalescingLoader(_load);

  Future<void> load({String? redetect}) {
    if (redetect != null) _pendingRedetectIds.add(redetect);
    return _loader.run();
  }

  Future<void> _load() async {
    final redetectIds = Set<String>.of(_pendingRedetectIds);
    _pendingRedetectIds.clear();
    try {
      if (_announced != null) _announcedIds = await _announced.load();
      categories = await _manager.loadCategories();
      final entries = await _manager.loadAll();
      final folderIds = await _manager.takenIds();
      _folderIds = folderIds;
      final previous = {for (final app in apps) app.descriptor.id: app};
      apps = await runZoned(
        () async => [
          for (final entry in entries)
            CustomAppView(
              entry: entry,
              installed: switch (previous[entry.descriptor.id]) {
                final before?
                    when !redetectIds.contains(entry.descriptor.id) &&
                        _sameDetection(before.descriptor, entry.descriptor) =>
                  before.installed,
                _ => await _detectQuietly(entry.descriptor),
              },
            ),
        ],
        zoneValues: {_detectionSnapshotKey: _newDetectionSnapshot()},
      );
      errorMessage = null;
    } catch (e) {
      AppLogger.instance.warn('טעינת התוכנות המותאמות נכשלה: $e');
      apps = const [];
    }
    notifyListeners();
  }

  static bool _sameDetection(AppDescriptor a, AppDescriptor b) =>
      a.installDir == b.installDir &&
      a.detect.exeName == b.detect.exeName &&
      a.detect.registryDisplayName == b.detect.registryDisplayName &&
      listEquals(a.detect.dirs, b.detect.dirs);

  Future<CustomAppInstallState?> _detectQuietly(AppDescriptor d) async {
    try {
      return await _manager.detectInstalled(d);
    } catch (_) {
      return null;
    }
  }

  /// גרסה שנמצאה ברשת לכל תוכנה, לפי מזהה. ריק עד שנעשית בדיקה — בדיקה
  /// היא תמיד יזומה, כי היא הפעולה היחידה כאן שנוגעת ברשת.
  final Map<String, String> onlineVersions = {};

  /// תוכנות שהבדיקה שלהן ברשת נכשלה (בדרך כלל: אין חיבור). זה **אינו**
  /// מצב שגיאה שיש להתריע עליו — במחשב המנותק הוא הנורמה.
  final Set<String> onlineUnavailable = {};

  final Map<String, ({GithubSource source, GithubRelease release})>
      _onlineReleases = {};

  /// המזהה של התוכנה שמורידה כרגע, או `null`. הורדה אחת בכל רגע: כולן
  /// חולקות את אותו רוחב פס, ובמקביל הן רק היו מאטות זו את זו.
  String? downloadingId;
  int? downloadReceived;
  int? downloadTotal;

  /// חשוף לטופס — הוא צריך להביא את רשימת הקבצים של ה-release **לפני**
  /// שהתוכנה נרשמה בכלל.
  GithubAppClient get github => _manager.github;

  /// לאן מגיעה תוכנה מסוג ארכיון.
  String get downloadsDir => _manager.downloadsDir;

  Future<bool> add(AppDescriptor descriptor) async {
    final ok = await _guard(() async {
      await _manager.add(descriptor);
      return true;
    });
    if (ok == true) await load();
    return ok == true;
  }

  Future<bool> update(AppDescriptor descriptor) async {
    _onlineReleases.remove(descriptor.id);
    final ok = await _guard(() async {
      await _manager.update(descriptor);
      return true;
    });
    if (ok == true) await load();
    return ok == true;
  }

  Future<bool> remove(String id) async {
    _onlineReleases.remove(id);
    final ok = await _guard(() async {
      await _manager.remove(id);
      return true;
    });
    if (ok == true) await load();
    return ok == true;
  }

  /// מזיז תוכנה אחת ברשימה. הסדר נשמר ל-`apps/order.json` ונוסע על הכונן
  /// — ראו [CustomAppOrderStore].
  ///
  /// הרשימה שבזיכרון מסודרת **מיד**, ורק אז נכתבת: לחיצה שממתינה לדיסק
  /// נראית תקועה, וטעינה מחדש הייתה סורקת שוב את כל ההתקנות שבמחשב.
  Future<bool> moveApp(int from, int to) async {
    if (from < 0 || from >= apps.length || to < 0 || to >= apps.length) {
      return false;
    }
    if (from == to) return true;

    final next = [...apps];
    next.insert(to, next.removeAt(from));
    apps = next;
    notifyListeners();

    return await _guard(() async {
          await _manager.saveOrder([for (final a in next) a.descriptor.id]);
          return true;
        }) ==
        true;
  }

  /// מעתיק קובץ התקנה אל הכונן. מחזיר את הרשומה שנשמרה, או `null` בכשל.
  Future<StoredInstaller?> attachInstaller(
    String id, {
    required String sourcePath,
    required String version,
  }) async {
    final stored = await _guard(
      () => _manager.attachInstaller(
        id,
        sourcePath: sourcePath,
        version: version,
      ),
    );
    if (stored != null) await load();
    return stored;
  }

  Future<bool> adoptInstallDir(AppDescriptor descriptor, String dir) async {
    final state = await _guard(
      () => _manager.adoptInstallDir(descriptor, dir),
    );
    if (state == null) return false;
    await load(redetect: descriptor.id);
    return true;
  }

  Future<void> checkOnline(AppDescriptor descriptor) async {
    final source = descriptor.github;
    if (descriptor.sourceKind != AppSourceKind.github || source == null) return;
    try {
      final release = await _manager.peekLatestOnline(descriptor);
      if (!_isCurrentSource(descriptor.id, source)) return;
      onlineUnavailable.remove(descriptor.id);
      if (release != null) {
        onlineVersions[descriptor.id] = release.version;
        _onlineReleases[descriptor.id] = (source: source, release: release);
      } else {
        _onlineReleases.remove(descriptor.id);
      }
    } catch (_) {
      if (!_isCurrentSource(descriptor.id, source)) return;
      onlineUnavailable.add(descriptor.id);
      _onlineReleases.remove(descriptor.id);
    }
    notifyListeners();
  }

  bool _isCurrentSource(String id, GithubSource source) => apps.any(
        (app) =>
            app.descriptor.id == id &&
            app.descriptor.sourceKind == AppSourceKind.github &&
            app.descriptor.github == source,
      );

  /// כמה תוכנות כבר נבדקו בסבב "בדיקה לכולן", ומתוך כמה. `null` כשאין סבב.
  int? checkAllDone;
  int? checkAllTotal;
  bool get isCheckingAll => checkAllTotal != null;

  /// האם יש בכלל מה לבדוק ברשת — תוכנה שקובץ ההתקנה שלה הובא ידנית אין לה
  /// מקור מקוון, ולכן כפתור "בדיקה לכולן" אינו קיים כשאין אף אחת כזו.
  bool get hasOnlineSources => _onlineApps.isNotEmpty;

  List<CustomAppView> get _onlineApps => [
        for (final app in apps)
          if (app.descriptor.sourceKind == AppSourceKind.github) app,
      ];

  bool _hasNewerOnline(CustomAppView app) {
    final id = app.descriptor.id;
    if (app.descriptor.sourceKind != AppSourceKind.github) return false;
    if (onlineUnavailable.contains(id)) return false;
    final online = onlineVersions[id];
    return online != null &&
        customAppOnlineIsNewer(online, app.storedInstaller?.version);
  }

  /// התוכנות שיש להן ברשת גרסה חדשה מזו שעל הכונן — אלה ואלה בלבד שההורדה
  /// המרוכזת נוגעת בהן.
  List<CustomAppView> get outdatedApps => [
        for (final app in apps)
          if (_hasNewerOnline(app)) app,
      ];

  /// בודק ברשת את **כל** התוכנות שיש להן מקור מקוון, במקום ללחוץ על כל
  /// כרטיס בנפרד.
  ///
  /// כשל בבדיקה אינו עוצר את השאר — הוא נספר ומדווח בסיכום, כי במחשב
  /// המנותק "אין רשת" הוא הנורמה ולא שגיאה.
  Future<({int checked, int updates, int failed})> checkAllOnline() async {
    if (isCheckingAll) return (checked: 0, updates: 0, failed: 0);
    final targets = _onlineApps;
    if (targets.isEmpty) return (checked: 0, updates: 0, failed: 0);

    await _checkEach(targets);

    var updates = 0;
    var failed = 0;
    for (final app in targets) {
      if (onlineUnavailable.contains(app.descriptor.id)) {
        failed++;
        continue;
      }
      if (_hasNewerOnline(app)) updates++;
    }
    return (checked: targets.length, updates: updates, failed: failed);
  }

  /// סדרתי בכוונה: אלה קריאות API קלות, ובמקביל הן רק היו מסכנות
  /// חסימת-קצב מול הריפו.
  Future<void> _checkEach(List<CustomAppView> targets) async {
    checkAllTotal = targets.length;
    checkAllDone = 0;
    notifyListeners();
    try {
      for (final app in targets) {
        await checkOnline(app.descriptor);
        checkAllDone = (checkAllDone ?? 0) + 1;
        notifyListeners();
      }
    } finally {
      checkAllTotal = null;
      checkAllDone = null;
      notifyListeners();
    }
  }

  /// כמה תוכנות כבר ירדו בסבב "הורדת כל העדכונים", ומתוך כמה. `null`
  /// כשאין סבב.
  int? downloadAllDone;
  int? downloadAllTotal;
  bool get isDownloadingAll => downloadAllTotal != null;

  /// מוריד לכונן את מה שיש לו ברשת גרסה חדשה מזו ששמורה — **ורק אותו**.
  ///
  /// תוכנה שטרם נבדקה בהרצה הזו נבדקת כאן תחילה, אחרת "אין מה להוריד"
  /// היה נאמר על מה שאיש לא בדק. מה שכבר נבדק אינו נבדק שוב — הכרטיס
  /// מציג את אותה תשובה.
  ///
  /// הורדה אחת בכל רגע, מאותה סיבה שב-[download]: כולן חולקות את אותו
  /// רוחב פס, ובמקביל הן רק היו מאטות זו את זו.
  Future<({int checked, int downloaded, int failed, int notChecked})>
      downloadAllOutdated() async {
    const nothing = (checked: 0, downloaded: 0, failed: 0, notChecked: 0);
    if (isCheckingAll || isDownloadingAll || downloadingId != null) {
      return nothing;
    }
    final online = _onlineApps;
    if (online.isEmpty) return nothing;

    final unchecked = [
      for (final app in online)
        if (!onlineVersions.containsKey(app.descriptor.id) &&
            !onlineUnavailable.contains(app.descriptor.id))
          app,
    ];
    if (unchecked.isNotEmpty) await _checkEach(unchecked);

    final notChecked = [
      for (final app in online)
        if (onlineUnavailable.contains(app.descriptor.id)) app,
    ].length;
    final checked = online.length - notChecked;

    // המזהים נלקחים מראש: כל הורדה מרעננת את הרשימה, והתצוגות שבה מוחלפות.
    final targets = [for (final app in outdatedApps) app.descriptor.id];
    if (targets.isEmpty) {
      return (
        checked: checked,
        downloaded: 0,
        failed: 0,
        notChecked: notChecked,
      );
    }

    downloadAllTotal = targets.length;
    downloadAllDone = 0;
    notifyListeners();
    var downloaded = 0;
    try {
      for (final id in targets) {
        if (await download(id) != null) downloaded++;
        downloadAllDone = (downloadAllDone ?? 0) + 1;
        notifyListeners();
      }
    } finally {
      downloadAllTotal = null;
      downloadAllDone = null;
      notifyListeners();
    }
    return (
      checked: checked,
      downloaded: downloaded,
      failed: targets.length - downloaded,
      notChecked: notChecked,
    );
  }

  Future<StoredInstaller?> download(String id) async {
    if (downloadingId != null) return null;
    downloadingId = id;
    downloadReceived = null;
    downloadTotal = null;
    notifyListeners();

    final checked = _onlineReleases[id];
    final stored = await _guard(
      () => _manager.downloadFromGithub(
        id,
        release: checked?.release,
        releaseSource: checked?.source,
        onProgress: (received, total) {
          downloadReceived = received;
          downloadTotal = total;
          notifyProgress();
        },
      ),
    );

    downloadingId = null;
    _onlineReleases.remove(id);
    if (stored != null) {
      onlineVersions.remove(id);
      await load();
    } else {
      notifyListeners();
    }
    return stored;
  }

  Future<({bool ok, String? copiedPath, String? learnedExeName})> install(
    String id, {
    String? copyToDir,
  }) async {
    final outcome =
        await _guard(() => _manager.install(id, copyToDir: copyToDir));
    isLearning = false;

    final ok = errorMessage == null;
    if (ok) await load(redetect: id);
    notifyListeners();
    return (
      ok: ok,
      copiedPath: outcome?.copiedPath,
      learnedExeName: outcome?.learned?.exeName,
    );
  }

  Future<bool> launch(CustomAppInstallState state) async {
    final ok = await _guard(() async {
      await _manager.launch(state);
      return true;
    });
    return ok == true;
  }

  Set<String> _folderIds = const {};

  Set<String> get takenIds =>
      {..._folderIds, for (final app in apps) app.descriptor.id};

  // ── מדיה: אייקון וצילומי מסך ──────────────────────────────────────────

  /// נבנה בכל קריאה מחדש ולא נשמר: הוא עולה כלום, והשורש קבוע כל ההרצה.
  CustomAppMedia _mediaOf(String id) => CustomAppMedia(
        appDir: CustomAppStore(mirrorRootDir: _mirrorRootDir).dirFor(id),
      );

  /// חילוץ האייקון מקובץ הרצה. תפר לבדיקות — האמיתי מריץ PowerShell.
  late final ExeIconExtraction _extractIcon;

  /// המזהים שכבר ניסינו למלא להם אייקון בהרצה הזו. ניסיון עולה תהליך
  /// PowerShell, ואין טעם לשלם עליו שוב על תוכנה שאין לה אייקון בקובץ.
  final Set<String> _iconAttempts = {};

  bool _fillingIcons = false;

  /// נתיב קובץ ההתקנה ששמור על הכונן, או `null` כשעוד לא הגיע קובץ.
  /// חשוף לטופס: כשהתוכנה אינה מותקנת במחשב הזה — והמצב הזה הוא הנורמה
  /// במחשב המקוון — המתקין הוא הקובץ היחיד שאפשר לחלץ ממנו אייקון.
  String? storedInstallerPathOf(String id) {
    for (final app in apps) {
      if (app.descriptor.id != id) continue;
      final installer = app.storedInstaller;
      if (installer == null) return null;
      return CustomAppStore(mirrorRootDir: _mirrorRootDir)
          .installerPathFor(id, installer);
    }
    return null;
  }

  /// נתיב האייקון, או `null` כשאין. סינכרוני בכוונה — הוא נקרא מתוך
  /// `build`, ו-`Image.file` ממילא מטפל בקובץ שנמחק.
  String? iconPathOf(AppDescriptor descriptor) =>
      _mediaOf(descriptor.id).iconPathOf(descriptor);

  List<String> screenshotPathsOf(AppDescriptor descriptor) =>
      _mediaOf(descriptor.id).screenshotPathsOf(descriptor);

  /// כותב מחדש את המדיה של תוכנה רשומה. המקורות הם נתיבים מלאים, ומה
  /// שלא נמסר נמחק — ראו `CustomAppsManager.saveMedia`.
  Future<bool> saveMedia(
    String id, {
    String? iconSource,
    List<String> screenshotSources = const [],
  }) async {
    final saved = await _guard(
      () => _manager.saveMedia(
        id,
        iconSource: iconSource,
        screenshotSources: screenshotSources,
      ),
    );
    if (saved == null) return false;
    await load();
    return true;
  }

  /// מאיזה קובץ הרצה אפשר לחלץ אייקון לתוכנה הזו, או `null` כשאין.
  ///
  /// הסדר הוא סדר האיכות: **התוכנה עצמה** כשהיא מותקנת כאן, ואחריה
  /// **המתקין ששמור על הכונן** — שנושא כמעט תמיד את אותו אייקון, והוא
  /// הקובץ היחיד שקיים במחשב המקוון, שבו התוכנה כלל אינה מותקנת.
  String? iconSourceExeOf(CustomAppView app) {
    if (app.installed?.launchPath case final path?) return path;
    final stored = storedInstallerPathOf(app.descriptor.id);
    if (stored != null && p.extension(stored).toLowerCase() == '.exe') {
      return stored;
    }
    return null;
  }

  /// ממלא אייקון לתוכנות שאין להן אחד — **ברירת המחדל, בלי שהמשתמש יבקש**.
  ///
  /// שקט לחלוטין: האייקון הוא קישוט, וכשל בחילוץ אינו שגיאה שמישהו צריך
  /// לראות. [readOnly] עוצר לגמרי — השמירה כותבת אל הכונן.
  Future<void> fillMissingIcons({bool readOnly = false}) async {
    if (readOnly || _fillingIcons) return;
    _fillingIcons = true;
    var filled = false;
    try {
      for (final app in apps) {
        if (await _fillIcon(app)) filled = true;
      }
    } finally {
      _fillingIcons = false;
    }
    if (filled) await load();
  }

  Future<bool> _fillIcon(CustomAppView app) async {
    final descriptor = app.descriptor;
    // אייקון שכבר יש, או משתמש שהסיר אחד במפורש — לא נוגעים.
    if (descriptor.iconFile != null || !descriptor.autoIcon) return false;
    if (!_iconAttempts.add(descriptor.id)) return false;

    final source = iconSourceExeOf(app);
    if (source == null) return false;
    final extracted = await _extractIcon(source);
    if (extracted == null) return false;

    try {
      // ⚠️ צילומי המסך נמסרים שוב: `saveMedia` כותב את **כל** המדיה
      // מחדש, ובלעדיהם מילוי האייקון היה מוחק אותם.
      await _manager.saveMedia(
        descriptor.id,
        iconSource: extracted,
        screenshotSources: screenshotPathsOf(descriptor),
      );
      return true;
    } catch (e) {
      AppLogger.instance.warn('שמירת האייקון של ${descriptor.id} נכשלה: $e');
      return false;
    }
  }

  // ── קטגוריות ──────────────────────────────────────────────────────────

  /// איזו רשימה מוצגת. נשמר בקונטרולר ולא במסך, כדי שיציאה ללשונית אחרת
  /// וחזרה לא יאפסו את הקטגוריה שנבחרה — המסך עצמו נשאר בעץ.
  CustomAppsPage page = CustomAppsPage.all;

  /// הקטגוריה הפתוחה, כש-[page] הוא `category`.
  String? openCategorySlug;

  CustomAppCategory? get openCategory {
    final slug = openCategorySlug;
    if (slug == null) return null;
    for (final category in categories) {
      if (category.slug == slug) return category;
    }
    return null;
  }

  void showAllApps() {
    page = CustomAppsPage.all;
    openCategorySlug = null;
    notifyListeners();
  }

  void showCategory(String slug) {
    page = CustomAppsPage.category;
    openCategorySlug = slug;
    notifyListeners();
  }

  void showUncategorized() {
    page = CustomAppsPage.uncategorized;
    openCategorySlug = null;
    notifyListeners();
  }

  Set<String> get _knownSlugs => {for (final c in categories) c.slug};

  List<CustomAppView> appsIn(String slug) => [
        for (final app in apps)
          if (app.descriptor.categorySlugs.contains(slug)) app,
      ];

  /// מה שאינו שייך לשום קטגוריה **קיימת**. שיוך לקטגוריה שנמחקה מכונן
  /// אחר נחשב כאן כאילו אינו — אחרת התוכנה הייתה נעלמת מכל הרשימות.
  List<CustomAppView> get uncategorizedApps {
    final known = _knownSlugs;
    return [
      for (final app in apps)
        if (!app.descriptor.categorySlugs.any(known.contains)) app,
    ];
  }

  /// מה שמוצג כרגע, לפי [page].
  List<CustomAppView> get visibleApps => switch (page) {
        CustomAppsPage.all => apps,
        CustomAppsPage.uncategorized => uncategorizedApps,
        CustomAppsPage.category =>
          openCategorySlug == null ? apps : appsIn(openCategorySlug!),
      };

  /// שם הקטגוריה לפי slug, או ה-slug עצמו כשאינה מוכרת — כך תגית של
  /// קטגוריה שהגיעה מכונן אחר עדיין אומרת משהו.
  String categoryName(String slug) {
    for (final category in categories) {
      if (category.slug == slug) return category.name;
    }
    return slug;
  }

  /// מוסיף קטגוריה חדשה ומחזיר את ה-slug שלה, או `null` בכשל.
  Future<String?> addCategory(String name, {String description = ''}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final slug = CustomAppCategory.slugFor(trimmed, taken: _knownSlugs);

    final ok = await _guard(() async {
      await _manager.saveCategories([
        ...categories,
        CustomAppCategory(
          slug: slug,
          name: trimmed,
          description: description.trim(),
        ),
      ]);
      return true;
    });
    if (ok != true) return null;
    await load();
    return slug;
  }

  /// שינוי שם או תיאור. ה-slug **אינו** משתנה — הוא רשום על התוכנות
  /// עצמן, ושינויו היה מנתק את כולן מהקטגוריה.
  Future<bool> renameCategory(
    String slug, {
    required String name,
    String? description,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;

    final ok = await _guard(() async {
      await _manager.saveCategories([
        for (final category in categories)
          if (category.slug == slug)
            category.copyWith(name: trimmed, description: description?.trim())
          else
            category,
      ]);
      return true;
    });
    if (ok == true) await load();
    return ok == true;
  }

  /// מסיר קטגוריה ומנתק ממנה את כל התוכנות. **אינו מסיר תוכנות** —
  /// הן פשוט חוזרות ל"ללא קטגוריה".
  Future<bool> removeCategory(String slug) async {
    final ok = await _guard(() async {
      await _manager.removeCategory(slug);
      return true;
    });
    if (ok != true) return false;
    if (openCategorySlug == slug) {
      page = CustomAppsPage.all;
      openCategorySlug = null;
    }
    await load();
    return true;
  }

  /// מריץ פעולה, מסמן עסוק, ולוכד את ההודעה המתורגמת של החבילה.
  Future<T?> _guard<T>(Future<T> Function() action) async {
    isBusy = true;
    errorMessage = null;
    notifyListeners();
    try {
      return await action();
    } on AppDescriptorException catch (e) {
      // ההודעה כבר מתורגמת ומסבירה בדיוק מה לא בסדר — מוצגת כמות שהיא.
      errorMessage = e.message;
      return null;
    } catch (e) {
      AppLogger.instance.warn('פעולה על תוכנה מותאמת נכשלה: $e');
      errorMessage = '$e';
      return null;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }
}

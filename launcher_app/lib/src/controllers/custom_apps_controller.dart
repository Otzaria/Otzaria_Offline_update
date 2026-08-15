import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;

import '../services/app_logger.dart';
import 'progress_notifier.dart';

/// הגרסה המוטבעת בקובץ הרצה, או `null`. ציבורי כי הבונה משתמש בו כדי
/// להציע גרסה מתוך קובץ ההתקנה עצמו — ב-Inno ובדומיו זו בדרך כלל הגרסה
/// של התוכנה, וזה חוסך מהמשתמש להקליד אותה.
String? readInstallerVersion(String path) =>
    CustomAppsController._readInstalledVersion(path);

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
}

/// מצב התוכנות המותאמות עבור הממשק.
///
/// **ריק הוא המצב הרגיל.** רוב המשתמשים לא יוסיפו אף תוכנה, והממשק חייב
/// להיעלם לגמרי כש-[apps] ריקה — ראו [hasApps].
class CustomAppsController extends ChangeNotifier with ProgressNotifier {
  /// נבנה בגוף הבנאי ולא ברשימת האתחול, כי `onLearningStarted` מצביע חזרה
  /// אל הקונטרולר — ורשימת אתחול אינה יכולה לגעת ב-`this`.
  CustomAppsController({
    required String mirrorRootDir,
    CustomAppsManager? manager,
  }) {
    _manager = manager ??
        CustomAppsManager(
          // כל המראות תחת אותו שורש שלצד התוכנה, כך שהכול נוסע יחד.
          resolveMirrorDir: () async => mirrorRootDir,
          // התפרים שהחבילה עצמה אינה ממשת, כדי להישאר נקייה מ-win32 —
          // הלאנצ'ר כבר מחזיק את כולם.
          readVersion: _readInstalledVersion,
          lookupUninstallDirs: _lookupUninstallDirs,
          lookupRunningProcess: _findRunningProcess,
          // שני התפרים של הלמידה שאחרי ההתקנה — ראו `InstallLearner`.
          lookupUninstallEntries: _uninstallEntries,
          lookupInstalledExe: findInstalledExe,
          onLearningStarted: _markLearning,
        );
  }

  void _markLearning() {
    isLearning = true;
    notifyListeners();
  }

  late final CustomAppsManager _manager;

  List<CustomAppView> apps = const [];
  bool isBusy = false;
  String? errorMessage;

  /// דולק כל זמן שממתינים לרישום ההסרה אחרי התקנה — עד דקה, כי קוד יציאה 0
  /// של מתקין אינו אומר שהרישום שלו כבר נכתב. המתנה בלי הודעה נראית כתקיעה.
  bool isLearning = false;

  /// הדגל היחיד שהממשק צריך כדי להחליט אם להציג משהו בכלל.
  bool get hasApps => apps.isNotEmpty;

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

  /// נתיב ההרצה של תהליך שרץ כרגע ושמו [exeName].
  ///
  /// אותו מנגנון שמאתר את אוצריא (`RunningOtzariaLocator`), רק עם שם אחר:
  /// `tasklist` נותן את ה-pid, ו-`QueryFullProcessImageNameW` את הנתיב.
  /// זו העדות החזקה ביותר — היא מוצאת גם התקנה בתיקייה שאיש לא ניחש.
  static Future<String?> _findRunningProcess(String exeName) async {
    try {
      for (final pid in await RunningOtzariaLocator.windowsPidsOf(exeName)) {
        final path = RunningOtzariaLocator.windowsImagePathOfPid(pid);
        if (path != null) return path;
      }
    } catch (_) {
      // אין הרשאה, או פלטפורמה אחרת — ממשיכים לחיפוש בתיקיות.
    }
    return null;
  }

  static List<String> _lookupUninstallDirs(RegExp displayName) {
    try {
      return const WindowsInstallRegistry()
          .installDirs(matchesDisplayName: displayName.hasMatch);
    } catch (_) {
      return const [];
    }
  }

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

  /// קובץ ההרצה של תוכנה בתוך [dir], לפי רמזי שם.
  ///
  /// מממש דרך `OtzariaAppLocator` ולא דרך סורק חדש: הוא כבר יודע לפסול
  /// `unins*.exe`, עזרי Flutter (`crashpad_handler.exe`) ואת קובצי ההרצה של
  /// הלאנצ'ר עצמו, וסורק לרוחב כדי שהתשובה תהיה זהה בכל מחשב. **"ה-exe
  /// הראשון בתיקייה" הוא באג מתועד בריפו הזה.**
  static Future<String?> findInstalledExe(
    String dir,
    List<String> nameHints,
  ) =>
      const OtzariaAppLocator().findIn(
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

  /// טוען את הרשימה וסורק מה מותקן. קריאת דיסק בלבד — לא נוגע ברשת.
  Future<void> load() async {
    try {
      final entries = await _manager.loadAll();
      final views = <CustomAppView>[];
      for (final entry in entries) {
        views.add(
          CustomAppView(
            entry: entry,
            installed: await _detectQuietly(entry.descriptor),
          ),
        );
      }
      apps = views;
      errorMessage = null;
    } catch (e) {
      // תקלה כאן לא אמורה לשבש את שאר הלאנצ'ר: זו תוספת, לא ליבה.
      AppLogger.instance.warn('טעינת התוכנות המותאמות נכשלה: $e');
      apps = const [];
    }
    notifyListeners();
  }

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

  /// שומר עריכה של רשומה קיימת. המזהה נשאר כשהיה — ראו
  /// [CustomAppsManager.update].
  Future<bool> update(AppDescriptor descriptor) async {
    final ok = await _guard(() async {
      await _manager.update(descriptor);
      return true;
    });
    if (ok == true) await load();
    return ok == true;
  }

  Future<bool> remove(String id) async {
    final ok = await _guard(() async {
      await _manager.remove(id);
      return true;
    });
    if (ok == true) await load();
    return ok == true;
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

  /// "בחירת מיקום ידנית" — המשתמש מצביע על התיקייה, בדיוק כמו בכפתור
  /// המקביל של אוצריא. `false` כשקובץ ההרצה אינו שם.
  ///
  /// מיקום שנמצא נרשם, ומצטרף למיקומים שייבדקו קודם בכל מחשב שהכונן
  /// יגיע אליו.
  Future<bool> adoptInstallDir(AppDescriptor descriptor, String dir) async {
    final state = await _guard(
      () => _manager.adoptInstallDir(descriptor, dir),
    );
    if (state == null) return false;
    await load();
    return true;
  }

  /// בדיקה קלה ברשת — קריאת API אחת, בלי הורדת קובץ. כשל נבלע ומסומן
  /// ב-[onlineUnavailable]: "אין רשת" אינו שגיאה בתוכנה שכל ייעודה לעבוד
  /// בלעדיה.
  Future<void> checkOnline(AppDescriptor descriptor) async {
    if (descriptor.sourceKind != AppSourceKind.github) return;
    try {
      final release = await _manager.peekLatestOnline(descriptor);
      onlineUnavailable.remove(descriptor.id);
      if (release != null) onlineVersions[descriptor.id] = release.version;
    } catch (_) {
      onlineUnavailable.add(descriptor.id);
    }
    notifyListeners();
  }

  /// **הפעולה היחידה כאן שדורשת אינטרנט**: מורידה מהריפו את הקובץ שנבחר
  /// אל הכונן.
  Future<StoredInstaller?> download(String id) async {
    if (downloadingId != null) return null;
    downloadingId = id;
    downloadReceived = null;
    downloadTotal = null;
    notifyListeners();

    final stored = await _guard(
      () => _manager.downloadFromGithub(
        id,
        onProgress: (received, total) {
          downloadReceived = received;
          downloadTotal = total;
          // ההתקדמות מגיעה פר-צ'אנק — עשרות אלפי קריאות בהורדה גדולה.
          // `notifyProgress` מאחד אותן ל-~10 לשנייה; `notifyListeners`
          // ישיר כאן היה עולה יותר מההורדה עצמה.
          notifyProgress();
        },
      ),
    );

    downloadingId = null;
    if (stored != null) {
      onlineVersions.remove(id);
      await load();
    } else {
      notifyListeners();
    }
    return stored;
  }

  /// מתקין מהעותק שעל הכונן, ואחר כך **לומד כיצד לזהות את התוכנה**.
  ///
  /// הלמידה יכולה להימשך עד דקה — קוד יציאה 0 של מתקין אינו אומר שהרישום
  /// שלו כבר נכתב — ולכן [isLearning] דולק בזמנה והממשק אומר זאת.
  /// [copyToDir] נמסר רק לתוכנה שהקובץ שלה הוא **התוכנה עצמה** — הממשק
  /// שואל לאן להעתיק לפני שהוא קורא לכאן.
  Future<({bool ok, String? copiedPath, String? learnedExeName})> install(
    String id, {
    String? copyToDir,
  }) async {
    final outcome =
        await _guard(() => _manager.install(id, copyToDir: copyToDir));
    isLearning = false;

    final ok = errorMessage == null;
    if (ok) await load();
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

  /// המזהים התפוסים — הבונה צריך אותם כדי לייצר מזהה פנוי.
  Set<String> get takenIds => {for (final app in apps) app.descriptor.id};

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

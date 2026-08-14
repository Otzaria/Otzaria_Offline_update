import 'dart:io';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

import 'models/app_descriptor.dart';
import 'models/app_source_kind.dart';
import 'models/custom_app_install_state.dart';
import 'models/custom_install_outcome.dart';
import 'models/github_release.dart';
import 'models/stored_installer.dart';
import 'services/custom_app_installer.dart';
import 'services/custom_app_locator.dart';
import 'services/custom_app_store.dart';
import 'services/github_app_client.dart';
import 'services/install_learner.dart';
import 'services/known_locations_store.dart';

/// נקודת הכניסה היחידה לתוכנות מותאמות.
///
/// ```dart
/// final manager = CustomAppsManager(
///   resolveMirrorDir: () async => p.join(appPaths.dataDir, 'mirror'),
///   readVersion: (exe) => versionReader.readVersion(exe),
/// );
///
/// // במחשב המקוון — התוכנה נרשמת מהטופס, וקובץ ההתקנה נאסף אליה:
/// await manager.add(descriptor);
/// await manager.attachInstaller(descriptor.id,
///     sourcePath: r'D:\downloads\MyApp-Setup.exe', version: '1.4.2');
///
/// // במחשב המנותק, אחרי שהכונן הגיע לשם:
/// await manager.install(descriptor.id);
/// ```
///
/// **אין כאן ייבוא של תיאור מקובץ.** תוכנה נוצרת אך ורק מהטופס שבממשק,
/// כלומר כל ריפו וכל קובץ התקנה נבחרו על ידי המשתמש עצמו — ולכן אין כאן
/// שום תיאור שהגיע מגורם שהוא אינו מכיר.
class CustomAppsManager {
  CustomAppsManager({
    required this.resolveMirrorDir,
    required AppVersionReader readVersion,
    UninstallDirLookup? lookupUninstallDirs,
    RunningProcessLookup? lookupRunningProcess,
    UninstallEntriesLookup? lookupUninstallEntries,
    LearnedExeLookup? lookupInstalledExe,
    void Function()? onLearningStarted,
    CustomProcessRunner? processRunner,
    String? downloadsDir,
    GithubAppClient? githubClient,
    InstallLearner? learner,
  })  : _locator = CustomAppLocator(
          readVersion: readVersion,
          lookupUninstallDirs: lookupUninstallDirs,
          lookupRunningProcess: lookupRunningProcess,
        ),
        _installer = CustomAppInstaller(
          processRunner: processRunner,
          downloadsDir: downloadsDir,
        ),
        _learner = learner ??
            InstallLearner(
              lookupUninstallEntries: lookupUninstallEntries,
              lookupExe: lookupInstalledExe,
              onStart: onLearningStarted,
            ),
        github = githubClient ?? GithubAppClient();

  /// תיקיית המראה נמסרת כ-callback ולא כמחרוזת — בדיוק כמו ב-
  /// `PluginsManager`, כדי ששינוי בזמן ריצה ייכנס לתוקף מיד.
  final Future<String> Function() resolveMirrorDir;

  /// חשוף כדי שהטופס יוכל להביא את רשימת הקבצים של ה-release **לפני**
  /// שהתוכנה נרשמה בכלל.
  final GithubAppClient github;

  final CustomAppLocator _locator;
  final CustomAppInstaller _installer;
  final InstallLearner _learner;

  /// לאן מגיעה תוכנה מסוג ארכיון.
  String get downloadsDir => _installer.downloadsDir;

  Future<CustomAppStore> _store() async =>
      CustomAppStore(mirrorRootDir: await resolveMirrorDir());

  /// כל התוכנות הרשומות. רשימה ריקה היא המצב הרגיל אצל רוב המשתמשים —
  /// והממשק חייב להיעלם לגמרי כשהיא ריקה.
  Future<List<CustomAppEntry>> loadAll() async => (await _store()).loadAll();

  Future<CustomAppEntry?> load(String id) async => (await _store()).load(id);

  /// רושם תוכנה חדשה. **התיאור נוצר תמיד כאן, מתוך הטופס** — אין ייבוא
  /// של תיאור מקובץ חיצוני, ולכן אין תיאור שהגיע מגורם שהמשתמש אינו
  /// מכיר. זה מה שמייתר דיאלוג אמון: הוא בחר בעצמו את הריפו ואת הקובץ.
  Future<void> add(AppDescriptor descriptor) async =>
      (await _store()).add(descriptor);

  /// מעדכן רשומה שכבר קיימת — מה שהטופס עושה כשפותחים אותו לעריכה.
  ///
  /// **המזהה אינו משתנה.** הוא שם התיקייה שבה כבר יושבים קובץ ההתקנה
  /// והמיקומים שנלמדו, ושינויו היה מנתק את התוכנה מהם.
  Future<void> update(AppDescriptor descriptor) async {
    final store = await _store();
    if (await store.load(descriptor.id) == null) {
      throw AppDescriptorException(
        AppL10n.strings.customAppsDomain.appNotRegistered(descriptor.id),
      );
    }
    await store.saveDescriptor(descriptor);
  }

  /// מסיר מהמרשם. **אינו מסיר את התוכנה מהמחשב** — ראו
  /// [CustomAppStore.remove].
  Future<void> remove(String id) async => (await _store()).remove(id);

  /// מעתיק קובץ התקנה אל תיקיית התוכנה במראה, כך שייסע על הכונן.
  ///
  /// מחליף קובץ קודם אם היה — "עדכון" במקור `manual` פירושו בדיוק זה.
  Future<StoredInstaller> attachInstaller(
    String id, {
    required String sourcePath,
    required String version,
  }) async {
    final t = AppL10n.strings.customAppsDomain;
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw AppDescriptorException(t.installerFileMissing(sourcePath));
    }

    final store = await _store();
    final entry = await store.load(id);
    if (entry == null) throw AppDescriptorException(t.appNotRegistered(id));

    // הקובץ הישן נמחק לפני ההעתקה, אחרת שינוי שם קובץ היה מותיר את שניהם
    // בתיקייה והכונן היה מתמלא בגרסאות שאיש לא יקרא.
    if (entry.installer case final old?) {
      try {
        await File(store.installerPathFor(id, old)).delete();
      } catch (_) {}
    }

    final fileName = p.basename(sourcePath);
    await Directory(store.dirFor(id)).create(recursive: true);
    await source.copy(p.join(store.dirFor(id), fileName));

    final stored = StoredInstaller(
      fileName: fileName,
      version: version,
      sizeBytes: await source.length(),
      addedAt: DateTime.now(),
    );
    await store.saveInstaller(id, stored);
    return stored;
  }

  /// בודק ברשת מה הגרסה האחרונה בריפו — **פעולה קלה**, קריאת API אחת בלי
  /// הורדת קובץ. זורק כשהתוכנה אינה מוגדרת עם ריפו.
  Future<GithubRelease?> peekLatestOnline(AppDescriptor descriptor) async {
    final source = descriptor.github;
    if (descriptor.sourceKind != AppSourceKind.github || source == null) {
      throw AppDescriptorException(
        AppL10n.strings.customAppsDomain.sourceIsNotGithub,
      );
    }
    return github.fetchLatest(source);
  }

  /// **הפעולה הכבדה שנוגעת ברשת**: מוריד מהריפו את הקובץ שנבחר אל המראה,
  /// כך שייסע על הכונן. רצה על המחשב המקוון בלבד.
  Future<StoredInstaller> downloadFromGithub(
    String id, {
    void Function(int received, int total)? onProgress,
  }) async {
    final t = AppL10n.strings.customAppsDomain;
    final store = await _store();
    final entry = await store.load(id);
    if (entry == null) throw AppDescriptorException(t.appNotRegistered(id));

    final release = await peekLatestOnline(entry.descriptor);
    if (release == null) throw AppDescriptorException(t.githubNoReleases);

    final asset = GithubAppClient.selectAsset(
      release,
      entry.descriptor.github!.assetPattern,
    );
    // התבנית נבנתה משם שהמשתמש בחר, אך שמות משתנים. הודעה מפורשת עדיפה
    // על הורדת "הקובץ הראשון", שהיא בדיוק הבאג שהתבנית קיימת כדי למנוע.
    if (asset == null) {
      throw AppDescriptorException(t.githubNoMatchingAsset(release.tagName));
    }

    // מורידים לשם זמני ומחליפים רק בסוף: הורדה שנקטעה לא תיראה כקובץ
    // שמוכן להתקנה במחשב המנותק.
    final dir = store.dirFor(id);
    final target = p.join(dir, asset.name);
    final temp = '$target.part';
    await github.download(asset, temp, onProgress: onProgress);

    if (entry.installer case final old? when old.fileName != asset.name) {
      try {
        await File(store.installerPathFor(id, old)).delete();
      } catch (_) {}
    }
    await File(temp).rename(target);

    final stored = StoredInstaller(
      fileName: asset.name,
      version: release.version,
      sizeBytes: await File(target).length(),
      addedAt: DateTime.now(),
    );
    await store.saveInstaller(id, stored);
    return stored;
  }

  /// מתקין מהקובץ ששמור במראה. **לא נוגע ברשת** — זה מה שעובד במחשב
  /// המנותק.
  ///
  /// מיד אחרי ההתקנה **נלמד כיצד לזהות את התוכנה** (ראו [InstallLearner]):
  /// זו הדרך שבה שם קובץ ההרצה ותבנית ה-`DisplayName` נכנסים לרשומה בלי
  /// שהמשתמש ייענה על שאלות שלא יכול היה לענות עליהן במחשב המקוון, שבו
  /// התוכנה כלל לא הייתה מותקנת.
  Future<CustomInstallOutcome> install(String id) async {
    final t = AppL10n.strings.customAppsDomain;
    final store = await _store();
    final entry = await store.load(id);
    if (entry == null) throw AppDescriptorException(t.appNotRegistered(id));

    final installer = entry.installer;
    if (installer == null) {
      throw AppDescriptorException(t.noInstallerInMirror);
    }

    // הצילום נלקח **לפני** ההרצה: אחריה אין דרך לדעת איזה רישום הסרה היה
    // כאן קודם ואיזה נולד עכשיו.
    final before = await _learner.snapshot();

    final outcome = await _installer.install(
      descriptor: entry.descriptor,
      installerPath: store.installerPathFor(id, installer),
    );
    // ארכיון אינו מותקן לשום מקום, ולכן אין ממה ללמוד.
    if (outcome.isArchive) return outcome;

    final learned = await _learner.learn(
      descriptor: entry.descriptor,
      before: before,
      installerFileName: installer.fileName,
    );
    if (learned == null) return outcome;

    final updated = entry.descriptor.copyWith(detect: learned);
    await store.saveDescriptor(updated);
    // זיהוי מיד אחרי הלמידה עושה שני דברים: מאמת שמה שנלמד באמת מוצא את
    // התוכנה, ורושם את התיקייה ל-`locations.json` — שהוא פר-מחשב, ולכן
    // המקום היחיד שנתיב מוחלט מותר לשכון בו.
    await detectInstalled(updated);
    return CustomInstallOutcome(
      kind: outcome.kind,
      archivePath: outcome.archivePath,
      learned: learned,
    );
  }

  /// מה מותקן על המחשב **הזה**, או `null` כשלא נמצאה התקנה.
  ///
  /// מיקום שנמצא **נרשם** ל-`locations.json` של התוכנה, כך שהמחשב הבא
  /// שהכונן יגיע אליו יחפש שם קודם — ראו [KnownLocationsStore].
  Future<CustomAppInstallState?> detectInstalled(
    AppDescriptor descriptor,
  ) async {
    final store = await _store();
    final locations = KnownLocationsStore(
      KnownLocationsStore.pathIn(store.dirFor(descriptor.id)),
    );

    final state = await _locator.detect(
      descriptor,
      learnedDirs: KnownLocationsStore.rank(await locations.load()),
    );
    if (state != null) await locations.record(state.installDir);
    return state;
  }

  /// "בחירת מיקום ידנית" — המשתמש מצביע על התיקייה, בדיוק כמו
  /// `OtzariaManager.adoptExistingInstall`.
  ///
  /// מחזיר `null` כשקובץ ההרצה אינו נמצא שם, כדי שהממשק יאמר "לא נמצאה שם
  /// התקנה" במקום לרשום מיקום שגוי. מיקום שנמצא נרשם ומצטרף למיקומים
  /// שיחופשו בכל מחשב.
  Future<CustomAppInstallState?> adoptInstallDir(
    AppDescriptor descriptor,
    String dir,
  ) async {
    final found = await _locator.findIn(dir, descriptor.detect.exeName);
    if (found == null) return null;

    final store = await _store();
    await KnownLocationsStore(
      KnownLocationsStore.pathIn(store.dirFor(descriptor.id)),
    ).record(found.installDir);
    return found;
  }

  /// מפעיל את התוכנה המותקנת. מנותק מהתהליך שלנו — סגירת הלאנצ'ר לא
  /// אמורה לסגור אותה.
  Future<void> launch(CustomAppInstallState state) async {
    if (!await File(state.launchPath).exists()) {
      throw AppDescriptorException(
        AppL10n.strings.customAppsDomain.launchFileMissing(state.launchPath),
      );
    }
    await Process.start(
      state.launchPath,
      const [],
      workingDirectory: state.installDir,
      mode: ProcessStartMode.detached,
    );
  }
}

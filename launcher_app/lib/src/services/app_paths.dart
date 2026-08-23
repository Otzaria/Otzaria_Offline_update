import 'dart:io';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

/// נזרק כשלא ניתן להשתמש בתיקייה שצמודה לתוכנה **וגם לא ניתן להתקין ממנה**
/// — ראו [AppPaths.resolve].
class AppPathsException implements Exception {
  const AppPathsException({required this.message, required this.attemptedDir});

  /// הודעה מנוסחת למשתמש — מוצגת ישירות במסך השגיאה.
  final String message;
  final String attemptedDir;

  @override
  String toString() => 'AppPathsException: $message ($attemptedDir)';
}

/// תיקיית הנתונים של הלאנצ'ר — **תמיד** צמודה לקובץ ההרצה, ואינה ניתנת
/// לשינוי. זו הדרישה המרכזית של עבודה מכונן נייד: הנתונים נוסעים עם
/// התוכנה, ולא נשארים על המחשב שממנו הורידו אותם.
class AppPaths {
  const AppPaths({
    required this.dataDir,
    required this.stateDir,
    this.readOnly = false,
  });

  /// שם התיקייה שנוצרת לצד קובץ ההרצה.
  static const String dirName = 'OtzariaData';

  /// שם התיקייה שבה נשמרים לוג ומצב כשהכונן עצמו לקריאה בלבד ([readOnly]).
  static const String machineDirName = 'OtzariaOfflineUpdate';

  /// המראה — המקור שממנו קוראים בדיקות והתקנות — תמיד לצד קובץ ההרצה.
  final String dataDir;

  /// לאן **כותבים**: לוג, הגדרות ומצב. זהה ל-[dataDir] בהרצה רגילה, ומצביע
  /// לתיקיית המשתמש שבמחשב הזה כשהכונן מוגן מפני כתיבה.
  final String stateDir;

  /// `true` = הכונן לקריאה בלבד. ההתקנות עובדות (הן כותבות למחשב), ההורדות
  /// מהרשת ועדכון הלאנצ'ר עצמו לא — אין לאן להוריד.
  final bool readOnly;

  /// שלושת ה-manifest שכל אחד מהם לבדו מוכיח שהמראה נמלאה בפועל.
  static const List<List<String>> _mirrorManifests = [
    ['mirror', 'library', 'releases.json'],
    ['mirror', 'app', 'latest-release.json'],
    ['mirror', 'plugins', 'catalog.json'],
  ];

  /// מאתר את התיקייה הצמודה לתוכנה ומוודא שניתן לכתוב בה בפועל.
  ///
  /// כשלא ניתן — ויש במקום מראה שכבר נמלאה — חוזר במצב [readOnly] במקום
  /// לזרוק: כונן שנעל אותו מי שמחלק אותו הוא תרחיש אמיתי (בעיה #25), וכל
  /// מסלולי ההתקנה כותבים למחשב ולא לכונן, ולכן הם עובדים כך. הלוג והמצב
  /// עוברים לתיקיית המשתמש שבמחשב — ושם הם גם נכונים יותר: "איזו גרסה
  /// מותקנת" היא תכונה של המחשב, לא של הכונן.
  ///
  /// זורק [AppPathsException] רק כשגם זה לא אפשרי — תיקייה לא-כותבת ובלי
  /// מראה (למשל התוכנה הועברה ל-`Program Files`). אין נפילה חזרה לתיקיית
  /// המשתמש עבור המראה עצמה: מיקום שאי אפשר להוריד אליו פירושו שהתוכנה
  /// הותקנה במקום הלא נכון, וזה מה שצריך להיאמר.
  static Future<AppPaths> resolve({Map<String, String>? environment}) async {
    final dataDir = p.join(_executableRoot(), dirName);
    final failure = await _probeWritable(dataDir);
    if (failure == null) {
      return AppPaths(dataDir: dataDir, stateDir: dataDir);
    }

    // הבדיקה הזו רצה **רק** אחרי כשל כתיבה, כדי שההרצה הרגילה תישאר סבב
    // I/O אחד.
    if (await _hasMirror(dataDir)) {
      final stateDir = _machineStateDir(environment ?? Platform.environment);
      if (stateDir != null && await _probeWritable(stateDir) == null) {
        return AppPaths(
          dataDir: dataDir,
          stateDir: stateDir,
          readOnly: true,
        );
      }
    }

    throw AppPathsException(
      message: AppL10n.strings.setupError
          .cannotWriteToDataDir(failure.osError?.message ?? failure.message),
      attemptedDir: dataDir,
    );
  }

  /// התיקייה שבה "יושבת" התוכנה מנקודת מבט המשתמש — התיקייה של ה-exe.
  static String _executableRoot() => p.dirname(Platform.resolvedExecutable);

  /// יוצר את התיקייה ובודק כתיבה **בפועל** (קובץ בדיקה), ולא רק שהיצירה
  /// לא זרקה: ב-Windows תיקייה יכולה להיווצר ואז לחסום כתיבה בגלל ACL.
  /// מחזיר את השגיאה במקום לזרוק — הקורא מחליט אם יש מסלול חלופי.
  static Future<FileSystemException?> _probeWritable(String dir) async {
    try {
      await Directory(dir).create(recursive: true);
      final probe = File(p.join(dir, '.write-test'));
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return null;
    } on FileSystemException catch (e) {
      return e;
    }
  }

  /// `true` אם המראה נושאת תוכן — קיומו של manifest אחד מספיק. תיקייה ריקה
  /// על כונן נעול אינה "מצב קריאה" אלא סתם מקום שאין ממנו מה להתקין.
  static Future<bool> _hasMirror(String dataDir) async {
    for (final parts in _mirrorManifests) {
      try {
        if (await File(p.joinAll([dataDir, ...parts])).exists()) return true;
      } on FileSystemException {
        // כונן שלא ניתן לקרוא ממנו בכלל — אין מראה, וזה נאמר בשגיאה.
      }
    }
    return false;
  }

  /// שמות קובצי ההעדפות שנוסעים עם הכונן — ראו [seedPreferences].
  static const List<String> preferenceFileNames = [
    'launcher_settings.json',
    'faq_customization.json',
  ];

  /// מעתיק פעם אחת את **העדפות** המשתמש מהכונן לתיקיית הכתיבה שבמחשב, כדי
  /// שכונן נעול שיצא מהבית עם שפה, ערכת נושא וערוץ נבחר יגיע איתם. קובצי
  /// המצב (מה מותקן ואיפה) אינם מועתקים בכוונה: הם מתארים את המחשב שכתב
  /// אותם, ולא את זה שקורא אותם עכשיו. best-effort — העדפה שלא הועתקה
  /// פירושה ברירת מחדל, לא כשל הרצה.
  Future<void> seedPreferences() async {
    if (!readOnly) return;
    for (final name in preferenceFileNames) {
      try {
        final target = File(p.join(stateDir, name));
        if (await target.exists()) continue;
        final source = File(p.join(dataDir, name));
        if (!await source.exists()) continue;
        await source.copy(target.path);
      } on FileSystemException {
        continue;
      }
    }
  }

  /// תיקיית הכתיבה שבמחשב הזה, או `null` כשאין ממה לגזור אותה.
  static String? _machineStateDir(Map<String, String> environment) {
    final base = Platform.isWindows
        ? environment['LOCALAPPDATA'] ?? environment['APPDATA']
        : environment['XDG_DATA_HOME'] ??
            _joinHome(environment, ['.local', 'share']);
    if (base == null || base.isEmpty) return null;
    return p.join(base, machineDirName);
  }

  static String? _joinHome(Map<String, String> environment, List<String> rest) {
    final home = environment['HOME'];
    if (home == null || home.isEmpty) return null;
    return p.joinAll([home, ...rest]);
  }
}

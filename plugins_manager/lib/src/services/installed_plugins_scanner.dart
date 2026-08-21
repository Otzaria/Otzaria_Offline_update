import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// סורק את התוספים שאוצריא כבר התקינה במחשב הזה.
///
/// המבנה של אוצריא: `<pluginsDir>/installed/<manifestId>/<הוצאה>/manifest.json`,
/// וה-`version` שבתוכו הוא הגרסה המותקנת בפועל. תיקיית ההוצאה היא `current`
/// בהתקנות הישנות ו-`.release-<hash>` בחדשות — **שתיהן** נסרקות, אחרת כל
/// תוסף שהותקן במבנה החדש נראה כלא-מותקן.
///
/// בדומה ל-`LibraryDbLocator`, הנתיב **מתגלה ולא מונח כקבוע**: קודם נתיב
/// שנמסר במפורש, אחר כך שורש הנתונים של ההתקנה שהלאנצ'ר זיהה (התקנה ניידת
/// שומרת אותו לידה ולא ב-`%APPDATA%`), ולבסוף ברירת המחדל של הפלטפורמה.
/// תיקייה שלא קיימת מחזירה מפה ריקה בשקט — זה המצב התקין כשאוצריא לא
/// מותקנת או שאין עדיין תוספים.
class InstalledPluginsScanner {
  const InstalledPluginsScanner({
    this.customPluginsDir,
    this.otzariaLaunchPath,
  });

  /// תיקיית התוספים של אוצריא כפי שנמסרה במפורש, אם נמסרה.
  final String? customPluginsDir;

  /// נתיב ההפעלה של אוצריא שהלאנצ'ר זיהה (`.exe` בווינדוס, חבילת `.app`
  /// ב-macOS). ממנו נגזרת תיקיית התוספים של התקנה ניידת. `null` = פשוט
  /// מדלגים על האפשרות הזו.
  final String? otzariaLaunchPath;

  /// שם תיקיית המשנה שאוצריא מתקינה לתוכה כל תוסף.
  static const String installedDirName = 'installed';

  /// שמות תיקיות ההוצאה שבתוך `installed/<manifestId>/` — המבנה הישן
  /// (`current`) והחדש (`.release-<hash>`).
  static const String currentDirName = 'current';
  static const String releaseDirPrefix = '.release-';

  /// סימון ההתקנה הניידת של אוצריא, ליד ה-executable שלה, ותיקיית הנתונים
  /// שהוא מפעיל. **חייבים להישאר תואמים ל-`LibraryDbLocator`** — אותו זיהוי
  /// בדיוק בשתי החבילות; יש בדיקה ב-`launcher_app` שמאמתת זאת.
  static const String portableMarkerFileName = 'portable.marker';
  static const String portableDataFolderName = 'otzaria_data';

  /// מחזיר `manifestId -> גרסה מותקנת`.
  Future<Map<String, String>> scan() async {
    final root = resolveInstalledDir();
    if (root == null) return const {};

    final dir = Directory(root);
    if (!await dir.exists()) return const {};

    final result = <String, String>{};
    await for (final entry in dir.list(followLinks: false)) {
      if (entry is! Directory) continue;
      final version = _readInstalledVersion(entry.path);
      if (version != null) result[p.basename(entry.path)] = version;
    }
    return result;
  }

  /// תיקיית ה-`installed` שתיסרק בפועל, או null אם אי אפשר לגזור אותה
  /// בפלטפורמה הזו.
  String? resolveInstalledDir() {
    final plugins = resolvePluginsDir();
    if (plugins == null) return null;
    // מי שמוסר נתיב יכול להצביע על `plugins` או ישירות על `plugins/installed`.
    return p.basename(plugins) == installedDirName
        ? plugins
        : p.join(plugins, installedDirName);
  }

  /// תיקיית ה-`plugins` של אוצריא, לפי סדר העדיפות שבתיאור המחלקה.
  String? resolvePluginsDir() {
    final custom = customPluginsDir;
    if (custom != null && custom.isNotEmpty) return custom;

    final portable = portablePluginsDir(otzariaLaunchPath);
    if (portable != null) return portable;

    final candidates = defaultPluginsDirs();
    for (final dir in candidates) {
      if (Directory(p.join(dir, installedDirName)).existsSync()) return dir;
    }
    return candidates.isEmpty ? null : candidates.first;
  }

  /// תיקיית התוספים של התקנה **ניידת** — `<exeDir>/otzaria_data/plugins` —
  /// או null כשההתקנה שזוהתה אינה ניידת.
  ///
  /// הסימון הוא התנאי, בדיוק כמו ב-`LibraryDbLocator`; תיקיית נתונים קיימת
  /// לצד קובץ ההרצה מתקבלת גם בלעדיו, כדי שהתקנה שהסימון שלה נמחק לא תיפול
  /// חזרה ל-`%APPDATA%` של מחשב אחר לגמרי.
  static String? portablePluginsDir(String? launchPath) {
    final exeDir = exeDirOf(launchPath);
    if (exeDir == null) return null;

    final plugins = p.join(exeDir, portableDataFolderName, 'plugins');
    if (File(p.join(exeDir, portableMarkerFileName)).existsSync() ||
        Directory(p.join(plugins, installedDirName)).existsSync()) {
      return plugins;
    }
    return null;
  }

  /// התיקייה שבה יושב ה-executable של אוצריא: ב-macOS זהו `Contents/MacOS`
  /// שבתוך חבילת ה-`.app`, ושם גם יושב סימון ההתקנה הניידת.
  static String? exeDirOf(String? launchPath) {
    if (launchPath == null || launchPath.isEmpty) return null;
    if (launchPath.toLowerCase().endsWith('.app')) {
      return p.join(launchPath, 'Contents', 'MacOS');
    }
    return p.dirname(launchPath);
  }

  /// `%APPDATA%\otzaria\plugins` בווינדוס,
  /// `~/Library/Application Support/otzaria/plugins` ב-macOS.
  static String? defaultPluginsDir() {
    final dirs = defaultPluginsDirs();
    return dirs.isEmpty ? null : dirs.first;
  }

  /// כל שורשי הנתונים של אוצריא בפלטפורמה הזו, לפי סדר עדיפות — התקנה
  /// למשתמש הנוכחי לפני התקנה מערכתית, כמו ב-`LibraryDbLocator`.
  static List<String> defaultPluginsDirs() {
    final env = Platform.environment;
    final dirs = <String>[];

    if (Platform.isWindows) {
      final appData = env['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        dirs.add(p.join(appData, 'otzaria', 'plugins'));
      }
      final programData = env['ProgramData'];
      if (programData != null && programData.isNotEmpty) {
        dirs.add(p.join(programData, 'otzaria', 'plugins'));
      }
      return dirs;
    }

    if (Platform.isMacOS) {
      final home = env['HOME'];
      if (home != null && home.isNotEmpty) {
        dirs.add(p.join(
            home, 'Library', 'Application Support', 'otzaria', 'plugins'));
      }
      dirs.add(p.join('/Library', 'Application Support', 'otzaria', 'plugins'));
      return dirs;
    }

    return dirs;
  }

  /// הגרסה המותקנת של תוסף אחד — מתוך תיקיית ההוצאה הפעילה שלו.
  static String? _readInstalledVersion(String pluginDir) {
    for (final dir in _releaseDirs(pluginDir)) {
      final version = _versionIn(dir);
      if (version != null) return version;
    }
    return null;
  }

  /// תיקיות ההוצאה של תוסף, בסדר עדיפות. `current` קודמת כי היא המצביע
  /// המפורש של המבנה הישן; אחריה `.release-<hash>` מהחדשה לישנה, כי זו
  /// שאוצריא כתבה אחרונה היא הפעילה.
  static List<String> _releaseDirs(String pluginDir) {
    final current = p.join(pluginDir, currentDirName);
    final result = <String>[if (Directory(current).existsSync()) current];

    final releases = <Directory>[];
    try {
      for (final entry in Directory(pluginDir).listSync(followLinks: false)) {
        if (entry is Directory &&
            p.basename(entry.path).startsWith(releaseDirPrefix)) {
          releases.add(entry);
        }
      }
    } catch (_) {
      return result; // תיקייה שאי אפשר לקרוא — מה שנמצא עד כה
    }
    // מיון משני לפי השם, כדי ששתי הוצאות באותה חותמת זמן ייבחרו בקביעות.
    releases.sort((a, b) {
      final byTime = _modified(b).compareTo(_modified(a));
      return byTime != 0
          ? byTime
          : p.basename(b.path).compareTo(p.basename(a.path));
    });
    result.addAll(releases.map((dir) => dir.path));
    return result;
  }

  static DateTime _modified(Directory dir) {
    try {
      return dir.statSync().modified;
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  static String? _versionIn(String releaseDir) {
    try {
      final file = File(p.join(releaseDir, 'manifest.json'));
      if (!file.existsSync()) return null;
      final decoded = jsonDecode(file.readAsStringSync().replaceFirst('﻿', ''));
      if (decoded is! Map) return null;
      final version = decoded['version'];
      return version is String && version.isNotEmpty ? version : null;
    } catch (_) {
      return null; // מניפסט פגום — מתעלמים בשקט מההוצאה הזו
    }
  }
}

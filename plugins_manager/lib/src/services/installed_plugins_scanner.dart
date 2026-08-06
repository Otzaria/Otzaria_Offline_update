import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// סורק את התוספים שאוצריא כבר התקינה במחשב הזה.
///
/// המבנה של אוצריא: `<pluginsDir>/installed/<manifestId>/current/manifest.json`,
/// וה-`version` שבתוכו הוא הגרסה המותקנת בפועל.
///
/// בדומה ל-`LibraryDbLocator`, הנתיב **מתגלה ולא מונח כקבוע**: קודם נתיב
/// שהמשתמש הגדיר, אחר כך ברירת המחדל של הפלטפורמה. תיקייה שלא קיימת
/// מחזירה מפה ריקה בשקט — זה המצב התקין כשאוצריא לא מותקנת או שאין עדיין
/// תוספים.
class InstalledPluginsScanner {
  const InstalledPluginsScanner({this.customPluginsDir});

  /// תיקיית התוספים של אוצריא כפי שהמשתמש הגדיר בהגדרות, אם הגדיר.
  final String? customPluginsDir;

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
    final custom = customPluginsDir;
    if (custom != null && custom.isNotEmpty) {
      // המשתמש יכול להצביע על `plugins` או ישירות על `plugins/installed`.
      return p.basename(custom) == 'installed'
          ? custom
          : p.join(custom, 'installed');
    }

    final base = defaultPluginsDir();
    return base == null ? null : p.join(base, 'installed');
  }

  /// `%APPDATA%\otzaria\plugins` בווינדוס,
  /// `~/Library/Application Support/otzaria/plugins` ב-macOS.
  static String? defaultPluginsDir() {
    final env = Platform.environment;
    if (Platform.isWindows) {
      final appData = env['APPDATA'];
      if (appData == null || appData.isEmpty) return null;
      return p.join(appData, 'otzaria', 'plugins');
    }
    if (Platform.isMacOS) {
      final home = env['HOME'];
      if (home == null || home.isEmpty) return null;
      return p.join(
          home, 'Library', 'Application Support', 'otzaria', 'plugins');
    }
    return null;
  }

  static String? _readInstalledVersion(String pluginDir) {
    try {
      final file = File(p.join(pluginDir, 'current', 'manifest.json'));
      if (!file.existsSync()) return null;
      final decoded = jsonDecode(file.readAsStringSync().replaceFirst('﻿', ''));
      if (decoded is! Map) return null;
      final version = decoded['version'];
      return version is String && version.isNotEmpty ? version : null;
    } catch (_) {
      return null; // מניפסט פגום — מתעלמים בשקט מהתוסף הזה
    }
  }
}

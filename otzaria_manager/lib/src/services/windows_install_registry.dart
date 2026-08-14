import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

import 'otzaria_app_locator.dart';

/// רישום הסרה בודד, כפי שהוא יושב ברג'יסטרי.
///
/// קיים כדי שאפשר יהיה **ללמוד** מהרג'יסטרי ולא רק לחפש בו: השוואת צילום
/// לפני התקנה ואחריה מזהה את התוכנה שהרגע הותקנה, ומשם מגיע ה-`DisplayName`
/// שלה. ראו `InstallLearner` ב-`custom_apps_manager`.
class InstallRegistryEntry {
  const InstallRegistryEntry({
    required this.keyName,
    required this.displayName,
    this.installDir,
  });

  /// שם המפתח תחת `…\Uninstall` — `{GUID}_is1` ב-Inno, קוד המוצר ב-MSI.
  /// **זו הזהות היציבה**, ולפיה משווים שני צילומים: ה-`DisplayName` מכיל
  /// בדרך כלל את מספר הגרסה ומשתנה יחד איתה.
  final String keyName;

  final String displayName;

  /// `InstallLocation` מנורמל, או הגיבוי מ-`UninstallString`. `null` כשאין
  /// תיקייה מוחלטת שקיימת בפועל — רישום כזה עדיין מזהה את התוכנה, ולכן
  /// הוא מוחזר ואינו מסונן.
  final String? installDir;
}

/// שולף מרישומי ההסרה של ווינדוס את תיקיות ההתקנה של אוצריא. ה-installer
/// (Inno Setup) רושם שם `InstallLocation`, ולכן זה המקום היחיד שיודע על
/// התקנה שיושבת בתיקייה שאינה ברשימת ברירות המחדל — **גם כשאוצריא סגורה**,
/// בשונה מזיהוי לפי התהליך הרץ ([RunningOtzariaLocator]).
///
/// מכאן נלקחת **התיקייה בלבד**. הגרסה נקראת תמיד מה-exe עצמו: `DisplayVersion`
/// משקף את מה שהמתקין רשם, ולא בהכרח את מה שיושב על הדיסק כרגע.
///
/// הזיהוי נעשה לפי ה-`DisplayName` בלבד, ומוחזרת רק תיקייה מוחלטת שקיימת
/// בפועל — ראו [installDirs].
///
/// כל כשל (אין הרשאה, ערך חסר, מפתח פגום) מדולג בשקט — הקורא ממשיך לזיהוי
/// לפי תיקיות ברירת המחדל, בדיוק כמו כשאין רישום בכלל.
class WindowsInstallRegistry {
  const WindowsInstallRegistry();

  static const String _uninstallKeyPath =
      r'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall';

  /// שלושת המקומות שבהם ווינדוס מחזיק רישומי הסרה, לפי סדר עדיפות: התקנה
  /// למשתמש הנוכחי (ברירת המחדל של המתקין של אוצריא) לפני התקנה לכלל
  /// המחשב, ושם 64 סיביות לפני 32 — שתי התצוגות נפרדות ברג'יסטרי.
  static const List<({int hive, int access})> _roots = [
    (hive: HKEY_CURRENT_USER, access: KEY_READ),
    (hive: HKEY_LOCAL_MACHINE, access: KEY_READ | KEY_WOW64_64KEY),
    (hive: HKEY_LOCAL_MACHINE, access: KEY_READ | KEY_WOW64_32KEY),
  ];

  /// אורך מרבי של שם מפתח ברג'יסטרי (255 תווים), ועוד תו סיום.
  static const int _maxKeyNameChars = 256;

  /// חוצץ לקריאת ערך. נתיב התקנה לא מתקרב לזה, ומפתח חריג שכן — מדולג.
  static const int _maxValueBytes = 8192;

  /// תיקיות ההתקנה הרשומות, בלי כפילויות ולפי סדר העדיפות של [_roots].
  /// רשימה ריקה = אין רישום (או שלא רצים על ווינדוס), לא שגיאה.
  ///
  /// [matchesDisplayName] בוחר אילו רישומים נחשבים. ברירת המחדל היא אוצריא,
  /// ולכן כל הקוראים הקיימים אינם מושפעים; תוכנה מותאמת מעבירה לכאן את
  /// התבנית שהתוסף שלה הצהיר עליה. הסינון נשאר על ה-`DisplayName` **בלבד**
  /// — ראו [_dirOfEntry] להסבר למה `InstallLocation` אינו סימן זהות.
  List<String> installDirs({
    bool Function(String displayName)? matchesDisplayName,
  }) {
    final dirs = <String>[];
    final seen = <String>{};
    for (final entry in entries(matchesDisplayName: matchesDisplayName)) {
      final dir = entry.installDir;
      if (dir != null && seen.add(dir.toLowerCase())) dirs.add(dir);
    }
    return dirs;
  }

  /// רישומי ההסרה עצמם, עם ה-`DisplayName` ושם המפתח — מה ש-[installDirs]
  /// זורק. רשומה בלי תיקייה מוחלטת שקיימת מוחזרת עם `installDir` שהוא `null`
  /// ואינה מסוננת: לזיהוי היא חסרת תועלת, אבל ל**למידה** היא בדיוק העדות
  /// שמחפשים ("איזה רישום חדש הופיע כאן עכשיו").
  ///
  /// בלי כפילויות לפי שם המפתח, לפי סדר העדיפות של [_roots] — אותה תוכנה
  /// עשויה להיות רשומה גם למשתמש וגם לכלל המחשב.
  List<InstallRegistryEntry> entries({
    bool Function(String displayName)? matchesDisplayName,
  }) {
    if (!Platform.isWindows) return const [];

    final matches = matchesDisplayName ?? OtzariaAppLocator.mentionsOtzaria;
    final result = <InstallRegistryEntry>[];
    final seen = <String>{};
    for (final root in _roots) {
      for (final entry in _entriesUnder(root.hive, root.access, matches)) {
        if (seen.add(entry.keyName.toLowerCase())) result.add(entry);
      }
    }
    return result;
  }

  List<InstallRegistryEntry> _entriesUnder(
    int hive,
    int access,
    bool Function(String displayName) matches,
  ) {
    final pathPtr = _uninstallKeyPath.toNativeUtf16();
    final keyPtr = calloc<IntPtr>();
    try {
      if (RegOpenKeyEx(hive, pathPtr, 0, access, keyPtr) != ERROR_SUCCESS) {
        return const [];
      }
      try {
        return _scanSubKeys(keyPtr.value, access, matches);
      } finally {
        RegCloseKey(keyPtr.value);
      }
    } finally {
      calloc.free(pathPtr);
      calloc.free(keyPtr);
    }
  }

  List<InstallRegistryEntry> _scanSubKeys(
    int uninstallKey,
    int access,
    bool Function(String displayName) matches,
  ) {
    final found = <InstallRegistryEntry>[];
    final namePtr = calloc<Uint16>(_maxKeyNameChars).cast<Utf16>();
    final nameLenPtr = calloc<Uint32>();

    try {
      for (var index = 0;; index++) {
        nameLenPtr.value = _maxKeyNameChars;
        final status = RegEnumKeyEx(
          uninstallKey,
          index,
          namePtr,
          nameLenPtr,
          nullptr,
          nullptr,
          nullptr,
          nullptr,
        );
        // שם ארוך מהחוצץ פוסל את המפתח הבודד, לא את ההמשך: `break` כאן היה
        // מוותר בשקט על כל הרישומים שאחריו, ואוצריא עלולה להיות ביניהם.
        if (status == ERROR_MORE_DATA) continue;
        if (status != ERROR_SUCCESS) break;

        final entry = _entryOf(
          uninstallKey,
          namePtr.toDartString(length: nameLenPtr.value),
          access,
          matches,
        );
        if (entry != null) found.add(entry);
      }
    } finally {
      calloc.free(namePtr);
      calloc.free(nameLenPtr);
    }
    return found;
  }

  /// רישום הסרה בודד, או null אם ה-`DisplayName` אינו תואם (או חסר).
  InstallRegistryEntry? _entryOf(
    int uninstallKey,
    String subKeyName,
    int access,
    bool Function(String displayName) matches,
  ) {
    final namePtr = subKeyName.toNativeUtf16();
    final keyPtr = calloc<IntPtr>();
    try {
      if (RegOpenKeyEx(uninstallKey, namePtr, 0, access, keyPtr) !=
          ERROR_SUCCESS) {
        return null;
      }
      final key = keyPtr.value;
      try {
        // ה-`DisplayName` הוא הסימן היחיד שנבדק: הוא מה שהמתקין של אוצריא
        // כותב ("אוצריא גירסה …"), בעוד ש-`InstallLocation` שמזכיר "otzaria"
        // יכול להיות של תוכנה אחרת לגמרי — ומשם היא נכנסת לזיהוי האוטומטי
        // בלי שום אימות נוסף.
        final displayName = _readString(key, 'DisplayName');
        if (displayName == null || !matches(displayName)) return null;

        return InstallRegistryEntry(
          keyName: subKeyName,
          displayName: displayName,
          installDir: _dirOf(key),
        );
      } finally {
        RegCloseKey(key);
      }
    } finally {
      calloc.free(namePtr);
      calloc.free(keyPtr);
    }
  }

  /// תיקיית ההתקנה של רישום פתוח, או `null` כשאין תיקייה מוחלטת שקיימת.
  static String? _dirOf(int key) {
    var dir = _readString(key, 'InstallLocation');
    if (dir == null) {
      // גיבוי: המתקין רשם רק את פקודת ההסרה — ה-uninstaller יושב בתיקיית
      // ההתקנה עצמה, כך שהתיקייה שלו היא התשובה.
      final uninstall = executableOf(_readString(key, 'UninstallString'));
      dir = uninstall == null ? null : p.dirname(uninstall);
    }
    if (dir == null || dir.isEmpty) return null;

    // רק תיקייה מוחלטת שקיימת בפועל: `UninstallString` של MSI הוא
    // `MsiExec.exe /X{GUID}`, ומשם יוצא נתיב יחסי וחסר משמעות.
    final normalized = p.normalize(dir);
    if (!p.isAbsolute(normalized)) return null;
    if (!Directory(normalized).existsSync()) return null;
    return normalized;
  }

  static String? _readString(int key, String valueName) {
    final namePtr = valueName.toNativeUtf16();
    final typePtr = calloc<Uint32>();
    final sizePtr = calloc<Uint32>()..value = _maxValueBytes;
    // `malloc` ולא `calloc`: האתחול לאפס של calloc בווינדוס הוא לולאת בייטים
    // ב-Dart, וכאן היא הייתה רצה על 8KB פעמיים לכל רישום הסרה במחשב.
    // אין בכך צורך — הקריאה חסומה לפי הגודל שה-API מחזיר.
    final dataPtr = malloc<Uint8>(_maxValueBytes);

    try {
      final status =
          RegQueryValueEx(key, namePtr, nullptr, typePtr, dataPtr, sizePtr);
      if (status != ERROR_SUCCESS) return null;
      if (typePtr.value != REG_SZ && typePtr.value != REG_EXPAND_SZ) {
        return null;
      }

      // הערך אינו חייב להיות מסתיים ב-NUL, ולכן נקראים בדיוק הבייטים
      // שהוחזרו והחיתוך נעשה ידנית.
      final text =
          dataPtr.cast<Utf16>().toDartString(length: sizePtr.value ~/ 2);
      final end = text.indexOf('\x00');
      var value = (end < 0 ? text : text.substring(0, end)).trim();
      if (typePtr.value == REG_EXPAND_SZ) value = expandVariables(value);
      return value.isEmpty ? null : value;
    } finally {
      calloc.free(namePtr);
      calloc.free(typePtr);
      calloc.free(sizePtr);
      malloc.free(dataPtr);
    }
  }

  /// מרחיב `%ProgramFiles%\Otzaria` לנתיב אמיתי. `REG_EXPAND_SZ` מוחזר כפי
  /// שנכתב, ובלי ההרחבה הזו הוא היה יוצא כנתיב עם אחוזים שלא קיים על הדיסק.
  /// משתנה שאינו מוגדר נשאר כמו שהוא — כמו `ExpandEnvironmentStrings`.
  static String expandVariables(String value, {Map<String, String>? env}) {
    final environment = env ?? Platform.environment;
    return value.replaceAllMapped(
      RegExp('%([^%]+)%'),
      (m) => environment[m[1]!] ?? m[0]!,
    );
  }

  /// שולף את קובץ ההרצה מתוך פקודת הסרה: מסיר מירכאות, ומוריד ארגומנטים
  /// שבאים אחרי ה-exe (`…\unins000.exe /SILENT`). בלי זה `p.dirname` היה
  /// חותך על הארגומנט ומחזיר נתיב שאינו תיקייה.
  static String? executableOf(String? value) {
    if (value == null) return null;
    if (value.startsWith('"')) {
      final close = value.indexOf('"', 1);
      return close < 0 ? null : value.substring(1, close);
    }
    final match = RegExp(r'^(.*?\.exe)(\s|$)', caseSensitive: false)
        .firstMatch(value.trim());
    return match?[1] ?? value.trim();
  }
}

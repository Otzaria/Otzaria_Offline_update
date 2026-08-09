import 'dart:io';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

/// נזרק כשלא ניתן להשתמש בתיקייה שצמודה לתוכנה — התוכנה מסרבת לרוץ במקרה
/// כזה במקום ליפול חזרה ל-%APPDATA%, כי היא מיועדת לרוץ מכונן נייד.
class AppPathsException implements Exception {
  const AppPathsException({required this.message, required this.attemptedDir});

  /// הודעה מנוסחת למשתמש — מוצגת ישירות במסך השגיאה.
  final String message;
  final String attemptedDir;

  @override
  String toString() => 'AppPathsException: $message ($attemptedDir)';
}

/// תיקיית הנתונים של הלאנצ'ר — **תמיד** צמודה לקובץ ההרצה, ולא ניתנת
/// לשינוי. זו הדרישה המרכזית של עבודה מכונן נייד: הנתונים נוסעים עם
/// התוכנה, ולא נשארים על המחשב שממנו הורידו אותם.
class AppPaths {
  const AppPaths({required this.dataDir});

  /// שם התיקייה שנוצרת לצד קובץ ההרצה.
  static const String dirName = 'OtzariaData';

  final String dataDir;

  /// מאתר את התיקייה הצמודה לתוכנה ומוודא שניתן לכתוב בה בפועל.
  ///
  /// זורק [AppPathsException] אם לא — למשל כשהתוכנה הועברה ל-`Program Files`
  /// או לכונן לקריאה בלבד. אין נפילה חזרה לתיקיית המשתמש: מיקום שאי אפשר
  /// לכתוב בו פירושו שהתוכנה הותקנה במקום הלא נכון, וזה מה שצריך להיאמר.
  static Future<AppPaths> resolve() async {
    final dataDir = p.join(_executableRoot(), dirName);
    await _ensureWritable(dataDir);
    return AppPaths(dataDir: dataDir);
  }

  /// התיקייה שבה "יושבת" התוכנה מנקודת מבט המשתמש. בווינדוס זו התיקייה של
  /// ה-exe; ב-macOS זו התיקייה שמכילה את חבילת ה-`.app`, ולא התיקייה
  /// שבתוכה (`Contents/MacOS`) — שם המשתמש בכלל לא מסתכל.
  static String _executableRoot() {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    if (!Platform.isMacOS) return exeDir;

    for (var dir = exeDir;; dir = p.dirname(dir)) {
      if (p.extension(dir) == '.app') return p.dirname(dir);
      if (p.dirname(dir) == dir) return exeDir; // הגענו לשורש — לא חבילה
    }
  }

  /// יוצר את התיקייה ובודק כתיבה **בפועל** (קובץ בדיקה), ולא רק שהיצירה
  /// לא זרקה: ב-Windows תיקייה יכולה להיווצר ואז לחסום כתיבה בגלל ACL.
  static Future<void> _ensureWritable(String dataDir) async {
    try {
      await Directory(dataDir).create(recursive: true);
      final probe = File(p.join(dataDir, '.write-test'));
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
    } on FileSystemException catch (e) {
      throw AppPathsException(
        message: AppL10n.strings.setupError
            .cannotWriteToDataDir(e.osError?.message ?? e.message),
        attemptedDir: dataDir,
      );
    }
  }
}

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// כמה מקום פנוי יש על הנפח שבו יושב נתיב נתון.
///
/// ל-Dart אין API לזה, ובלעדיו כל מסלול הורדה/חילוץ במודול הזה פשוט התנגש
/// בדיסק מלא באמצע: המשתמש קיבל `FileSystemException … errno = 112` באנגלית,
/// על נתיב `.new` שהוא לא מכיר, בלי לדעת כמה לפנות ואיפה.
///
/// **כשל מדידה מחזיר `null`, לא אפס.** מדידה שלא הצליחה אינה עדות שאין מקום,
/// ואסור לה לחסום עדכון — כל הקוראים מדלגים על הבדיקה כשהתשובה `null`.
abstract final class DiskSpaceProbe {
  /// הבייטים הפנויים לחשבון הנוכחי על הנפח של [path], או `null` כשלא ניתן
  /// למדוד. [path] יכול להיות קובץ שעדיין אינו קיים — נמדדת התיקייה הקיימת
  /// הראשונה שמעליו.
  static int? freeBytesFor(String path) {
    final dir = _nearestExistingDir(path);
    if (dir == null) return null;
    try {
      if (Platform.isWindows) return _windowsFreeBytes(dir);
      if (Platform.isMacOS || Platform.isLinux) return _posixFreeBytes(dir);
    } catch (_) {
      // כל כשל — ספרייה חסרה, הרשאות, פורמט פלט לא צפוי — הוא "לא יודע".
    }
    return null;
  }

  /// התיקייה הקיימת הראשונה מ-[path] ומעלה. יעד התקנה טרייה עדיין אינו קיים,
  /// והנפח שלו הוא זה של ההורה שכן קיים.
  static String? _nearestExistingDir(String path) {
    var current =
        Directory(path).existsSync() ? Directory(path) : Directory(path).parent;
    // חסם: נתיב שאינו קיים כלל (אות כונן שנשלפה) לא ילופף לנצח.
    for (var depth = 0; depth < 64; depth++) {
      if (current.existsSync()) return current.path;
      final parent = current.parent;
      if (parent.path == current.path) return null;
      current = parent;
    }
    return null;
  }

  static int? _windowsFreeBytes(String dir) {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final getDiskFreeSpaceEx = kernel32.lookupFunction<
        Int32 Function(
            Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>),
        int Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>,
            Pointer<Uint64>)>('GetDiskFreeSpaceExW');

    final pathPtr = dir.toNativeUtf16();
    final freeToCaller = malloc<Uint64>();
    final total = malloc<Uint64>();
    final totalFree = malloc<Uint64>();
    try {
      final ok = getDiskFreeSpaceEx(pathPtr, freeToCaller, total, totalFree);
      if (ok == 0) return null;
      // ה"פנוי לחשבון הזה" ולא ה"פנוי בנפח": מכסת דיסק היא בדיוק המקרה שבו
      // השניים שונים, ומה שקובע הוא מה שאנחנו יכולים לכתוב.
      return freeToCaller.value;
    } finally {
      malloc.free(pathPtr);
      malloc.free(freeToCaller);
      malloc.free(total);
      malloc.free(totalFree);
    }
  }

  /// macOS/Linux דרך `df -k` — פשוט ואמין יותר מ-`statfs` ב-FFI, שהמבנה שלו
  /// שונה בין פלטפורמות וגרסאות. `df` קיים בשתיהן תמיד.
  static int? _posixFreeBytes(String dir) {
    final result = Process.runSync('df', ['-k', dir]);
    if (result.exitCode != 0) return null;
    final lines = (result.stdout as String).trim().split('\n');
    if (lines.length < 2) return null;
    // Filesystem 1024-blocks Used Available ... — העמודה הרביעית.
    final fields = lines.last.trim().split(RegExp(r'\s+'));
    if (fields.length < 4) return null;
    final availableKb = int.tryParse(fields[3]);
    if (availableKb == null) return null;
    return availableKb * 1024;
  }

  /// `true` כשידוע בוודאות שחסר מקום ל-[neededBytes] תחת [path].
  /// מדידה שנכשלה מחזירה `false` — "לא יודע" אינו "אין".
  ///
  /// [headroomBytes] הוא רזרבה מעל הדרוש: כתיבה שממלאת נפח עד הבייט האחרון
  /// מפילה גם דברים אחרים במחשב, ו-NTFS/exFAT צריכים מקום למטא-דאטה.
  static bool isKnownInsufficient(
    String path,
    int neededBytes, {
    int headroomBytes = 256 << 20,
  }) {
    final free = freeBytesFor(path);
    if (free == null) return false;
    return free < neededBytes + headroomBytes;
  }
}

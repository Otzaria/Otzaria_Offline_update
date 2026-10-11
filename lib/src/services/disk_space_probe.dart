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

  static const int fatMaxFileBytes = 0xFFFFFFFF;

  static bool isKnownFat(String path) {
    final dir = _nearestExistingDir(path);
    if (dir == null) return false;
    try {
      final String? name;
      if (Platform.isWindows) {
        name = _windowsFileSystemName(dir);
      } else if (Platform.isMacOS || Platform.isLinux) {
        name = _posixFileSystemName(dir);
      } else {
        name = null;
      }
      return name != null && isFatFileSystemName(name);
    } catch (_) {
      return false;
    }
  }

  static bool isFatFileSystemName(String name) => const {
        'fat',
        'fat12',
        'fat16',
        'fat32',
        'msdos',
        'vfat',
      }.contains(name.trim().toLowerCase());

  static String? fileSystemFromMountTable(String mountOutput, String device) {
    final prefix = '$device on ';
    for (final line in mountOutput.split('\n')) {
      if (!line.startsWith(prefix)) continue;
      final linux = RegExp(r' type (\S+) \(').allMatches(line);
      if (linux.isNotEmpty) return linux.last.group(1);
      final options = line.lastIndexOf(' (');
      if (options < 0) return null;
      final rest = line.substring(options + 2);
      final end = rest.indexOf(RegExp('[,)]'));
      return (end < 0 ? rest : rest.substring(0, end)).trim();
    }
    return null;
  }

  static String? _posixFileSystemName(String dir) {
    final df = Process.runSync('df', ['-P', '-k', dir]);
    if (df.exitCode != 0) return null;
    final lines = (df.stdout as String).trim().split('\n');
    if (lines.length < 2) return null;
    final device = lines.last.trim().split(RegExp(r'\s+')).first;
    if (device.isEmpty) return null;
    final mount = Process.runSync('mount', const []);
    if (mount.exitCode != 0) return null;
    return fileSystemFromMountTable(mount.stdout as String, device);
  }

  static String? _windowsFileSystemName(String dir) {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final getVolumePathName = kernel32.lookupFunction<
        Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32),
        int Function(
            Pointer<Utf16>, Pointer<Utf16>, int)>('GetVolumePathNameW');
    final getVolumeInformation = kernel32.lookupFunction<
        Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32, Pointer<Uint32>,
            Pointer<Uint32>, Pointer<Uint32>, Pointer<Utf16>, Uint32),
        int Function(
            Pointer<Utf16>,
            Pointer<Utf16>,
            int,
            Pointer<Uint32>,
            Pointer<Uint32>,
            Pointer<Uint32>,
            Pointer<Utf16>,
            int)>('GetVolumeInformationW');

    const capacity = 1024;
    final pathPtr = dir.toNativeUtf16();
    final root = malloc<Uint16>(capacity).cast<Utf16>();
    final fsName = malloc<Uint16>(capacity).cast<Utf16>();
    try {
      if (getVolumePathName(pathPtr, root, capacity) == 0) return null;
      final ok = getVolumeInformation(
          root, nullptr, 0, nullptr, nullptr, nullptr, fsName, capacity);
      if (ok == 0) return null;
      return fsName.toDartString();
    } finally {
      malloc.free(pathPtr);
      malloc.free(root);
      malloc.free(fsName);
    }
  }

  static const int defaultHeadroomBytes = 256 << 20;

  static bool lacksSpace(
    int? freeBytes,
    int neededBytes, {
    int headroomBytes = defaultHeadroomBytes,
  }) =>
      freeBytes != null && freeBytes < neededBytes + headroomBytes;

  static bool isKnownInsufficient(
    String path,
    int neededBytes, {
    int headroomBytes = defaultHeadroomBytes,
  }) =>
      lacksSpace(freeBytesFor(path), neededBytes, headroomBytes: headroomBytes);
}

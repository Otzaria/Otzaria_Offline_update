import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// מאתר את **הקובץ שהמשתמש מפעיל בפועל** — זה שצריך להוחלף בעדכון, ולא
/// ה-exe שרץ כרגע.
///
/// בווינדוס ההפצה היא exe בודד (ה-stub) שמחלץ לידו `app-files\` ומריץ משם
/// את `launcher_app.exe`; `Platform.resolvedExecutable` מחזיר את השני, ולכן
/// אי אפשר להסתמך עליו. ב-macOS מה שמוחלף הוא חבילת ה-`.app` כולה.
///
/// [LauncherInstallLayout.dataDirName] אינו מופיע כאן במפורש בכוונה:
/// `OtzariaData/` יושבת **בתוך** `app-files`, וההחלפה נוגעת רק בקובץ ההרצה
/// שלצידה — ראו `LauncherSelfInstaller`.
class LauncherInstallLayout {
  const LauncherInstallLayout({required this.executablePath});

  /// הקובץ (או חבילת ה-`.app`) שהמשתמש מפעיל.
  final String executablePath;

  /// התיקייה שבה הוא יושב — לשם מגיעה הגרסה החדשה, "אותו מיקום בדיוק".
  String get executableDir => p.dirname(executablePath);

  /// התיקייה שה-stub מחלץ אליה, ובתוכה המרקר. ווינדוס בלבד — ב-macOS אין
  /// חילוץ בכלל, ו-[executablePath] הוא חבילת ה-`.app` עצמה.
  String get payloadDir => p.join(executableDir, payloadDirName);

  String get readyMarkerPath => p.join(payloadDir, readyMarkerName);

  /// שם התיקייה שה-stub מחלץ אליה. **חייב להתאים ל-`kPayloadDir` שב-`stub.c`
  /// ול-`$payloadDirName` שב-`package.ps1`** — `stub_contract_test.dart`
  /// מאמת זאת.
  static const String payloadDirName = 'app-files';

  /// משתנה הסביבה שה-stub מציב לפני שהוא מריץ את הלאנצ'ר, עם הנתיב המלא
  /// שלו עצמו. זו התשובה המדויקת; כל השאר הוא ניחוש.
  static const String stubPathEnvVar = 'OTZARIA_LAUNCHER_STUB';

  /// משתנה סביבה שני מה-stub: גרסת ה-payload שהוא **נושא**. ראו
  /// `PayloadCheck` — היא מושווית לגרסה שרצה בפועל.
  static const String payloadVersionEnvVar = 'OTZARIA_PAYLOAD_VERSION';

  /// המרקר שה-stub כותב בתוך [payloadDirName] בסוף חילוץ שהצליח. מחיקתו היא
  /// הדרך לבקש חילוץ מחדש בהרצה הבאה.
  static const String readyMarkerName = '.ready';

  /// שם ה-exe כפי ש-`package.ps1` מייצר אותו — משמש **רק** כשוברים תיקו בין
  /// כמה exe באותה תיקייה.
  static const String packagedExeName = 'עדכוני אוצריא.exe';

  /// אותו קובץ, בשם שבו הוא יושב על ה-release. גיטהאב מנקה תווים שאינם ASCII
  /// משמות נכסים, ושם שכולו עברית נמחק אצלו עד `default.exe` (כך אכן פורסמה
  /// v0.1.1) — ולכן ג'וב הפרסום נותן לו שם לטיני, וזה השם שנדבק למי שהוריד
  /// ידנית. שני השמות שוברי תיקו, ולא יותר מזה.
  static const String publishedExeName = 'Otzaria-Updates.exe';

  static const Set<String> _ourExeNames = {packagedExeName, publishedExeName};

  static const String stubInternalName = 'launcher_stub';

  /// הדגל שבו מריצים את ה-stub החדש אחרי החלפה: הוא ממתין שהתהליך הזה
  /// ייסגר לפני שהוא מחלץ מחדש ל-`app-files`.
  static const String afterUpdateFlag = '--after-update';

  static LauncherInstallLayout? _processLayout;
  static bool _processLayoutResolved = false;

  static LauncherInstallLayout? resolve({
    String? resolvedExecutable,
    Map<String, String>? environment,
    bool? isWindows,
    bool? isMacOS,
  }) {
    final injected = resolvedExecutable != null ||
        environment != null ||
        isWindows != null ||
        isMacOS != null;
    if (!injected && _processLayoutResolved) return _processLayout;

    final exe = resolvedExecutable ?? Platform.resolvedExecutable;
    final env = environment ?? Platform.environment;
    final windows = isWindows ?? Platform.isWindows;
    final macOS = isMacOS ?? Platform.isMacOS;

    final layout = windows
        ? _resolveWindows(exe, env)
        : macOS
            ? _resolveMacOS(exe)
            : null;
    if (!injected) {
      _processLayout = layout;
      _processLayoutResolved = true;
    }
    return layout;
  }

  static LauncherInstallLayout? _resolveWindows(
    String resolvedExecutable,
    Map<String, String> environment,
  ) {
    final fromStub = environment[stubPathEnvVar];
    if (fromStub != null &&
        fromStub.isNotEmpty &&
        File(fromStub).existsSync()) {
      return LauncherInstallLayout(executablePath: fromStub);
    }

    final appFilesDir = p.dirname(resolvedExecutable);
    if (p.basename(appFilesDir).toLowerCase() != payloadDirName) return null;

    final parent = p.dirname(appFilesDir);
    final exes = <String>[];
    try {
      for (final entry in Directory(parent).listSync(followLinks: false)) {
        if (entry is File && p.extension(entry.path).toLowerCase() == '.exe') {
          exes.add(entry.path);
        }
      }
    } on FileSystemException {
      return null;
    }

    for (final exe in exes) {
      if (_ourExeNames.contains(p.basename(exe))) {
        return LauncherInstallLayout(executablePath: exe);
      }
    }
    if (exes.length == 1 && _carriesStubVersionInfo(exes.single)) {
      return LauncherInstallLayout(executablePath: exes.single);
    }
    return null;
  }

  static const int _maxVersionInfoBytes = 64 * 1024;
  static const int _maxSections = 96;
  static const int _maxResourceEntries = 1024;
  static const int _rtVersion = 16;
  static const int _subdirectoryBit = 0x80000000;

  static bool _carriesStubVersionInfo(String path) {
    final marker = <int>[
      for (final unit in stubInternalName.codeUnits) ...[unit, 0],
    ];
    RandomAccessFile? file;
    try {
      file = File(path).openSync();
      final versionInfo = _readVersionResource(file);
      return versionInfo != null &&
          _indexOf(versionInfo, versionInfo.length, marker) >= 0;
    } on FileSystemException {
      return false;
    } finally {
      try {
        file?.closeSync();
      } catch (_) {}
    }
  }

  static Uint8List? _readVersionResource(RandomAccessFile file) {
    final length = file.lengthSync();
    ByteData? read(int offset, int count) {
      if (offset < 0 || count <= 0 || offset + count > length) return null;
      file.setPositionSync(offset);
      final bytes = file.readSync(count);
      if (bytes.length != count) return null;
      return ByteData.sublistView(bytes);
    }

    const le = Endian.little;
    final dos = read(0, 64);
    if (dos == null || dos.getUint16(0, le) != 0x5A4D) return null;
    final peOffset = dos.getUint32(0x3C, le);
    final coff = read(peOffset, 24);
    if (coff == null || coff.getUint32(0, le) != 0x00004550) return null;
    final sectionCount = coff.getUint16(6, le);
    final optionalSize = coff.getUint16(20, le);
    if (sectionCount == 0 || sectionCount > _maxSections) return null;

    final optional = read(peOffset + 24, optionalSize);
    if (optional == null || optionalSize < 2) return null;
    final directoriesAt = switch (optional.getUint16(0, le)) {
      0x10b => 96,
      0x20b => 112,
      _ => -1,
    };
    if (directoriesAt < 0 || optionalSize < directoriesAt + 24) return null;
    if (optional.getUint32(directoriesAt - 4, le) < 3) return null;
    final resourceRva = optional.getUint32(directoriesAt + 16, le);
    if (resourceRva == 0) return null;

    final sections = read(peOffset + 24 + optionalSize, sectionCount * 40);
    if (sections == null) return null;
    int? toFileOffset(int rva) {
      for (var i = 0; i < sectionCount; i++) {
        final base = i * 40;
        final virtualSize = sections.getUint32(base + 8, le);
        final virtualAddress = sections.getUint32(base + 12, le);
        final rawSize = sections.getUint32(base + 16, le);
        final rawPointer = sections.getUint32(base + 20, le);
        final span = max(virtualSize, rawSize);
        if (rva < virtualAddress || rva >= virtualAddress + span) continue;
        final delta = rva - virtualAddress;
        return delta < rawSize ? rawPointer + delta : null;
      }
      return null;
    }

    final resourceBase = toFileOffset(resourceRva);
    if (resourceBase == null) return null;
    int? entry(int directoryOffset, {int? id}) {
      final header = read(resourceBase + directoryOffset, 16);
      if (header == null) return null;
      final total = header.getUint16(12, le) + header.getUint16(14, le);
      if (total == 0 || total > _maxResourceEntries) return null;
      final entries = read(resourceBase + directoryOffset + 16, total * 8);
      if (entries == null) return null;
      for (var i = 0; i < total; i++) {
        if (id == null || entries.getUint32(i * 8, le) == id) {
          return entries.getUint32(i * 8 + 4, le);
        }
      }
      return null;
    }

    final typeDirectory = entry(0, id: _rtVersion);
    if (typeDirectory == null || typeDirectory & _subdirectoryBit == 0) {
      return null;
    }
    final nameDirectory = entry(typeDirectory & ~_subdirectoryBit);
    if (nameDirectory == null || nameDirectory & _subdirectoryBit == 0) {
      return null;
    }
    final dataEntry = entry(nameDirectory & ~_subdirectoryBit);
    if (dataEntry == null || dataEntry & _subdirectoryBit != 0) return null;
    final leaf = read(resourceBase + dataEntry, 16);
    if (leaf == null) return null;
    final dataOffset = toFileOffset(leaf.getUint32(0, le));
    final size = leaf.getUint32(4, le);
    if (dataOffset == null || size > _maxVersionInfoBytes) return null;
    final data = read(dataOffset, size);
    return data?.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  static int _indexOf(Uint8List haystack, int length, List<int> needle) {
    final first = needle.first;
    final last = length - needle.length;
    outer:
    for (var i = 0; i <= last; i++) {
      if (haystack[i] != first) continue;
      for (var j = 1; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  /// חבילת ה-`.app` שבתוכה רץ ה-exe. `OtzariaData/` יושבת **לצד** החבילה
  /// (ראו `AppPaths`), ולכן החלפת החבילה כולה אינה נוגעת בה.
  static LauncherInstallLayout? _resolveMacOS(String resolvedExecutable) {
    for (var dir = p.dirname(resolvedExecutable);; dir = p.dirname(dir)) {
      if (p.extension(dir) == '.app') {
        return LauncherInstallLayout(executablePath: dir);
      }
      if (p.dirname(dir) == dir) return null; // הגענו לשורש — לא חבילה
    }
  }
}

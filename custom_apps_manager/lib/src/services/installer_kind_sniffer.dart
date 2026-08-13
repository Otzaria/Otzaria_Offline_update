import 'dart:io';
import 'dart:typed_data';

import '../models/custom_installer_kind.dart';

/// מזהה את סוג חבילת ההתקנה מתוך הקובץ עצמו.
///
/// **זו הצעה, לא הכרעה.** הבונה בממשק מציב את התוצאה כברירת מחדל והמשתמש
/// יכול לשנות אותה. זה מה שמאפשר לסניפר להיות לא-מושלם בשקט: `null`
/// פירושו "לא ידעתי, תבחר בעצמך", ולא כשל.
///
/// הסיבה שהוא קיים בכלל: "איזה framework בנה את ה-installer הזה" היא
/// השאלה היחידה בכל התוסף שמשתמש רגיל אינו יכול לענות עליה.
class InstallerKindSniffer {
  const InstallerKindSniffer();

  /// חתימת קובץ OLE Compound — כל קובץ MSI מתחיל בה.
  static const List<int> _oleMagic = [
    0xD0,
    0xCF,
    0x11,
    0xE0,
    0xA1,
    0xB1,
    0x1A,
    0xE1,
  ];

  /// חתימת ZIP.
  static const List<int> _zipMagic = [0x50, 0x4B, 0x03, 0x04];

  /// המחרוזות שמזהות את שני ה-framework-ים הנפוצים בתוך גוף ה-exe.
  static const String _innoMarker = 'Inno Setup';
  static const String _nsisMarker = 'Nullsoft';

  /// עד כמה לקרוא בחיפוש אחר החתימה. מעבר לזה מוותרים ומחזירים `null` —
  /// עדיף מלקרוא installer של 200MB רק כדי למלא שדה בטופס.
  static const int maxScanBytes = 32 << 20;

  static const int _chunkSize = 1 << 20;

  /// מחזיר את הסוג המשוער, או `null` כשלא ניתן לקבוע.
  Future<CustomInstallerKind?> sniff(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return null;

    final head = await _readHead(file, _oleMagic.length);
    if (head == null) return null;

    // MSI ו-ZIP מוכרעים בחתימה שבתחילת הקובץ — אין צורך לסרוק כלום.
    if (_startsWith(head, _oleMagic)) return CustomInstallerKind.msi;
    if (_startsWith(head, _zipMagic)) return CustomInstallerKind.zipPortable;

    return _scanForMarkers(file);
  }

  Future<Uint8List?> _readHead(File file, int length) async {
    RandomAccessFile? handle;
    try {
      handle = await file.open();
      return await handle.read(length);
    } catch (_) {
      return null;
    } finally {
      await handle?.close();
    }
  }

  /// סורק את גוף הקובץ אחרי הסימנים של Inno ו-NSIS.
  ///
  /// הסריקה היא על צ'אנקים עם **חפיפה** בגודל הסימן הארוך: בלעדיה סימן
  /// שנופל בדיוק על גבול הצ'אנק היה מוחמץ.
  Future<CustomInstallerKind?> _scanForMarkers(File file) async {
    final overlap = [_innoMarker.length, _nsisMarker.length]
        .reduce((a, b) => a > b ? a : b);

    var scanned = 0;
    var carry = '';

    try {
      await for (final chunk in file.openRead(0, maxScanBytes)) {
        // הסימנים הם ASCII, ולכן פענוח בייט-לתו מספיק ואינו יכול להיכשל
        // על בייטים שאינם טקסט.
        final text = carry + String.fromCharCodes(chunk);
        if (text.contains(_innoMarker)) return CustomInstallerKind.innoSetup;
        if (text.contains(_nsisMarker)) return CustomInstallerKind.nsis;

        carry = text.length <= overlap
            ? text
            : text.substring(text.length - overlap);

        scanned += chunk.length;
        if (scanned >= maxScanBytes) break;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static bool _startsWith(Uint8List bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }

  /// גודל הצ'אנק המומלץ לקריאה — חשוף לבדיקות בלבד.
  static int get chunkSize => _chunkSize;
}

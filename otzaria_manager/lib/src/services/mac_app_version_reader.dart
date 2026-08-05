import 'dart:io';

import 'package:path/path.dart' as p;

import 'installed_version_reader.dart';

/// קורא מידע מתוך `Contents/Info.plist` של חבילת `.app` — המקבילה ב-macOS
/// ל-version resource של Windows.
///
/// אומת מול חבילה אמיתית (`otzaria-macos.zip` של 0.9.96+736):
/// `CFBundleShortVersionString` שם הוא `0.9.96` — כלומר תג ה-release בלי
/// סיומת ה-build (`+736`). זאת הסיבה שההשוואה ב-
/// [OtzariaUpdateCheckResult.updateAvailable] מנרמלת ומתעלמת מהחלק שאחרי
/// ה-`+`. (`CFBundleVersion` שם הוא `90960` — לא שימושי להשוואה מול תג.)
/// `CFBundleIdentifier` הוא `com.example.otzaria`.
///
/// **למה דרך `plutil` ולא פענוח בקוד:** ה-Info.plist שיוצא מבנייה של
/// Flutter/macOS הוא **binary plist**, לא XML, ולכן אי אפשר לקרוא ממנו
/// שדות בעזרת קריאת טקסט/regex. `plutil` הוא כלי מערכת קבוע ב-macOS
/// (`/usr/bin/plutil`) שמטפל בשני הפורמטים.
class MacAppVersionReader implements InstalledVersionReader {
  const MacAppVersionReader();

  static const String _plutilPath = '/usr/bin/plutil';

  /// [launchPath] הוא נתיב חבילת ה-`.app`. אם הועבר בטעות נתיב לקובץ
  /// ההפעלה שבתוך ה-bundle, גם זה עובד — עולים לשורש ה-bundle.
  @override
  String? readVersion(String launchPath) =>
      _readKey(launchPath, 'CFBundleShortVersionString');

  /// מזהה ה-bundle (`CFBundleIdentifier`) — משמש כדי לוודא שחבילת `.app`
  /// שנמצאה בתיקייה משותפת כמו `/Applications` היא בכלל אוצריא.
  String? readBundleIdentifier(String launchPath) =>
      _readKey(launchPath, 'CFBundleIdentifier');

  String? _readKey(String launchPath, String key) {
    if (!Platform.isMacOS) {
      throw UnsupportedError('MacAppVersionReader עובד רק ב-macOS.');
    }

    final bundlePath = _bundleRootOf(launchPath);
    if (bundlePath == null) return null;

    final plistPath = p.join(bundlePath, 'Contents', 'Info.plist');
    if (!File(plistPath).existsSync()) return null;

    try {
      final result = Process.runSync(_plutilPath, [
        '-extract',
        key,
        'raw',
        '-o',
        '-',
        plistPath,
      ]);
      if (result.exitCode != 0) return null;

      final value = result.stdout.toString().trim();
      return value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  /// מטפס מהנתיב שהתקבל אל שורש חבילת ה-`.app` שמכילה אותו, או null אם
  /// הנתיב אינו בתוך `.app` בכלל.
  String? _bundleRootOf(String path) {
    var current = p.normalize(path);
    while (true) {
      if (p.basename(current).toLowerCase().endsWith('.app')) return current;
      final parent = p.dirname(current);
      if (parent == current) return null;
      current = parent;
    }
  }
}

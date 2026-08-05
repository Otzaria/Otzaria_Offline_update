import 'dart:io' show Platform;

import '../models/otzaria_release.dart';
import 'mac_app_version_reader.dart';
import 'windows_exe_version_reader.dart';

/// קורא את הגרסה **מתוך ההתקנה עצמה** (ולא ממה שהלאנצ'ר "זוכר" בקובץ
/// המצב שלו) — כך שאפשר לזהות התקנה קיימת שלא בוצעה דרך הלאנצ'ר, ולדעת
/// איזו גרסה יש בה.
abstract interface class InstalledVersionReader {
  /// [launchPath] הוא הנתיב שמחזיר [OtzariaAppLocator]: קובץ `.exe`
  /// בווינדוס, חבילת `.app` ב-macOS.
  ///
  /// מחזיר null אם הנתיב לא קיים, אין בו מידע גרסה, או שהקריאה נכשלה מכל
  /// סיבה אחרת — כלומר "לא הצלחנו לקבוע שזו התקנה של אוצריא".
  String? readVersion(String launchPath);
}

/// המימוש המתאים ל-[platform].
InstalledVersionReader installedVersionReaderFor(
    OtzariaTargetPlatform platform) {
  return switch (platform) {
    OtzariaTargetPlatform.windows => const WindowsExeVersionReader(),
    OtzariaTargetPlatform.macos => const MacAppVersionReader(),
  };
}

/// המימוש המתאים לפלטפורמה שהלאנצ'ר רץ עליה בפועל.
InstalledVersionReader currentInstalledVersionReader() =>
    installedVersionReaderFor(
      OtzariaTargetPlatform.detect(Platform.operatingSystem),
    );

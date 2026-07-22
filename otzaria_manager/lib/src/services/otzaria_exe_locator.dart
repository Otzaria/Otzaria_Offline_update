import 'dart:io';

import 'package:path/path.dart' as p;

/// סורק תיקייה ומחפש את קובץ ה-exe הראשי של אוצריא. לא מניחים שם קבוע
/// (otzaria.exe) כדי להישאר עמידים אם זה ישתנה — פוסלים רק את
/// uninstall-*.exe/unins*.exe שה-installer עצמו יוצר.
///
/// שימוש כפול: גם על ידי [OtzariaInstaller] מיד אחרי התקנה טרייה, וגם
/// על ידי זיהוי התקנה קיימת (שלא בוצעה דרך הלאנצ'ר).
class OtzariaExeLocator {
  const OtzariaExeLocator();

  Future<String?> findExeIn(String directory) async {
    final dir = Directory(directory);
    if (!await dir.exists()) return null;

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path).toLowerCase();
      if (!name.endsWith('.exe')) continue;
      if (name.startsWith('unins')) continue;
      return entity.path;
    }
    return null;
  }
}

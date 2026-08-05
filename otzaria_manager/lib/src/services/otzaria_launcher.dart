import 'dart:io';

import 'package:path/path.dart' as p;

/// מפעיל את ההתקנה שהתגלתה — קובץ `.exe` בווינדוס, חבילת `.app` ב-macOS.
/// נפרד מ-[OtzariaInstaller] כי "הפעלה" יכולה לקרות גם בלי שהתבצעה
/// התקנה/עדכון בסשן הנוכחי (למשל בכל פתיחה של הלאנצ'ר, כשההתקנה כבר
/// עדכנית).
class OtzariaLauncher {
  const OtzariaLauncher();

  /// מפעיל את אוצריא כתהליך עצמאי (לא ממתין לסיום שלו — אחרת הלאנצ'ר
  /// ייחסם כל עוד אוצריא פתוחה).
  Future<void> launch(String launchPath) async {
    final isAppBundle = p.basename(launchPath).toLowerCase().endsWith('.app');

    // חבילת .app היא **תיקייה**, לא קובץ — בדיקת File.exists עליה תחזיר
    // false תמיד. חייבים לבדוק את הסוג הנכון לפי מה שקיבלנו.
    final exists = isAppBundle
        ? await Directory(launchPath).exists()
        : await File(launchPath).exists();
    if (!exists) {
      throw StateError('קובץ ההפעלה לא נמצא בנתיב: $launchPath');
    }

    if (isAppBundle) {
      // `open` הוא הדרך הנכונה להפעיל bundle ב-macOS: הוא עובר דרך Launch
      // Services, ולכן האפליקציה מקבלת את הסביבה הרגילה שלה (Dock, תפריטים,
      // הרשאות לפי ה-bundle id). הרצה ישירה של Contents/MacOS/<exe> "עובדת"
      // אבל מייצרת תהליך חסר-זהות שמתנהג אחרת. אין כאן -n בכוונה: אם אוצריא
      // כבר פתוחה, עדיף להביא אותה לחזית מלפתוח מופע שני שיילחם על ה-DB.
      final result = await Process.run('/usr/bin/open', [launchPath]);
      if (result.exitCode != 0) {
        throw StateError(
          'הפעלת אוצריא נכשלה (open החזיר ${result.exitCode}): ${result.stderr}',
        );
      }
      return;
    }

    await Process.start(
      launchPath,
      const [],
      mode: ProcessStartMode.detached,
    );
  }
}

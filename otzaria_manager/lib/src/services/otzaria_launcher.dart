import 'dart:io';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

/// מפעיל את ההתקנה שהתגלתה — קובץ `.exe` בווינדוס, חבילת `.app` ב-macOS.
/// נפרד מ-[OtzariaInstaller] כי "הפעלה" יכולה לקרות גם בלי שהתבצעה
/// התקנה/עדכון בסשן הנוכחי (למשל בכל פתיחה של הלאנצ'ר, כשההתקנה כבר
/// עדכנית).
class OtzariaLauncher {
  const OtzariaLauncher();

  /// מפעיל את אוצריא כתהליך עצמאי (לא ממתין לסיום שלו — אחרת הלאנצ'ר
  /// ייחסם כל עוד אוצריא פתוחה).
  ///
  /// [withUri] הוא קישור עומק (`otzaria://...`) שנמסר כארגומנט — ראו
  /// `OtzariaDeepLinks`. מסירה ישירה לקובץ ההרצה ולא דרך מטפל הפרוטוקול של
  /// מערכת ההפעלה, כדי שזה יעבוד גם בהתקנה ניידת שאינה רושמת את הסכימה.
  Future<void> launch(String launchPath, {String? withUri}) async {
    final isAppBundle = p.basename(launchPath).toLowerCase().endsWith('.app');

    // חבילת .app היא **תיקייה**, לא קובץ — בדיקת File.exists עליה תחזיר
    // false תמיד. חייבים לבדוק את הסוג הנכון לפי מה שקיבלנו.
    final exists = isAppBundle
        ? await Directory(launchPath).exists()
        : await File(launchPath).exists();
    if (!exists) {
      throw StateError(
        AppL10n.strings.appDomain.launchFileMissing(launchPath),
      );
    }

    if (isAppBundle) {
      // `open` הוא הדרך הנכונה להפעיל bundle ב-macOS: הוא עובר דרך Launch
      // Services, ולכן האפליקציה מקבלת את הסביבה הרגילה שלה (Dock, תפריטים,
      // הרשאות לפי ה-bundle id). הרצה ישירה של Contents/MacOS/<exe> "עובדת"
      // אבל מייצרת תהליך חסר-זהות שמתנהג אחרת. אין כאן -n בכוונה: אם אוצריא
      // כבר פתוחה, עדיף להביא אותה לחזית מלפתוח מופע שני שיילחם על ה-DB.
      // `open -a <bundle> <uri>` הוא הדרך למסור URI לחבילה; בלי URI זו הפעלה
      // רגילה של אותו bundle.
      final result = await Process.run(
        '/usr/bin/open',
        withUri == null ? [launchPath] : ['-a', launchPath, withUri],
      );
      if (result.exitCode != 0) {
        throw StateError(
          AppL10n.strings.appDomain
              .launchFailed(result.exitCode, '${result.stderr}'),
        );
      }
      return;
    }

    await Process.start(
      launchPath,
      [if (withUri != null) withUri],
      mode: ProcessStartMode.detached,
    );
  }
}

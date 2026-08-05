import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/otzaria_release.dart';

/// סורק תיקייה ומחפש בתוכה את מה שצריך להפעיל כדי להריץ את אוצריא:
/// קובץ ה-`.exe` הראשי בווינדוס, או חבילת ה-`.app` ב-macOS.
///
/// בשתי הפלטפורמות **לא מניחים שם קבוע** (`otzaria.exe` / `אוצריא.app`) כדי
/// להישאר עמידים אם השם ישתנה — רק פוסלים דברים שבוודאות אינם האפליקציה
/// עצמה (uninstaller בווינדוס, שאריות `__MACOSX` של zip ב-macOS).
///
/// שימוש כפול: גם על ידי [OtzariaInstaller] מיד אחרי התקנה טרייה, וגם על
/// ידי זיהוי התקנה קיימת (שלא בוצעה דרך הלאנצ'ר).
class OtzariaAppLocator {
  const OtzariaAppLocator({OtzariaTargetPlatform? platform})
      : _platformOverride = platform;

  /// null = לגזור מהפלטפורמה שרצה בפועל. נדרס בבדיקות כדי לבדוק את שני
  /// המסלולים מאותה מכונה.
  final OtzariaTargetPlatform? _platformOverride;

  OtzariaTargetPlatform get _platform =>
      _platformOverride ??
      OtzariaTargetPlatform.detect(Platform.operatingSystem);

  /// עומק החיפוש שבו מסתפקים כברירת מחדל ב-macOS. חבילת ה-`.app` יושבת
  /// בשורש תיקיית ההתקנה או רמה-שתיים מתחתיה (למשל אחרי חילוץ zip עם
  /// תיקייה עוטפת), ואין סיבה לסרוק לעומק.
  static const int defaultMacMaxDepth = 3;

  /// מחזיר את הנתיב להפעלה שנמצא ב-[directory], או null אם אין שם התקנה.
  ///
  /// [accept] מסנן מועמדים: מוחזר רק מועמד שעבורו הוא מחזיר true. נחוץ
  /// כשסורקים תיקייה **משותפת** שיש בה גם אפליקציות אחרות — בראש ובראשונה
  /// `/Applications` ב-macOS, שבלי סינון היה מחזיר את האפליקציה הראשונה
  /// שנתקלנו בה (Safari, למשל) ומדווח עליה כאוצריא.
  ///
  /// [macMaxDepth] מגביל את עומק הסריקה ב-macOS. שווה להקטין ל-1 כשסורקים
  /// `/Applications`: ה-`.app` תמיד יושבת שם ישירות, ואין טעם לצלול לתוך
  /// עשרות אלפי קבצים של אפליקציות אחרות.
  Future<String?> findIn(
    String directory, {
    bool Function(String candidatePath)? accept,
    int macMaxDepth = defaultMacMaxDepth,
  }) async {
    if (!await Directory(directory).exists()) return null;

    return switch (_platform) {
      OtzariaTargetPlatform.windows => _findWindowsExe(directory, accept),
      OtzariaTargetPlatform.macos =>
        _findMacAppBundle(directory, accept, macMaxDepth),
    };
  }

  Future<String?> _findWindowsExe(
    String directory,
    bool Function(String candidatePath)? accept,
  ) async {
    await for (final entity
        in Directory(directory).list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path).toLowerCase();
      if (!name.endsWith('.exe')) continue;
      // unins*.exe הוא ה-uninstaller ש-Inno Setup עצמו יוצר בתיקיית ההתקנה.
      if (name.startsWith('unins')) continue;
      if (accept != null && !accept(entity.path)) continue;
      return entity.path;
    }
    return null;
  }

  /// סריקת רוחב (BFS) שמחזירה את חבילת ה-`.app` **הרדודה ביותר**: כך אם
  /// תיקיית ההתקנה מכילה גם `.app` עוטפת וגם helper bundles מקוננות, נבחר
  /// את הראשית. מסיבה זו גם **לא נכנסים** לתוך `.app` שנמצאה — בתוך
  /// `Contents/Frameworks` של אפליקציית Flutter יש לעיתים `.app` פנימיות.
  Future<String?> _findMacAppBundle(
    String directory,
    bool Function(String candidatePath)? accept,
    int maxDepth,
  ) async {
    var level = <Directory>[Directory(directory)];

    for (var depth = 0; depth < maxDepth && level.isNotEmpty; depth++) {
      final next = <Directory>[];

      for (final dir in level) {
        final List<FileSystemEntity> entries;
        try {
          entries = await dir.list(followLinks: false).toList();
        } on FileSystemException {
          // תיקייה בלי הרשאת קריאה (שכיח כשסורקים /Applications) — מדלגים.
          continue;
        }

        for (final entity in entries) {
          if (entity is! Directory) continue;
          final name = p.basename(entity.path);
          // תיקיות נקודה מדולגות בכוונה: כך גם תיקיות ה-staging וה-גיבוי
          // שה-installer יוצר בתוך תיקיית ההתקנה אינן נתפסות כהתקנה.
          if (name.startsWith('.') || name == '__MACOSX') continue;
          if (name.toLowerCase().endsWith('.app')) {
            if (accept == null || accept(entity.path)) return entity.path;
            // .app שנפסלה — לא נכנסים לתוכה, אבל ממשיכים לחפש בשאר הרמה.
            continue;
          }
          next.add(entity);
        }
      }

      level = next;
    }

    return null;
  }
}

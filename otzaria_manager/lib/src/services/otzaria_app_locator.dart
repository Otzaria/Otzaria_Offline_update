import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/otzaria_release.dart';

/// סורק תיקייה ומחפש בתוכה את מה שצריך להפעיל כדי להריץ את אוצריא:
/// קובץ ה-`.exe` הראשי בווינדוס, או חבילת ה-`.app` ב-macOS.
///
/// שם תואם (`otzaria` / `אוצריא`) **מנצח מיד**, אבל אינו תנאי: אם אין כזה
/// חוזר מועמד גיבוי, כדי להישאר עמידים אם השם ישתנה. לצד זה נפסלים דברים
/// שבוודאות אינם האפליקציה עצמה — uninstaller ו-exe עזר של Flutter בווינדוס,
/// שאריות `__MACOSX` של zip ב-macOS.
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

  /// עומק החיפוש בווינדוס. ה-installer של Inno שם את ה-exe בשורש תיקיית
  /// ההתקנה, והעומק הנוסף הוא בשביל חילוץ עם תיקייה עוטפת. הגבול אינו
  /// קוסמטי: `C:\אוצריא` היא גם תיקיית התקנה אפשרית וגם מיקום נפוץ של
  /// ספריית הספרים (~1GB), וסריקה עמוקה שלה חזרה בכל בדיקה.
  static const int defaultWindowsMaxDepth = 3;

  /// exe-ים שנשלחים **לצד** אפליקציית Flutter ואינם האפליקציה עצמה. בלי
  /// הרשימה הזו `crashpad_handler.exe` ניצח את `otzaria.exe` בתיקיית ההתקנה
  /// האמיתית — הוא פשוט קודם לו באלף-בית.
  static const Set<String> _windowsHelperExeNames = {
    'crashpad_handler',
    'crashpad_wer',
    'elevation_service',
    'msedgewebview2',
  };

  /// ה-exe-ים של הלאנצ'ר **עצמו** (ה-stub שב-`windows_stub/package.ps1`
  /// ותוכנית ה-Flutter שמתחתיו). שם ה-stub מכיל "אוצריא", ולכן בלי הפסילה
  /// הזו סריקה של תיקייה שהמשתמש העתיק אליה את הלאנצ'ר — `C:\אוצריא` היא
  /// מיקום סביר לכך — הייתה מאמצת את הלאנצ'ר כאוצריא, קוראת את הגרסה שלו
  /// ומריצה אותו במקומה.
  static const Set<String> _ourOwnExeNames = {
    'launcher_app',
    'עדכוני אוצריא',
  };

  /// האם שם הקובץ/החבילה מזהה את אוצריא. משותף גם ל-`OtzariaManager`, שמסנן
  /// בו מועמדים בתיקייה משותפת — אותו זיהוי בדיוק בשני המקומות.
  static bool nameLooksLikeOtzaria(String candidatePath) =>
      mentionsOtzaria(p.basenameWithoutExtension(candidatePath));

  /// האם הטקסט מזכיר את אוצריא — גם `DisplayName` מהרג'יסטרי נבדק כך.
  static bool mentionsOtzaria(String text) {
    final lower = text.toLowerCase();
    return lower.contains('otzaria') || lower.contains('אוצריא');
  }

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
    int windowsMaxDepth = defaultWindowsMaxDepth,
  }) async {
    if (!await Directory(directory).exists()) return null;

    return switch (_platform) {
      OtzariaTargetPlatform.windows =>
        _findWindowsExe(directory, accept, windowsMaxDepth),
      OtzariaTargetPlatform.macos =>
        _findMacAppBundle(directory, accept, macMaxDepth),
    };
  }

  /// סריקת רוחב, כמו במסלול ה-macOS: שם תואם מנצח מיד, וכשאין כזה נבחר
  /// מועמד הגיבוי **הרדוד ביותר**. הרוחב-לפני-עומק אינו רק חסם עלות — הוא
  /// מה שהופך את התשובה לוודאית, כי סדר ההחזרה של `Directory.list` אינו
  /// מובטח, ובלעדיו exe מקונן היה יכול לנצח את זה שבשורש.
  Future<String?> _findWindowsExe(
    String directory,
    bool Function(String candidatePath)? accept,
    int maxDepth,
  ) async {
    var level = <Directory>[Directory(directory)];
    String? fallback;

    for (var depth = 0; depth < maxDepth && level.isNotEmpty; depth++) {
      final next = <Directory>[];
      final named = <String>[];
      final others = <String>[];

      for (final dir in level) {
        final List<FileSystemEntity> entries;
        try {
          entries = await dir.list(followLinks: false).toList();
        } on FileSystemException {
          // תיקייה בלי הרשאת קריאה — מדלגים, בדיוק כמו במסלול ה-macOS.
          continue;
        }

        for (final entity in entries) {
          if (entity is Directory) {
            next.add(entity);
            continue;
          }
          if (entity is! File) continue;

          final name = p.basename(entity.path).toLowerCase();
          if (!name.endsWith('.exe')) continue;
          // unins*.exe הוא ה-uninstaller ש-Inno Setup עצמו יוצר בתיקייה.
          if (name.startsWith('unins')) continue;
          final base = p.basenameWithoutExtension(name);
          if (_ourOwnExeNames.contains(base)) continue;
          if (p.equals(entity.path, Platform.resolvedExecutable)) continue;
          if (accept != null && !accept(entity.path)) continue;

          if (nameLooksLikeOtzaria(entity.path)) {
            named.add(entity.path);
          } else if (!_windowsHelperExeNames.contains(base)) {
            others.add(entity.path);
          }
        }
      }

      // מיון בתוך הרמה: שתי תיקיות באותו עומק אינן מסודרות בין מכונות.
      if (named.isNotEmpty) return (named..sort()).first;
      if (fallback == null && others.isNotEmpty) {
        fallback = (others..sort()).first;
      }

      level = next;
    }

    return fallback;
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

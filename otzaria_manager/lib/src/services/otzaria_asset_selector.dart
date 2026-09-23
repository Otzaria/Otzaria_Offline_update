import '../models/otzaria_release.dart';

/// בוחר, מתוך רשימת האסטים של release, את קובץ ההתקנה המתאים לפלטפורמת
/// היעד. פונקציה טהורה (בלי `Platform` ובלי רשת) כדי שתהיה ניתנת לבדיקה
/// עבור Windows ו-macOS גם יחד מאותה מכונה.
///
/// **למה לפי סיומת ולא לפי שם מלא:** מספר הגרסה משובץ בשם האסט של ווינדוס
/// (`otzaria-0.9.96-windows.exe`), ואילו האסטים של macOS דווקא **בלי**
/// גרסה (`otzaria-macos.zip`). התאמה לפי סיומת מכסה את שני המקרים.
///
/// **למה הסיומות האלה מדויקות דיו:** בכל ה-releases שנבדקו (0.9.91–0.9.96)
/// קיימות במקביל גם חבילות "FULL" ענקיות (~2GB) שכוללות את הספרייה בתוכן —
/// `otzaria-<ver>-windows-full.exe` ו-`otzaria-macos-full.zip`. אלה
/// מסתיימות ב-`full.exe`/`full.zip`, לא ב-`windows.exe`/`macos.zip`, ולכן
/// **נפסלות מעצמן** בהתאמת הסיומת של [select] — וזה מכוון: ההורדה הרגילה
/// מביאה את הספרייה בנפרד (library_manager), ואין סיבה למשוך 2GB כפולים.
/// אותו דבר לגבי `-windows-silent.exe`.
///
/// חבילת ה-FULL **אינה נתמכת יותר**, ומה שנשאר ממנה כאן הוא
/// [isFullPackage] בלבד — לזהות קובץ כזה שנשאר על כונן ישן ולמחוק אותו.
class OtzariaAssetSelector {
  const OtzariaAssetSelector();

  /// סיומות מועדפות, בסדר עדיפות יורד, לכל פלטפורמה — ומה סוג ההתקנה של
  /// כל אחת.
  static const Map<OtzariaTargetPlatform, List<(String, OtzariaInstallerKind)>>
      _candidatesByPlatform = {
    OtzariaTargetPlatform.windows: [
      ('windows.exe', OtzariaInstallerKind.windowsSetupExe),
    ],
    OtzariaTargetPlatform.macos: [
      // zip לפני dmg: חילוץ zip הוא פעולה אחת (`ditto`) בלי להרכיב ולנתק
      // דמות דיסק, ולכן פחות דברים שיכולים להיתקע באמצע.
      ('macos.zip', OtzariaInstallerKind.macAppZip),
      ('macos.dmg', OtzariaInstallerKind.macAppDmg),
    ],
  };

  /// סיומות חבילות ה-FULL, שנשארו רק כדי למחוק קובץ שירד בגרסה ישנה.
  /// `-full` ולא רק `full`, כדי שאסט אנדרואיד (`otzaria-android-full.zip`)
  /// לא ייתפס בטעות.
  static const List<String> fullPackageSuffixes = [
    'windows-full.exe',
    'macos-full.zip',
    'macos-full.dmg',
  ];

  /// אסטים שמסתיימים בסיומת של מתקין אבל אינם מתקין אוצריא.
  /// מסייע ההורדה (`Otzaria-Download-Assistant-windows.exe`) דורש אינטרנט,
  /// ובמיון רגיש-רישיות הוא קודם למתקין.
  static const List<String> _nonInstallerMarkers = ['download-assistant'];

  static bool _isNonInstaller(String lowerName) =>
      _nonInstallerMarkers.any(lowerName.contains);

  /// האם [assetName] הוא חבילת FULL — כלומר קובץ שיש למחוק מהמראה.
  static bool isFullPackage(String assetName) {
    final lower = assetName.toLowerCase();
    return fullPackageSuffixes.any(lower.endsWith);
  }

  /// הסיומות שמחפשים עבור [platform] — לשימוש בהודעות שגיאה.
  static List<String> expectedSuffixesFor(OtzariaTargetPlatform platform) =>
      _candidatesByPlatform[platform]!.map((c) => c.$1).toList(growable: false);

  /// מחזיר את האסט הנבחר וסוג ההתקנה שלו, או null אם אין אסט מתאים.
  ///
  /// [assets] הוא זוגות (שם אסט, האסט עצמו) — הטיפוס נשאר גנרי כדי שהבורר
  /// לא יהיה תלוי בצורת ה-JSON של GitHub.
  (T, OtzariaInstallerKind)? select<T>({
    required OtzariaTargetPlatform platform,
    required List<T> assets,
    required String Function(T asset) nameOf,
  }) =>
      _selectFrom(_candidatesByPlatform[platform]!, assets, nameOf);

  static (T, OtzariaInstallerKind)? _selectFrom<T>(
    List<(String, OtzariaInstallerKind)> candidates,
    List<T> assets,
    String Function(T asset) nameOf,
  ) {
    for (final (suffix, kind) in candidates) {
      for (final asset in assets) {
        final lower = nameOf(asset).toLowerCase();
        if (lower.endsWith(suffix) && !_isNonInstaller(lower)) {
          return (asset, kind);
        }
      }
    }
    return null;
  }
}

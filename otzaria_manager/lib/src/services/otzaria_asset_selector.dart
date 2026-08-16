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
/// מי שכן רוצה את חבילת ה-FULL מבקש אותה במפורש בהגדרות, ואז [selectFull]
/// מוצא אותה — בורר נפרד, כדי ששני המסלולים לא יוכלו להתבלבל ביניהם.
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

  /// הסיומות של חבילות ה-FULL — אותו מתקין **עם הספרייה בתוכו**.
  ///
  /// הן אינן חופפות לסיומות הרגילות: `otzaria-0.9.96-windows-full.exe`
  /// מסתיים ב-`full.exe` ולא ב-`windows.exe`, ולכן כל בורר מוצא בדיוק את
  /// שלו. `-full` ולא רק `full` כדי שלא ייתפס אסט אנדרואיד
  /// (`otzaria-android-full.zip`) בבורר של macOS.
  static const Map<OtzariaTargetPlatform, List<(String, OtzariaInstallerKind)>>
      _fullCandidatesByPlatform = {
    OtzariaTargetPlatform.windows: [
      ('windows-full.exe', OtzariaInstallerKind.windowsSetupExe),
    ],
    OtzariaTargetPlatform.macos: [
      ('macos-full.zip', OtzariaInstallerKind.macAppZip),
      ('macos-full.dmg', OtzariaInstallerKind.macAppDmg),
    ],
  };

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

  /// חבילת ה-FULL של אותו release, או null כשה-release לא פרסם כזו. `null`
  /// כאן הוא מצב תקין ולא שגיאה — בשונה מ-[select], שהיעדרו פוסל את
  /// ה-release כולו.
  (T, OtzariaInstallerKind)? selectFull<T>({
    required OtzariaTargetPlatform platform,
    required List<T> assets,
    required String Function(T asset) nameOf,
  }) =>
      _selectFrom(_fullCandidatesByPlatform[platform]!, assets, nameOf);

  static (T, OtzariaInstallerKind)? _selectFrom<T>(
    List<(String, OtzariaInstallerKind)> candidates,
    List<T> assets,
    String Function(T asset) nameOf,
  ) {
    for (final (suffix, kind) in candidates) {
      for (final asset in assets) {
        if (nameOf(asset).toLowerCase().endsWith(suffix)) {
          return (asset, kind);
        }
      }
    }
    return null;
  }
}

/// הופך **`DisplayName` שנקרא מרג'יסטרי ההסרה** לתבנית שתמשיך להתאים גם
/// אחרי שהתוכנה תתעדכן.
///
/// שמירת ה-`DisplayName` כמות שהוא היא שני באגים בו-זמנית. ראשית, הוא נצרך
/// כביטוי רגולרי, ו-`MyApp 1.4.2 (x64)` מכיל תווי רגקס — הסוגריים והנקודות
/// היו זורקים או תופסים משהו אחר. שנית, הוא מכיל את **מספר הגרסה**, ולכן
/// היה מפסיק להתאים בדיוק ברגע שהתוכנה מתעדכנת. אותה מלכודת בדיוק שבגללה
/// קיים [GithubAssetPattern] עבור שמות קבצים.
abstract final class RegistryDisplayNamePattern {
  /// מספר גרסה בתוך `DisplayName`: **רווח**, אחר כך `v` אופציונלי, ואז
  /// ספרה. הדרישה לרווח לפניו היא מה שמציל את `x64` ואת `7-Zip` — שם
  /// הספרות דבוקות לאות או פותחות את השם, ואינן גרסה.
  static final RegExp _versionTail =
      RegExp(r'\s+v?\d.*$', caseSensitive: false);

  /// קידומת קצרה מדי היא תבנית שתתפוס חצי מהמחשב. מתחת לזה עדיף לשמור את
  /// ה-`DisplayName` השלם, גם במחיר שהוא יתיישן עם הגרסה הבאה.
  static const int _minPrefixLength = 2;

  /// תבנית שמתאימה לאותה תוכנה בכל גרסה.
  ///
  /// התבנית מעוגנת **בהתחלה בלבד**, כי מה שנחתך הוא הזנב: מספר הגרסה וכל
  /// מה שאחריו (`(x64)`, `(64-bit)`). המשמעות היא "מתחיל ב-", ולכן נוסף
  /// גם lookahead שמונע מ-`Git` להתאים ל-`GitHub Desktop`.
  static String fromDisplayName(String displayName) {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return '';

    final prefix = trimmed.replaceFirst(_versionTail, '').trim();
    final base = prefix.length >= _minPrefixLength ? prefix : trimmed;
    // ה-lookahead הוא ASCII בכוונה: `\p{L}` דורש את דגל ה-unicode, ובלעדיו
    // Dart היה מפרש אותו כתווים מילוליים — תבנית ששותקת ולא מתאימה לכלום.
    return '^${RegExp.escape(base)}(?![A-Za-z\\d])';
  }

  /// האם [displayName] תואם ל-[pattern]. תבנית פגומה אינה מפילה את הבדיקה,
  /// בדיוק כמו ב-[GithubAssetPattern.matches] — היא פשוט לא מתאימה לכלום.
  static bool matches(String pattern, String displayName) {
    final compiled = compile(pattern);
    return compiled != null && compiled.hasMatch(displayName);
  }

  /// מהדר את התבנית, או `null` כשהיא פגומה.
  ///
  /// ⚠️ `RegExp(...)` על תבנית שהגיעה מקובץ `descriptor.json` **חייב** לעבור
  /// כאן: `FormatException` שנזרק בתוך הזיהוי נבלע במעלה הזרם, והתוצאה היא
  /// תוכנה שמדווחת "אינה מותקנת" לנצח בלי שום סימן שמשהו נשבר.
  static RegExp? compile(String? pattern) {
    if (pattern == null || pattern.isEmpty) return null;
    try {
      return RegExp(pattern, caseSensitive: false);
    } catch (_) {
      return null;
    }
  }
}

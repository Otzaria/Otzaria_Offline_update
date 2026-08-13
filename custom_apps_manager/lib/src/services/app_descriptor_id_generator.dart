import '../models/app_descriptor_id.dart';

/// מייצר מזהה תקין מתוך טקסט חופשי.
///
/// המשתמש אינו אמור לחשוב על המזהה בכלל: הוא ממלא שם בעברית ובוחר קובץ,
/// והמזהה נגזר מכאן. הוא רק **שם תיקייה ומפתח**, ולא משהו שמוצג.
abstract final class AppDescriptorIdGenerator {
  /// כשלא נשאר כלום אחרי הניקוי — למשל שם שכולו עברית.
  static const String fallback = 'app';

  /// מזהה פנוי שנגזר מ-[source] ואינו נמצא ב-[taken].
  ///
  /// עדיף להזין לכאן את **שם קובץ ההרצה** ולא את שם התוכנה: הוא לטיני
  /// כמעט תמיד, והוא גם מתאר את התוכנה בפועל.
  static String from(String source, {Set<String> taken = const {}}) {
    final base = _slug(source);
    if (!taken.contains(base)) return base;

    // ריבוי גרסאות של אותה תוכנה אינו מקרה קצה — הוא מה שקורה כשמישהו
    // מוסיף בטעות את אותה תוכנה פעמיים.
    for (var i = 2; i < 1000; i++) {
      final candidate = '$base-$i';
      if (!taken.contains(candidate)) return candidate;
    }
    return base;
  }

  static String _slug(String source) {
    final buffer = StringBuffer();
    var lastWasSeparator = true;

    for (final rune in source.toLowerCase().runes) {
      final char = String.fromCharCode(rune);
      if (RegExp(r'[a-z0-9]').hasMatch(char)) {
        buffer.write(char);
        lastWasSeparator = false;
        continue;
      }
      // כל מה שאינו לטיני-או-ספרה הופך למקף אחד, בלי כפילויות. נקודה
      // אינה נשמרת בכוונה: היא מותרת במזהה אך `..` אסור, ומקף פשוט יותר.
      if (!lastWasSeparator && buffer.isNotEmpty) {
        buffer.write('-');
        lastWasSeparator = true;
      }
    }

    var slug = buffer.toString();
    while (slug.endsWith('-')) {
      slug = slug.substring(0, slug.length - 1);
    }
    if (slug.length > AppDescriptorId.maxLength) {
      slug = slug.substring(0, AppDescriptorId.maxLength);
      while (slug.endsWith('-')) {
        slug = slug.substring(0, slug.length - 1);
      }
    }

    // הבדיקה האחרונה היא מול המאמת עצמו ולא מול ההיגיון כאן — כך שם
    // התקן שמור כמו `con` אינו יכול לחמוק החוצה.
    return AppDescriptorId.isValid(slug) ? slug : fallback;
  }
}

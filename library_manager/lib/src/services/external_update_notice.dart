import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// סימון ש-`seforim.db` עודכן **מבחוץ**, ע"י הלאנצ'ר הזה, עם מזהי הספרים
/// שתוכנם השתנה.
///
/// **למה זה קיים:** כשאוצריא מעדכנת את הספרייה בעצמה היא מאנדקסת מחדש את
/// הספרים שהשתנו. עדכון שנעשה מבחוץ עוקף את המסלול הזה: `isBookIndexed`
/// בודק נוכחות מפתח ולא תוכן, ולכן ספר שתוכנו השתנה נשאר מאונדקס בגרסתו
/// הישנה, והחיפוש בו מחזיר תוכן ישן.
///
/// **מה אוצריא עושה עם זה:** את הקובץ עצמו היא לא קוראת. הפתרון שהיא מימשה
/// הוא קישור העומק `otzaria://library/reindex` (`OtzariaDeepLinks`), שמרענן
/// את הקטלוג ומריץ `StartIndexing` + `ReconcileIndex` — ההשוואה שם היא של
/// טביעות-אצבע, ולכן היא מזהה לבד אילו ספרים השתנו ואינה צריכה
/// [booksTouched]. לכן הקובץ נשאר אצלנו בתפקיד אחד: **הסימון המתמשך שבקשת
/// אינדוקס ממתינה**. הוא נכתב אחרי apply מוצלח, שורד הפעלות מחדש של
/// הלאנצ'ר, ונמחק ([clear]) רק אחרי שהבקשה נמסרה לאוצריא בפועל.
class ExternalUpdateNotice {
  const ExternalUpdateNotice();

  static const String fileName = '.otzaria-external-update.json';
  static const int formatVersion = 1;

  /// המסלול שבו בוצע העדכון. ב-[routeFull] אין רשימת ספרים.
  static const String routeDelta = 'delta';
  static const String routeFull = 'full';

  /// כותב את הסימון לצד [dbPath]. best-effort: כשל כתיבה לא מבטל עדכון
  /// שכבר הצליח.
  ///
  /// **מצטבר.** סימון קודם שהבקשה עליו עוד לא נמסרה (שני עדכונים לפני
  /// שאוצריא נפתחה) נבלע לתוך החדש במקום להידרס.
  Future<void> write({
    required String dbPath,
    required String route,
    Set<int> booksTouched = const {},
    int? dbVersion,
    String? releaseTag,
    DateTime? updatedAt,
  }) async {
    try {
      final file = _fileFor(dbPath);
      final pending = await read(dbPath: dbPath);
      // מסלול מלא גורף ממילא, ולכן מנצח בכל מיזוג.
      final mergedRoute = (route == routeFull || pending?.route == routeFull)
          ? routeFull
          : route;
      await file.writeAsString(jsonEncode({
        'formatVersion': formatVersion,
        'source': 'otzaria-launcher',
        'updatedAt': (updatedAt ?? DateTime.now()).toIso8601String(),
        'route': mergedRoute,
        if (dbVersion != null) 'dbVersion': dbVersion,
        if (releaseTag != null) 'releaseTag': releaseTag,
        'booksTouched':
            <int>{...?pending?.booksTouched, ...booksTouched}.toList()..sort(),
      }));
    } catch (_) {}
  }

  /// הסימון שממתין לצד [dbPath], או `null` כשאין כזה. קובץ פגום או בפורמט
  /// שאינו מוכר נחשב "אין" — ובלי למחוק אותו.
  Future<ExternalUpdateNoticeData?> read({required String dbPath}) async {
    try {
      final file = _fileFor(dbPath);
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['formatVersion'] != formatVersion) return null;
      return ExternalUpdateNoticeData(
        route: decoded['route'] as String? ?? routeFull,
        dbVersion: decoded['dbVersion'] as int?,
        releaseTag: decoded['releaseTag'] as String?,
        updatedAt: DateTime.tryParse(decoded['updatedAt'] as String? ?? ''),
        booksTouched:
            (decoded['booksTouched'] as List?)?.whereType<int>().toSet() ??
                const <int>{},
      );
    } catch (_) {
      return null;
    }
  }

  /// מוחק את הסימון. נקרא **רק** אחרי שהבקשה נמסרה לאוצריא בפועל: מחיקה
  /// מוקדמת הייתה משאירה את האינדקס על התוכן הישן בלי שאיש יידע.
  Future<void> clear({required String dbPath}) async {
    try {
      final file = _fileFor(dbPath);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  File _fileFor(String dbPath) => File(p.join(p.dirname(dbPath), fileName));
}

/// תוכן הסימון שנקרא מהדיסק.
class ExternalUpdateNoticeData {
  const ExternalUpdateNoticeData({
    required this.route,
    this.dbVersion,
    this.releaseTag,
    this.updatedAt,
    this.booksTouched = const {},
  });

  final String route;
  final int? dbVersion;
  final String? releaseTag;
  final DateTime? updatedAt;

  /// מזהי הספרים שתוכנם השתנה (מסלול דלתא בלבד). אוצריא אינה צריכה אותם —
  /// ראו [ExternalUpdateNotice].
  final Set<int> booksTouched;

  bool get isFullRoute => route == ExternalUpdateNotice.routeFull;
}

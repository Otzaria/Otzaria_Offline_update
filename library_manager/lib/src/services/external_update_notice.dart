import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// סימון ש-`seforim.db` עודכן **מבחוץ**, ע"י הלאנצ'ר הזה, עם מזהי הספרים
/// שתוכנם השתנה.
///
/// **למה זה קיים:** כשאוצריא מעדכנת את הספרייה בעצמה היא מקבלת מ-
/// `PatchApplier` את `booksTouched` ומאנדקסת מחדש בדיוק את הספרים האלה
/// (`RefreshLibrary(changedBookKeys:)` + `StartIndexing`), ובמסלול ההורדה
/// המלאה היא מריצה `ReconcileIndex`. עדכון שנעשה מבחוץ עוקף את שני
/// המסלולים: בעלייה הבאה `StartIndexing` מוסיף רק ספרים **חדשים** ומדלג על
/// קיימים, ולכן ספר שתוכנו השתנה נשאר מאונדקס בגרסתו הישנה.
///
/// הקובץ הזה הוא הצד שלנו בפתרון: הלאנצ'ר כותב מה השתנה, ואוצריא תוכל
/// לקרוא ולאפס את האינדקס לאותם ספרים (ואז למחוק את הקובץ). **אוצריא עדיין
/// לא קוראת אותו** — ראו `library_manager/README.md`, "אינדקס החיפוש".
class ExternalUpdateNotice {
  const ExternalUpdateNotice();

  static const String fileName = '.otzaria-external-update.json';
  static const int formatVersion = 1;

  /// המסלול שבו בוצע העדכון. ב-[full] אין רשימת ספרים — שם המקבילה
  /// באוצריא היא `ReconcileIndex` (השוואת טביעות-אצבע).
  static const String routeDelta = 'delta';
  static const String routeFull = 'full';

  /// כותב את הסימון לצד [dbPath]. best-effort: כשל כתיבה לא מבטל עדכון
  /// שכבר הצליח.
  ///
  /// **מצטבר.** סימון קודם שאוצריא עוד לא קראה (שני עדכונים לפני שנפתחה)
  /// נבלע לתוך החדש במקום להידרס — אחרת הספרים מהעדכון הראשון היו נשארים
  /// מאונדקסים בגרסתם הישנה.
  Future<void> write({
    required String dbPath,
    required String route,
    Set<int> booksTouched = const {},
    int? dbVersion,
    String? releaseTag,
    DateTime? updatedAt,
  }) async {
    try {
      final file = File(p.join(p.dirname(dbPath), fileName));
      final pending = await _pending(file);
      // מסלול מלא גורף ממילא (`ReconcileIndex`) ולכן מנצח בכל מיזוג.
      final mergedRoute = (route == routeFull || pending.route == routeFull)
          ? routeFull
          : route;
      await file.writeAsString(jsonEncode({
        'formatVersion': formatVersion,
        'source': 'otzaria-launcher',
        'updatedAt': (updatedAt ?? DateTime.now()).toIso8601String(),
        'route': mergedRoute,
        if (dbVersion != null) 'dbVersion': dbVersion,
        if (releaseTag != null) 'releaseTag': releaseTag,
        'booksTouched': <int>{...pending.books, ...booksTouched}.toList()
          ..sort(),
      }));
    } catch (_) {}
  }

  /// מה שכבר רשום בקובץ (אם יש). קובץ פגום או בפורמט אחר נחשב "אין".
  Future<({String? route, Set<int> books})> _pending(File file) async {
    const empty = (route: null, books: <int>{});
    try {
      if (!await file.exists()) return empty;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return empty;
      if (decoded['formatVersion'] != formatVersion) return empty;
      return (
        route: decoded['route'] as String?,
        books: (decoded['booksTouched'] as List?)?.whereType<int>().toSet() ??
            <int>{},
      );
    } catch (_) {
      return empty;
    }
  }
}

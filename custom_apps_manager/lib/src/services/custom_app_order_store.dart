import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'custom_app_store.dart';

/// סדר התצוגה של התוכנות הנוספות, בקובץ אחד: `apps/order.json`.
///
/// יושב ליד תיקיות התוכנות ולא בתוכן, מאותה סיבה כמו הקטגוריות: הסדר
/// שייך לרשימה כולה ולא לתוכנה בודדת. **רשימת מזהים בלבד** — מיקום שנרשם
/// בתוך `descriptor.json` היה מתנגש ברגע שמישהו מעתיק אליו תיקיית תוכנה
/// מחבר, ותיקייה כזו היא בדיוק דרך ההפצה של הכונן.
///
/// **נוסע על הכונן** — הסדר נקבע פעם אחת במחשב המקוון ומגיע כפי שהוא.
class CustomAppOrderStore {
  CustomAppOrderStore({required this.mirrorRootDir});

  final String mirrorRootDir;

  static const int currentSchemaVersion = 1;
  static const String fileName = 'order.json';

  String get filePath => p.join(mirrorRootDir, 'apps', fileName);

  /// קובץ חסר או פגום נקרא כרשימה ריקה, כלומר "מיון לפי שם" — הסדר הוא
  /// העדפה, ותקלה בו אסור לה למנוע את הצגת התוכנות עצמן.
  Future<List<String>> load() async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return const [];
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return const [];
      final schema = json['schemaVersion'];
      // קובץ שנכתב בפורמט חדש יותר — עדיף ריק על ניחוש שדות שלא היו כאן.
      if (schema is int && schema > currentSchemaVersion) return const [];
      final raw = json['order'];
      if (raw is! List) return const [];
      return [
        for (final id in raw)
          if (id is String && id.trim().isNotEmpty) id.trim(),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// כתיבה אטומית: קובץ זמני ואז החלפה — בדיוק כמו `CustomAppCategoriesStore`.
  /// כונן שנשלף באמצע הכתיבה היה מותיר כאן JSON חתוך, כלומר סדר אבוד.
  Future<void> save(List<String> ids) async {
    final file = File(filePath);
    await file.parent.create(recursive: true);
    final temp = File('$filePath.tmp');
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': currentSchemaVersion,
        'order': ids,
      }),
    );
    await temp.rename(filePath);
  }

  /// ממיין את [entries] לפי [order]. מה שאינו ברשימה נופל **לסוף**, ממוין
  /// לפי שם — כך תיקיית תוכנה שהועתקה מכונן אחר מצטרפת בלי לדרוס דבר.
  /// מזהה ברשימה שאין לו תוכנה מדולג, וזו תוכנה שהוסרה מהמרשם.
  ///
  /// המיון של `List.sort` אינו יציב, ולכן ההשוואה לפי שם כתובה במפורש.
  static List<CustomAppEntry> sort(
    List<CustomAppEntry> entries,
    List<String> order,
  ) {
    if (order.isEmpty) return entries;
    final rank = {for (var i = 0; i < order.length; i++) order[i]: i};
    final sorted = [...entries];
    sorted.sort((a, b) {
      final ra = rank[a.descriptor.id];
      final rb = rank[b.descriptor.id];
      if (ra != null && rb != null) return ra.compareTo(rb);
      if (ra != null) return -1;
      if (rb != null) return 1;
      return a.descriptor.name.compareTo(b.descriptor.name);
    });
    return sorted;
  }
}

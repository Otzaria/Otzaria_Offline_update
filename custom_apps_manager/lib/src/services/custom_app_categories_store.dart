import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/custom_app_category.dart';

/// רשימת הקטגוריות של התוכנות הנוספות, בקובץ אחד: `apps/categories.json`.
///
/// יושבת ליד תיקיות התוכנות ולא בתוכן, כי היא שייכת לכולן.
/// `CustomAppStore.loadAll` מדלג על מה שאינו תיקייה, ולכן הקובץ אינו מפריע.
///
/// **נוסעת על הכונן** — הקטגוריות נקבעות פעם אחת במחשב המקוון, ומגיעות
/// למחשב המנותק כפי שהן.
class CustomAppCategoriesStore {
  CustomAppCategoriesStore({required this.mirrorRootDir});

  final String mirrorRootDir;

  static const int currentSchemaVersion = 1;
  static const String fileName = 'categories.json';

  String get filePath => p.join(mirrorRootDir, 'apps', fileName);

  /// קובץ חסר או פגום נקרא כרשימה ריקה — "אין קטגוריות" הוא המצב הרגיל,
  /// ותקלה כאן אסור לה למנוע את הצגת התוכנות עצמן.
  Future<List<CustomAppCategory>> load() async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return const [];
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return const [];
      final schema = json['schemaVersion'];
      // קובץ שנכתב בפורמט חדש יותר — עדיף ריק על ניחוש שדות שלא היו כאן.
      if (schema is int && schema > currentSchemaVersion) return const [];
      final raw = json['categories'];
      if (raw is! List) return const [];
      return [
        for (final item in raw)
          if (CustomAppCategory.fromJson(item) case final category?) category,
      ];
    } catch (_) {
      return const [];
    }
  }

  /// כתיבה אטומית: קובץ זמני ואז החלפה. כונן שנשלף באמצע הכתיבה היה
  /// מותיר כאן JSON חתוך, כלומר את כל הקטגוריות אבודות.
  Future<void> save(List<CustomAppCategory> categories) async {
    final file = File(filePath);
    await file.parent.create(recursive: true);
    final temp = File('$filePath.tmp');
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': currentSchemaVersion,
        'categories': [for (final c in categories) c.toJson()],
      }),
    );
    await temp.rename(filePath);
  }
}

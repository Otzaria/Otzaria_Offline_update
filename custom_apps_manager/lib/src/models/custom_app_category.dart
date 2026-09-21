import '../services/app_descriptor_id_generator.dart';
import 'app_descriptor_id.dart';

/// קטגוריה של תוכנות נוספות, כפי שהמשתמש הגדיר אותה.
///
/// **הכול מקומי.** בשונה מקטגוריות התוספים, שמגיעות מ-otzaria.org, כאן
/// אין שרת: המשתמש יוצר את הרשימה במחשב המקוון, והיא נוסעת על הכונן יחד
/// עם התוכנות עצמן.
///
/// ה-[slug] הוא המפתח היציב — הוא זה שנרשם על כל תוכנה, ולכן שינוי השם
/// אינו נוגע בו.
class CustomAppCategory {
  const CustomAppCategory({
    required this.slug,
    required this.name,
    this.description = '',
  });

  /// הבסיס ל-slug כששם הקטגוריה כולו בעברית ולא שרד ממנו תו לטיני.
  static const String slugFallback = 'category';

  final String slug;

  /// השם שהמשתמש רואה. **תוכן, לא מלל של התוכנה** — אינו מתורגם.
  final String name;

  final String description;

  /// slug פנוי שנגזר מ-[name]. אינו מוצג לעולם — הוא שם מפתח בלבד, ולכן
  /// מותר לו ליפול ל-`category-2` כששם הקטגוריה בעברית.
  static String slugFor(String name, {Set<String> taken = const {}}) =>
      AppDescriptorIdGenerator.from(
        name,
        taken: taken,
        whenEmpty: slugFallback,
      );

  /// רשומה בלי slug תקין אינה שמישה (אין לפיה סינון, והיא גם שם מפתח)
  /// ולכן מדולגת — קובץ אחד שנשבר לא ימנע מהשאר להיטען.
  static CustomAppCategory? fromJson(Object? json) {
    if (json is! Map) return null;
    final slug = json['slug'];
    if (slug is! String || !AppDescriptorId.isValid(slug)) return null;
    final name = json['name'];
    return CustomAppCategory(
      slug: slug,
      name: name is String && name.trim().isNotEmpty ? name.trim() : slug,
      description:
          json['description'] is String ? json['description'] as String : '',
    );
  }

  Map<String, dynamic> toJson() => {
        'slug': slug,
        'name': name,
        if (description.isNotEmpty) 'description': description,
      };

  CustomAppCategory copyWith({String? name, String? description}) =>
      CustomAppCategory(
        slug: slug,
        name: name ?? this.name,
        description: description ?? this.description,
      );

  @override
  bool operator ==(Object other) =>
      other is CustomAppCategory &&
      other.slug == slug &&
      other.name == name &&
      other.description == description;

  @override
  int get hashCode => Object.hash(slug, name, description);
}

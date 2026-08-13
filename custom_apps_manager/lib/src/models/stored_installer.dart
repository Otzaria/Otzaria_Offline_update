/// קובץ ההתקנה ששמור במראה עבור תוכנה מותאמת.
///
/// במקור `manual` אין מה "לבדוק ברשת": מה שיש כאן **הוא** הגרסה הזמינה.
/// הקובץ נוסע על הכונן ומותקן במחשב המנותק, בדיוק כמו קובץ ההתקנה של
/// אוצריא.
class StoredInstaller {
  const StoredInstaller({
    required this.fileName,
    required this.version,
    required this.sizeBytes,
    required this.addedAt,
  });

  /// שם הקובץ בתוך תיקיית התוכנה במראה. **שם בלבד ולא נתיב** — המראה
  /// נוסעת בין מחשבים ובין אותיות כונן, ונתיב מוחלט שנשמר בקובץ היה נשבר
  /// בדיוק כשהכונן מגיע ליעדו.
  final String fileName;

  /// הגרסה שהקובץ הזה מתקין, כפי שנקראה מה-exe או כפי שהמשתמש הקליד.
  final String version;

  final int sizeBytes;

  /// מתי נוסף — מוצג למשתמש כדי שיבין מה יושב אצלו על הכונן.
  final DateTime addedAt;

  factory StoredInstaller.fromJson(Map<String, dynamic> json) =>
      StoredInstaller(
        fileName: json['fileName'] as String,
        version: json['version'] as String? ?? '',
        sizeBytes: json['sizeBytes'] as int? ?? 0,
        addedAt: DateTime.tryParse(json['addedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  Map<String, dynamic> toJson() => {
        'fileName': fileName,
        'version': version,
        'sizeBytes': sizeBytes,
        'addedAt': addedAt.toIso8601String(),
      };
}

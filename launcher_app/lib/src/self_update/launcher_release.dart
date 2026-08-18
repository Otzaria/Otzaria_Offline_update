import 'launcher_version.dart';

/// release של **הלאנצ'ר עצמו** ב-GitHub, עם האסט היחיד שמעניין אותנו: קובץ
/// ההרצה לפלטפורמה הנוכחית.
class LauncherRelease {
  const LauncherRelease({
    required this.tagName,
    required this.name,
    required this.assetName,
    required this.downloadUrl,
    required this.sizeBytes,
    this.publishedAt,
    this.releaseNotes,
  });

  final String tagName;
  final String name;

  /// שם הקובץ כפי שהוא ב-release. בווינדוס זה ה-exe הבודד שמופץ, ולכן שמו
  /// עברי ומכיל נקודות שגיטהאב הוסיף במקום רווחים — לעולם לא מסתמכים עליו
  /// לזיהוי, רק על הסיומת.
  final String assetName;
  final String downloadUrl;
  final int sizeBytes;
  final DateTime? publishedAt;
  final String? releaseNotes;

  /// הגרסה המנורמלת של התג — זו שמוצגת למשתמש ומושווית למותקנת.
  ///
  /// ה-`.0` שבסוף התג יורד: התג הוא `v0.2.0` (בן שלושה חלקים, כדי שלאנצ'רים
  /// ותיקים יזהו אותו) אבל המספר שהתוכנה מדווחת על עצמה הוא `0.2`, ושני
  /// מספרים שונים על אותו עדכון מבלבלים.
  String get version {
    final normalized = LauncherVersion.normalize(tagName);
    final parts = normalized.split('.');
    if (parts.length == 3 && parts.last == '0') {
      return '${parts[0]}.${parts[1]}';
    }
    return normalized;
  }

  Map<String, dynamic> toJson() => {
        'tagName': tagName,
        'name': name,
        'assetName': assetName,
        'downloadUrl': downloadUrl,
        'sizeBytes': sizeBytes,
        if (publishedAt != null) 'publishedAt': publishedAt!.toIso8601String(),
        if (releaseNotes != null) 'releaseNotes': releaseNotes,
      };

  /// זורק [FormatException] על רשומה שחסר בה שדה חובה — הקורא (המראה) הופך
  /// זאת ל"אין גרסה מוכנה", שהיא התשובה הנכונה גם לקובץ פגום.
  factory LauncherRelease.fromJson(Map<String, dynamic> json) {
    String required(String key) {
      final value = json[key];
      if (value is! String || value.isEmpty) {
        throw FormatException('LauncherRelease: שדה חסר או פגום — $key');
      }
      return value;
    }

    final size = json['sizeBytes'];
    if (size is! int) {
      throw const FormatException('LauncherRelease: sizeBytes חסר או פגום');
    }

    final publishedAt = json['publishedAt'];
    return LauncherRelease(
      tagName: required('tagName'),
      name:
          json['name'] is String ? json['name'] as String : required('tagName'),
      assetName: required('assetName'),
      downloadUrl: required('downloadUrl'),
      sizeBytes: size,
      publishedAt:
          publishedAt is String ? DateTime.tryParse(publishedAt) : null,
      releaseNotes: json['releaseNotes'] is String
          ? json['releaseNotes'] as String
          : null,
    );
  }
}

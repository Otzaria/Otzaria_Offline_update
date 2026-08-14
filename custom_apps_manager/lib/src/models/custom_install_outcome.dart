import 'app_detect_rules.dart';
import 'custom_installer_kind.dart';

/// מה שקרה בהתקנה אחת של תוכנה נוספת.
///
/// קודם לכן `install` החזירה `String?` — נתיב הארכיון או `null` — ולכן לא
/// היה בה מקום לספר שני דברים שהממשק כן צריך: איזה סוג התקנה זוהה בפועל,
/// ומה **נלמד** על התוכנה אחרי שהותקנה.
class CustomInstallOutcome {
  const CustomInstallOutcome({
    required this.kind,
    this.archivePath,
    this.learned,
  });

  /// הסוג שזוהה מהקובץ ברגע ההרצה. אינו נשמר ברשומה — ראו
  /// [CustomAppInstaller.install].
  final CustomInstallerKind kind;

  /// לאן הועתק ארכיון. `null` בכל סוג אחר — ארכיון אינו מותקן אלא מונח
  /// בתיקיית ההורדות.
  final String? archivePath;

  /// כללי הזיהוי שנלמדו מההתקנה הזו, או `null` כשלא נלמד כלום.
  ///
  /// `null` הוא מצב תקין ושכיח: תוכנה ניידת אינה רושמת הסרה, וגם רשומה
  /// שכבר יודעת לזהות אינה צריכה ללמוד שוב.
  final AppDetectRules? learned;

  bool get isArchive => kind.isArchive;

  /// האם הלמידה הוסיפה משהו — הממשק אומר על כך למשתמש, כי מכאן והלאה
  /// הכרטיס שלו יפסיק לומר "לא ניתן לזהות".
  bool get didLearn => learned != null;
}

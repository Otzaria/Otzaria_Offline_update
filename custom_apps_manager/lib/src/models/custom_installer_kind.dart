/// סוג חבילת ההתקנה של תוכנה מותאמת.
///
/// **רשימה סגורה בכוונה.** התוסף מצהיר "זה Inno" — הוא **אינו** כותב דגלים.
/// הדגלים מגיעים מכאן, מהלאנצ'ר. שתי סיבות: תוסף שמכתיב שורת פקודה שלמה הוא
/// פרימיטיב של הרצת קוד שרירותי, ומחבר תוסף שמנחש דגלים בעצמו טועה.
enum CustomInstallerKind {
  /// Inno Setup — `/VERYSILENT`. הדגלים האלה **אומתו בריפו הזה** מול
  /// ה-installer האמיתי של אוצריא (ראו `OtzariaInstaller`).
  innoSetup('inno'),

  /// NSIS — `/S`. מוסכמה מתועדת של NSIS; לא אומתה כאן מול installer אמיתי.
  nsis('nsis'),

  /// חבילת MSI — מורצת דרך `msiexec`, לא ישירות. לא אומתה כאן.
  msi('msi'),

  /// ארכיון ZIP של תוכנה ניידת — אין מה להריץ, רק לחלץ.
  /// [silentCommand] מחזיר `null` עבורו.
  zipPortable('zip'),

  /// הקובץ **הוא** התוכנה, ולא מתקין שלה — הוא רק מועתק לאן שהמשתמש בחר.
  ///
  /// ⚠️ זה הסוג היחיד שאינו מרוחרח מהקובץ אלא מוצהר ברשומה
  /// ([AppDescriptor.portableFile]), כי אי אפשר להסיק אותו מהבייטים: exe
  /// נייד ומתקין של framework שאיננו מכירים נראים זהים לחלוטין. הרצת
  /// הראשון "כמתקין" פשוט מפעילה את התוכנה מהכונן — היא לעולם לא תגיע
  /// למחשב.
  portableFile('file'),

  /// לא הצלחנו לזהות איזה framework בנה את הקובץ.
  ///
  /// **הנפילה לכאן אינה כישלון** — הקובץ מורץ כרגיל, והמשתמש לוחץ "הבא"
  /// בחלון של המתקין. הוא ממילא עומד מול המחשב המנותק באותו רגע. לנחש
  /// דגלי שקט של framework לא מוכר היה גרוע בהרבה: דגל שגוי עלול לפתוח
  /// חלון שאיש לא מצפה לו, או להתקין למקום לא נכון.
  interactive('interactive');

  const CustomInstallerKind(this.id);

  /// המזהה כפי שהוא נכתב ב-JSON של התוסף.
  final String id;

  static CustomInstallerKind? byId(String id) {
    for (final kind in values) {
      if (kind.id == id) return kind;
    }
    return null;
  }

  /// כל המזהים החוקיים — לשימוש בהודעת שגיאה שמסבירה מה כן מותר.
  static List<String> get allIds => [for (final k in values) k.id];

  /// האם ההתקנה היא חילוץ ארכיון ולא הרצת תהליך.
  bool get isArchive => this == CustomInstallerKind.zipPortable;

  /// האם אין כאן התקנה בכלל אלא העתקת הקובץ בלבד. שני הסוגים האלה אינם
  /// מריצים דבר, ולכן גם אין מהם מה ללמוד ברג'יסטרי ההסרה.
  bool get isCopyOnly =>
      this == CustomInstallerKind.zipPortable ||
      this == CustomInstallerKind.portableFile;

  /// הפקודה שמריצה את ההתקנה בשקט, או `null` כשאין מה להריץ ([isArchive]).
  ///
  /// [installDir] אופציונלי: בלעדיו ה-installer מתקין לברירת המחדל שלו —
  /// וזה בדרך כלל **עדיף**, כי אז התקנה קיימת מתעדכנת במקומה.
  CustomInstallerCommand? silentCommand({
    required String installerPath,
    String? installDir,
  }) {
    final dir =
        (installDir != null && installDir.isNotEmpty) ? installDir : null;

    return switch (this) {
      CustomInstallerKind.innoSetup => CustomInstallerCommand(
          executable: installerPath,
          arguments: [
            '/VERYSILENT',
            '/SUPPRESSMSGBOXES',
            '/NORESTART',
            if (dir != null) '/DIR=$dir',
          ],
        ),
      // ⚠️ ב-NSIS ‏`/D=` חייב להיות **הארגומנט האחרון**, בלי מרכאות — גם
      // כשהנתיב מכיל רווחים. כל מה שאחריו נבלע לתוך הנתיב. הבנייה כאן
      // מוסיפה אותו אחרון תמיד, כדי שלא יהיה אפשר לשבור את זה מבחוץ.
      CustomInstallerKind.nsis => CustomInstallerCommand(
          executable: installerPath,
          arguments: [
            '/S',
            if (dir != null) '/D=$dir',
          ],
        ),
      // חבילת MSI אינה קובץ הרצה — מריצים אותה דרך msiexec.
      CustomInstallerKind.msi => CustomInstallerCommand(
          executable: 'msiexec',
          arguments: [
            '/i',
            installerPath,
            '/qn',
            '/norestart',
            if (dir != null) 'INSTALLDIR=$dir',
          ],
        ),
      CustomInstallerKind.zipPortable => null,
      CustomInstallerKind.portableFile => null,
      // בלי דגלים בכלל: המתקין נפתח, והמשתמש מסיים אותו בעצמו.
      CustomInstallerKind.interactive => CustomInstallerCommand(
          executable: installerPath,
          arguments: const [],
        ),
    };
  }

  /// האם ההתקנה תרוץ בשקט. `false` ל-[interactive] — והממשק חייב לומר
  /// זאת מראש, כדי שחלון שנפתח לא ייראה כתקלה.
  bool get isSilent => this != CustomInstallerKind.interactive && !isCopyOnly;
}

/// פקודת התקנה מוכנה להרצה — מה מריצים ועם אילו ארגומנטים.
class CustomInstallerCommand {
  const CustomInstallerCommand({
    required this.executable,
    required this.arguments,
  });

  final String executable;
  final List<String> arguments;

  @override
  String toString() => [executable, ...arguments].join(' ');
}

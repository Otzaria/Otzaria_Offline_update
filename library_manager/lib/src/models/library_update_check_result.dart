import 'package:seforim_library_updater/seforim_library_updater.dart';

/// תוצאת בדיקת עדכון למסד (ה-DB).
///
/// [dbPath] כבר לא יכול להיות null בזרימה הרגילה: אם לא נמצא DB קיים (לא
/// בנתיב מותאם אישית ולא בברירת המחדל של אוצריא), [LibraryManager]
/// מצביע אוטומטית על נתיב ברירת מחדל משלו וממשיך לתוכנית הורדה מלאה —
/// בדיוק כמו שהתקנה ראשונה של אוצריא עצמה עובדת. [isFreshInstall] מציין
/// את המצב הזה כדי שה-UI יוכל להציג הודעה מתאימה ("מוריד בפעם הראשונה"
/// לעומת "מעדכן"). המשתמש עדיין יכול להצביע ידנית על קובץ DB קיים משלו
/// דרך `LibraryManager.setCustomDbPath`, אבל זו כבר לא חובה.
class LibraryUpdateCheckResult {
  const LibraryUpdateCheckResult({
    required this.dbPath,
    this.localVersion,
    this.plan,
    this.isFreshInstall = false,
  });

  final String? dbPath;
  final LocalDbVersion? localVersion;
  final LibraryUpdatePlan? plan;
  final bool isFreshInstall;

  /// נשמר לצורך תאימות לאחור בלבד — כמעט ולא אמור להיות true יותר, כי
  /// [LibraryManager.checkForUpdate] תמיד מצביע על נתיב (קיים או ברירת
  /// מחדל חדשה) מעכשיו.
  bool get needsManualDbPath => dbPath == null;

  bool get updateAvailable =>
      plan != null && plan!.kind != LibraryUpdatePlanKind.none;
}

import 'package:seforim_library_updater/seforim_library_updater.dart';

import '../services/companion_assets.dart';

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
    this.latestVersion,
    this.latestContentTag,
    this.pendingCompanions = const {},
    this.unavailableCompanions = const {},
  });

  final String? dbPath;
  final LocalDbVersion? localVersion;
  final LibraryUpdatePlan? plan;
  final bool isFreshInstall;

  /// הקבצים הנלווים (תלמוד/קטלוג/מילון) שבמראה יש מהם חדש ממה שמותקן.
  /// אוצריא מרעננת אותם בכל עדכון ספרייה, ולכן גם מסד מעודכן יכול להשאיר
  /// עבודה — ראו `CompanionAssetsInstaller`.
  ///
  /// **קבוצה ולא `bool`:** הצעה שאינה יודעת לומר על מה היא מדברת מוצגת
  /// כ"יש עדכון לספרייה" ליד "גרסה 27 → 27", ונקראת כתקלה.
  final Set<CompanionAsset> pendingCompanions;

  /// פריטים שרשומים במניפסט של המראה אבל הקובץ שלהם חסר או קטוע שם. **אינם
  /// הצעה** — אי אפשר להשלים אותם כאן — אבל כן מגיעים ללוג, כי הם אומרים
  /// שהמראה שעל הכונן חלקית.
  final Set<CompanionAsset> unavailableCompanions;

  bool get companionsPending => pendingCompanions.isNotEmpty;

  /// הגרסה הגבוהה ביותר שיש במראה — מה שהמסד אמור להגיע אליו.
  final int? latestVersion;

  /// ה-tag של ה-release **החדש ביותר** שבמראה, זה שהתוכן העדכני מגיע ממנו.
  /// נרשם אחרי החלה שהגיעה ל-[latestVersion] כ"התוכן שמותקן אצלנו", וכך
  /// מזוהה בהמשך מסד שפורסם מחדש באותו `db_version`. **לא** ה-tag של נושא
  /// המסד המלא — הוא יושב ב-`LibraryUpdatePlan.fullDbReleaseTag`.
  final String? latestContentTag;

  /// נשמר לצורך תאימות לאחור בלבד — כמעט ולא אמור להיות true יותר, כי
  /// [LibraryManager.checkForUpdate] תמיד מצביע על נתיב (קיים או ברירת
  /// מחדל חדשה) מעכשיו.
  bool get needsManualDbPath => dbPath == null;

  /// יש עבודה על המסד עצמו (דלתא או הורדה מלאה).
  bool get dbUpdateAvailable =>
      plan != null && plan!.kind != LibraryUpdatePlanKind.none;

  /// `true` כשמסלול הדלתא נכשל וניתן לנסות במקומו את המסד המלא שבמראה —
  /// ראו [LibraryManager.applyUpdate] ו-[LibraryUpdatePlan.fullDownloadFallback].
  bool get canFallBackToFullDownload => plan?.fullDownloadFallback != null;

  bool get updateAvailable => dbUpdateAvailable || companionsPending;
}

/// אומדן **זמן העדכון אצל המשתמש** — כמה זמן ייקח להביא את המסד לגרסה
/// האחרונה במחשב הלא-מקוון, לפי כל אחד משני המסלולים. זו פונקציה טהורה של
/// גודל הנכסים; אין כאן שום גישה לדיסק או לרשת.
///
/// **למה זה קיים:** את מה שנכנס למראה בוחרים במחשב המקוון, אבל את המחיר
/// משלם מי שמפעיל את הכונן במחשב שלו. השוואה לפי גודל בלבד ("מה שוקל יותר")
/// אינה מתארת את המחיר הזה: החלת patch משלמת סריקת-hash של **כל** המסד בכל
/// צעד, ולכן קובץ עדכון קטן אינו בהכרח עדכון קצר, וקובץ עדכון גדול הוא
/// שעה. ראו `LibraryMirrorExporter._fullDbBeatsPatches`.
///
/// **הקבועים כוילו על מדידות אמיתיות** מלוג של משתמש (ספטמבר 2026,
/// `update() מתחיל` → `update() הסתיים`), ומ-`DB_UPDATE_SPEED_PLAN.md`:
///
/// | מסלול | נכס | זמן שנמדד | האומדן כאן |
/// | --- | --- | --- | --- |
/// | מלא | 1.31GB דחוס | 129s (מהיר) / 581s (איטי) | 262s |
/// | דלתא | patch 6.8MB | 133s / 734s | 337s |
/// | דלתא | patch 8.5MB | 214s / 790s / 1039s | 347s |
/// | דלתא | patch 585MB | **3,864s** | 3,517s |
///
/// הפיזור בין מכונות הוא פי 3–5, ולכן האומדן אינו מבטיח שניות אלא **סדר
/// גודל והשוואה בין שני המסלולים** על אותה מכונה. זה גם כל מה שנדרש ממנו.
class ApplyTimeEstimate {
  const ApplyTimeEstimate({
    this.fullSecondsPerMb = 0.2,
    this.stepFixedSeconds = 300,
    this.stepSecondsPerMb = 5.5,
    this.slowRouteRatio = 2.0,
    this.slowRouteMarginSeconds = 600,
  });

  /// חילוץ ה-zstd וכתיבת המסד, לכל MB **דחוס** של `seforim.db.zst`.
  final double fullSecondsPerMb;

  /// המחיר הקבוע של צעד דלתא אחד, בלי קשר לגודל הקובץ: סריקת ה-hash הלוגי
  /// על כל המסד (~5.9GB לוגיים ב-23MB/s). זה מה שהופך שרשרת של חמישה צעדים
  /// לחמש פעמים המחיר הזה.
  final double stepFixedSeconds;

  /// החלק שגדל עם הקובץ: חילוץ ה-patch והחלתו, לכל MB דחוס.
  final double stepSecondsPerMb;

  /// **הטווח, חלק א׳:** פי כמה מסלול הדלתא רשאי להיות איטי מהמסלול המלא
  /// לפני שהוא מפסיד. הוא אינו חייב להיות מהיר יותר — הוא חוסך ~1.3GB
  /// בהורדה במחשב המקוון, וזה שווה כמה דקות אצל מי שמעדכן.
  final double slowRouteRatio;

  /// **הטווח, חלק ב׳:** ההפרש המוחלט שמתחתיו אין דיון. בלעדיו יחס של פי 2
  /// על עדכון של שתי דקות היה גורר הורדה של 1.3GB בשביל דקה.
  final double slowRouteMarginSeconds;

  static const int _mb = 1 << 20;

  /// זמן החלפת המסד המלא: חילוץ [compressedBytes] וכתיבת המסד.
  double fullRouteSeconds(int compressedBytes) =>
      (compressedBytes / _mb) * fullSecondsPerMb;

  /// זמן החלת שרשרת דלתא, לפי הגודל הדחוס של כל צעד בה.
  double deltaRouteSeconds(Iterable<int> stepCompressedBytes) {
    var seconds = 0.0;
    for (final bytes in stepCompressedBytes) {
      seconds += stepFixedSeconds + (bytes / _mb) * stepSecondsPerMb;
    }
    return seconds;
  }

  /// האם מסלול הדלתא יצא **מחוץ לטווח** — איטי מהמסלול המלא גם ביחס וגם
  /// בהפרש מוחלט. רק אז שווה לוותר על היסטוריית ה-patches.
  bool isOutOfRange(double deltaSeconds, double fullSeconds) =>
      deltaSeconds > fullSeconds * slowRouteRatio &&
      deltaSeconds - fullSeconds >= slowRouteMarginSeconds;

  /// דקות מעוגלות כלפי מעלה, להצגה למשתמש — 0 דקות אינו זמן.
  static int minutesOf(double seconds) {
    final minutes = (seconds / 60).ceil();
    return minutes < 1 ? 1 : minutes;
  }
}

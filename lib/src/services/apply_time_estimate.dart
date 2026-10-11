/// אומדן **זמן העדכון אצל המשתמש** — כמה זמן ייקח להביא את המסד לגרסה
/// האחרונה במחשב הלא-מקוון, לפי כל אחד משני המסלולים. זו פונקציה טהורה של
/// גודל הנכסים; אין כאן שום גישה לדיסק או לרשת.
///
/// **למה זה קיים:** את מה שנכנס למראה בוחרים במחשב המקוון, אבל את המחיר
/// משלם מי שמפעיל את הכונן במחשב שלו. השוואה לפי גודל בלבד ("מה שוקל יותר")
/// אינה מתארת את המחיר הזה: החלת patch משלמת סריקת-hash של **כל** המסד בכל
/// צעד, ולכן קובץ עדכון קטן אינו בהכרח עדכון קצר, וקובץ עדכון גדול הוא
/// שעה. ראו `LibraryMirrorExporter._dropSlowPatches` ו-`LibraryUpdatePlanner`.
///
/// **הקבועים כוילו על מדידות אמיתיות** מלוג של משתמש (ספטמבר 2026,
/// `update() מתחיל` → `update() הסתיים`) ומסבב המדידות על המסד האמיתי
/// (ראו AGENTS.md §5.1):
///
/// | מסלול | נכס | זמן שנמדד | האומדן כאן |
/// | --- | --- | --- | --- |
/// | מלא | 1.31GB דחוס | 129s (מהיר) / 581s (איטי) | 262s |
/// | דלתא | patch 6.8MB | 133s / 734s | 337s |
/// | דלתא | patch 8.5MB | 214s / 790s / 1039s | 347s |
/// | דלתא | patch 585MB | **3,864s** | 3,517s |
/// | דלתא | patch 114MiB (v31→v32) | לא נמדד | 927s |
///
/// הפיזור בין מכונות הוא פי 3–5, ולכן האומדן אינו מבטיח שניות אלא **סדר
/// גודל והשוואה בין שני המסלולים** על אותה מכונה. זה גם כל מה שנדרש ממנו.
///
/// **זיכוי הורדה:** הטווח מורחב בשווי ההורדה שנחסכת במחשב המקוון
/// ([downloadSecondsPerMb]) — patch של 114MiB מול מסד של 1.73GB חוסך ~1.6GB,
/// וזה שווה כ-14 דקות. בלי הזיכוי patch גדול ב-4% בלבד היה נפסל.
class ApplyTimeEstimate {
  const ApplyTimeEstimate({
    this.fullSecondsPerMb = 0.2,
    this.stepFixedSeconds = 300,
    this.stepIntermediateSeconds = 60,
    this.stepSecondsPerMb = 5.5,
    this.slowRouteRatio = 2.0,
    this.slowRouteMarginSeconds = 600,
    this.downloadSecondsPerMb = 0.5,
  });

  /// חילוץ ה-zstd וכתיבת המסד, לכל MB **דחוס** של `seforim.db.zst`.
  final double fullSecondsPerMb;

  /// המחיר הקבוע של שרשרת דלתא, בלי קשר לגודל הקבצים: סריקת ה-hash הלוגי
  /// על כל המסד (~5.9GB לוגיים ב-23MB/s). נגבה **פעם אחת לשרשרת** — ה-applier
  /// מאמת hash מקור רק בצעד הראשון ויעד רק באחרון.
  final double stepFixedSeconds;

  /// מחיר קבוע קטן לכל צעד ביניים בשרשרת (פתיחת ה-patch ומעבר צעד).
  /// **אומדן ולא נמדד.**
  final double stepIntermediateSeconds;

  /// החלק שגדל עם הקובץ: חילוץ ה-patch והחלתו, לכל MB דחוס.
  final double stepSecondsPerMb;

  /// **הטווח, חלק א׳:** פי כמה מסלול הדלתא רשאי להיות איטי מהמסלול המלא
  /// לפני שהוא מפסיד. הוא אינו חייב להיות מהיר יותר — הוא חוסך ~1.3GB
  /// בהורדה במחשב המקוון, וזה שווה כמה דקות אצל מי שמעדכן.
  final double slowRouteRatio;

  /// **הטווח, חלק ב׳:** ההפרש המוחלט שמתחתיו אין דיון. בלעדיו יחס של פי 2
  /// על עדכון של שתי דקות היה גורר הורדה של 1.3GB בשביל דקה.
  final double slowRouteMarginSeconds;

  /// שווי שנייה-הורדה לכל MB שנחסך במחשב המקוון: ~2MB/s אגרגטי של GitHub.
  final double downloadSecondsPerMb;

  static const int _mb = 1 << 20;

  /// זמן החלפת המסד המלא: חילוץ [compressedBytes] וכתיבת המסד.
  double fullRouteSeconds(int compressedBytes) =>
      (compressedBytes / _mb) * fullSecondsPerMb;

  /// זמן החלת שרשרת דלתא: מחיר קבוע מלא פעם אחת, מחיר ביניים קטן לכל צעד
  /// נוסף, והחלק שגדל עם הגודל הדחוס של כל צעד.
  double deltaRouteSeconds(Iterable<int> stepCompressedBytes) {
    var seconds = 0.0;
    var first = true;
    for (final bytes in stepCompressedBytes) {
      seconds += (first ? stepFixedSeconds : stepIntermediateSeconds) +
          (bytes / _mb) * stepSecondsPerMb;
      first = false;
    }
    return seconds;
  }

  /// עלות צעד בשרשרת שנבנית בהדרגה (תכנון דינמי): כמו צעד ביניים. את
  /// ההפרש עד המחיר הקבוע המלא מוסיפים פעם אחת — [chainStartExtraSeconds].
  double intermediateStepSeconds(int compressedBytes) =>
      stepIntermediateSeconds + (compressedBytes / _mb) * stepSecondsPerMb;

  /// התוספת על סכום [intermediateStepSeconds] של שרשרת לא ריקה.
  double get chainStartExtraSeconds =>
      stepFixedSeconds - stepIntermediateSeconds;

  /// האם מסלול הדלתא יצא **מחוץ לטווח** — איטי מהמסלול המלא גם ביחס וגם
  /// בהפרש מוחלט. רק אז שווה לוותר על היסטוריית ה-patches.
  ///
  /// [savedDownloadBytes] — כמה בייטים ההורדה בדלתא חוסכת מול המסד המלא
  /// (מלא פחות גודל מסלול ה-patch, לא פחות מ-0); שווים נוסף על ההפרש הנדרש.
  /// כשאין חיסכון (patches שסכומם עולה על המסד) אין זיכוי.
  bool isOutOfRange(
    double deltaSeconds,
    double fullSeconds, {
    int savedDownloadBytes = 0,
  }) {
    final saved = savedDownloadBytes < 0 ? 0 : savedDownloadBytes;
    final margin =
        slowRouteMarginSeconds + (saved / _mb) * downloadSecondsPerMb;
    return deltaSeconds > fullSeconds * slowRouteRatio &&
        deltaSeconds - fullSeconds >= margin;
  }

  /// דקות מעוגלות כלפי מעלה, להצגה למשתמש — 0 דקות אינו זמן.
  static int minutesOf(double seconds) {
    final minutes = (seconds / 60).ceil();
    return minutes < 1 ? 1 : minutes;
  }
}

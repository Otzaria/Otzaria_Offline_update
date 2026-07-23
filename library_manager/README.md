# library_manager

חבילת Flutter שמחווטת (wiring) את
[`seforim_library_updater`](../README.md) אל תוך הלאנצ'ר המאוחד: איתור
תיקיית ה-DB בפועל של המשתמש, בדיקה שאוצריא סגורה לפני כל שינוי בקובץ,
והרצת מסלול העדכון (delta/הורדה מלאה) מקצה לקצה.

## ממצאים חשובים (נכון ליולי 2026, מקוד המקור של Otzaria)

- **מיקום ברירת המחדל של ה-DB בווינדוס הוא `C:/אוצריא/seforim.db`** —
  אומת ישירות מול `lib/main.dart` (`initLibraryPath`) ו-
  `lib/data/constants/database_constants.dart`
  (`DatabaseConstants.databaseFileName = 'seforim.db'`) בריפו
  `Sivan22/otzaria`. זה בדיוק הערך ש-Otzaria עצמה קובעת אם המשתמש לא
  שינה את `key-library-path` שלו.
- מיקום מותאם אישית (אם המשתמש כן שינה) **לא** נקרא אוטומטית מתוך
  הגדרות ה-Settings/Hive של אוצריא — [`LibraryDbLocator`](lib/src/services/library_db_locator.dart)
  בודק קודם נתיב ששמור אצלנו (`LibraryStateStore`), ורק אם גם זה וגם
  ברירת המחדל לא נמצאים, מחזיר `null` — ה-UI צריך לבקש מהמשתמש להצביע
  ידנית (לפי ההחלטה איתו).
- **אסור לגעת ב-`seforim.db` כשאוצריא רצה**: ה-orchestrator המקורי
  בתוך אוצריא (`PACKAGE_PLAN.md`) סוגר את חיבור ה-SQLite שלו לפני שינוי
  חיצוני ופותח אותו מחדש אחר כך — משהו שאנחנו, כתהליך נפרד, לא יכולים
  לעשות בשבילה. [`OtzariaProcessGuard`](lib/src/services/otzaria_process_guard.dart)
  בודק דרך `tasklist` אם `otzaria.exe` רץ, וחוסם אם כן (המשתמש צריך
  לסגור ידנית — **לא** ניסינו לסגור אוטומטית, לפי ההחלטה איתו).

## מבנה

- `services/library_db_locator.dart` — איתור נתיב ה-DB (custom → ברירת מחדל → null).
- `services/library_state_store.dart` — שמירת נתיב מותאם אישית.
- `services/otzaria_process_guard.dart` — בדיקת "האם אוצריא רצה" דרך `tasklist`.
- `services/zstd_decompressor.dart` — מימוש `decompress` הנדרש על ידי `PatchDownloader`, דרך `package:archive`.
- `library_manager.dart` — האורקסטרטור: `checkForUpdate()` / `applyUpdate()`.

## ⚠️ מה עדיין לא מאומת / סיכונים ידועים

1. **חילוץ zstd לא נבדק בפועל** — `package:archive`'s `ZstdDecoder` לא
   הורץ כאן (אין Windows/Flutter בסביבה הזו). אם החילוץ נכשל/מתנהג
   אחרת, כל מסלול ה-delta (ואילך fullDownload) לא יעבוד.
2. **מסלול ה-DB המלא (fullDownload) מחלץ zstd בזיכרון, על כל הבייטים
   בבת אחת** (`File.readAsBytes` + `ZstdDecoder().decodeBytes`) — ה-DB
   המלא מתועד כ-~1.1GB דחוס (ראו התיעוד המקורי של `PatchDownloader`
   ב-`seforim_library_updater`). זה עלול לצרוך RAM רב ולהיות איטי.
   `downloadToFile` עצמו סטרימינג לדיסק (בסדר), אבל שלב החילוץ
   שאחריו **אינו** streaming כרגע. אם זה מתברר כבעייתי, יש להחליף
   לחילוץ streaming (למשל דרך קריאה ל-`zstd.exe` חיצוני, או binding
   native ל-libzstd) — לא ל-`package:archive` כמו שכתוב כרגע.
3. **`_allowPrerelease = true` כברירת מחדל** עבור releases של
   `Otzaria/SeforimLibrary` (המסד) — זו **לא** אותה החלטה שהתקבלה עם
   המשתמש לגבי `otzaria_manager` (שם ההחלטה הייתה מפורשת, כי ריפו
   אוצריא עצמו כמעט ולא מפרסם יציבים). כאן זו ברירת מחדל סבירה שנבחרה
   בנפרד, לא אושרה במפורש — כדאי לבדוק אם SeforimLibrary כן מפרסם
   יציבים סדירים, ואם כן לשקול `false`.
4. **שם תהליך קבוע (`otzaria.exe`)** ב-`OtzariaProcessGuard` — לא
   מחובר דינמית לשם ה-exe בפועל שהתגלה על ידי `otzaria_manager`
   (`OtzariaExeLocator`). אם שם הקובץ ישתנה, הבדיקה תפספס. שיפור עתידי:
   להזריק את שם ה-exe בפועל מ-`OtzariaManager.checkForUpdate()`'s
   `installState.exePath` דרך הדשבורד המאוחד, במקום קבוע.

## שימוש

```dart
final manager = LibraryManager(dataDir: r'C:\Users\me\AppData\Roaming\OurLauncher');

var check = await manager.checkForUpdate();
if (check.needsManualDbPath) {
  // הצג בחירת תיקייה למשתמש (native folder picker), ואז:
  await manager.setCustomDbPath(userChosenDbPath);
  check = await manager.checkForUpdate();
}

if (check.updateAvailable) {
  try {
    await manager.applyUpdate(
      check,
      onStage: (stage) => print(stage),
      onDownloadProgress: (received, total) => print('$received/$total'),
    );
  } on OtzariaIsRunningException {
    // הצג הודעה: "סגור/י את אוצריא ונסה/י שוב"
  }
}

manager.dispose();
```

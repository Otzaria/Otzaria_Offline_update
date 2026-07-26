# library_manager

חבילת Flutter שמחווטת (wiring) את
[`seforim_library_updater`](../README.md) אל תוך הלאנצ'ר המאוחד: איתור
תיקיית ה-DB בפועל של המשתמש, בדיקת גרסה מול הענן, והורדת קבצים עדכניים
לתיקייה מקומית בלבד (**ללא** patch/apply על ה-DB החי — ראו הערה למטה).

## ממצאים חשובים (עודכן יולי 2026, לפי דיווח משתמש בפועל)

- **מיקום ברירת המחדל האמיתי של ה-DB בווינדוס הוא
  `%APPDATA%\otzaria\books\seforim.db`** — מבוסס על דיווח בפועל ממשתמש
  שהריץ Otzaria 0.9.9x. ⚠️ הטענה הקודמת כאן (`C:\אוצריא\seforim.db`,
  "אומת מול קוד המקור") הייתה **שגויה** — לא באמת נבדקה מול קוד המקור
  כפי שנטען, והמיקום בפועל אצל המשתמש היה שונה לגמרי.
  [`LibraryDbLocator`](lib/src/services/library_db_locator.dart) בודק
  היום את `%APPDATA%\otzaria\books\` קודם, ונופל חזרה ל-`C:\אוצריא\`
  כגיבוי משני (למקרה שזה עדיין נכון בהתקנות מסוימות, כמו חבילת FULL).
- מיקום מותאם אישית (אם המשתמש כן שינה) **לא** נקרא אוטומטית מתוך
  הגדרות ה-Settings/Hive של אוצריא — `LibraryDbLocator` בודק קודם נתיב
  ששמור אצלנו (`LibraryStateStore`), ורק אם גם זה וגם שני המיקומים
  האחרים לא נמצאים, מחזיר `null` — ה-UI צריך לבקש מהמשתמש להצביע
  ידנית (לפי ההחלטה איתו).
- **בדיקת "האם אוצריא רצה" הוסרה** יחד עם מנגנון ה-apply כולו (ראו
  הערה למטה) — היא הייתה רלוונטית רק כשה-manager כתב בפועל ל-
  `seforim.db` החי. כיום ה-manager הזה לא נוגע בקובץ ה-DB בכלל, אז אין
  יותר צורך לבדוק אם אוצריא רצה מתוכו.

## מבנה

- `services/library_db_locator.dart` — איתור נתיב ה-DB (custom → ברירת מחדל → null).
- `services/library_state_store.dart` — שמירת נתיב מותאם אישית.
- `library_manager.dart` — האורקסטרטור: `checkForUpdate()` (בדיקה בלבד) +
  `exportOfflineMirror()`/`refreshOfflineMirrorCache()` (**הורדה לתיקייה
  מקומית בלבד** — אין כאן שום patch/apply על ה-DB החי, ואין תלות ב-Isolate).

> **הערה (עודכן):** מנגנון ה-`applyUpdate` הקודם (delta patch דרך
> `Isolate.run` + `PatchApplier`, כולל `OtzariaProcessGuard`/
> `zstd_decompressor.dart`) **הוסר לגמרי** מה-manager ומה-UI, לפי החלטה
> מפורשת: החיבור לענן משמש רק לבדיקה ולהורדת קבצים לתיקייה מקומית, ולא
> לעדכון ה-DB החי בפועל. הסיבה המקורית: קריסת
> `Illegal argument in isolate message: object is unsendable` — הסוגר
> שנשלח ל-`Isolate.run` גישה לשדה פרטי (`_applier`) וכך תפס בטעות את כל
> `this` (כולל `_cloudClient`/`HttpClient` חי, שאינו ניתן לשליחה בין
> isolates). הקבצים `services/otzaria_process_guard.dart` ו-
> `services/zstd_decompressor.dart` נשארו בריפו (עדיין מיוצאים דרך
> `library_manager.dart`) אך אינם בשימוש עוד על ידי `LibraryManager`.

## ⚠️ מה עדיין לא מאומת / סיכונים ידועים

1. **`_allowPrerelease = true` כברירת מחדל** עבור releases של
   `Otzaria/SeforimLibrary` (המסד) — זו **לא** אותה החלטה שהתקבלה עם
   המשתמש לגבי `otzaria_manager` (שם ההחלטה הייתה מפורשת, כי ריפו
   אוצריא עצמו כמעט ולא מפרסם יציבים). כאן זו ברירת מחדל סבירה שנבחרה
   בנפרד, לא אושרה במפורש — כדאי לבדוק אם SeforimLibrary כן מפרסם
   יציבים סדירים, ואם כן לשקול `false`.
2. **אין עוד מסלול שמעדכן את ה-`seforim.db` החי אוטומטית.** כל שה-UI
   עושה כרגע הוא להוריד את הגרסה העדכנית לתיקיית `offlineMirrorCacheDir`
   ולתת למשתמש לפתוח אותה (USB / תיקייה משותפת). אם בעתיד כן ירצו מסלול
   התקנה אוטומטי של ה-DB עצמו, יהיה צריך לתכנן אותו מחדש (ולא פשוט
   להחזיר את קוד ה-`applyUpdate` הישן, בגלל הבאג שתואר למעלה).

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
  // מוריד את הגרסה העדכנית לתיקייה מקומית בלבד — לא נוגע ב-DB החי.
  await manager.refreshOfflineMirrorCache(
    onStage: (stage) => print(stage),
  );
  print('הקבצים המעודכנים נמצאים ב-${manager.offlineMirrorCacheDir}');
}

manager.dispose();
```

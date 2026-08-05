# library_manager

חבילת Flutter שמחווטת (wiring) את
[`seforim_library_updater`](../README.md) אל תוך הלאנצ'ר המאוחד: איתור
תיקיית ה-DB בפועל של המשתמש, בדיקת גרסה מול הענן, והחלה בפועל (patch
דלתאי או החלפת DB מלא) על ה-DB **החי** דרך [`LibraryUpdateApplier`](lib/src/services/library_update_applier.dart) —
נבנה מחדש אחרי שהוסר עקב באג, ראו "היסטוריית התיקון" למטה.

## ממצאים חשובים (עודכן יולי 2026, לפי דיווח משתמש בפועל)

- **מיקום ברירת המחדל האמיתי של ה-DB בווינדוס הוא
  `%APPDATA%\otzaria\books\seforim.db`** — מבוסס על דיווח בפועל ממשתמש
  שהריץ Otzaria 0.9.9x. ⚠️ הטענה הקודמת כאן (`C:\אוצריא\seforim.db`,
  "אומת מול קוד המקור") הייתה **שגויה** — לא באמת נבדקה מול קוד המקור
  כפי שנטען, והמיקום בפועל אצל המשתמש היה שונה לגמרי.
  [`LibraryDbLocator`](lib/src/services/library_db_locator.dart) בודק
  היום את `%APPDATA%\otzaria\books\` קודם, ונופל חזרה ל-`C:\אוצריא\`
  כגיבוי משני (למקרה שזה עדיין נכון בהתקנות מסוימות, כמו חבילת FULL).
- **ב-macOS ברירת המחדל היא
  `~/Library/Application Support/otzaria/books/seforim.db`**, ובהתקנה
  מערכתית `/Library/Application Support/otzaria/books/`. הפעם זה **כן**
  נגזר מקוד המקור של אוצריא — `AppPaths.getDataRootPath()` +
  `getDefaultLibraryPath()` ב-`lib/core/app_paths.dart` — ולא מניחוש. באותה
  הזדמנות נוסף גם `%ProgramData%\otzaria\books` לווינדוס, שהוא מה שאוצריא
  משתמשת בו בהתקנה מערכתית.
- מיקום מותאם אישית (אם המשתמש כן שינה) **לא** נקרא אוטומטית מתוך
  הגדרות ה-Settings/Hive של אוצריא — `LibraryDbLocator` בודק קודם נתיב
  ששמור אצלנו (`LibraryStateStore`), ורק אם גם זה וגם המיקומים
  האחרים לא נמצאים, מחזיר `null` — ה-UI צריך לבקש מהמשתמש להצביע
  ידנית (לפי ההחלטה איתו).
- **בדיקת "האם אוצריא רצה"** (`OtzariaProcessGuard`) פעילה דרך
  `LibraryUpdateApplier.applyUpdate` — רלוונטית כי ה-manager כן כותב
  בפועל ל-`seforim.db` החי. פעילה בשתי הפלטפורמות: `tasklist` בווינדוס,
  `pgrep -x` ב-macOS/לינוקס.
- **שם התהליך של אוצריא ב-macOS הוא `אוצריא`** — בעברית, כי זה
  ה-`CFBundleExecutable` של החבילה (אומת מול `otzaria-macos.zip` אמיתי;
  `pgrep` מטפל ב-UTF-8 בשם התהליך). ההתאמה היא ב-`pgrep -x` (שם מלא,
  לא תת-מחרוזת) **בכוונה**: התאמה חלקית או `pgrep -f` על שורת הפקודה
  הייתה תופסת גם את הלאנצ'ר עצמו — הנתיב שלו מכיל את המילה otzaria —
  והיינו חוסמים כל עדכון בגלל התהליך שמריץ אותו.

## מבנה

- `services/library_db_locator.dart` — איתור נתיב ה-DB (custom → ברירת מחדל → null).
- `services/library_state_store.dart` — שמירת נתיב מותאם אישית.
- `services/library_update_applier.dart` — **`LibraryUpdateApplier`**: ההחלה
  בפועל של delta/fullDownload על ה-DB החי (patch/apply דרך `Isolate.run` נכון,
  גיבוי/שחזור, בדיקת "אוצריא רצה").
- `services/otzaria_process_guard.dart` — בדיקת תהליך אוצריא פעיל: `otzaria.exe` דרך `tasklist` בווינדוס, `אוצריא` דרך `pgrep -x` ב-macOS.
- `services/zstd_decompressor.dart` — מוזרק ל-`PatchDownloader` וגם לחילוץ ה-DB המלא.
- `library_manager.dart` — האורקסטרטור: `checkForUpdate()` (בדיקה+תכנון) +
  `applyUpdate()` (**ההחלה בפועל על ה-DB החי**) + `exportOfflineMirror()`/
  `refreshOfflineMirrorCache()` (הכנת מראה offline להעברה למחשב אחר).

> **היסטוריית התיקון:** מנגנון ה-apply המקורי הוסר בעבר עקב קריסת
> `Illegal argument in isolate message: object is unsendable` — הסוגר
> שנשלח ל-`Isolate.run` ניגש לשדה **מופע** (`_applier.apply(...)`), וכך
> תפס implicitly את כל `this` (כולל `_cloudClient`/`HttpClient` חי, שאינו
> ניתן לשליחה בין isolates). לזמן מה `LibraryManager` רק בדק והוריד
> לתיקייה מקומית, בלי לגעת ב-DB החי בכלל.
>
> **המנגנון נבנה מחדש** ב-[`LibraryUpdateApplier`](lib/src/services/library_update_applier.dart):
> כל קריאת `Isolate.run` עוברת דרך פונקציית **top-level** שמקבלת רק
> ארגומנטים פרימיטיביים/מבני-דאטה (records, `String`, `Uint8List`,
> `DeltaManifest`) — אותו דפוס שכבר עבד נכון ב-
> `LibraryDbRecoveryService.cloneOrCopyFile`. `LibraryManager.applyUpdate(check)`
> הוא נקודת הכניסה: מפעיל `OtzariaProcessGuard` (חוסם אם אוצריא פתוחה),
> מוריד ומחיל מסלול delta (patch-אחר-patch, כל אחד
> אטומי) או fullDownload (הורדה + חילוץ zstd + כתיבה אטומית עם
> גיבוי/שחזור דרך `LibraryDbRecoveryService`), ומאמת את הגרסה הסופית מול
> `LocalDbVersionReader`.
>
> **מגבלה ידועה (MVP) במסלול fullDownload:** החילוץ הוא בזיכרון (לא
> streaming) — כל ה-DB המלא (עד כ-1.1GB) נטען ל-RAM. עובד, אך צורך יותר
> זיכרון משיא אפשרי על מחשבים חלשים; שדרוג ל-streaming extractor (כמו
> ה-onboarding של אוצריא עצמה) הוא צעד המשך סביר אם זה יתברר כבעיה.
> `services/zstd_decompressor.dart` נשאר בשימוש (מוזרק ל-`PatchDownloader`
> ולחילוץ ה-DB המלא כאחד); `services/otzaria_process_guard.dart` נשאר
> בשימוש דרך `LibraryUpdateApplier`.

## ⚠️ מה עדיין לא מאומת / סיכונים ידועים

1. **`_allowPrerelease = true` כברירת מחדל** עבור releases של
   `Otzaria/SeforimLibrary` (המסד) — זו **לא** אותה החלטה שהתקבלה עם
   המשתמש לגבי `otzaria_manager` (שם ההחלטה הייתה מפורשת, כי ריפו
   אוצריא עצמו כמעט ולא מפרסם יציבים). כאן זו ברירת מחדל סבירה שנבחרה
   בנפרד, לא אושרה במפורש — כדאי לבדוק אם SeforimLibrary כן מפרסם
   יציבים סדירים, ואם כן לשקול `false`.
2. **`LibraryUpdateApplier` לא נבדק בפועל על ווינדוס אמיתי** (הסביבה כאן
   היא Linux) — הלוגיקה נכתבה לפי ה-API המתועד של `seforim_library_updater`
   ועברה `dart analyze`, אך לא `flutter run` על DB אמיתי בגודל מלא. יש
   לבדוק בפועל: מסלול delta על שרשרת patches אמיתית, מסלול fullDownload
   על קובץ ~1GB (כולל צריכת הזיכרון בפועל של החילוץ בזיכרון), והתנהגות
   `OtzariaProcessGuard`/`tasklist` כשאוצריא פתוחה.

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
    // מוריד ומחיל בפועל (delta או full) על ה-DB החי.
    await manager.applyUpdate(
      check,
      onProgress: (p) => print('${p.stage} ${p.bytesDownloaded}/${p.bytesTotal}'),
    );
    print('ה-DB עודכן בהצלחה ל-${check.plan?.targetVersion}');
  } on OtzariaIsRunningException {
    print('סגור קודם את אוצריא ונסה שוב');
  } on LibraryApplyException catch (e) {
    print('העדכון נכשל: $e');
  }
}

// לחלופין (או בנוסף), עדיין אפשר להכין מראה offline להעברה למחשב אחר:
// await manager.exportOfflineMirror(destDir: r'D:\seforim-mirror');

manager.dispose();
```

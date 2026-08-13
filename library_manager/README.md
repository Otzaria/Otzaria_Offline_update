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
- **מיקום מותאם אישית כן נקרא היום מההגדרות של אוצריא** (עודכן אוגוסט
  2026). זו הייתה הסטייה החמורה ביותר מהעדכון המקוון: אוצריא לוקחת את
  הנתיב מ-`DatabaseConstants.getDatabasePath()`, שקורא
  `key-library-path` + `key-library-folder-name` מקופסת ה-Hive
  `app_preferences` שבשורש הנתונים שלה. משתמש שהעביר את הספרייה לכונן
  אחר עשה זאת **שם**, וללא קריאת ההגדרה עדכנו קובץ אחר או חשבנו שאין
  מסד בכלל. [`OtzariaSettingsReader`](lib/src/services/otzaria_settings_reader.dart)
  קורא את הקופסה **מעותק** בתיקייה זמנית, כדי שלא ניצור קובץ נעילה
  בתיקייה של אוצריא ולא נתנגש איתה כשהיא פתוחה; כל כשל מוחזר כ-`null`
  והאיתור ממשיך לברירות המחדל. סדר החיפוש המלא:
  נתיב ששמור אצלנו → ההגדרה של אוצריא (בשורש נייד ואז בשורש הרגיל) →
  ספרייה מצורפת (חבילת FULL ב-macOS) → ברירות המחדל → `C:\אוצריא`.
- **התקנה טרייה נוחתת באותם מיקומים בדיוק** (עודכן אוגוסט 2026).
  `LibraryDbLocator.resolveInstallDbPath()` מחזיר את ההגדרה של אוצריא (גם
  כשהקובץ עוד לא קיים — שם היא תחפש) ואחרת את ברירת המחדל של הפלטפורמה.
  ⚠️ קודם לכן `LibraryManager.checkForUpdate` הצביע ל-`<dataDir>/library`,
  כלומר לתיקיית הנתונים של הלאנצ'ר: לאנצ'ר שרץ מכונן נייד התקין את המסד
  **על הכונן**, והוא נעלם מהמחשב ברגע שנשלף. `<dataDir>` נשארה רשת ביטחון
  לפלטפורמה שאין בה מיקום ידוע בכלל.
  `isKnownToOtzaria(dbPath)` עונה על השאלה ההפוכה — האם אוצריא תמצא את
  המסד שנבחר בעצמה. `false` הוא מה שמפעיל את אזהרת ה-UI: המשתמש יצטרך
  להצביע על המיקום מתוך ההגדרות של אוצריא, אחרת היא לא תראה שם ספרים.
- **הנתיב ששמור אצלנו הוא פר-מחשב** (issue #23, אוגוסט 2026).
  `library_state.json` יושב ב-`OtzariaData/`, כלומר על הכונן — ולכן נתיב
  מוחלט שנשמר בו נוסע לכל מחשב שהכונן מגיע אליו. ⚠️ קודם לכן הייתה שם רשומה
  גלובלית אחת, ואחרי התקנת ספרייה במחשב אחד (שם החשבון שם `user`) המחשב
  הבא **הצביע להתקנה** אל `C:\Users\user\AppData\Roaming\otzaria\books` —
  תיקייה שאינה קיימת שם, ושמשתמש רגיל אינו יכול ליצור תחת `C:\Users`. התוצאה
  הייתה שגיאת גישה בהתקנה, שנפתרה רק בבחירת מיקום ידנית.
  `LibraryStateStore` שומר עכשיו ב-`customDbPaths` לפי
  `currentMachineKey()` (שם מחשב + שם חשבון — שני חשבונות באותו מחשב הם שני
  `%APPDATA%`), ורשומה גלובלית מגרסה קודמת נחשבת רק אם היא נתיב מוחלט
  בפלטפורמה הזו ותיקיית האם שלו קיימת כאן.
- **התקנה ניידת של אוצריא** (`portable.marker` ליד ה-executable) מזיזה את
  שורש הנתונים כולו אל `otzaria_data` שלידו. הלאנצ'ר מזהה זאת דרך נתיב
  ההפעלה שמודול התוכנה מצא (`LibraryDbLocator.otzariaLaunchPath`), ולכן
  `AppShell.checkAll()` בודק את מודול התוכנה **לפני** מודול הספרייה.
- **בדיקת "האם אוצריא רצה"** (`OtzariaProcessGuard`) פעילה דרך
  `LibraryUpdateApplier.applyDelta` / `.applyFullDownload` — רלוונטית כי
  ה-manager כן כותב
  בפועל ל-`seforim.db` החי. פעילה בשתי הפלטפורמות: `tasklist` בווינדוס,
  `pgrep -x` ב-macOS/לינוקס.
- **שם התהליך של אוצריא ב-macOS הוא `אוצריא`** — בעברית, כי זה
  ה-`CFBundleExecutable` של החבילה (אומת מול `otzaria-macos.zip` אמיתי;
  `pgrep` מטפל ב-UTF-8 בשם התהליך). ההתאמה היא ב-`pgrep -x` (שם מלא,
  לא תת-מחרוזת) **בכוונה**: התאמה חלקית או `pgrep -f` על שורת הפקודה
  הייתה תופסת גם את הלאנצ'ר עצמו — הנתיב שלו מכיל את המילה otzaria —
  והיינו חוסמים כל עדכון בגלל התהליך שמריץ אותו.

## התאמה לעדכון המקוון של אוצריא

הצד השני של אותו מנגנון חי ב-`Otzaria/otzaria`, ב-`lib/library_update/`
(`LibraryUpdateRepository`, `LibraryUpdateBloc`, `CompanionAssetsService`),
מעל אותה חבילת מנוע בדיוק — `seforim_library_updater`, שהיא השורש של המאגר
הזה. המנוע זהה; מה שיושר כאן (אוגוסט 2026) הוא שכבת התזמור:

- **דגלי ה-apply** — `checkForeignKeys: false`, כמו
  `LibraryUpdateRepository._runApplyIsolate`. אימות ה-hash שאחרי ההחלה הוא
  הערובה האמיתית וגם מכסה את ה-FK; הפעלת ה-FK-check הוסיפה קריאה מלאה
  נוספת של המסד לכל patch.

  **כאן אנחנו כן חורגים מאוצריא, בכוונה:** אוצריא מאמתת hash בכל צעד
  בשרשרת, ואנחנו מאמתים **פעם אחת, בצעד האחרון**. ה-hash הוא על תוכן ה-DB
  כולו, ולכן התאמה ל-`toContentHash` של הצעד האחרון מוכיחה את כל השרשרת —
  ומסד של 7.4GB נקרא פעם אחת במקום פעם לכל patch. מה שמחזיק את זה בטוח הוא
  `<db>.unverified`: שרשרת שנקטעה משאירה מסד שהוחל נקי אך לא אומת, הסימון
  רושם את גרסתו, וההחלה הבאה משם מפעילה `verifyFromHash` ומאמתת אותו לפני
  שהיא בונה עליו. ראו `LibraryUpdateApplier.applyDelta`.
- **דיווח תת-שלבים** — `onStage`/`onVerifyProgress` חוזרים דרך `ReceivePort`
  ומגיעים ל-UI (`LibraryApplyProgress.patchStage` / `verifyProgress`), עם
  קובץ hint (`verify_total_bytes.txt`) ל-total מדויק. בלי זה שלב ה-hash
  נראה כתקיעה של דקות. מאותו טעם `ZstdFileDecompressor` מדווח כמה נקרא
  מהקובץ הדחוס (`bytesDone`/`bytesTotal` בשלב `decompressingFullDb`) —
  חילוץ של ~1GB הוא השלב הארוך הבא.
- **`PRAGMA quick_check` לפני ההחלפה** — במסלול ההורדה המלאה, ב-isolate,
  על הקובץ המחולץ, ורק אז ה-rename. קודם החלפנו ואז בדקנו גרסה בלבד.
- **הקבצים הנלווים** — ראו הסעיף הבא.
- **עומק שרשרת הדלתא** — המראה שומרת את עשרת ה-releases האחרונים
  (`LibraryMirrorExporter.defaultHistoryDepth`) ולא רק את האחרון, כדי
  שמכונה כמה גרסאות מאחור תקבל patches ולא הורדה של ~1.1GB. את **כל**
  ההיסטוריה עדיין לא שומרים — היעד הוא כונן נייד. מחלון ההיסטוריה יורדים
  ה-patches בלבד; את ה-DB המלא (~1.5GB) מורידים **פעם אחת**, מהגרסה
  הגבוהה ביותר שנושאת אותו — היחיד שהמסלול המלא באופליין בוחר.
- **מצב "עדכון אישי"** — תוספת שאין באוצריא: `personalUpdateMode` מצמצם את
  ההורדה ל-patches מהגרסה שנרשמה ומעלה, בלי המסד המלא. הגרסה נרשמת **רק**
  ב-`captureLocalDbVersion()` (לחיצה במסך הספרייה), לא בבדיקה שגרתית — הכונן
  מגיע גם למחשב המקוון, וקריאה אוטומטית שם הייתה דורסת את הגרסה של המחשב
  שבשבילו מורידים. נשמרת רשומה לכל מחשב (`knownDbVersions`) וההורדה יוצאת
  מהנמוכה. במצב הזה אין `fullDownloadFallback`, ולכן הוא מאושר בדיאלוג
  אזהרה. ראו AGENTS.md §1.
- **ניקוי נכסים נטושים** — בסוף כל הורדה מוצלחת נמחק מ-`assets/` כל מה
  שאינו במניפסט החדש (`release` שנפל מהחלון, נכס שהוחלף). קובצי ה-`.resume`
  של נכסים שכן במניפסט נשמרים — הם הזהות שמאפשרת לדלג על הורדה חוזרת.
- **ערוץ הספרייה** — יציב בלבד, כמו `allowPrerelease: () => false` באוצריא.
- **התאוששות מכשל דלתא** — כאן יש תוספת שאין באוצריא: כל תוכנית דלתא נושאת
  את ההורדה המלאה כמסלול חלופי (`LibraryUpdatePlan.fullDownloadFallback`),
  ו-`applyUpdate(useFullDownloadFallback: true)` מריץ אותו. הסיבה היא
  issue #19 — patch שהתנגש ב-`UNIQUE` של `tocText.text` הותיר את המשתמש בלי
  שום דרך להשלים את העדכון. באוצריא המקוונת הבעיה קטנה יותר: היא הולכת על
  כל גרף ה-patches ויכולה למשוך מסד מלא מהרשת בכל רגע. **אינו אוטומטי** —
  ~1.5GB + חילוץ ~5.5GB הם אישור של המשתמש, לא החלפת מסלול שקטה.

### הקבצים הנלווים

אוצריא מריצה `CompanionAssetsService.verifyAndUpdate()` אחרי כל בדיקה וכל
החלה, ומרעננת **מהרשת** שלושה דברים. במחשב לא-מקוון אין רשת, ולכן הם
נוסעים במראה:

| פריט | מקור | יעד (לצד `seforim.db`) | סימון גרסה |
| --- | --- | --- | --- |
| תלמוד בבלי | `Otzaria/otzaria-library`, `talmud_bavli_latest.tar.zst` | `תלמוד בבלי/` | `.version` = digest (או תג) |
| קטלוג otzar-HB | `Otzaria/otzar-HB_catalog`, `otzar-HB_catalog.db.zst` + `version.txt` | `otzar-HB_catalog.db` | `db_meta.version` |
| מילון החיפוש | `Otzaria/SeforimMagicIndexer`, הנכס שה-URL שלו מסתיים ב-`/lexical.db` | `lexical.db` | `lexical.db.version` = תג |

הצד המוריד הוא [`CompanionAssetsMirror`](lib/src/services/companion_assets_mirror.dart)
(רץ בסוף `downloadToMirror`, כותב `companions.json`), והצד המתקין הוא
[`CompanionAssetsInstaller`](lib/src/services/companion_assets_installer.dart)
(רץ בסוף `applyUpdate`, ומדווח גם ב-`checkForUpdate` דרך
`LibraryUpdateCheckResult.companionsPending`). כמו באוצריא, **כל פריט הוא
best-effort**: כשל באחד לא מפיל את השאר ולא מבטל עדכון מסד שכבר הצליח.
סימון ה-`installing` נכתב לפני חילוץ התלמוד, כך שחילוץ שנקטע מסומן
כהתקנה חלקית ואוצריא מתעלמת ממנה.

### אינדקס החיפוש — נסגר דרך `otzaria://library/reindex`

**הבעיה.** כשאוצריא מעדכנת בעצמה היא מאנדקסת מחדש את מה שהשתנה. עדכון
שנעשה **מבחוץ** עוקף את המסלול הזה: `isBookIndexed` בודק רק נוכחות מפתח
ב-`booksDone` ולא תוכן, ולכן `StartIndexing` מדלג על ספר שתוכנו התחלף,
ו-`requiresManualReindex` תלוי בסכמת ה-tantivy ולא בגרסת המסד. התוצאה:
החיפוש בספרים ששונו מחזיר תוכן ישן.

**הפתרון שאוצריא מימשה** (בקשתנו ב-
[issue #734](https://github.com/Otzaria/otzaria/issues/734#issuecomment-5251000659);
הקוד בענף `dev`, commit `78f395f3`, ומתועד ב-`docs/deep_links.md` שלה):
קישור העומק

```text
otzaria://library/reindex
```

הוא טוען מחדש את הקטלוג מהדיסק (`RefreshLibrary`) ואז מריץ `StartIndexing`
(ספרים חדשים) ו-`ReconcileIndex` (ספרים שתוכנם השתנה, לפי השוואת
טביעות-אצבע) — **גם כשההגדרה "עדכון אינדקס אוטומטי" כבויה**, כי בקשה
חיצונית נחשבת מפורשת. אין בו פרמטרים: אוצריא מזהה לבד מה השתנה, ולכן
`booksTouched` שאנחנו רושמים אינו נדרש לה.

**הצד שלנו.** בסוף כל `applyUpdate` מוצלח נכתב לצד המסד
[`.otzaria-external-update.json`](lib/src/services/external_update_notice.dart)
(`route`, `dbVersion`, `releaseTag`, `booksTouched`) — לא בשביל שאוצריא
תקרא אותו, אלא כ**סימון מתמשך שבקשה ממתינה**: הוא שורד הפעלות מחדש של
הלאנצ'ר, נקרא ב-`LibraryManager.pendingReindexRequest()`, ונמחק
(`clearReindexRequest()`) **רק** אחרי שהבקשה נמסרה בפועל. הלאנצ'ר מוסר
אותה בשתי דרכים, שתיהן ב-`launcher_app`:

- **יזום** — `OtzariaManager.requestLibraryReindex()`, מהאריח שבמסך
  הספרייה ומהדיאלוג שקופץ מיד אחרי עדכון מסד.
- **בנסיעה חופשית** — כל הפעלה רגילה של אוצריא מהלאנצ'ר מוסרת את הקישור
  כארגומנט כשיש בקשה ממתינה. את אוצריא המשתמש פותח ממילא.

המסירה היא **לקובץ ההרצה שזוהה** (`otzaria.exe <url>` / `open -a`), ולא
דרך מטפל הפרוטוקול של מערכת ההפעלה — בדיוק כמו התקנת תוסף
(`PluginDirectInstaller`), ומאותו טעם: התקנה ניידת אינה רושמת את הסכימה
`otzaria://` בכלל. מופע פתוח מקבל את הקישור דרך ה-single-instance של
אוצריא ולא נפתח שוב.

**מה לא מכוסה:** משתמש שפותח את אוצריא **לא** דרך הלאנצ'ר (קיצור דרך
בשולחן העבודה) לא מוסר את הבקשה, והסימון פשוט ממתין להזדמנות הבאה. זו
המחיר של פתרון מבוסס-קישור לעומת קריאת הקובץ; הבקשה המקורית, שכן קראה
אותו, נשמרה ב-[`OTZARIA_REINDEX_REQUEST.md`](../OTZARIA_REINDEX_REQUEST.md).

## מבנה

- `services/library_db_locator.dart` — איתור נתיב ה-DB (custom → ההגדרה של
  אוצריא → ספרייה מצורפת → ברירות מחדל → null).
- `services/otzaria_settings_reader.dart` — קריאת `app_preferences.hive` של
  אוצריא, מעותק.
- `services/companion_assets*.dart` — המראה וההתקנה של הקבצים הנלווים.
- `services/external_update_notice.dart` — סימון "המסד עודכן מבחוץ".
- `services/library_state_store.dart` — שמירת נתיב מותאם אישית ושל
  `appliedReleaseTag` (ה-release שממנו הגיע תוכן ה-DB — כך מזוהה מסד שפורסם
  מחדש באותו `db_version`).
- `services/library_update_applier.dart` — **`LibraryUpdateApplier`**: ההחלה
  בפועל של delta/fullDownload על ה-DB החי (patch/apply דרך `Isolate.run` נכון,
  סימון עדכון-שנקטע, בדיקת "אוצריא רצה").
- `services/otzaria_process_guard.dart` — בדיקת תהליך אוצריא פעיל: `otzaria.exe` דרך `tasklist` בווינדוס, `אוצריא` דרך `pgrep -x` ב-macOS.
- `services/zstd_decompressor.dart` — חילוץ zstd **בזיכרון**. מוזרק
  ל-`PatchDownloader` (קובצי patch, עשרות MB — סביר בזיכרון), וגם משמש כמסלול
  גיבוי לחילוץ ה-DB המלא.
- `services/zstd_file_decompressor.dart` — חילוץ zstd **בזרימה**, קובץ-לקובץ,
  דרך `ZSTD_decompressStream` של libzstd (ה-bindings של `zstandard_native`).
  זה המסלול הרגיל של ה-DB המלא: שיא הזיכרון הוא חוצצים בודדים ולא ~1.1GB.
  מחזיר `false` כשאין ספריית zstd לטעינה, ואז נופלים לחילוץ בזיכרון.
- `library_manager.dart` — האורקסטרטור. **מקור אחד בלבד:** `mirrorDir`
  (`<dataDir>/mirror/library`, לצד קובץ ההרצה). `downloadToMirror()` היא הפעולה
  היחידה שנוגעת ברשת; `checkForUpdate()` ו-`applyUpdate()` קוראות מהתיקייה
  המקומית תמיד, וזורקות `LibraryMirrorMissingException` אם היא עוד ריקה.
  אין נפילה לענן — ראו ה-landmine ב-AGENTS.md.

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
> `DeltaManifest`) — אותו דפוס שכבר עבד נכון ב-`ZstdFileDecompressor`.
>
> **ואז הבאג חזר, מסיבה שנייה ועדינה יותר.** לא מספיק שהסוגר עצמו אינו נוגע
> ב-`this`: דארט חולק אובייקט `Context` **אחד** בין כל הסוגרים שנוצרים באותו
> בלוק לקסיקלי — לא רק בין אלה שמשתמשים בפועל במשתנה מסוים
> ([dart-lang/sdk#52661](https://github.com/dart-lang/sdk/issues/52661),
> "Closures over-capture, cannot be sent to other isolate"). ב-`applyDelta`
> נוצר באותו בלוק גם סוגר ה-`onProgress` שמגיע מהצרכן, והוא סוגר-שרשרת על
> `LibraryModuleController` וממנו על עץ ה-widgets כולו. גם כשקוד הסוגר של
> ה-`Isolate.run` אינו מזכיר את `onProgress` בכלל, ה-`Context` המשותף כן
> מכיל אותו — והשליחה נכשלת.
>
> לכן קריאת ה-`Isolate.run` יושבת במתודה **נפרדת לגמרי** (`_runApplyIsolate`),
> ולא רק בסוגר נפרד: מתודה נפרדת = frame לקסיקלי נפרד = אין `Context` משותף
> עם ה-callbacks. ה-callbacks עצמם נשארים במתודה שמעליה
> (`_isolateApplyPatch`), ודיווח תת-השלבים חוזר מה-isolate דרך `ReceivePort`.
> **אין להחזיר את הקריאה ל-`Isolate.run` אל גוף `applyDelta`** — זה מחזיר
> בדיוק את הקריסה הזו.
> `LibraryManager.applyUpdate(check)`
> הוא נקודת הכניסה: מפעיל `OtzariaProcessGuard` (חוסם אם אוצריא פתוחה),
> מוריד ומחיל מסלול delta (patch-אחר-patch, כל אחד
> אטומי) או fullDownload (הורדה + חילוץ zstd + אימות + החלפה ב-rename),
> ומאמת את הגרסה הסופית מול `LocalDbVersionReader`.
>
> **אין גיבוי של המסד, ואין הגדרה כזו.** `LibraryDbRecoveryService` כותב
> סימון (`<db>.applying`) ולא יותר: מסלול patch עטוף ב-transaction יחיד
> שמתגלגל אחורה מעצמו, ומסלול המסד המלא מחלץ ל-`<db>.new`, מאמת אותו
> (`quick_check` + גרסה) ורק אז מחליף ב-rename — כלומר בשני המסלולים המסד
> החי שלם עד הרגע האחרון. עותק שני של ~1GB היה מכפיל את הדרישה מהכונן בלי
> להוסיף ביטחון. סימון שנשאר מריצה שקרסה נבדק בעלייה
> (`checkDbHealthAfterCrash`) ומנוקה; שאריות `.backup` מגרסאות קודמות
> נמחקות שם גם הן.
>
> **מסלול fullDownload צורך זיכרון קבוע.** בעבר הוא היה בזיכרון: הקובץ
> הדחוס נקרא במלואו, חולץ ל-`Uint8List` של ~1.1GB, וזה נשלח ל-`Isolate.run`
> שכתב אותו — כלומר עוד העתק של אותו GB, כי שליחה ל-isolate מעתיקה. היום
> ההורדה זורמת לדיסק (`PatchDownloader.downloadToFile`) והחילוץ זורם ממנו
> לקובץ `<db>.new` (`ZstdFileDecompressor`), וההחלפה היא `rename` באותו
> volume. `services/zstd_decompressor.dart` נשאר בשימוש לקובצי ה-patch
> וכמסלול גיבוי; `services/otzaria_process_guard.dart` נשאר בשימוש דרך
> `LibraryUpdateApplier`.
>
> `test/zstd_file_decompressor_test.dart` בודק את החילוץ בזרימה מול libzstd
> אמיתי (סבב 8MB מרובה-צ׳אנקים, קובץ קטוע, קובץ ריק). הוא מדלג את עצמו
> כשאין ספריית zstd לטעינה; ב-Windows יש להריץ עם התיקייה של
> `zstandard_windows.dll` ב-`PATH`, למשל
> `launcher_app/build/windows/x64/runner/Debug`.

## ⚠️ מה עדיין לא מאומת / סיכונים ידועים

1. **הקריאה מקופסת ה-Hive של אוצריא נבדקה מול קופסה שנכתבה בבדיקות בלבד**
   (`hive_ce`, אותה חבילה שאוצריא כותבת איתה) — לא מול `app_preferences.hive`
   של התקנה אמיתית, ולא במקביל לאוצריא פתוחה.
2. **הקבצים הנלווים לא נבדקו מקצה לקצה**: ההורדה נבדקה מול שרת מדומה בלבד
   ולא מול ה-API האמיתי של שלושת המאגרים, וההתקנה נבדקה על ארכיון
   `tar.zst` שנבנה בבדיקה — לא על `talmud_bavli_latest.tar.zst` אמיתי
   (מאות MB), ולא מול אוצריא שקוראת את התוצאה בפועל.
3. **בקשת עדכון האינדקס לא נבדקה מול אוצריא אמיתית.** הצד שלנו (הסימון,
   הקריאה, המחיקה אחרי מסירה, מסירת הקישור לקובץ ההרצה) מכוסה בבדיקות
   יחידה בלבד. מה שלא הורץ: `otzaria://library/reindex` מול התקנת אוצריא
   אמיתית אחרי עדכון מסד — כלומר שהאינדוקס בפועל מתחיל, שהוא באמת מאתר את
   הספרים שהשתנו, וכמה זמן `ReconcileIndex` לוקח על ספרייה מלאה. ראו
   "אינדקס החיפוש" למעלה.
4. **`LibraryUpdateApplier` לא נבדק בפועל על ווינדוס אמיתי** (הסביבה כאן
   היא Linux) — הלוגיקה נכתבה לפי ה-API המתועד של `seforim_library_updater`
   ועברה `dart analyze`, אך לא `flutter run` על DB אמיתי בגודל מלא. יש
   לבדוק בפועל: מסלול delta על שרשרת patches אמיתית, מסלול fullDownload
   על קובץ ~1GB, והתנהגות `OtzariaProcessGuard`/`tasklist` כשאוצריא פתוחה.
   החילוץ בזרימה עצמו **כן** אומת מול libzstd אמיתי ב-Windows (ראו
   `test/zstd_file_decompressor_test.dart`), אך לא על קובץ בסדר גודל של DB מלא.
5. **המסלול החלופי (`useFullDownloadFallback`) נבדק ביחידות בלבד** — בדיקה
   עם מסד זעיר בתיקייה זמנית. לא הורץ אחרי כשל דלתא אמיתי על מסד ~5.5GB,
   וגם לא נבדק שיש מקום פנוי לשני הקבצים בזמן ההחלפה.

## שימוש

```dart
final manager = LibraryManager(dataDir: r'C:\Users\me\AppData\Roaming\OurLauncher');

var check = await manager.checkForUpdate();
if (check.needsManualDbPath) {
  // הצג בחירת תיקייה למשתמש (native folder picker), ואז:
  await manager.setCustomDbPath(userChosenDbPath);
  check = await manager.checkForUpdate();
}

// התקנה טרייה יורדת אל `await manager.installDbPath()` — המיקום שאוצריא
// מחפשת בו. אם המשתמש בוחר אחר, חובה להזהיר: `isDbPathKnownToOtzaria`
// מחזיר false, ואוצריא לא תראה שם ספרים עד שיצביע על המיקום בהגדרות שלה.
if (!await manager.isDbPathKnownToOtzaria(manager.dbPathIn(userChosenDir))) {
  // ...דיאלוג אזהרה, ורק אחריו:
  await manager.setCustomDbPath(manager.dbPathIn(userChosenDir));
}

if (check.updateAvailable) {
  try {
    // מוריד ומחיל בפועל (delta או full) על ה-DB החי.
    await manager.applyUpdate(
      check,
      onProgress: (p) => print('${p.stage} ${p.bytesDone}/${p.bytesTotal}'),
    );
    print('ה-DB עודכן בהצלחה ל-${check.plan?.targetVersion}');
  } on OtzariaIsRunningException {
    print('סגור קודם את אוצריא ונסה שוב');
  } on LibraryApplyException catch (e) {
    print('העדכון נכשל: $e');
  }
}

// במחשב עם אינטרנט, לפני הכול — ממלא את התיקייה שלצד התוכנה:
// await manager.downloadToMirror(onStage: print);

manager.dispose();
```

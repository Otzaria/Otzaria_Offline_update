# בקשה לצוות אוצריא: לזהות עדכון מסד שנעשה מבחוץ, ולאנדקס אחריו

> ## ✅ נענתה — אבל אחרת. המסמך נשמר כרקע בלבד.
>
> אוצריא מימשה את הבקשה בענף `dev`, commit `78f395f3`
> ([issue #734](https://github.com/Otzaria/otzaria/issues/734#issuecomment-5251000659)),
> **לא** דרך קריאת הקובץ שמתואר כאן אלא דרך קישור עומק:
>
> ```text
> otzaria://library/reindex
> ```
>
> הוא מרענן את הקטלוג מהדיסק (`RefreshLibrary`, עם `requestIds` כדי שהאינדוקס
> ייקשר לרענון שקלט את הבקשה) ואז מריץ `StartIndexing` + `ReconcileIndex` —
> גם כש"עדכון אינדקס אוטומטי" כבוי. אין לו פרמטרים: `ReconcileIndex` משווה
> טביעות-אצבע ומזהה לבד אילו ספרים השתנו, ולכן `booksTouched` (§2 כאן) אינו
> נדרש. התיעוד שלהם: `docs/deep_links.md`.
>
> **מה זה שינה אצלנו:** `.otzaria-external-update.json` נשאר נכתב, אבל
> כסימון *שלנו* שבקשה ממתינה — לא כמסר לאוצריא. הלאנצ'ר מוסר את הקישור
> לקובץ ההרצה שזוהה (יזום מהמסך, וגם בכל הפעלה רגילה של אוצריא), ומוחק את
> הסימון רק אחרי מסירה שהצליחה. הפירוט:
> [`library_manager/README.md`](library_manager/README.md), "אינדקס החיפוש".
>
> **הפער שנשאר:** מי שפותח את אוצריא לא דרך הלאנצ'ר אינו מוסר את הבקשה. אם
> יום אחד ייקלט גם המסלול של §3 כאן (קריאת הקובץ בעלייה), הפער הזה ייסגר —
> ולכן המסמך לא נמחק.

---

מסמך אחד, מוכן להעברה. הצד שלנו (הלאנצ'ר הלא-מקוון) כבר עושה את כל מה
שהוא יכול; מה שנשאר הוא **חיווט אחד** בצד אוצריא — כל התשתית שהוא צריך
כבר קיימת ועובדת אצלכם במסלול המקוון.

**הריפו: [`Otzaria/otzaria`](https://github.com/Otzaria/otzaria), ענף
ברירת המחדל `dev`** (לא `main` — שם הקוד ישן ואין בו את התשתית הזאת בכלל).
לא `SeforimLibrary` ולא `otzaria_library_updater`: שניהם בסדר כמו שהם.
כל שמות הקבצים, החתימות ומספרי השורות במסמך אומתו מול `dev` בגרסה
`cd1dc942` (2026-08-09).

---

## 1. מה הבעיה

אוצריא של משתמש לא-מקוון מתעדכנת דרך הלאנצ'ר שלנו: מחשב מקוון מוריד
`seforim.db` + patches + הקבצים הנלווים לכונן נייד, והלאנצ'ר במחשב
הלא-מקוון מחיל אותם על ה-DB החי — אותו מנוע בדיוק
(`PatchApplier` / `otzaria_library_updater`), אותם דגלים, אותו אימות hash.

כשאוצריא מעדכנת **בעצמה**, מה שקורה אחרי apply מוצלח הוא
(`lib/navigation/view/main_window_screen.dart:2230-2250`):

```dart
if (state.status == LibraryUpdateStatus.completed && state.hasUpdate) {
  _indexAfterLibraryReload = true;
  _reconcileAfterLibraryReload = state.isFullDownloadPlan;
  context.read<LibraryBloc>().add(
    RefreshLibrary(
      changedBookKeys: {
        for (final id in state.changedBookIds)
          IndexingRepository.officialBookKey(id),
      },
    ),
  );
}
```

עדכון שנעשה **מבחוץ** לא עובר שם, ולכן אף אחד לא יודע שהתוכן התחלף. זה לא
פער תיאורטי — הוא נובע משתי עובדות בקוד:

1. `booksDone` נשמר לדיסק, ו-`IndexingRepository.isBookIndexed(book)` בודק
   **נוכחות מפתח** (`catalogueOrderKey` → `officialBookKey(id)` → `'id:$id'`,
   `indexing_repository.dart:1153`). אין שם שום השוואת תוכן, ולכן ספר
   שתוכנו התחלף במסד נשאר "מאונדקס" ו-`StartIndexing` מדלג עליו.
2. `requiresManualReindex` תלוי בסכמת ה-tantivy, לא בגרסת המסד — ולכן
   `decideStartupIndexing` בעלייה שאחרי העדכון יחזיר `startIndexing` או
   `checkIndexStatus`, ולא `autoReindexThenStart`.

**התוצאה בפועל:** חיפוש בספר שתוכנו עודכן מחזיר תוכן ישן, בלי שום
אינדיקציה למשתמש, עד אינדוקס מלא ידני.

אגב, `docs/seforim_library_delta_update_plan.md` שלכם מזכיר את זה כעבודה
עתידית ("בעתיד אפשר להשתמש ב-booksTouched"). מאז היא נעשתה — `ReindexChangedBooks`
ו-`ReconcileIndex` קיימים ומחווטים. נשאר רק לחבר אליהם את המקרה החיצוני.

---

## 2. מה אנחנו כבר כותבים בשבילכם

בסוף כל `applyUpdate` מוצלח הלאנצ'ר כותב **לצד `seforim.db`** את הקובץ:

```
.otzaria-external-update.json
```

זו אותה תיקייה שמחזיר `DatabaseConstants.getDatabasePath` — הלאנצ'ר מאתר
אותה מ-`key-library-path` + `key-library-folder-name` בקופסת ה-Hive
`app_preferences` שלכם (מעותק, כדי לא ליצור נעילה), ולכן זה תמיד ה-DB
שאוצריא באמת פותחת, גם למי שהעביר את הספרייה לכונן אחר.

```json
{
  "formatVersion": 1,
  "source": "otzaria-launcher",
  "updatedAt": "2026-08-10T09:14:22.183Z",
  "route": "delta",
  "dbVersion": 1024,
  "releaseTag": "v1024",
  "booksTouched": [17, 233, 981, 1204]
}
```

| שדה | משמעות |
| --- | --- |
| `formatVersion` | `1`. ערך אחר — התעלמו מהקובץ, **בלי למחוק**. |
| `source` | תמיד `otzaria-launcher`. |
| `route` | `"delta"` — יש רשימת ספרים מדויקת. `"full"` — הורדת DB מלא, אין רשימה. |
| `dbVersion` | ה-`db_version` שאליו הגענו. |
| `releaseTag` | תג ה-release שממנו הגיע התוכן. |
| `booksTouched` | **בדיוק** אותם `int`-ים שנכנסים אצלכם ל-`LibraryUpdateState.changedBookIds` — שניהם באים מ-`PatchApplier`. ריק במסלול `full`. |

שלוש התנהגויות שכדאי להכיר:

- **הקובץ מצטבר.** שני עדכונים לפני שאוצריא נפתחה → הרשימות מתמזגות ולא
  נדרסות. `route: "full"` מנצח בכל מיזוג (הוא גורף ממילא).
- **הכתיבה best-effort.** כשל בכתיבה לא מבטל עדכון שהצליח, ולכן הקוד
  הקורא חייב לסבול היעדר קובץ / JSON פגום בשקט.
- **המחיקה באחריותכם.** אנחנו רק כותבים. כל עוד לא נמחק, הבקשה תחזור
  בכל עלייה — וזה מכוון.

המימוש שלנו:
[`external_update_notice.dart`](library_manager/lib/src/services/external_update_notice.dart).

---

## 3. מה צריך לעשות

אין צורך ב-event חדש, ב-API חדש או בשינוי ב-`IndexingRepository`. הכול
קיים; חסר רק מי שקורא את הקובץ ומזין את המסלולים שכבר בנויים.

### 3.1 קורא לקובץ

קובץ חדש, למשל
`lib/library_update/services/external_update_notice_reader.dart`: קורא את
ה-JSON מתיקיית ה-DB ומחזיר `route` + `Set<int> booksTouched`, `null` בכל
כשל; ועוד `Future<void> clear()` שמוחק אותו.

### 3.2 החיווט — ב-`_resolveStartupIndexing`

הנקודה: `lib/navigation/view/main_window_screen.dart:902`, בתוך
`_resolveStartupIndexing` (נקרא מ-`_checkAndStartIndexing:826`, שמופעל
מה-`BlocListener<LibraryBloc>` שבשורה 2251 — כלומר **אחרי** שהספרייה
נטענה). זה בדיוק התנאי שנדרש: הקטלוג כבר נבנה מה-DB החדש.

הבדיקה נכנסת אחרי `requiresManualReindex` ולפני `decideStartupIndexing`:

```dart
final notice = await ExternalUpdateNoticeReader().read();

// אם ממילא צריך איפוס מלא של האינדקס — הוא גורף גם את מה שהעדכון שינה.
if (notice != null && !requiresManualReindex) {
  // הפורטה חייבת להיפתח גם במסלול הזה, אחרת עבודות ה-startup
  // המושהות (סנכרון רקע, StartLibraryUpdate) לא ירוצו כלל.
  _startupWorkGate.markIndexingDecisionResolved(expectIndexing: autoUpdateIndex);
  _tryStartDeferredStartupWork();

  if (!autoUpdateIndex) {
    // כמו promptManualReindex — לשאול, לא לאנדקס בשקט.
    await _showExternalUpdateReindexDialog(context, library, notice);
    return;
  }

  final indexingBloc = context.read<IndexingBloc>();

  if (notice.route == 'full') {
    // אותו זוג בדיוק כמו ב-_indexAfterDbUpdateIfNeeded:890-898 —
    // StartIndexing לספרים חדשים, ReconcileIndex למה שהשתנה.
    indexingBloc.add(StartIndexing(library));
    indexingBloc.add(ReconcileIndex(library));
  } else {
    final changedKeys = {
      for (final id in notice.booksTouched)
        IndexingRepository.officialBookKey(id),
    };
    final changedBooks = library
        .getAllBooks()
        .where(IndexingRepository.isIndexableBook)
        .where(
          (b) => changedKeys.contains(IndexingRepository.catalogueOrderKey(b)),
        )
        .toList();
    if (changedBooks.isNotEmpty) {
      indexingBloc.add(ReindexChangedBooks(changedBooks, library));
    }
  }
  return; // לא ממשיכים ל-decideStartupIndexing בעלייה הזאת
}
```

**למה לא `RefreshLibrary(changedBookKeys:)` כמו במסלול המקוון?** כי במסלול
המקוון הקטלוג בזיכרון עוד מתאר את ה-DB הישן, ולכן צריך רענון. בעלייה
שאחרי עדכון חיצוני הקטלוג **כבר** נבנה מה-DB החדש, ו-`RefreshLibrary`
היה סתם בונה אותו שוב. שני היעדים זהים: `RefreshLibrary` רק ממפה מפתחות
לספרים (`library_bloc.dart:208-217`) ומזין את `changedBooksToIndex`,
שה-listener שבשורה 2280 הופך ל-`ReindexChangedBooks` — בדיוק ה-event
שהקוד למעלה שולח ישירות. (מי שמעדיף בכל זאת לעבור במסלול הגנרי, ישלח
`RefreshLibrary(changedBookKeys: changedKeys)` ויקבל את אותה תוצאה במחיר
בנייה אחת מיותרת של הקטלוג.)

### 3.3 מחיקת הקובץ — רק אחרי הצלחה

להאזין ל-`IndexingBloc` (יש כבר listener כזה בשורה 2318) ולמחוק את הקובץ
כשהעבודה הסתיימה בהצלחה, לפי ה-`workId` שחזר. **לא** למחוק מיד עם
השליחה: אינדוקס שנקטע (סגירה, ביטול, קריסה) חייב להשאיר את הקובץ, אחרת
האינדקס נשאר על התוכן הישן ואף אחד לא ידע. הצטברות היא ההתנהגות הבטוחה.

במקרה של `requiresManualReindex` (שנבלע בתנאי למעלה) — אפשר למחוק מיד
כשהאיפוס המלא הסתיים, כי הוא גורף ממילא.

---

## 4. פרטים שכדאי לא לפספס

- **אל תשתמשו ב-`StartIndexing` לבד במסלול `delta`.** הוא מדלג על ספרים
  שכבר ב-`booksDone` — כלומר בדיוק על הספרים שהשתנו.
- **אל תקראו ל-`clearIndex()`.** אינדוקס מלא מאפס על ~5.5GB הוא שעות; כל
  הפואנטה של `booksTouched` היא להימנע מזה.
- **`_startupWorkGate` הוא מלכודת אמיתית.** כל ענף שיוצא מ-
  `_resolveStartupIndexing` בלי `markIndexingDecisionResolved` +
  `_tryStartDeferredStartupWork` משאיר את `consumeStartPermission()`
  סגור לנצח, ואיתו את סנכרון הרקע ואת `StartLibraryUpdate`.
- **`IndexingBloc` מריץ `IndexingWorkEvent` עם `transformer: sequential()`**,
  ולכן `StartIndexing` ואחריו `ReconcileIndex` בטוח — זה מה שהקוד הקיים
  עושה בשורות 890-898.
- **מזהה שלא נמצא בספרייה — התעלמו.** ספר שהוסר בעדכון פשוט לא יימצא;
  `DropOrphanedIndexEntries` (שרץ ממילא בכל טעינת ספרייה, שורה 2267)
  מטפל בשאריות שלו.
- **כבדו את `autoUpdateIndex`**, כמו שעושים ה-listeners בשורות 2286 ו-890.
  בדיאלוג אפשר הפעם לומר מה באמת קרה: "הספרייה עודכנה, N ספרים דורשים
  אינדוקס מחדש".
- **`formatVersion` לא מוכר → התעלמות בלי מחיקה.** נעלה גרסה רק אם נוסיף
  שדות; מחיקה של קובץ שלא הובן מאבדת מידע.
- **גרסת המסד לא צריכה טיפול.** `LocalDbVersionReader` קורא את
  `db_version` מה-DB עצמו, ולכן אוצריא מזהה את הגרסה החדשה לבד ולא תציע
  את העדכון שוב.
- **הקבצים הנלווים כבר מטופלים.** הלאנצ'ר מתקין את התלמוד הבבלי, קטלוג
  otzar-HB ומילון החיפוש לאותם יעדים ועם אותם סימוני-גרסה ש-
  `CompanionAssetsService` בודק, כך ש-`verifyAndUpdate()` יראה אותם
  מעודכנים ולא ינסה להוריד מרשת שאינה קיימת.
- **אין צורך ב-`LibraryRuntimeRefreshService`.** הלאנצ'ר מסרב לעדכן
  כשאוצריא פתוחה (`tasklist` בווינדוס, `pgrep -x` ב-macOS), ולכן העדכון
  תמיד נראה מאוצריא כמסד חדש בעלייה נקייה.

---

## 5. מפת הקבצים (`Otzaria/otzaria`, ענף `dev`)

| קובץ:שורה | תפקידו בבקשה |
| --- | --- |
| `lib/navigation/view/main_window_screen.dart:902` | `_resolveStartupIndexing` — **נקודת החיווט**. |
| `…:826` / `…:2251-2279` | `_checkAndStartIndexing` וה-listener שמפעיל אותו אחרי טעינת הספרייה. |
| `…:2230-2250` | המסלול המקוון המקביל — התבנית להעתיק ממנה. |
| `…:2280-2295` | `changedBooksToIndex` → `ReindexChangedBooks`. |
| `…:875-900` | `_indexAfterDbUpdateIfNeeded` — הזוג `StartIndexing` + `ReconcileIndex`. |
| `lib/navigation/view/startup_work_gate.dart` | `StartupWorkGate` — ראו המלכודת ב-§4. |
| `lib/navigation/startup_indexing_decision.dart` | `decideStartupIndexing` — הבדיקה החדשה נכנסת לפניו. |
| `lib/indexing/bloc/indexing_event.dart:36,48` | `ReindexChangedBooks`, `ReconcileIndex` — קיימים. |
| `lib/indexing/repository/indexing_repository.dart:1153` | `officialBookKey(int id)` → `'id:$id'`; וגם `catalogueOrderKey`, `isIndexableBook`, `reindexChangedBooks`, `reconcileIndexWithLibrary`, `dropBookIndexEntries`. |
| `lib/library/bloc/library_bloc.dart:208-217` | מיפוי `changedBookKeys` → `changedBooksToIndex`. |
| `lib/library_update/services/companion_assets_service.dart` | הקבצים הנלווים; לא נדרש שינוי, ראו §4. |

---

## 6. למה זה לא ניתן לפתרון מהצד שלנו

`booksDone` ואינדקס ה-tantivy הם מבנים פנימיים של אוצריא, וכתיבה אליהם
מבחוץ הייתה עוקפת את המנגנון שלכם — בדיוק כמו שחילוץ `.otzplugin` ידני
עוקף את רישום הפלאגינים (ולכן אנחנו מתקינים פלאגינים רק דרך
`otzaria://plugin/install-local`). לכן הצד שלנו נעצר בכתיבת עובדה מדויקת
לדיסק, והבקשה היא לקרוא אותה.

הריפו שלנו: [`Yehuda-Zakesh/Otzariya_update`](https://github.com/Yehuda-Zakesh/Otzariya_update).
הפער מתועד אצלנו ב-`library_manager/README.md`, סעיף
"אינדקס החיפוש — פער שנשאר פתוח מול אוצריא".

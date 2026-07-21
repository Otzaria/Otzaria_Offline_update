# תוכנית עבודה — חבילת `seforim_library_updater`

מסמך זה מתאר איך מוציאים את מנגנון עדכון הספרייה (שנמצא היום ב‑`otzaria/lib/library_update/`)
לחבילת **Dart טהורה** ועצמאית, ואיך מחברים את אפליקציית Otzaria אליה בלי לשנות התנהגות.

> **גרסה 2** — שולבו 7 שיפורים מסבב ביקורת: חבילת Dart טהורה (לא Flutter), barrel עם
> `show`, fixtures לחוזה מול Kotlin, יישור גרסאות, שלב baseline, החלטת היסטוריית git, ותיעוד
> פעולות חוסמות.

---

## 1. רקע — מה בעצם בנינו, ולמה זה מתאים לחבילה

מאגר הספרים `Otzaria/SeforimLibrary` (כתוב ב‑Kotlin) הוא ה**יצרן**: הוא בונה את קובץ ה‑DB
המלא (`seforim.db.zst`) ואת קובצי ההפרש (`patch-vX-vY.db.zst`) בין גרסאות, יחד עם קובץ
מניפסט (`*.manifest.json`) שמתאר כל הפרש.

הקוד שכתבנו ב‑Otzaria הוא ה**צרכן** של אותו פורמט: הוא מוריד את ההפרשים, מאמת אותם,
מחיל אותם על ה‑DB המקומי, ומוודא שהתוצאה זהה למה שה‑Kotlin התכוון אליו. שני רכיבים מתוך
הקוד הזה הם תרגום ישיר של לוגיקת ה‑Kotlin ל‑Dart, והם חייבים להסכים איתה בית‑בית:

1. **`LogicalContentHasher`** — חישוב טביעת‑אצבע (hash) לוגית של תוכן ה‑DB. תרגום מדויק של
   `LogicalContentHasher.kt`. כאן נמצא מלכוד ה‑BOM הקריטי (תו U+FEFF בתחילת טקסט שה‑decoder
   של Dart בולע) — אם מישהו ישנה את אופן קריאת העמודות, ה‑hash יפסיק להתאים ל‑Kotlin וכל
   עדכון יידחה. (ראה זיכרון: `library-update-delta-system`.)
2. **`PatchApplier`** — סדר טבלאות לפי תלויות מפתח‑זר (foreign key), סמנטיקת טרנזקציה,
   ואימות ש‑hash התוצאה שווה ל‑`toContentHash` שבמניפסט.

**המסקנה המעשית:** המנוע הזה (אלגוריתמים + מודלים של הפורמט) הוא הקוד ש"מדבר עם הפורמט של
SeforimLibrary". הוא אינו תלוי באפליקציית Otzaria — לא ב‑Flutter, לא ב‑BLoC, לא במסכים.
הוצאה לחבילת **Dart core טהורה** נותנת לו בית עצמאי, נבדק‑בנפרד, וברור — שזו בדיוק החוזה
(contract) של צד ה‑Dart מול פורמט הפצות SeforimLibrary.

> **תיקון קל בניסוח:** זה אינו "תחליף למודול הקוטלין". הקוטלין ממשיך ליצור את ה‑DB
> וההפרשים; מה שבנינו הוא ה**מקבילה הצורכת** בצד הלקוח — מימוש Dart שחייב להסכים עם הקוטלין
> בשני החוזים שלמעלה.

### למה דווקא חבילה (ולא תיקייה רגילה)?
- **גבול נקי ונאכף:** מנתח ה‑Dart יכשל אם מישהו ינסה בטעות לייבא ב‑hasher משהו מ‑Otzaria
  או מ‑Flutter. היום אין דבר שמונע זאת.
- **בדיקה בבידוד:** את החוזה מול הקוטלין אפשר לבדוק עם `dart test` בלבד, בלי לבנות את Flutter.
- **שימוש חוזר:** כל אפליקציית Dart/Flutter שתצרוך הפצות SeforimLibrary תוכל להוסיף את החבילה.

---

## 2. קו‑החיתוך המדויק — מה עובר ומה נשאר

מיפוי ה‑imports אומת בפועל. **אף אחד מהקבצים "הטהורים" לא מייבא `package:otzaria/` או
`package:flutter/`.** רק שלושה קבצים קושרים ל‑Otzaria.

### 2א. עובר לחבילה — "המנוע" (12 קבצים, ~1,764 שורות)

| קובץ | תלויות חיצוניות | תפקיד |
|------|------------------|--------|
| `models/delta_manifest.dart` | equatable | מבנה המניפסט של ההפרש |
| `models/library_release.dart` | equatable | מודל release/asset של GitHub |
| `models/library_update_plan.dart` | equatable | תוכנית עדכון (none/delta/full/blocked) |
| `models/patch_table_spec.dart` | — | שתי רשימות הטבלאות (סדר FK לעומת סדר hash) |
| `services/github_library_release_client.dart` | http | קריאת releases מ‑GitHub (pagination) |
| `services/library_db_recovery_service.dart` | dart:io/isolate/convert | גיבוי/marker/שחזור אטומי |
| `services/library_update_discovery.dart` | — | איסוף releases וזיהוי הגרסה האחרונה |
| `services/library_update_planner.dart` | — | בחירת מסלול (Dijkstra) בין גרסאות |
| `services/local_db_version_reader.dart` | sqlite3 | קריאת `schema_meta` במצב read‑only |
| `services/logical_content_hasher.dart` | crypto, sqlite3 | **תרגום הקוטלין** — hash לוגי |
| `services/patch_applier.dart` | sqlite3 | החלת הפרש אטומית + אימות hash |
| `services/patch_downloader.dart` | http, crypto, path | הורדה, אימות sha256/גודל; **חילוץ מוזרק** |

**תלויות החבילה (סך הכול):** `equatable`, `http`, `crypto`, `path`, `sqlite3` — **כולן חבילות
Dart טהורות**. אין `flutter`, אין `bloc`, אין `zstandard`/`zstandard_native`/`ffi`.

### 2ב. נשאר ב‑Otzaria — "דבק האפליקציה" (5 קבצים, ~789 שורות)

| קובץ | למה נשאר |
|------|-----------|
| `bloc/library_update_bloc.dart` | שכבת BLoC + UI; תלוי ב‑`flutter_bloc` |
| `bloc/library_update_event.dart` | חלק מה‑BLoC |
| `bloc/library_update_state.dart` | חלק מה‑BLoC |
| `services/library_runtime_refresh_service.dart` | תלוי ב‑`otzaria/core/app_runtime_reset` + providers |
| `repository/library_update_repository.dart` | ה**מתזמר** — קשור קשיח ל‑3 רכיבי Otzaria |

ה‑**orchestrator** (`LibraryUpdateRepository`) נשאר מפני שיש לו שלוש תלויות קשיחות באפליקציה:
1. `DatabaseLibraryProvider.operationQueue` — תור הסריאליזציה של פעולות ה‑DB.
2. `SqliteDataProvider.instance.closeForExternalWrite()/reopenAfterExternalWrite()`.
3. `refreshService.refreshAfterDbUpdate()` — ריענון ה‑runtime (ספציפי ל‑Otzaria).

הוא גם מגדיר טיפוסים שנשארים איתו: `LibraryUpdatePhase`, `LibraryUpdateProgress`,
`LibraryUpdateProgressCallback`, `FullDbExtractor`, וממשק `LibraryUpdateService`.

### 2ג. zstd — הופך לתלות מוזרקת (שיפור מהותי)

היום `patch_downloader` מייבא `package:zstandard` ישירות, מה שהיה הופך את החבילה ל‑Flutter
package. אבל `PatchDownloader` כבר מקבל פונקציית `decompress` בהזרקה. לכן:

- **בחבילה:** הופכים את `decompress` לפרמטר **חובה**, מוחקים את `import 'package:zstandard'`
  ואת שדה `_zstandard`/ברירת המחדל. החבילה הופכת ל‑Dart core טהורה.
- **ב‑Otzaria:** ב‑[main.dart:1112](../otzaria/lib/main.dart) מזריקים מתאם קטן:
  ```dart
  downloader: PatchDownloader(
    decompress: (bytes) => Zstandard().decompress(bytes),
  ),
  ```
  (חילוץ חד‑פעמי בזיכרון, ל‑patches הקטנים.)

החילוץ ה**זורם** (FFI דרך `zstandard_native`, ל‑DB המלא ~1.1GB) נשאר ב‑Otzaria
(`zstd_stream_extractor.dart`, משותף עם onboarding) ומוזרק כ‑`FullDbExtractor` ל‑orchestrator.
כך **שני** סוגי ה‑zstd נשארים בצד Otzaria, והחבילה אגנוסטית לחילוץ לחלוטין.

---

## 3. שם החבילה ומבנה התיקיות

**שם מומלץ:** `seforim_library_updater` (החבילה אגנוסטית ל‑Otzaria במכוון — שם `seforim_*`
ישר יותר). חלופה לעקביות עם החבילות האחיות: `otzaria_library_update`. החלפת מחרוזת בשורה אחת.

מבנה (קונבנציית Dart: API ציבורי דרך barrel‑file אחד, פנימיות תחת `lib/src/`):

```
seforim_library_updater/
├── pubspec.yaml
├── README.md            ← כולל אזהרת "פעולות חוסמות — הרץ ב‑Isolate" (ראה §7)
├── CHANGELOG.md
├── LICENSE
├── analysis_options.yaml
├── lib/
│   ├── seforim_library_updater.dart      ← barrel: export ... show ... (לא הכול!)
│   └── src/
│       ├── models/        (4 הקבצים מ‑2א)
│       └── services/      (8 הקבצים מ‑2א)
└── test/                  ← הבדיקות שעוברות; fixtures inline (DB בזיכרון): golden + BOM
```

> **תכונה שמפשטת הכול:** הקבצים עוברים מ‑`library_update/{models,services}` אל
> `lib/src/{models,services}` — **המבנה היחסי בין `models/` ל‑`services/` נשמר זהה.** לכן כל
> ה‑imports ה**יחסיים** הפנימיים נשארים תקפים ללא שינוי. עורכים imports **רק בצד Otzaria**.

---

## 4. `pubspec.yaml` של החבילה (חבילת Dart טהורה)

```yaml
name: seforim_library_updater
description: >-
  לקוח Dart לצריכת הפצות הדלתא של Otzaria/SeforimLibrary — גילוי, תכנון מסלול,
  הורדה, אימות hash לוגי, והחלה אטומית של הפרשי DB.
version: 0.1.0
publish_to: none

environment:
  sdk: ">=3.2.6 <4.0.0"      # מיושר ל‑Otzaria

dependencies:
  equatable: ^2.0.8
  crypto: ^3.0.7
  path: ^1.9.1
  http: ^1.6.0
  sqlite3: ^3.3.3

dev_dependencies:
  test: ^1.30.1              # מיושר ל‑Otzaria
  lints: ^4.0.0             # מקבילת ה‑Dart הטהורה; ^5 דורש Dart ≥3.5 ומתנגש ב‑sdk ≥3.2.6
```

> **יישור גרסאות (חשוב לתלות path):** ה‑SDK וה‑`test` מועתקים מ‑`otzaria/pubspec.yaml`
> (`>=3.2.6 <4.0.0`, `test: ^1.30.1`). Otzaria משתמש ב‑`flutter_lints: ^6.0.0`; חבילת Dart
> טהורה משתמשת ב‑`lints` הישיר (flutter_lints 6 ממילא בנוי על lints 5). אם resolution ייכשל —
> ליישר גרסאות מדויק.

> **sqlite3 בבדיקות:** `dart test` צריך ספריית `libsqlite3` מקומית. ב‑macOS היא קיימת מערכתית
> ונמצאת אוטומטית. ב‑CT אחר ייתכן שיידרש להתקין sqlite. בדיקות שנוגעות ב‑DB ממילא מוגנות
> (ראה שלב 2).

---

## 5. שלבי הביצוע

כל שלב מסתיים ב**שער אימות** (`analyze` נקי + הבדיקות הרלוונטיות עוברות). לא ממשיכים עם שגיאה.

### שלב 0 — baseline לפני נגיעה בקוד
```bash
cd otzaria && flutter test test/library_update/
```
לתעד שהכול ירוק **לפני** ההוצאה. כך כל כשל אחרי ההוצאה מיוחס בוודאות להוצאה, לא לכשל קיים.

**שער:** כל בדיקות `test/library_update/` עוברות במצב הנוכחי.

### שלב 1 — שלד החבילה
1. ליצור: `pubspec.yaml` (§4), `analysis_options.yaml`, `README.md` (כולל אזהרת §7),
   `CHANGELOG.md`, `LICENSE`, ו‑`lib/src/{models,services}/` ריקים + barrel ריק.
2. `cd seforim_library_updater && dart pub get` — חייב לעבור.

**שער:** `dart pub get` מצליח.

### שלב 2 — העברת קבצי המנוע + ניתוק zstd
1. להעביר את 12 הקבצים מ‑2א ל‑`lib/src/{models,services}/`. **לא לגעת ב‑imports היחסיים**.
2. **לנתק את zstd מ‑`patch_downloader.dart`** (§2ג): להפוך `decompress` לחובה, להסיר
   `import 'package:zstandard'`, את שדה `_zstandard` ואת ברירת המחדל `_zstandard.decompress`.
3. למלא barrel **עם `show`** — חושפים רק API ציבורי, לא helpers. עיקרון: ה‑API = הטיפוסים
   שה‑orchestrator + ה‑BLoC + הבדיקות צורכים. דוגמה ל‑helper שלא ייחשף: `cloneOrCopyFile`
   ב‑`library_db_recovery_service.dart` (פונקציה top‑level לשימוש פנימי). הוא נשאר top‑level
   (כדי שבדיקות יוכלו לייבא אותו ישירות מ‑`src/`), אך **לא** נכלל ב‑`show` של ה‑barrel.
   ```dart
   // טיוטה — לאמת מול הצרכנים בפועל בעת הביצוע:
   export 'src/models/delta_manifest.dart';
   export 'src/models/library_release.dart';
   export 'src/models/library_update_plan.dart';
   export 'src/models/patch_table_spec.dart';
   export 'src/services/github_library_release_client.dart' show GithubLibraryReleaseClient;
   export 'src/services/library_db_recovery_service.dart'
       show LibraryDbRecoveryService, RecoveryResult, RecoveryAction, BackupIntegrityException;
   export 'src/services/library_update_discovery.dart' show LibraryUpdateDiscovery, DiscoveryResult;
   export 'src/services/library_update_planner.dart' show LibraryUpdatePlanner;
   export 'src/services/local_db_version_reader.dart' show LocalDbVersionReader;
   export 'src/services/logical_content_hasher.dart' show LogicalContentHasher;
   export 'src/services/patch_applier.dart' show PatchApplier;
   export 'src/services/patch_downloader.dart'
       show PatchDownloader, PatchDownloadException, PatchDownloadCancelled;
   ```

**שער:** `dart analyze` בחבילה — נקי לחלוטין.

### שלב 3 — בדיקות המנוע: fixtures + העברה
1. **fixtures לחוזה (inline בזיכרון):** בדיקות הבונות DB זעירים ב‑`openInMemory`, כולל:
   מקרה BOM (עמודת טקסט שמתחילה ב‑U+FEFF), `golden hash` קבוע, ו‑apply מלא של patch אחד
   (כבר קיים ב‑`patch_applier_test`). ה‑golden נלקח מהרצת ה‑hasher המאומת (שכבר אומת מול
   Kotlin על שרשרת v14/v15). שכבת ה‑fixtures לוכדת **רגרסיה** ב‑CI גם בלי גישה ל‑DB האמיתיים.
2. **release DBs אמיתיים → env‑gated:** להמיר את הנתיב הקשיח
   `/Users/david/Downloads/releases` (ב‑`patch_applier_test.dart:271` ו‑
   `logical_content_hasher_test.dart:66`) למשתנה סביבה `SEFORIM_LIBRARY_RELEASES_DIR`;
   אם אינו מוגדר — לדלג (skip), לא לקודד נתיב מכונה.
3. להעביר ל‑`test/` את 7 קבצי הבדיקה הטהורים (~1,182 שורות) ולהחליף בהם
   `import 'package:otzaria/library_update/...'` ב‑`package:seforim_library_updater/...`
   (בדיקות שצריכות helper פנימי מייבאות `package:seforim_library_updater/src/...`).

**שער:** בחבילה — `dart test` עובר (fixtures רצים תמיד; בדיקות ה‑release רצות אם
`SEFORIM_LIBRARY_RELEASES_DIR` מוגדר).

### שלב 4 — חיבור Otzaria ומחיקת הישנים
1. `otzaria/pubspec.yaml` → תחת `dependencies` (כמו `otzaria_search_engine`):
   ```yaml
   seforim_library_updater:
     path: ../seforim_library_updater
   ```
2. **למחוק** את 12 קבצי המנוע מ‑`otzaria/lib/library_update/`; להשאיר `bloc/`,
   `repository/library_update_repository.dart`, `services/library_runtime_refresh_service.dart`.
3. לעדכן imports בקבצים שנשארו:
   - `repository/library_update_repository.dart`: 6 ה‑`import '../services/...'` +
     `import '../models/library_update_plan.dart'` → ייבוא barrel בודד.
     **לשמר** `import '../services/library_runtime_refresh_service.dart'` (מקומי).
   - `bloc/library_update_bloc.dart`: `library_update_plan` + `patch_downloader` → barrel.
   - שתי בדיקות שנשארות (`..._bloc_test`, `..._repository_test`): ייבוא ה‑models/services → barrel.
4. **`main.dart:1112`** — להזריק את ה‑decompress ולהוסיף `import 'package:zstandard/zstandard.dart'`:
   ```dart
   downloader: PatchDownloader(decompress: (b) => Zstandard().decompress(b)),
   ```
5. `cd otzaria && flutter pub get`.

**שער:** `flutter analyze` נקי בכל Otzaria.

### שלב 5 — אימות סופי (שני הצדדים)
```bash
cd ../seforim_library_updater && dart analyze && dart test
cd ../otzaria && flutter analyze
flutter test test/library_update/ test/empty_library/ test/utils/file/
```
התנהגות זהה ל‑baseline משלב 0 — רק כתובות הקוד השתנו.

---

## 6. נקודות סיכון ומלכודות

1. **חוזה ה‑hash מול Kotlin — לא לגעת בלוגיקה.** ההוצאה היא העברת קבצים בלבד; אסור לשנות שורה
   ב‑`logical_content_hasher.dart` (במיוחד קריאת TEXT כ‑`CAST AS BLOB` ששומרת BOM).
2. **ניתוק zstd — לוודא שאין שימוש בברירת מחדל שנעלמה.** אחרי הפיכת `decompress` לחובה, כל יצירת
   `PatchDownloader` חייבת לספק `decompress`. ב‑Otzaria יש נקודה אחת בלבד (`main.dart:1112`).
3. **sqlite3 native ב‑`dart test`.** ב‑macOS קיים מערכתית. בדיקות הנוגעות ב‑DB מוגנות (fixtures
   קטנים תמיד; release אמיתי env‑gated).
4. **תאימות גרסאות תלות path.** SDK/`test`/`sqlite3`/`http`/`crypto` חייבים לתאום בין שני
   ה‑pubspec — אחרת `pub get` ייכשל. הועתקו מ‑Otzaria.
5. **לא לשבור onboarding.** `zstd_stream_extractor.dart` נשאר ב‑Otzaria; אין לבלבל בינו ל‑
   `package:zstandard`. ה‑`FullDbExtractor` ממשיך מוזרק ל‑orchestrator.

---

## 7. דרישת תיעוד — פעולות חוסמות (חובה ב‑README/doc‑comments)

`PatchApplier.apply` ו‑`LogicalContentHasher.compute` הם **סינכרוניים וכבדים** (ה‑hash ~42 שניות
על DB מלא). ב‑Otzaria הם רצים ב‑`Isolate.run` בתוך תור פעולות ה‑DB, וכך **חייב** להישאר.
החבילה לא כופה Isolate (זו החלטת המתזמר), אך ה‑README ו‑doc‑comments של שתי הפונקציות חייבים
לכלול אזהרה מפורשת: **"פעולה חוסמת — אל תריץ על ה‑UI isolate; עטוף ב‑`Isolate.run`."**

---

## 8. החלטות פתוחות (להכריע לפני/בתחילת הביצוע)

1. **שם החבילה:** `seforim_library_updater` (מומלץ) או `otzaria_library_update`.
2. **היסטוריית git:** אם החבילה ב‑repo נפרד, `git mv` **לא** ישמר blame בין הריפואים. אפשרויות:
   (א) `git filter-repo`/subtree לשימור היסטוריה; (ב) להתחיל copy ראשוני ולתעד ב‑CHANGELOG את
   commit המקור ב‑Otzaria. ה‑hasher/applier עברו 5 סבבי ביקורת — ההיסטוריה שלהם יקרה.
   (ג) חלופה: לשמור כ‑submodule במונוריפו. **להכריע בשלב 1.**

---

## 9. הרחבה עתידית (אופציונלי, לא חוסם) — הוצאת ה‑orchestrator עם ports

אם בעתיד נרצה שגם ה‑orchestrator יחיה בחבילה, נפשיט את שלוש התלויות הקשיחות לממשקים מוזרקים:
- `DbWriteGate` — מופשט סביב `operationQueue` + `closeForExternalWrite`/`reopenAfterExternalWrite`.
- `RuntimeRefresh` — מופשט סביב `refreshAfterDbUpdate()`.

אז ה‑orchestrator עובר לחבילה ו‑Otzaria מספק adapters קטנים. **לא נדרש להוצאה הראשונה.**

---

## 10. צ'קליסט סופי

- [ ] שלב 0: baseline — `test/library_update/` ירוק לפני ההוצאה.
- [ ] שלב 1: שלד + `dart pub get` עובר; הוכרעו שם החבילה והיסטוריית git (§8).
- [ ] שלב 2: 12 קבצים הועברו; zstd נותק מ‑`patch_downloader`; barrel עם `show`; `analyze` נקי.
- [ ] שלב 3: fixtures committed (כולל BOM + golden hash); נתיב release → `SEFORIM_LIBRARY_RELEASES_DIR`;
      7 בדיקות הועברו; `dart test` עובר.
- [ ] שלב 4: Otzaria תלוי בחבילה (path); 12 קבצים נמחקו; imports עודכנו; decompress הוזרק ב‑main;
      `flutter analyze` נקי.
- [ ] שלב 5: שתי סוויטות ירוקות; התנהגות זהה ל‑baseline.
- [ ] README כולל אזהרת פעולות חוסמות (§7).

---

### נספח: סיכום כמותי
- **עובר לחבילה:** 12 קבצי מקור (~1,764 שורות) + 7 קבצי בדיקה (~1,182 שורות).
- **נשאר ב‑Otzaria:** 5 קבצי מקור (~789 שורות) + 2 קבצי בדיקה (~462 שורות).
- כ‑75% מקוד ה‑lib וכ‑72% מקוד הבדיקות עוברים — חיתוך נקי, ללא הפשטות חדשות, בסיכון נמוך.

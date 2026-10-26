# עדכוני אוצריא — Otzaria Offline Update

תוכנה לעדכון **אופליין** של [אוצריא](https://github.com/Otzaria): התוכנה עצמה, ספריית הספרים והתוספים.
מוקדשת ללומדי התורה הנמנעים משימוש באינטרנט, גם החסום.

## איך זה עובד

הרשת נדרשת רק להורדה. כל השאר — בדיקת גרסאות, התקנה ועדכון — קורא מתיקייה מקומית בלבד.

1. **במחשב מקוון** — מורידים את הרכיבים שנבחרו (תוכנה / ספרייה / תוספים) אל תיקיית מראה (`OtzariaData`) שצמודה לקובץ ההרצה, למשל על כונן נייד.
2. **במחשב הלא־מקוון** — מריצים את הלאנצ'ר מהכונן, והוא מתקין ומעדכן מתוך המראה.

הלאנצ'ר מוצג למשתמש בשם **"עדכוני אוצריא"**, ותומך ב-**Windows** וב-**macOS**.

## מבנה הריפו

כל תיקייה היא package נפרד עם `pubspec.yaml` ו-README משלו.

| תיקייה | תפקיד |
| --- | --- |
| `/` (root), `tool/`, `test/` | `otzaria_offline_update` — כלי המאגר: מדידת כיסוי לכל החבילות וכלי מדידה של ה-hash הלוגי |
| [`otzaria_downloads/`](otzaria_downloads) | הורדות עם המשך, לקוח GitHub משותף, והרמת הרשאות בווינדוס |
| [`otzaria_manager/`](otzaria_manager) | התקנה, עדכון והפעלה של אפליקציית אוצריא עצמה |
| [`library_manager/`](library_manager) | חיווט עדכון המסד (`seforim.db`) לתוך הלאנצ'ר |
| [`plugins_manager/`](plugins_manager) | חנות התוספים האופליינית: סנכרון הקטלוג מ-`otzaria.org` והתקנה דרך `otzaria://` |
| [`custom_apps_manager/`](custom_apps_manager) | מרשם "תוכנות נוספות" שנוסעות על הכונן |
| [`error_reports_manager/`](error_reports_manager) | איסוף דיווחי טעויות במחשב הלא־מקוון והעלאתם ממחשב מקוון |
| [`otzaria_l10n/`](otzaria_l10n) | מחרוזות ממשק (עברית ואנגלית) |
| [`launcher_app/`](launcher_app) | אפליקציית Flutter לדסקטופ שמחברת את כל המודולים לחלון אחד |

`launcher_app` תלוי בשאר ה-packages דרך `path:` יחסי, ולכן הם חייבים לשבת באותה רמה בריפו.
מנוע עדכון המסד אינו בריפו הזה (למטה).

## מנוע עדכון המסד: `seforim_library_updater`

החבילה של [`Otzaria/otzaria_library_updater`](https://github.com/Otzaria/otzaria_library_updater) — אותה חבילה שאוצריא עצמה מתעדכנת דרכה ברשת. `library_manager`, `launcher_app` וכלי השורש תלויים בה כתלות git מוצמדת. מדיניות המראה (אופליין) היא המחלקות `Offline*` שבה; שינויים במנוע נעשים שם.

זו חבילת Flutter שהיא **צד הלקוח** של פורמט ההפצה של `SeforimLibrary`. היא:

- מגלה גרסאות ב-GitHub Releases ובוחרת מסלול עדכון — דלתא או הורדה מלאה.
- מורידה ומאמתת קובצי `patch-vX-vY.db.zst`.
- מחילה אותם אטומית על ה-DB המקומי.
- מוודאת שה-hash הלוגי של התוצאה זהה לזה שה-Kotlin ייצר.

**צרכן, לא יצרן.** מאגר ה-Kotlin מייצר את המסד וההפרשים. `LogicalContentHasher` ו-`PatchApplier` הם תרגום ישיר של הלוגיקה שם, וחייבים להסכים איתה בית־בית.

נקודות שכדאי לדעת:

- **אין כאן UI.** ה-package הוא לוגיקה בלבד; מסכים והתקדמות באחריות האפליקציה הצורכת.
- **פלטפורמות native בלבד** (Android, iOS, macOS, Windows, Linux) — `dart:io` אינו נתמך ב-Web.
- **חילוץ zstd מוזרק** על ידי הצרכן (`PatchDownloader.decompress`).
- **חישוב SHA-256 עובר דרך `FastSha256`** (CNG ב-Windows, CommonCrypto ב-macOS, `package:crypto` כגיבוי) — המסד כולו נקרא בכל אימות, והמימוש הנייטיבי מהיר בסדר גודל מהדארטי.
- **⚠️ פעולות כבדות — הריצו ב-Isolate.** `LogicalContentHasher.compute` ו-`PatchApplier.apply` סינכרוניות וארוכות:

```dart
await Isolate.run(() => const PatchApplier().apply(/* ... */));
```

## בנייה והרצה

```bash
cd launcher_app
flutter pub get
flutter run -d windows   # או: -d macos
```

- **Windows:** תיקיית `windows/` נוצרת ב-CI; מקומית יש להריץ קודם `flutter create --platforms=windows .`. ההפצה היא קובץ exe בודד שמחלץ את עצמו (`windows_stub/package.ps1`).
- **macOS:** `flutter build macos --release` מייצר `Otzaria Launcher.app`. ההפצה היא ה-`.app` עצמו, בחתימה ad-hoc.

פרטים מלאים, כולל שחרור גרסאות ועדכון עצמי: [`launcher_app/README.md`](launcher_app/README.md).

## בדיקות

```bash
flutter test                     # כלי השורש
cd launcher_app && flutter test  # הלאנצ'ר
```

בדיקות המנוע, כולל אלה שמול הפצות אמיתיות, רצות בריפו של `otzaria_library_updater`.

### מדידת כיסוי לכל הפרויקט

משורש המאגר, עם Flutter ו-Dart בנתיב:

```bash
dart pub global activate coverage 1.15.1
dart tool/coverage.dart --collect
```

הפקודה מריצה את הבדיקות בשמונה החבילות ושומרת בכל אחת
`build/coverage/lcov.info` ולוג ריצה. הדוח המשוקלל נמצא
ב-`build/coverage/summary.json`; מוצג גם הכיסוי ללא חבילת התרגומים.
לסיכום חוזר של הדוחות הקיימים: `dart tool/coverage.dart`.

רף ברירת המחדל הוא לפחות 60% בכל חבילה ולפחות 80% בפרויקט כולו.
אפשר לשנות אותו באמצעות `--min=80 --target=80`. ריצה מתחת לרף
או כשל בבדיקות מחזירים קוד יציאה שונה מאפס. `--packages=library_manager,launcher_app`
מגביל את האיסוף והסיכום לחבילות שנבחרו. ב-CI הכיסוי נאסף ב-Windows בשני
חלקים במקביל, כל אחד עם `--packages=` משלו, וג'וב נפרד מאחד את הדוחות
ומריץ `dart tool/coverage.dart` על כל שמונה החבילות.

המדידה היא כיסוי שורות Dart תחת `lib/`, משוקלל לפי מספר השורות
המדידות ולא ממוצע של אחוזי החבילות. בזמן המדידה נוצר זמנית קובץ
בדיקה שטוען את כל ספריות הקוד בלי להפעיל אותן, ומוסר בסוף הריצה;
כך גם קוד שלא הגיעו אליו הבדיקות נכנס למכנה. בדיקת הטעינה היא
לצורכי מדידה בלבד. קבצים שאין להם שורות מדידות מפורטים בדוח.
קוד native ובדיקות שתלויות במחשב אחר או בקבצי fixture חיצוניים
אינם נעשים מאומתים מעצם אחוז הכיסוי.

## מסמכים נוספים

- [`AGENTS.md`](AGENTS.md) — כללי עבודה וקונבנציות בפרויקט
- [`CHANGELOG.md`](CHANGELOG.md) — היסטוריית שינויים
- [`LICENSE`](LICENSE)

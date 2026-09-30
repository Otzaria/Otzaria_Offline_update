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
| `/` (root), `lib/` | `seforim_library_updater` — עדכון מסד הספרים מהפצות דלתא של [`SeforimLibrary`](https://github.com/Otzaria/SeforimLibrary) |
| [`otzaria_manager/`](otzaria_manager) | התקנה, עדכון והפעלה של אפליקציית אוצריא עצמה |
| [`library_manager/`](library_manager) | חיווט עדכון המסד (`seforim.db`) לתוך הלאנצ'ר |
| [`plugins_manager/`](plugins_manager) | חנות התוספים האופליינית: סנכרון הקטלוג מ-`otzaria.org` והתקנה דרך `otzaria://` |
| [`custom_apps_manager/`](custom_apps_manager) | מרשם "תוכנות נוספות" שנוסעות על הכונן |
| [`error_reports_manager/`](error_reports_manager) | איסוף דיווחי טעויות במחשב הלא־מקוון והעלאתם ממחשב מקוון |
| [`otzaria_l10n/`](otzaria_l10n) | מחרוזות ממשק (עברית ואנגלית) |
| [`launcher_app/`](launcher_app) | אפליקציית Flutter לדסקטופ שמחברת את כל המודולים לדשבורד אחד |
| `tool/`, `test/` | סקריפטי עזר ובדיקות של ה-package הראשי |

`launcher_app` תלוי בשאר ה-packages דרך `path:` יחסי, ולכן הם חייבים לשבת באותה רמה בריפו.

## ה-package הראשי: `seforim_library_updater`

חבילת Flutter שהיא **צד הלקוח** של פורמט ההפצה של `SeforimLibrary`. היא:

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
dart test                                                  # ה-package הראשי: fixtures בלבד
SEFORIM_LIBRARY_RELEASES_DIR=/path/to/releases dart test   # + בדיקות מול הפצות אמיתיות (אופציונלי)
cd launcher_app && flutter test                            # הלאנצ'ר
```

## מסמכים נוספים

- [`AGENTS.md`](AGENTS.md) — כללי עבודה וקונבנציות בפרויקט
- [`CHANGELOG.md`](CHANGELOG.md) — היסטוריית שינויים
- [`LICENSE`](LICENSE)

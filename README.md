# seforim_library_updater

> **מבנה הרפו:** ה‑package הראשי (`seforim_library_updater`) יושב ב‑root, כמו קודם. בתיקיות
> [`otzaria_manager/`](otzaria_manager) ו-[`library_manager/`](library_manager) יושבים packages נוספים,
> נפרדים, לניהול עדכון/התקנה/הפעלה של **אפליקציית אוצריא עצמה** ולחיווט המסד לתוך לאנצ'ר מאוחד,
> בהתאמה — חלק ממיזם לאנצ'ר מאוחד. לכל package יש `pubspec.yaml` משלו.

חבילת **Flutter** לצריכת הפצות הדלתא של [`Otzaria/SeforimLibrary`](https://github.com/Otzaria/SeforimLibrary).

החבילה היא צד‑הלקוח של פורמט ההפצה: היא מגלה גרסאות ב‑GitHub Releases, בוחרת מסלול עדכון
(דלתא או הורדה מלאה), מורידה ומאמתת קובצי `patch-vX-vY.db.zst`, מחילה אותם אטומית על ה‑DB
המקומי, ומוודאת שטביעת‑האצבע הלוגית (hash) של התוצאה תואמת למה שה‑Kotlin ייצר.

> **לא יצרן — צרכן.** מאגר ה‑Kotlin (`SeforimLibrary`) מייצר את ה‑DB וההפרשים; חבילה זו
> צורכת אותם. שני רכיבים כאן הם תרגום ישיר של לוגיקת ה‑Kotlin וחייבים להסכים איתה בית‑בית:
> `LogicalContentHasher` (תואם `LogicalContentHasher.kt`) ו‑`PatchApplier`.

## חבילת Flutter

החבילה הומרה מ‑Dart טהור ל‑Flutter package: `pubspec.yaml` מכריז תלות ב‑`flutter` (sdk),
ונוסף `sqlite3_flutter_libs` כדי לספק את ספריות ה‑native של SQLite עבור
Android/iOS/macOS/Windows/Linux בלי הסתמכות על ספריית מערכת מותקנת מראש. הלוגיקה עצמה
(המודלים והשירותים תחת `lib/src`) לא השתנתה — היא Dart טהור ועובדת זהה בתוך אפליקציית
Flutter. אין ב‑package הזה widgets או UI; האינטגרציה עם ממשק המשתמש (progress bars, כפתורי
עדכון וכו') היא באחריות האפליקציה הצורכת.

חילוץ zstd עדיין **מוזרק** על‑ידי הצרכן (ל‑`PatchDownloader.decompress`), כך שה‑package לא
נעול לספריית דחיסה מסוימת.

**הערת web:** Flutter Web אינו תומך ב‑`dart:io`, שבו משתמשים `PatchApplier`,
`LibraryDbRecoveryService` ו‑`LocalDbVersionReader`. החבילה מיועדת לפלטפורמות ה‑native
(Android, iOS, macOS, Windows, Linux) בלבד.

## ⚠️ פעולות חוסמות — הרץ ב‑Isolate

`LogicalContentHasher.compute` ו‑`PatchApplier.apply` הן **סינכרוניות וכבדות** (חישוב ה‑hash
עשוי להימשך עשרות שניות על DB מלא). **אל תריץ אותן על ה‑UI isolate** — עטוף ב‑`Isolate.run`:

```dart
await Isolate.run(() => const PatchApplier().apply(/* ... */));
```

## בדיקות

- **fixtures inline** — הבדיקות בונות DB זעירים בזיכרון (`openInMemory`), כולל golden hash
  קבוע ומקרה BOM; רצים תמיד ולוכדים רגרסיה בחוזה מול Kotlin.
- **בדיקות מול הפצות אמיתיות** — אופציונליות, מופעלות כשמשתנה הסביבה
  `SEFORIM_LIBRARY_RELEASES_DIR` מצביע לתיקייה עם `v14/seforim.db` ו‑
  `v15/{seforim.db, patch-v14-v15.db, patch-v14-v15r.db}`. אחרת מדלגות.

```bash
dart test                                   # fixtures בלבד
SEFORIM_LIBRARY_RELEASES_DIR=/path/to/releases dart test   # + חוזה מלא
```

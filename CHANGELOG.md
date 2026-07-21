# Changelog

## 0.2.0

- הומרה לחבילת **Flutter** (`pubspec.yaml` מוסיף תלות ב-`flutter: sdk: flutter`
  ובאילוץ `environment.flutter`).
- נוסף `sqlite3_flutter_libs` לבינדינג הנייטיב של SQLite בכל פלטפורמות Flutter.
- `analysis_options.yaml` עבר מ-`lints` ל-`flutter_lints`; נוסף `flutter_test`
  ל-`dev_dependencies` (בנוסף ל-`test` הקיים, שממשיך לשמש את קבצי הבדיקה).
- אין שינוי בלוגיקת המודלים/השירותים תחת `lib/src` — Dart טהור, ללא תלות ב-widgets.

## 0.1.0

גרסה ראשונית — הוצאה מ-`otzaria/lib/library_update/` לחבילת Dart עצמאית.

- **מקור:** commit `d6d4e9facf5da322e83bdfbc199b899d3b210915` בריפו Otzaria.
- מנוע צריכת הפצות SeforimLibrary: מודלים, גילוי/תכנון מסלול, הורדה ואימות,
  hash לוגי (תואם `LogicalContentHasher.kt` של Kotlin), והחלת patch אטומית.
- חבילת Dart טהורה — ללא תלות ב-Flutter. חילוץ zstd מוזרק על-ידי הצרכן.

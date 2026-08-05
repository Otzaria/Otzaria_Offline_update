# Changelog

## Unreleased — תמיכת macOS בלאנצ'ר

הלאנצ'ר (`launcher_app` + `otzaria_manager` + `library_manager`) עובד מעכשיו
גם ב-macOS 10.15+, לצד Windows. ה-package הראשי (`seforim_library_updater`)
לא נדרש לשינוי — הוא היה כבר cross-platform.

**`otzaria_manager`** — הופשט מהנחות Windows והפך לדו-מסלולי:

- נוסף `OtzariaTargetPlatform` (windows/macos), שניתן לדרוס בבדיקות; כל
  השירותים בוחרים מסלול לפיו במקום לפי `Platform` ישירות.
- `OtzariaRelease` — השדות `windowsInstaller*` שונו ל-`installer*` ונוסף
  `installerKind`; `NoWindowsAssetException` → `NoInstallerAssetException`.
  ⚠️ שינוי API שובר, בתוך הרפו בלבד.
- `OtzariaAssetSelector` (חדש) בוחר `otzaria-macos.zip` (או `.dmg` כגיבוי)
  ב-macOS ו-`*-windows.exe` בווינדוס. חבילות ה-FULL של ~2GB נפסלות בשתיהן.
- `OtzariaExeLocator` → `OtzariaAppLocator`: מאתר גם חבילות `.app` (הרדודה
  ביותר, בלי להיכנס לתוכה), עם סינון אופציונלי לתיקיות משותפות.
- `OtzariaInstaller` — מסלול התקנה ל-macOS: חילוץ עם `ditto` (שומר על
  החתימה, בשונה מ-`unzip`) לתיקיית staging, החלפה אטומית של ה-`.app`
  הקיים עם שחזור אם ההחלפה נכשלה, והסרת `com.apple.quarantine`.
- `MacAppVersionReader` (חדש) קורא `CFBundleShortVersionString` /
  `CFBundleIdentifier` מ-`Info.plist` דרך `plutil` (הקובץ הוא binary plist).
  הוא ו-`WindowsExeVersionReader` מממשים ממשק משותף (`InstalledVersionReader`).
- `OtzariaLauncher` — מפעיל `.app` דרך `open`. תוקן גם באג אמיתי: `.app`
  היא תיקייה, ולכן בדיקת `File.exists` עליה נכשלה על התקנה תקינה.
- `OtzariaUpdateCheckResult.updateAvailable` מנרמל גרסאות (מסיר `v` מוביל
  ואת מה שאחרי `+`) — בלי זה זיהוי התקנה קיימת (שמדווחת `0.9.96` מול תג
  `0.9.96+736`) נראה כמו "יש עדכון" ומוריד 73MB לחינם בכל פתיחה.
- `OtzariaInstallState.exePath` → `launchPath`, עם קריאה של המפתח הישן
  מה-JSON כדי שהתקנה קיימת של משתמש Windows לא "תישכח".
- ב-macOS גם `/Applications` נסרקת לזיהוי התקנה קיימת — עם אימות זהות
  (שם/`CFBundleIdentifier`), אחרת הסריקה הייתה מחזירה אפליקציה זרה.

**`library_manager`**:

- `OtzariaProcessGuard` עובד ב-macOS/לינוקס דרך `pgrep -x` (שם מלא בלבד,
  כדי לא לזהות את הלאנצ'ר עצמו). שם התהליך של אוצריא ב-macOS הוא `אוצריא`.
- הבדיקה "האם אוצריא פתוחה" אינה מדולגת יותר מחוץ לווינדוס.
- `LibraryDbLocator` מכיר את ברירות המחדל של macOS
  (`~/Library/Application Support/otzaria/books`, ובהתקנה מערכתית
  `/Library/...`) ואת `%ProgramData%\otzaria\books` בווינדוס — נגזר מ-
  `app_paths.dart` של אוצריא. הנתיבים ניתנים להזרקה, כך שהבדיקות לא
  תלויות בהתקנה אמיתית על מכונת המפתח.

**`launcher_app`**:

- נוספה תיקיית `macos/` (**נשמרת בגיט**, בשונה מ-`windows/`): bundle id
  `org.otzaria.launcher`, `CFBundleDisplayName` בעברית, App Sandbox כבוי
  (הכרחי — הלאנצ'ר כותב חבילות `.app`, נוגע ב-DB מחוץ ל-container ומריץ
  כלי מערכת), ו-`PRODUCT_NAME = Otzaria Launcher` שחייב להישאר שונה מ-
  `אוצריא` כדי שה-process guard לא יזהה את הלאנצ'ר כאוצריא פתוחה.
- `FileReveal` (חדש) מחליף את הקריאות הישירות ל-`explorer.exe` בפתיחה
  ב-Explorer/Finder לפי הפלטפורמה.

**CI**: `build-macos.yml` (חדש) + ג'וב macOS ל-`launcher_app` ומטריצת
`ubuntu`+`macos` ל-`otzaria_manager` ב-`ci.yml`. האריזה היא `ditto` ולא
`zip`, כדי לא לשבור את חתימת ה-bundle.

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

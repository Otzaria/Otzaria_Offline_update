# Changelog

## Unreleased — מצב אופליין יחיד, ותיקייה צמודה לתוכנה

עד כה התוכנה עבדה בכפילות: גם ניסתה לעדכן ישירות מהרשת, וגם בנתה מראה
אופליין. אין בכך צורך — אוצריא עצמה יודעת לעדכן דרך הרשת. מעכשיו יש **מצב
אחד**: הורדה אל תיקייה שצמודה לקובץ ההרצה, והתקנה משם.

**תיקיית הנתונים צמודה לתוכנה ואינה ניתנת לשינוי.**

- `AppPaths` (חדש) מאתר את `<תיקיית ה-exe>/OtzariaData` ובודק כתיבה בפועל.
  ב-macOS התיקייה נוצרת ליד חבילת ה-`.app`, לא בתוכה.
- כשאין הרשאת כתיבה התוכנה **מסרבת לרוץ** ומציגה `SetupErrorScreen` עם הסבר,
  במקום ליפול ל-`%APPDATA%` — נפילה כזו הייתה משאירה את הנתונים על המחשב
  המקוון, כלומר שוברת בשקט את כל הרעיון.
- כל ההגדרות של נתיבים הוסרו: `otzariaInstallPath`, `libraryPath`,
  `pluginsPath`, `preferredUsbPath`. `AppSettings.schemaVersion` = 2; קובץ מגרסה 1
  נקרא בלי לזרוק, והשדות שהוסרו פשוט מתעלמים.

**הרשת נוגעת בדבר אחד — ההורדה.**

- `LibraryManager`: `useLocalMirror()`/`useCloud()`/`currentLocalMirrorPath()`
  ו-`exportOfflineMirror(destDir:)` הוסרו. במקומם `downloadToMirror()`, ו-
  `_resolveSource()` מחזיר תמיד את המראה המקומית או זורק
  `LibraryMirrorMissingException`. **אין יותר נפילה לענן** — היא הייתה גורמת
  להתנהגות שונה תלוי אם המחשב מחובר.
- `OtzariaAppMirror` (חדש) — הפער האמיתי: מודול התוכנה לא היה לו מראה בכלל,
  ולכן במחשב אופליין הוא נכשל. עכשיו `latest-release.json` נשמר לצד קובץ
  ההתקנה, `checkForUpdate()` קורא ממנו בלי רשת, ו-`OtzariaInstaller.installFromFile`
  מתקין מהדיסק. `load()` פוסלת מראה חלקית (קובץ חסר או בגודל שגוי).
- "מה התחדש" בגרסה מוצג ממקור אחר: `OtzariaChangelogClient` (חדש) שולף את
  הפסקה המתאימה מיומן השינויים המרוכז של אוצריא (`assets/יומן שינויים.md`
  בענף `dev`), ומעדיף אותה על פני `release.body` הגולמי מ-GitHub, שלעיתים
  ריק. נשמר לצד שאר המטא־דאטה במראה המקומית, כך שגם קריא בלי רשת.
- כרטיס "מקור העדכון", כרטיס "תוכן להעברה" וכרטיס "נתיבים ואחסון" הוסרו
  מהממשק. במקומם כרטיס הורדה אחד עם בחירת רכיבים (`syncApp`/`syncLibrary`/
  `syncPlugins`), שרצים בטור.
- ההתקנה האוטומטית (`autoInstallApp`/`autoInstallLibrary`) הייתה מתג מת —
  הוצג בממשק ולא חובר לשום דבר. עכשיו היא מחווטת ב-`AppShell.checkAll`,
  ומדלגת על עדכון מסד כשאוצריא פתוחה.

**ערוצי גרסאות = דגל `prerelease` של GitHub.** release רגיל הוא יציב,
pre-release אינו. הערוץ מחווט בפועל ל-`LibraryManager` ול-`OtzariaManager`
(קודם הוא היה קיים בהגדרות ולא השפיע). מכיוון שהריפו של אוצריא כמעט לא
מפרסם יציב, ערוץ "יציב בלבד" זורק `NoStableReleaseException` שמסביר לעבור
ערוץ — במקום ליפול בשקט ל-pre-release.

**שני תיקוני נכונות שהתגלו בדרך:**

- **עדכון מסד ללא שינוי מספר גרסה היה בלתי־נראה.** SeforimLibrary מפרסם
  לפעמים מסד מתוקן באותו `db_version`, ו-`LibraryUpdatePlanner` החזיר `none`
  כי הוא השווה מספרים בלבד. עכשיו הוא משווה גם את ה-release tag שהוחל
  (`LibraryStateStore.appliedReleaseTag`) — אך ורק כשהוא ידוע, כדי לא להציע
  הורדה של ~1GB בכל פתיחה על סמך ניחוש ב-DB שלא הותקן דרך הלאנצ'ר.
- **המראה כללה את כל היסטוריית ה-patches** והגיעה לכמה ג'יגה-בייט — לא
  מתאים לכונן נייד. `LibraryMirrorExporter` מוריד עכשיו רק את ה-release
  האחרון (ואת האחרון שנושא DB מלא, אם שונה).

## חנות התוספים האופליינית

חלק התוספים בלאנצ'ר הופסק מלהיות "פריסה ומצב ריק" והפך למודול עובד. הבסיס
הוא המרה ישירה ל-Flutter של חנות התוספים האופליינית שנבנתה ב-Electron
(`Yehuda-Zakesh/Offline-repository-plugin-store`), שנגזרה בעצמה מחנות
התוספים באתר (`Otzaria/Otzaria_Website`).

**`plugins_manager` (חבילה חדשה)** — Dart טהור, במקביל ל-`otzaria_manager`:

- `PluginsManager` — ה-facade היחיד: `sync()` (במחשב המקוון) מול
  `load()`/`directInstall()`/`saveCopy()` (במחשב הלא-מקוון).
- `PluginStoreClient` — `GET otzaria.org/api/plugins` והורדת נכסים, כולל
  הסקת סיומת מ-`Content-Disposition` (גם `filename*=UTF-8''` לשמות עבריים)
  ומ-`Content-Type`.
- `PluginMirrorStore` — הקטלוג והקבצים נשמרים ב-`<mirrorDir>/plugins/`,
  כלומר **בתוך המראה הקיימת של הספרייה**: העתקה אחת ל-USB מעבירה את
  שתיהן. הנתיבים בקטלוג יחסיים ועם `/`, כדי שהמראה תעבוד גם מאות כונן
  אחרת וגם כשנכתבה בווינדוס ונקראת ב-macOS. הכתיבה אטומית.
- `PluginMirrorSync` — פורט של `syncNow`: דילוג על הורדה חוזרת של קובץ
  תוסף שגרסתו לא השתנתה, ותמונות/צילומי מסך שכן מתעדכנים בכל סנכרון.
  כשל בנכס בודד הופך לאזהרה ואינו מפיל את הסנכרון.
- `PluginManifestReader` — מחלץ את ה-`id` האמיתי מ-`manifest.json` שבתוך
  ה-`.otzplugin` (כולל הסרת BOM). ⚠️ זהו המפתח היחיד להשוואה מול
  התוספים המותקנים; ה-`id` שה-API מחזיר הוא מזהה מסד-הנתונים של האתר.
- `InstalledPluginsScanner` — סורק
  `<pluginsDir>/installed/<manifestId>/current/manifest.json`. הנתיב
  **מתגלה ולא מונח**, כמו ב-`LibraryDbLocator`.
- `PluginDirectInstaller` — התקנה דרך
  `otzaria://plugin/install-local?path=` בלבד, שעובדת בלי רשת. אין
  חילוץ ZIP עצמאי לתוך תיקיות אוצריא, כדי לא לעקוף את הרישום הפנימי
  של אוצריא. הכישלון מוחזר כערך ולא כחריג, כמו ב-`FileReveal`.
- 35 בדיקות יחידה עוברות.

**`launcher_app`**:

- `PluginsModuleController` — עוטף את `PluginsManager` כ-`ChangeNotifier`,
  עם חיפוש, סינון סטטוס/תגית, ומתג "רק לא-מותקן או שיש לו עדכון" (דלוק
  כברירת מחדל, כמו במקור).
- `screens/plugins/` — חנות מלאה: רשת כרטיסים עם תמונות וגלולות, עמוד
  פרטי תוסף, גלריית צילומי מסך עם lightbox (חצים ומקלדת), שכבת סנכרון עם
  התקדמות ואזהרות, והודעת "יש עדכונים זמינים" בכניסה.
- `services/hebrew_date.dart` — המרה גרגוריאני→עברי + גימטריה. נדרש כי
  ל-`package:intl` אין לוח שנה עברי, בשונה מ-`Intl` בדפדפן שהחנות
  המקורית השתמשה בו.
- כרטיס התוספים בדף הבית מציג נתונים אמיתיים במקום "המודול בבנייה".

**הגדרות** — כל החלקים שנגעו בתוספים היו טקסט מציין-עתיד ("יתאפשר כשמודול
התוספים ייבנה") או שדות שלא חוברו לכלום. כולם עודכנו:

- `pluginsPath` חובר לבחירת תיקייה, ומוזן ל-`InstalledPluginsScanner`.
- **"סנכרון חנות התוספים בפתיחה"** (`autoDownloadAllPlugins`) — מחווט
  בפועל ב-`AppShell._loadPlugins`: כבוי בברירת מחדל, נחסם כש-`offlineOnly`
  דלוק, ודורש אישור באזהרה כי זו הורדה ברשת בכל פתיחה. מסנכרן בלבד —
  התקנה נשארת יזומה תמיד.
- שני מתגי "תוספים מותקנים" נשארים מושבתים, אבל עם הסבר **אמיתי** במקום
  "המודול טרם נבנה": סנכרון חלקי אינו קיים (`PluginMirrorSync` מביא את כל
  הקטלוג), והתקנה פותחת את אוצריא לכל תוסף בנפרד ולכן אינה מתאימה לרקע.
- **`pluginsChannel`** חדל להתחזות לערוץ prerelease. לתוספים יש `status`
  לכל תוסף, ולכן הוא קובע כעת את סינון ברירת המחדל שהחנות נפתחת בו
  (`pluginStatusFilterFor`), עם תוויות "יציב בלבד" / "כולל בטא וניסיוני".
  שינוי בהגדרות נכנס לתוקף מיד, בלי לדרוס סינון שהמשתמש בחר ידנית בחנות.

**לא מומש בכוונה**: הורדת גרסה היסטורית של תוסף (ה-API מחזיר `versions`),
וסנכרון חלקי של המותקנים בלבד.

**לא אומת**: המסלול המלא מקצה לקצה — סנכרון אמיתי מ-`otzaria.org`, העברה
ב-USB, ופתיחת הפרוטוקול מול התקנה אמיתית של אוצריא.

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

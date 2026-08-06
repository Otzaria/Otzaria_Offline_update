# otzaria_manager

חבילת Dart טהורה (ללא תלות ב-Flutter) לניהול **אפליקציית אוצריא עצמה**
(לא ה-DB — לזה יש את [`seforim_library_updater`](https://github.com/Yehuda-Zakesh/Otzariya_update))
בתוך לאנצ'ר חיצוני: בדיקת גרסה עדכנית, הורדה, התקנה שקטה, והפעלה.
תומכת ב-**Windows וב-macOS**.

## שני מסלולים, אותו API

הצרכן (הדשבורד) קורא ל-[`OtzariaManager`](lib/src/otzaria_manager.dart)
בלי לדעת על איזו פלטפורמה הוא רץ. הבחירה מרוכזת ב-
[`OtzariaTargetPlatform`](lib/src/models/otzaria_release.dart), שאפשר גם
לדרוס בבדיקות — וכך שני המסלולים נבדקים מאותה מכונה:

| שלב | Windows | macOS |
| --- | --- | --- |
| האסט שנבחר | `otzaria-<ver>-windows.exe` | `otzaria-macos.zip`, ובהיעדרו `otzaria-macos.dmg` |
| התקנה | הרצת Inno Setup בשקט (`/VERYSILENT /DIR=`) | חילוץ עם `ditto` והחלפת ה-`.app` בתיקיית ההתקנה |
| מה מאתרים | `*.exe` (למעט `unins*`) | חבילת `.app` (הרדודה ביותר, בלי להיכנס לתוכה) |
| קריאת גרסה | `ProductVersion` מה-version resource (FFI, `package:win32`) | `CFBundleShortVersionString` מ-`Info.plist` (דרך `plutil`) |
| הפעלה | `Process.start` מנותק | `open <bundle>` (דרך Launch Services) |
| זיהוי אוטומטי של התקנה קיימת | התיקייה המנוהלת | התיקייה המנוהלת, ואחריה `/Applications` |

**חבילות ה-FULL של ~2GB** (`otzaria-<ver>-windows-full.exe`,
`otzaria-macos-full.zip`) נפסלות בשתי הפלטפורמות — הן מכילות את הספרייה
בתוכן, והלאנצ'ר מוריד אותה בנפרד דרך `library_manager`. ההתאמה לפי סיומת
(`windows.exe`/`macos.zip`) פוסלת אותן מעצמה, כי הן מסתיימות ב-`full.exe`/
`full.zip`.

### ממצאים שאומתו מול חבילת macOS אמיתית (`otzaria-macos.zip`, 0.9.96+736)

- ה-bundle נקרא **`אוצריא.app`** — בעברית, וכך גם קובץ ההפעלה שבתוכו
  (`CFBundleExecutable = אוצריא`). לכן זה גם **שם התהליך**, ו-
  `OtzariaProcessGuard` ב-`library_manager` מחפש אותו כך.
- `CFBundleIdentifier = com.example.otzaria` (ברירת מחדל של תבנית Flutter
  שלא הוחלפה). הזיהוי ב-`/Applications` מסתמך על **סיומת** `.otzaria`,
  כדי שתיקון עתידי של המזהה לא ישבור אותו.
- `CFBundleShortVersionString = 0.9.96` — כלומר תג ה-release **בלי**
  סיומת ה-build (`+736`). בגלל זה
  [`OtzariaUpdateCheckResult`](lib/src/models/otzaria_update_check_result.dart)
  מנרמל את שתי המחרוזות לפני ההשוואה; בלי זה כל זיהוי של התקנה קיימת
  היה נראה כמו "יש עדכון" ומוריד 73MB לחינם, בכל פתיחה.
- ה-`.app` חתום **ad-hoc** (בלי Developer ID, בלי notarization). לכן
  החילוץ הוא ב-`ditto` דווקא: `unzip`/`package:archive` שוברים את
  ה-symlinks וה-xattrs של ה-bundle ואיתם את החתימה, ואז macOS מסרב
  להריץ. יש בדיקה שמאמתת בפועל ש-`codesign --verify --deep` עובר אחרי
  ההתקנה (ראו למטה).
- הורדה דרך `dart:io` אינה מסמנת quarantine, ולכן Gatekeeper לא חוסם.
  בכל זאת יש הסרה best-effort של `com.apple.quarantine` אחרי ההתקנה,
  למקרה שהמשתמש הביא את הארכיון בעצמו (דפדפן/AirDrop).

## ממצאים חשובים (נכון ליולי 2026)

- **הריפו האמיתי**: `github.com/Sivan22/otzaria` (לא "Otzaria/otzaria").
- ה-release ה**יציב** האחרון (`prerelease=false`) הוא `v0.2.7` מיולי 2025 —
  ישן משמעותית. כל הפעילות האמיתית מאז היא **PR-preview builds**
  (`prerelease=true`), עם אזהרת "Use at your own risk".
  [`OtzariaReleaseClient`](lib/src/services/otzaria_release_client.dart) מסנן
  לפי `prerelease` בהתאם לערוץ שנבחר (release = יציב, pre-release = לא יציב).
  **המשמעות המעשית:** בערוץ "יציב בלבד" סביר שלא תימצא גרסה כלל, והלקוח
  זורק `NoStableReleaseException` שמסביר למשתמש לעבור ערוץ. אין נפילה שקטה
  ל-pre-release — זה היה מטשטש בדיוק את ההבחנה שהערוץ אמור לבטא.
- שם קובץ ה-installer לווינדוס אינו קבוע (מספר הגרסה משובץ בשם, למשל
  `otzaria-0.9.53-windows.exe`) — הבחירה מתבססת על סיומת `windows.exe`.
  בחלק מה-releases קיימים גם `otzaria-windows.zip`/`otzaria.msix`, אבל
  לא בעקביות — **לא** נסמכים עליהם.
- ה-installer עצמו הוא **Inno Setup 6.1.0** (אומת ידנית מול קובץ אמיתי
  שהורד, לא הנחה) — ולכן שקט/נתיב-מותאם מבוססים על דגלי Inno Setup
  הסטנדרטיים: `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR=<path>`.
  אם `Sivan22` יחליף framework בעתיד, יהיה צריך לעדכן את
  [`OtzariaInstaller`](lib/src/services/otzaria_installer.dart).
- ל-Inno Setup יש לפעמים תהליך "עוטף" (SetupLdr) שמסתיים מיד לפני
  שההתקנה בפועל נגמרת — לכן לא סומכים רק על קוד היציאה של התהליך; יש
  polling נפרד שמחכה שקובץ `.exe` יופיע בתיקיית ההתקנה המנוהלת.
- **מבנה קבוע בתוך ה-installer**: הקובץ המותקן תמיד יושב ב-`app/otzaria.exe`
  בתוך תיקיית ההתקנה (אומת עם `innoextract` על installer אמיתי).
- **`otzaria.exe` מכיל Windows version resource תקני**: `ProductVersion`/
  `FileVersion` תואמים בדיוק לתג ה-release (אומת בפועל: release
  `0.9.53-pr-715-146` → `ProductVersion` בתוך ה-exe הוא `"0.9.53"`). זו
  הדרך שבה [`WindowsExeVersionReader`](lib/src/services/windows_exe_version_reader.dart)
  מזהה גרסה מותקנת בפועל, גם אם ההתקנה לא בוצעה דרך הלאנצ'ר הזה.
- ⚠️ בבדיקה מול ה-API (יולי 2026, 36 releases סה"כ) **לא נמצא release
  בתג "0.9.95"** — הגבוה ביותר שנמצא הוא `0.9.53`. כדאי לוודא מול מקור
  אחר אם המספר הזה נכון.

## שימוש

```dart
final manager = OtzariaManager(dataDir: appPaths.dataDir);

// במחשב עם אינטרנט — הפעולה היחידה שנוגעת ברשת. ממלאת את
// `<dataDir>/mirror/app` (מטא־דאטה + קובץ ההתקנה).
await manager.downloadToMirror(onProgress: (received, total) {
  print('$received / $total');
});

// בכל מחשב, כולל בלי רשת בכלל — בדיקה והתקנה קוראות מהמראה בלבד.
final check = await manager.checkForUpdate();
if (check.needsDownload) {
  print('עוד לא הורדה גרסה');
} else if (check.updateAvailable) {
  await manager.update(check);
}
await manager.launch();

// זרימה חד-פעמית: למשתמש שכבר יש לו אוצריא מותקנת במיקום משלו
final detected = await manager.detectExistingInstall(customDir: userChosenDir);
if (detected != null) {
  await manager.adoptExistingInstall(detected); // מכאן והלאה עדכונים יתבצעו לתוך userChosenDir
}

manager.close();
```

## מבנה

- `models/` — `OtzariaRelease` (+`OtzariaTargetPlatform`, `OtzariaInstallerKind`), `OtzariaInstallState`, `OtzariaUpdateCheckResult`.
- `services/otzaria_release_client.dart` — שליפת release אחרון מ-GitHub API.
- `services/otzaria_changelog_client.dart` — שליפת הפסקה המתאימה מיומן
  השינויים המרוכז של אוצריא (`assets/יומן שינויים.md` בענף `dev`), כדי
  להעדיף אותה על פני `release.body` שלא תמיד מלא.
- `services/otzaria_asset_selector.dart` — בחירת האסט לפי פלטפורמה; פונקציה טהורה (בלי רשת ובלי `Platform`), ולכן ניתנת לבדיקה עבור שתי הפלטפורמות.
- `services/otzaria_installer.dart` — הורדה + התקנה + גילוי מה שהותקן; מסלול לכל `OtzariaInstallerKind`, ותיקיית יעד לבחירה (ברירת מחדל, או תיקייה קיימת שאומצה).
- `services/otzaria_app_locator.dart` — סריקת תיקייה ואיתור ה-exe/`.app` הראשי (משותף בין installer לזיהוי התקנה קיימת), עם סינון אופציונלי לתיקיות משותפות כמו `/Applications`.
- `services/installed_version_reader.dart` — הממשק המשותף + בחירת המימוש לפי פלטפורמה.
- `services/windows_exe_version_reader.dart` — קריאת `ProductVersion` מתוך Windows version resource, דרך FFI (`package:win32`).
- `services/mac_app_version_reader.dart` — קריאת `CFBundleShortVersionString`/`CFBundleIdentifier` מ-`Info.plist` (binary plist, ולכן דרך `plutil`).
- `services/otzaria_state_store.dart` — שמירה/טעינה של קובץ ה-state המקומי.
- `services/otzaria_launcher.dart` — הפעלת אוצריא כתהליך עצמאי / דרך `open`.
- `otzaria_manager.dart` — האורקסטרטור המאחד את כולם; נקודת הכניסה ל-UI.

## בדיקות

`dart test` מריץ הכול; הבדיקות התלויות ב-macOS מדולגות אוטומטית במקום אחר.

בנוסף יש **בדיקת קצה-לקצה מול חבילה אמיתית**, אופציונלית (כמו הבדיקות מול
הפצות אמיתיות ב-`seforim_library_updater`) — מתקינה בפועל `.app` שהורד
מ-releases, ומאמתת שהחתימה שרדה את החילוץ ושהתקנה חוזרת מחליפה את
ה-bundle במקום להוסיף עותק שני:

```bash
curl -L -o /tmp/otzaria-macos.zip \
  'https://github.com/Otzaria/otzaria/releases/download/0.9.96%2B736/otzaria-macos.zip'
OTZARIA_MACOS_ZIP=/tmp/otzaria-macos.zip dart test test/otzaria_installer_macos_test.dart
```

## מה עדיין לא מטופל כאן (בכוונה, לשלב הבא)

- הסרה/ניקוי של גרסה קודמת לפני התקנת גרסה חדשה (כרגע Inno Setup
  מתקין "מעל" הקיים לאותה תיקייה — עובד לרוב, אבל לא מטפל בקבצים
  שהוסרו בין גרסאות).
- קישור ל-DB/תוספים (יתבצע במודולי `library_manager`/`plugins_manager`
  ובממשק המאוחד).
- מנגנון resume/retry להורדת ה-installer אם הרשת נופלת (כרגע: כישלון
  → זריקת שגיאה, בלי retry אוטומטי — installer הוא הורדה חד-פעמית
  יחסית קטנה, בניגוד ל-DB המלא).
- **`WindowsExeVersionReader` לא נבדק בפועל על ווינדוס** — צריך לבדוק
  קומפילציה/ריצה אצלך. חשודים סבירים: שמות/חתימות פונקציות ב-
  `package:win32` בין גרסאות, ו-casting של מצביעים. (המסלול המקביל
  ב-macOS, `MacAppVersionReader`, כן אומת מול חבילה אמיתית.)
- **הסרת גרסה קודמת ב-macOS**: ההתקנה מחליפה את חבילת ה-`.app` במלואה,
  ולכן שם דווקא *כן* אין בעיית "קבצים שהוסרו בין גרסאות" — היא קיימת רק
  במסלול Inno Setup של Windows.
- **`/Applications` שאינה בבעלות המשתמש**: אם אומצה התקנה משם ואין
  הרשאת כתיבה, העדכון ייכשל עם שגיאה (אין fallback אוטומטי להתקנה
  לתיקייה המנוהלת).
- אין עדיין UI/הגדרה למשתמש להזין ידנית "תיקיית התקנה קיימת שלי" —
  `detectExistingInstall`/`adoptExistingInstall` מוכנים ברמת הלוגיקה,
  אבל חיבור לשדה קלט במסך אמיתי יגיע עם הדשבורד המאוחד.

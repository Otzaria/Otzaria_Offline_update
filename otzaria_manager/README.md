# otzaria_manager

חבילת Dart טהורה (ללא תלות ב-Flutter) לניהול **אפליקציית אוצריא עצמה**
(לא ה-DB — לזה יש את [`seforim_library_updater`](https://github.com/Yehuda-Zakesh/Otzariya_update))
בתוך לאנצ'ר חיצוני: בדיקת גרסה עדכנית, הורדה, התקנה שקטה, והפעלה.

## ממצאים חשובים (נכון ליולי 2026)

- **הריפו האמיתי**: `github.com/Sivan22/otzaria` (לא "Otzaria/otzaria").
- ה-release ה**יציב** האחרון (`prerelease=false`) הוא `v0.2.7` מיולי 2025 —
  ישן משמעותית. כל הפעילות האמיתית מאז היא **PR-preview builds**
  (`prerelease=true`), עם אזהרת "Use at your own risk". **בכוונה** —
  ולפי בקשת המשתמש — [`OtzariaReleaseClient`](lib/src/services/otzaria_release_client.dart)
  מתעלם משדה `prerelease` ולוקח את ה-release הראשון שמוחזר מה-API
  (העדכני ביותר כרונולוגית), אחרת הלאנצ'ר יתקע משתמשים על גרסה ישנה.
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

## שימוש

```dart
final manager = OtzariaManager(dataDir: r'C:\Users\me\AppData\Roaming\OurLauncher');

final check = await manager.checkForUpdate();
if (check.updateAvailable) {
  await manager.update(check, onProgress: (received, total) {
    print('$received / $total');
  });
}

await manager.launch();
manager.close();
```

## מבנה

- `models/` — `OtzariaRelease`, `OtzariaInstallState`, `OtzariaUpdateCheckResult`.
- `services/otzaria_release_client.dart` — שליפת release אחרון מ-GitHub API.
- `services/otzaria_installer.dart` — הורדה + התקנה שקטה + גילוי ה-exe שהותקן.
- `services/otzaria_state_store.dart` — שמירה/טעינה של קובץ ה-state המקומי.
- `services/otzaria_launcher.dart` — הפעלת אוצריא כתהליך עצמאי.
- `otzaria_manager.dart` — האורקסטרטור המאחד את כולם; נקודת הכניסה ל-UI.

## מה עדיין לא מטופל כאן (בכוונה, לשלב הבא)

- הסרה/ניקוי של גרסה קודמת לפני התקנת גרסה חדשה (כרגע Inno Setup
  מתקין "מעל" הקיים לאותה תיקייה — עובד לרוב, אבל לא מטפל בקבצים
  שהוסרו בין גרסאות).
- קישור ל-DB/תוספים (יתבצע במודולי `library_manager`/`plugins_manager`
  ובממשק המאוחד).
- מנגנון resume/retry להורדת ה-installer אם הרשת נופלת (כרגע: כישלון
  → זריקת שגיאה, בלי retry אוטומטי — installer הוא הורדה חד-פעמית
  יחסית קטנה, בניגוד ל-DB המלא).

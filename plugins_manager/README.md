# plugins_manager

חנות התוספים של אוצריא, במצב **אופליין**. חבילת Dart טהורה (ללא Flutter),
במקביל ל-`otzaria_manager`.

היא נגזרת מחנות התוספים באתר (`Otzaria/Otzaria_Website`) ומהגרסה
האופליינית שנבנתה עליה ב-Electron
(`Yehuda-Zakesh/Offline-repository-plugin-store`) — הקוד כאן הוא המרה
ישירה של הלוגיקה שם, לא כתיבה מחדש.

## שני מסלולים

| מסלול | API | רץ על | רשת |
| --- | --- | --- | --- |
| מילוי המראה | `PluginsManager.sync()` | המחשב **המקוון** | נדרשת |
| קריאה + התקנה | `PluginsManager.load()` / `.directInstall()` | המחשב **הלא-מקוון** | לא נדרשת |

זהו בדיוק אותו עקרון של `library_manager`: מורידים במחשב אחד, מחילים
במחשב אחר, ימים אחר כך.

```dart
final manager = PluginsManager(
  // התיקייה שלצד קובץ ההרצה — ראו AppPaths בלאנצ'ר. הקטלוג יושב תחת
  // `<mirrorRoot>/plugins/`.
  resolveMirrorDir: () async => p.join(appPaths.dataDir, 'mirror'),
);

// במחשב עם אינטרנט:
await manager.sync(onProgress: (p) => print(p.message));

// במחשב בלי אינטרנט (אחרי שהמראה הועתקה לשם):
final view = await manager.load();
await manager.directInstall(view.catalog.plugins.first);
```

תיקיית המראה נמסרת כ-**callback** ולא כמחרוזת קבועה, כדי שמעבר בין המראה
האוטומטית לכונן USB שהמשתמש בחר ייכנס לתוקף מיד — בדיוק כמו
`LibraryManager._resolveSource`.

## מבנה האחסון

החנות יושבת **בתוך** תיקיית המראה של הספרייה, כך שהעתקה אחת ל-USB
מעבירה את שתיהן:

```
<mirrorDir>/
├── releases.json, assets/…        ← הספרייה (LibraryMirrorExporter)
└── plugins/                       ← החבילה הזו
    ├── catalog.json
    └── files/<pluginId>/
        ├── image.png
        ├── screenshot-0.png …
        └── plugin.otzplugin
```

`LibraryMirrorExporter.export` רק יוצר תיקיות ואינו מוחק את היעד, ולכן
`plugins/` שורדת רענון של מראת הספרייה.

כל הנתיבים ב-`catalog.json` נשמרים **יחסית ל-`plugins/` ועם `/`** — כדי
שהמראה תעבוד גם מאות כונן אחרת וגם כשהיא נכתבה בווינדוס ונקראת ב-macOS.

## מוקשים — אל תשנו בלי להבין

**ההשוואה למותקן היא לפי `manifestId`, לא לפי `id` של הקטלוג.** ה-`id`
שה-API הציבורי מחזיר הוא מזהה מסד-הנתונים של האתר, ואוצריא מתקינה תחת
`plugins/installed/<manifest.id>/`. את `manifestId` מחלצים מ-`manifest.json`
שבתוך קובץ ה-`.otzplugin` שכבר ירד מקומית — ולכן תוסף שקובץ ההתקנה שלו
עוד לא ירד מקבל `PluginInstallStatus.unknown`, וזה תקין.

**ההתקנה היא פרוטוקול בלבד:** `otzaria://plugin/install-local?path=<abs>`.
לא מחלצים את ה-ZIP בעצמנו לתוך תיקיות אוצריא — לאוצריא יש רישום פנימי
לתוספים המותקנים מעבר לתיקיית `installed/`, ופרישה ידנית עוקפת אותו.
`install-local` קורא את הקובץ מהדיסק ולכן עובד בלי שום גישה לרשת (בשונה
מ-`install?url=` הישן, שדורש אינטרנט ולכן אינו בשימוש).

**הסרת BOM לפני `jsonDecode`.** עורכים בווינדוס שומרים לעיתים JSON עם
U+FEFF מוביל. אותו טיפול בדיוק כמו ב-`LogicalContentHasher`.

**כשל בנכס בודד אינו מפיל את הסנכרון.** הוא מדווח כ-
`PluginSyncPhase.warning` והתוסף נשאר בקטלוג בלי אותו קובץ. רק כשל
בטעינת רשימת התוספים עצמה זורק (`PluginStoreException`).

**דילוג על הורדה חוזרת של קובץ תוסף שגרסתו לא השתנתה.** תמונות וצילומי
מסך כן מתעדכנים בכל סנכרון, כי הם קטנים.

**`otzaria://` נפתח דרך `Process.run`** ולא דרך `url_launcher` — מאותה
סיבה שמתועדת ב-`FileReveal` בלאנצ'ר. הכישלון מוחזר כערך
(`PluginInstallResult`), לא כחריג.

**תיקיית התוספים מתגלה ולא מונחת.** `%APPDATA%\otzaria\plugins` /
`~/Library/Application Support/otzaria/plugins`. תיקייה שלא קיימת מחזירה
מפה ריקה בשקט — אוצריא לא מותקנת, או שאין עדיין תוספים. `resolvePluginsDir`
עדיין קיים ב-API לדריסה בבדיקות, אבל הלאנצ'ר אינו מעביר אותו: אין הגדרת
נתיבים בממשק (ראו `AppPaths`).

## חוזה ה-API של האתר

`GET https://otzaria.org/api/plugins` מחזיר מערך של תוספים מאושרים. השדות
שהחבילה קוראת: `id`, `name`, `shortDescription`, `description`, `version`,
`status`, `author`, `updatedAt`, `originalDate`, `compatibleWith`,
`maxAppVersion`, `requiresNetwork`, `tags`, `homepage`, `downloadCount`,
`supportsDirectInstall`, `isPinned`, `image`, `screenshots`, `downloadUrl`.

`image`, `screenshots` ו-`downloadUrl` הם נתיבים יחסיים לאתר. אם כתובת
האתר תשתנה — `PluginStoreClient.defaultBaseUrl`.

השדה `versions` (היסטוריית גרסאות) מגיע מה-API אך **אינו** נצרך כאן:
המסלול היחיד הוא לגרסה החיה. הורדת גרסה היסטורית לא מומשה.

## ⚠️ מה אומת בפועל ומה לא

**אומת:** 35 בדיקות יחידה (`dart test`) עוברות — קריאת `manifest.json`
מ-`.otzplugin` אמיתי שנבנה ב-`archive` (כולל BOM, ZIP פגום, manifest
חסר), סריקת תוספים מותקנים מול עץ תיקיות זמני, round-trip של
`catalog.json` (כולל קטלוג פגום חלקית), פירוק `Content-Disposition`
(כולל שמות עבריים), השוואת גרסאות והכרעת מצב ההתקנה, ודחיית קובץ חסר /
סיומת שגויה בהתקנה הישירה. `dart analyze` נקי.

**לא אומת:** המסלול המלא מקצה לקצה מול האתר החי — סנכרון אמיתי מ-
`otzaria.org`, ההעברה ב-USB למחשב לא-מקוון, ופתיחת
`otzaria://plugin/install-local` מול התקנה אמיתית של אוצריא. אין בדיקות
מול שרת HTTP מדומה: `PluginStoreClient` מקבל `http.Client` בבנאי, כך
שזה אפשרי — פשוט טרם נכתב.

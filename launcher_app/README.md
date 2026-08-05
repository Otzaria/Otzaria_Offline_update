# launcher_app

הדשבורד המאוחד של לאנצ'ר אוצריא — אפליקציית Flutter דסקטופ
(**Windows ו-macOS**) שמחווטת יחד בממשק אחד את:

- **`otzaria_manager`** — עדכון/התקנה/הפעלה של אפליקציית אוצריא עצמה.
- **`library_manager`** — עדכון מסד הספרים (`seforim.db`), כולל חיווט
  מלא של `seforim_library_updater`.
- **חנות התוספים** — מוצג כרגע ככרטיס מנוטרל "בקרוב" (`plugins_manager`
  עדיין לא נבנה).

כל שלושת המודולים (וה-package הראשי `seforim_library_updater`) יושבים
כ-packages נפרדים באותו ריפו; `launcher_app` תלוי בהם דרך `path:` יחסי
(`../otzaria_manager`, `../library_manager`), כך שהוא צריך לשבת **באותה
רמה** בריפו — לצד `otzaria_manager/` ו-`library_manager/`, לא בתוכם.

## עיצוב

פלטת "חדר עיון": דיו כהה (`#1E3A3A`) על גבי קלף בהיר (`#F5F1E8`), עם
מבטא זהב מושחז (`#9C7A2E`) שנשמר אך ורק לסימון "עדכון זמין". כותרות
בגופן Frank Ruhl Libre (סריף עברי קלאסי), גוף הטקסט ב-Assistant.
כל מודול מוצג ככרטיס עם "פס כריכה" צבעוני בצד לפי הסטטוס (ירוק=מעודכן,
זהב=עדכון זמין, דיו=מתעדכן, אדום=שגיאה/נדרשת פעולה).

## סנכרון אוטומטי

בפתיחת האפליקציה (וגם בכל pull-to-refresh), הדשבורד לא רק *בודק* עדכון —
אם נמצא עדכון זמין (לאוצריא או למסד), הוא **מוריד ומתקין אותו מיד,
אוטומטית**, בלי לחכות ללחיצה על "עדכן". המטרה: אחרי ריצה ראשונה עם
אינטרנט, המשתמש מסונכרן עם הגרסה העדכנית ביותר ויכול להמשיך לעבוד לגמרי
אופליין. לוגיקה ב-`DashboardScreen._syncOtzaria`/`_syncLibrary`.

## macOS

```bash
cd launcher_app
flutter pub get
flutter run -d macos          # פיתוח
flutter build macos --release # הפלט: build/macos/Build/Products/Release/Otzaria Launcher.app
```

תיקיית `macos/` **נשמרת בגיט** (בשונה מ-`windows/`, שנוצרת ב-CI) — היא
מכילה התאמות שאינן ברירת המחדל של `flutter create`, ולכן הרצה של
`flutter create --platforms=macos .` תדרוס אותן. ההתאמות:

| מה | איפה | למה |
| --- | --- | --- |
| `PRODUCT_NAME = Otzaria Launcher` | `macos/Runner/Configs/AppInfo.xcconfig` | קובע גם את שם **התהליך**. חייב להיות שונה מ-`אוצריא` — אחרת `OtzariaProcessGuard` (`pgrep -x אוצריא`) היה מזהה את הלאנצ'ר עצמו כאוצריא פתוחה וחוסם כל עדכון מסד. |
| `CFBundleDisplayName = לאנצ'ר אוצריא` | `macos/Runner/Info.plist` | השם שהמשתמש רואה, בעברית — מופרד משם קובץ ההפעלה. |
| `org.otzaria.launcher` | `AppInfo.xcconfig` | ה-bundle id; קובע גם את `getApplicationSupportDirectory()`, כלומר את מקום ה-data dir. |
| `app-sandbox = false` | `Release.entitlements`, `DebugProfile.entitlements` | הכרחי: הלאנצ'ר כותב חבילות `.app`, נוגע ב-`seforim.db` שמחוץ לכל container, ומריץ כלי מערכת (`ditto`, `open`, `pgrep`). ההפצה היא דרך GitHub Releases ולא App Store. אוצריא עצמה בנויה כך גם היא. |

### אריזה והפצה

אין מתקין ל-macOS — ההפצה היא ה-`.app` עצמו, שהמשתמש גורר ל-`Applications`.
האריזה נעשית עם `ditto` (ראו `.github/workflows/build-macos.yml`) ולא עם
`zip` רגיל, כי רק `ditto` שומר על ה-symlinks וה-extended attributes של
ה-bundle — אריזה רגילה שוברת את החתימה, ואז macOS מסרב להריץ.

הבנייה חתומה ad-hoc (בלי Developer ID ובלי notarization), בדיוק כמו
ההפצה של אוצריא עצמה. משמעות מעשית: מי שמוריד את ה-zip דרך דפדפן יקבל
סימון quarantine ויצטרך לאשר פתיחה דרך *System Settings → Privacy &
Security*, או להסיר את הסימון: `xattr -dr com.apple.quarantine "Otzaria Launcher.app"`.

## אריזה ל-EXE יחיד (inno_bundle) — Windows

הבנייה הרגילה (`flutter build windows`) מייצרת תיקייה שלמה (exe + DLLs +
נתונים), לא קובץ יחיד. לכן נוסף [`inno_bundle`](https://pub.dev/packages/inno_bundle)
כ-dev dependency, שעוטף הכול לקובץ התקנה EXE יחיד דרך Inno Setup:

```bash
cd launcher_app
dart run inno_bundle:build --release
```

הפלט (installer יחיד) אמור לנחות תחת `launcher_app/installer/` (למשל
`installer/Output/*.exe`) — **לא אומת בפועל** כאן (אין Windows/Inno
Setup בסביבה הזו), אז אם הנתיב בפועל שונה, זה יבלוט מיד ב-CI (הצעד
`upload-artifact` יכשל עם "no files found" אם הglob לא תפס כלום).

⚠️ ה-`id` (GUID) בסקשן `inno_bundle:` ב-`pubspec.yaml` הוא קבוע —
**אסור** לשנות אותו בעתיד, אחרת מנגנון הזיהוי-כעדכון-לא-כאפליקציה-חדשה
של Inno Setup יישבר עבור מי שכבר התקין.

ב-CI, Inno Setup מותקן דרך Chocolatey (`choco install innosetup -y`)
לפני ההרצה — לא אומת שזה עובד ב-runner בפועל, רק שזו הדרך המתועדת.

## ⚠️ מה אומת בפועל ומה לא

**macOS — אומת.** האפליקציה נבנתה (`flutter build macos --release`) והורצה
בפועל: היא שלפה את ה-release העדכני מ-GitHub, הורידה את
`otzaria-macos.zip`, התקינה את `אוצריא.app` לתיקייה המנוהלת, ושמרה
`launchPath` שמצביע עליה. `OtzariaProcessGuard` זוהה נכון אוצריא שרצה
בפועל על אותה מכונה וחסם את עדכון המסד כמתוכנן.

**Windows — לא אומת בסביבה הזו.** תיקיית `windows/` עדיין לא הופקה
מקומית; ה-CI משלים אותה עם `flutter create --platforms=windows .` לפני
הבנייה. להרצה מקומית:

```bash
cd launcher_app
flutter create --platforms=windows .   # משלים את תיקיית windows/ החסרה
flutter pub get
flutter run -d windows
```

`flutter create .` על תיקייה קיימת **לא** אמור לדרוס את `lib/` או את
ה-`pubspec.yaml` — אבל **כן** ידרוס את ההתאמות ב-`macos/` אם יורץ עם
`--platforms=macos`. מומלץ לבדוק `git diff` אחרי ההרצה לפני commit.

נותר לא-מאומת גם: **בחירת קובץ ה-DB** ב-Windows (`file_picker` עם
`FileType.custom, allowedExtensions: ['db']`) — יש לוודא בפועל שדיאלוג
הבחירה של Windows אכן מסנן לפי `.db` כצפוי.

## מבנה

```
lib/
├── main.dart                          — נקודת כניסה, data dir דרך path_provider
└── src/
    ├── theme/app_theme.dart           — טוקני עיצוב (צבע/טיפוגרפיה)
    ├── controllers/
    │   ├── otzaria_module_controller.dart   — עוטף OtzariaManager כ-ChangeNotifier
    │   └── library_module_controller.dart   — עוטף LibraryManager כ-ChangeNotifier
    ├── services/
    │   ├── app_logger.dart            — לוג לקובץ תחת <dataDir>/logs
    │   └── file_reveal.dart           — פתיחת תיקייה ב-Explorer/Finder
    ├── widgets/
    │   ├── module_card.dart           — כרטיס מודול אחיד (סטטוס/התקדמות/פעולה)
    │   └── coming_soon_card.dart       — כרטיס מנוטרל למודול עתידי
    └── screens/dashboard_screen.dart  — המסך הראשי, מרכיב הכול יחד
```

## מה עדיין חסר (מעבר לבדיקה בפועל)

- מודול **plugins_manager** עצמו (הכרטיס כאן הוא placeholder בלבד).
- טיפול UI מלא בשגיאות ספציפיות (למשל `OtzariaIsRunningException` מוצג
  היום כטקסט שגיאה גנרי בכרטיס — אפשר לשדרג לדיאלוג ייעודי).
- בדיקות widget (`flutter test`) — לא נכתבו בסבב הזה.

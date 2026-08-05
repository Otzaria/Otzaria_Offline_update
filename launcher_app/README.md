# launcher_app

הדשבורד המאוחד של לאנצ'ר אוצריא — אפליקציית Flutter דסקטופ
(**Windows ו-macOS**) שמחווטת יחד בממשק אחד את:

- **`otzaria_manager`** — עדכון/התקנה/הפעלה של אפליקציית אוצריא עצמה.
- **`library_manager`** — עדכון מסד הספרים (`seforim.db`), כולל חיווט
  מלא של `seforim_library_updater`.
- **מסך התוספים** — פריסה בלבד עם מצב ריק אמיתי (`plugins_manager`
  עדיין לא נבנה).

כל שלושת המודולים (וה-package הראשי `seforim_library_updater`) יושבים
כ-packages נפרדים באותו ריפו; `launcher_app` תלוי בהם דרך `path:` יחסי
(`../otzaria_manager`, `../library_manager`), כך שהוא צריך לשבת **באותה
רמה** בריפו — לצד `otzaria_manager/` ו-`library_manager/`, לא בתוכם.

## ארבעת המסכים

הניווט הוא סרגל צד קבוע (`NavRailItem`) עם ארבעה מסכים, לפי
[OFFLINE_UPDATE_APP_PLAN.md](../OFFLINE_UPDATE_APP_PLAN.md) §2.1:

| מסך | קובץ | תפקיד |
| --- | --- | --- |
| דף הבית | `screens/home_screen.dart` | תמונת מצב אחת + עדכון תוכנת אוצריא |
| ספרייה | `screens/library_screen.dart` | מצב ה-DB, מקור העדכון, תוכן להעברה |
| תוספים | `screens/plugins_screen.dart` | פריסה + מצב ריק (המודול טרם נבנה) |
| הגדרות | `screens/settings_screen.dart` | אוטומציה, ערוצים, נתיבים, רשת, ממשק |

מעליהם סרגל מצב קבוע (`AppShell._TopBar`): מצב רשת, מקור העדכון הפעיל,
אזהרה כשאוצריא פתוחה, בדיקה מחדש ופתיחת יומן הפעילות.

## עיצוב — מועתק מאוצריא

שכבת העיצוב אינה מקורית: היא **פורט מ-`otzaria/lib/theme/` ומ-
`otzaria/lib/widgets/`**, כדי ששתי האפליקציות ייראו זהות. אותו
`ColorScheme.fromSeed` (seed ברירת מחדל: `#2C1B02` בהיר, `#9C27B0` כהה),
אותו רדיוס 8 לכל הפינות, אותו hover בצבע `primary` ואותם טוקני מרווח.

מה מותר להשתמש בו — בדיוק כמו ב-`otzaria/AGENTS.md`:

| צורך | הרכיב היחיד המותר |
| --- | --- |
| אייקונים | `fluentui_system_icons`; `RtlIcon` לאייקון כיווני, `Icon` לשאר |
| כפתורי פעולה | `ActionButton.recommended` / `.neutral` / `.ghost` / `.warning` |
| הודעות למשתמש | `UiSnack.show` / `.showSuccess` / `.showError` |
| דיאלוגים | `showSingleActionDialog` / `showTwoActionsDialog` / `showWarningDialog` |
| כרטיסי הגדרות | `SettingsCard` + `SettingsActionTile` (`.text` / `.path` / `switchTile` / `segmentedTile`) |
| כרטיס תוכן | `AppCard` / `AppCard.section` |
| 2–4 אפשרויות | `AppSegmentedControl` (לא RadioButton) |
| קלט טקסט | `RtlTextField` (לא `TextField`) |
| חיווי מצב | `StatusChip` — תמיד סמל **וגם** טקסט, לא צבע בלבד |

**אסור** `ElevatedButton`/`TextButton`/`OutlinedButton` ישירות, אסור
`ScaffoldMessenger.showSnackBar`, ואסור `.withValues(alpha:)` /
`hoverColor` / `splashColor` מחוץ ל-`lib/src/theme/` — שקיפויות וצבעי
אינטראקציה מוגדרים ב-`AppSurfaces` ו-`AppThemeData` בלבד.

מה שלא פורט (ומתועד במקום): `RtlTextField` כאן הוא עטיפה דקה — תיקוני
מקשי החיצים של Flutter Desktop לא הועברו; ו-`UiSnack` בלי תור הודעות
ובלי כפתורי פעולה.

## אין הורדה או התקנה אוטומטית

בפתיחה מתבצעת **בדיקת מטא־דאטה בלבד** (וגם היא ניתנת לכיבוי בהגדרות).
כל הורדה או התקנה דורשת לחיצה מפורשת, ועדכון ה-DB דורש אישור בדיאלוג.
כל מתגי האוטומציה ב-`AppSettings` כבויים בברירת מחדל פרט ל-
`autoMetadataCheck`, והדלקת **התקנה** אוטומטית דורשת אישור באזהרה
(`_confirmAutoInstall`). ההגדרות נשמרות ל-`launcher_settings.json` עם
`schemaVersion` וכתיבה אטומית (קובץ זמני + rename).

> שינוי התנהגות מהגרסה הקודמת: הדשבורד הישן הוריד והתקין אוטומטית בכל
> פתיחה. זה בוטל בכוונה (תכנון §2.2).

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

**ארבעת המסכים — אומתו ברמת רינדור בלבד.** `flutter analyze` נקי,
`flutter test` עובר (13 בדיקות, כולל pump של כל אחד מארבעת המסכים),
והאפליקציה נבנית ונפתחת ב-macOS ללא שגיאות ריצה. **לא** נבדק בפועל מסלול
עדכון אמיתי מהממשק החדש (הורדה/החלה/הכנת USB), ולא נבדק כלום ב-Windows.

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
├── main.dart                          — נקודת כניסה, data dir, MaterialApp (locale he-IL)
└── src/
    ├── theme/                         — פורט מ-otzaria/lib/theme/
    │   ├── app_theme_data.dart        — createColorScheme + light/dark
    │   ├── app_tokens.dart            — מרווחים, רדיוס 8, טיפוגרפיה
    │   ├── app_surfaces.dart          — רקעים ושקיפויות (נקודת ה-override היחידה)
    │   ├── app_colors.dart / app_seed_colors.dart / layout_tokens.dart
    │   └── theme_exports.dart
    ├── widgets/                       — פורט מ-otzaria/lib/widgets/
    │   ├── action_buttons.dart, app_card.dart, app_dialogs.dart
    │   ├── settings_card.dart, segmented_control.dart, custom_switch.dart
    │   ├── nav_rail_item.dart, rtl_icon.dart, rtl_text_field.dart
    │   ├── status_chip.dart, info_rows.dart, screen_body.dart, ui_snack.dart
    │   └── widgets_exports.dart
    ├── settings/
    │   ├── app_settings.dart          — ההגדרות כ-immutable + JSON עם schemaVersion
    │   └── settings_controller.dart   — טעינה ושמירה אטומית
    ├── controllers/
    │   ├── otzaria_module_controller.dart   — עוטף OtzariaManager כ-ChangeNotifier
    │   └── library_module_controller.dart   — עוטף LibraryManager כ-ChangeNotifier
    ├── services/
    │   ├── app_logger.dart            — לוג לקובץ תחת <dataDir>/logs
    │   └── file_reveal.dart           — פתיחת תיקייה ב-Explorer/Finder
    └── screens/
        ├── app_shell.dart             — סרגל ניווט, סרגל מצב, IndexedStack
        └── home_screen.dart, library_screen.dart, plugins_screen.dart,
            settings_screen.dart
```

## מה עדיין חסר (מעבר לבדיקה בפועל)

- מודול **plugins_manager** עצמו — מסך התוספים הוא פריסה ומצב ריק בלבד.
- **הפרדה בין הורדה להתקנה** בפועל: `otzaria_manager.update()` ו-
  `LibraryManager.applyUpdate()` עדיין מורידים ומתקינים בקריאה אחת, ולכן
  הכפתור אחד ("הורדה והתקנה"). מתוכנן לשלב 2 בתכנון.
- מתגי האוטומציה **נשמרים אך עדיין אינם מפעילים כלום** מלבד
  `autoMetadataCheck` — מנוע המדיניות הוא שלב 5 בתכנון.
- `NetworkStatusService` אמיתי — כרגע מצב הרשת נגזר מהצלחה/כשל של בדיקת
  המטא־דאטה, ולא מבדיקת זמינות מקורות (captive portal, rate limit).
- חבילת ה-USB האחידה (`update-manifest.json` לתוכנה + ספרייה + תוספים)
  ואימות חתימות — שלבים 3 ו-6 בתכנון. כרגע קיימת רק המראה של הספרייה.
- נתיב התקנת אוצריא ותיקיית התוספים מוצגים בהגדרות אך אינם מחווטים ל-
  `OtzariaInstallationLocator` (שטרם נבנה).
- בדיקות: יש בדיקות מודל ובדיקות רינדור לארבעת המסכים
  (`test/widget_test.dart`, `test/screens_test.dart`). אין בדיקות
  end-to-end של ניווט מקלדת, DPI גבוה או מצבי שגיאה אמיתיים.

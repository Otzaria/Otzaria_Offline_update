# launcher_app

הדשבורד המאוחד של לאנצ'ר אוצריא — אפליקציית Flutter דסקטופ
(**Windows ו-macOS**) שמחווטת יחד בממשק אחד את:

- **`otzaria_manager`** — עדכון/התקנה/הפעלה של אפליקציית אוצריא עצמה.
- **`library_manager`** — עדכון מסד הספרים (`seforim.db`), כולל חיווט
  מלא של `seforim_library_updater`.
- **`plugins_manager`** — חנות התוספים האופליינית: סנכרון הקטלוג מ-
  `otzaria.org` אל תיקיית המראה, זיהוי התוספים המותקנים באוצריא, והתקנה
  דרך הפרוטוקול `otzaria://`.

כל שלושת המודולים (וה-package הראשי `seforim_library_updater`) יושבים
כ-packages נפרדים באותו ריפו; `launcher_app` תלוי בהם דרך `path:` יחסי
(`../otzaria_manager`, `../library_manager`, `../plugins_manager`), כך
שהוא צריך לשבת **באותה רמה** בריפו — לצדם, לא בתוכם.

## ארבעת המסכים

הניווט הוא סרגל צד קבוע (`NavRailItem`) עם ארבעה מסכים, לפי
[OFFLINE_UPDATE_APP_PLAN.md](../OFFLINE_UPDATE_APP_PLAN.md) §2.1:

| מסך | קובץ | תפקיד |
| --- | --- | --- |
| דף הבית | `screens/home_screen.dart` | כרטיס ההורדה (בחירת רכיבים) + מצב שלושת הרכיבים |
| ספרייה | `screens/library_screen.dart` | מצב ה-DB והחלת העדכון מהתיקייה המקומית |
| תוספים | `screens/plugins/` | חנות התוספים: רשת כרטיסים, עמוד פרטים, הורדה |
| הגדרות | `screens/settings_screen.dart` | אוטומציה, ערוצים, אחסון, רשת, ממשק |

מעליהם סרגל מצב קבוע (`AppShell._TopBar`): מצב רשת, תיקיית הנתונים,
אזהרה כשאוצריא פתוחה, בדיקה מחדש ופתיחת יומן הפעילות.

יש גם מסך חמישי שאינו בניווט: `screens/setup_error_screen.dart`, שמוצג
במקום האפליקציה כשלא ניתן לכתוב לתיקייה שלצד קובץ ההרצה.

## מלכודת בנייה ב-Windows: `ZSTD_ROOT`

ה-plugin `zstandard_windows` מזריק את נתיב מקורות ה-zstd ישירות ל-
`add_library()` ב-CMake. אם משתנה הסביבה `ZSTD_ROOT` מוגדר עם backslashes
(למשל `C:\pub-cache\...`), CMake מפרש `\p` כ-escape לא חוקי והבנייה נופלת
על `Invalid character escape` — לפני שהקוד של הפרויקט מתקמפל בכלל. הפתרון:
להגדיר את הנתיב עם forward slashes.

```bash
ZSTD_ROOT="C:/pub-cache/hosted/pub.dev/zstandard_native-1.5.0/src/zstd" \
  flutter run -d windows
```

זו בעיה בסביבת הפיתוח בלבד — ב-CI המשתנה אינו מוגדר וההיתר נופל
לפתרון מ-`package_config.json`, ששם הנתיב כבר עם forward slashes.

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
ובלי כפתורי פעולה. ⚠️ מאז שנוסף שדה החיפוש בחנות התוספים יש בלאנצ'ר
קלט טקסט אמיתי ראשון, ולכן פורט מלא של
`otzaria/lib/widgets/text/rtl_text_field.dart` הוא כעת חוב פתוח.

### תוספת שאינה פורט — רכיבי חנות התוספים

`screens/plugins/plugin_visuals.dart` מגדיר ארבעה רכיבים שאין להם מקבילה
במערכת העיצוב של אוצריא: `PluginBadge` (גלולת מטא-דאטה), `PluginTagPill`,
`PluginInstallChip` (עוטף `StatusChip`) ו-`PluginThumbnail`. אליהם מצטרף
ה-lightbox ב-`plugin_screenshot_lightbox.dart`. הם נדרשו כי החנות היא
המרה של ממשק אינטרנט עם רשת כרטיסים ותמונות, ולא מסך הגדרות.

**מסך התוספים הוא היחיד שאינו משתמש ב-`ScreenBody`.** במקומו
`plugin_store_body.dart`, שפורס לרוחב **מלא** ולא מגביל ל-860px
וממרכז. הסיבה: רשת הכרטיסים נגזרת מרוחב מינימלי של 300px לכרטיס (כמו
`minmax(300px, 1fr)` ב-CSS המקורי), ולכן הגבלת רוחב הייתה מקבעת אותה על
שתי עמודות גם במסך רחב. הפריסה כאן מכוונת להיות זהה לחנות המקורית:
שורת סנכרון קבועה בראש (בלי מיתוג — הלאנצ'ר כבר מציג סרגל עליון משלו),
כרטיס חיפוש/סטטוס/מתג בשורה אחת, שורת תגיות מתקפלת עם "הצג עוד", שורת
סיכום, ואז הרשת.

חריגה מכוונת מהמקור: סינון הסטטוס הוא `AppSegmentedControl` ולא תפריט
נפתח, כי מערכת העיצוב מחייבת אותו ל-2–4 אפשרויות.

הכללים שנשמרו בהם: כל הצבעים מ-`ColorScheme` ומ-`AppTokens` (אין hex
קשיח), הפעולות דרך `ActionButton`, ההודעות דרך `UiSnack`, הדיאלוגים דרך
`showTwoActionsDialog`/`showSingleActionDialog`, הקלט דרך `RtlTextField`,
סינון הסטטוס דרך `AppSegmentedControl`, וחיווי מותקן/עדכון דרך
`StatusChip` — סמל וגם טקסט. הרכיבים נשארים **מקומיים** לתיקייה
`screens/plugins/` ואינם מיוצאים ל-`widgets/`, כדי שלא ייחשבו בטעות
לרכיבים מאושרים של מערכת העיצוב.

`flutter_svg` לא נוסף כתלות, ולכן לוגו ה-SVG שהחנות המקורית הציגה כ-
fallback הוחלף באייקון `puzzle_piece` על רקע `primaryContainer`.

### תאריך עברי

`services/hebrew_date.dart` — המרה גרגוריאני→עברי וגימטריה. הדרוש כאן
מפני שהחנות המקורית קיבלה את זה מ-`Intl` בדפדפן
(`he-u-ca-hebrew`), ול-`package:intl` ב-Dart אין לוח שנה עברי. מגובה
בבדיקות מול עוגנים מוכרים (ה' באייר תש"ח, פורים תשפ"ד, ראש השנה תשפ"ו)
ובבדיקה שראש השנה לא נופל בימים א׳/ד׳/ו׳ ב-70 שנים רצופות.

## תיקיית הנתונים צמודה לתוכנה

`AppPaths.resolve()` קובע את `<תיקיית ה-exe>/OtzariaData` — וזה לא ניתן
לשינוי. **ב-`AppSettings` אין אף שדה נתיב.** כשאין הרשאת כתיבה שם, `main()`
מציג `SetupErrorScreen` ולא מפעיל את האפליקציה; הנפילה שהייתה מתקבלת מאליה
(`%APPDATA%`) פסולה כאן, כי היא משאירה את הנתונים על המחשב המקוון ובכך
שוברת בשקט את השימוש בכונן נייד.

## הרשת נדרשת רק להורדה

`AppShell.downloadAll()` היא הפעולה היחידה בכל האפליקציה שנוגעת ברשת. היא
מורידה לתיקייה המקומית רק את הרכיבים שסומנו (`syncApp`/`syncLibrary`/
`syncPlugins`), בטור ולא במקביל — הם חולקים רוחב פס והמסד לבדו ~1GB.

`checkAll()`, כל בדיקת גרסה וכל התקנה — קוראות **מהתיקייה המקומית בלבד**,
גם כשהמחשב מחובר. אין נפילה לרשת בשום מסלול.

התקנה מהתיקייה דורשת לחיצה מפורשת, ועדכון ה-DB דורש אישור בדיאלוג. הדלקת
**התקנה אוטומטית** (`autoInstallApp`/`autoInstallLibrary`, כבויים בברירת
מחדל) דורשת אישור באזהרה — `_confirmAutoInstall` — ומחווטת ב-
`AppShell._autoInstallIfEnabled`, שמדלג על עדכון מסד כשאוצריא פתוחה.
ההגדרות נשמרות ל-`launcher_settings.json` עם `schemaVersion` וכתיבה אטומית
(קובץ זמני + rename).

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

## אריזה ל-Windows — portable ZIP, בלי מתקין

`flutter build windows` מייצר תיקייה שלמה (exe + DLLs + `data/`) ולא קובץ
יחיד — וזו מגבלה של Flutter, לא של האריזה. לכן אין מתקין: ההפצה היא
תיקיית ה-Release ארוזה ב-zip, שמוציאים ומריצים ממנה את ה-exe ישירות, בלי
התקנה ובלי רישום ב-Windows. `inno_bundle` הוסר ב-`748accf`.

```bash
cd launcher_app
flutter build windows --release
# הפלט: build/windows/x64/runner/Release/
```

שני ה-workflows שבונים ל-Windows (`ci.yml` ו-`build-exe.yml`) עושים בדיוק
את זה ואז `Compress-Archive` על התיקייה. ⚠️ אם מחזירים בעתיד מתקין, יש
להחזיר קודם את התלות ל-`pubspec.yaml` — חוסר ההתאמה הזה בין ה-workflow
ל-pubspec הוא מה שהחזיק את ה-CI אדום בין 24 ביולי ל-6 באוגוסט 2026.

## ⚠️ מה אומת בפועל ומה לא

**ארבעת המסכים — אומתו ברמת רינדור בלבד.** `flutter analyze` נקי,
`flutter test` עובר (28 בדיקות, כולל pump של כל אחד מארבעת המסכים ושל
חנות התוספים במצב ריק ועם תוסף בקטלוג), והאפליקציה נבנית ונפתחת ב-macOS
ללא שגיאות ריצה. **לא** נבדק בפועל מסלול עדכון אמיתי מהממשק החדש
(הורדה/החלה/הכנת USB/סנכרון תוספים), ולא נבדק כלום ב-Windows.

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
    │   ├── library_module_controller.dart   — עוטף LibraryManager כ-ChangeNotifier
    │   └── plugins_module_controller.dart   — עוטף PluginsManager כ-ChangeNotifier
    ├── services/
    │   ├── app_logger.dart            — לוג לקובץ תחת <dataDir>/logs
    │   ├── file_reveal.dart           — פתיחת תיקייה ב-Explorer/Finder
    │   └── hebrew_date.dart           — המרה לתאריך עברי + גימטריה
    └── screens/
        ├── app_shell.dart             — סרגל ניווט, סרגל מצב, IndexedStack
        ├── home_screen.dart, library_screen.dart, settings_screen.dart
        └── plugins/                   — חנות התוספים
            ├── plugins_screen.dart          — רשימה ↔ פרטים, סנכרון
            ├── plugin_store_card.dart       — כרטיס ברשת
            ├── plugin_detail_view.dart      — עמוד פרטי תוסף
            ├── plugin_filters_bar.dart      — חיפוש, סטטוס, תגיות
            ├── plugin_screenshot_lightbox.dart
            ├── plugin_sync_overlay.dart, plugin_updates_dialog.dart
            └── plugin_visuals.dart          — רכיבים מקומיים (לא פורט)
```

## מה עדיין חסר (מעבר לבדיקה בפועל)

- **חנות התוספים לא נבדקה מקצה לקצה** — הבדיקות מכסות רינדור ולוגיקה,
  אבל סנכרון אמיתי מ-`otzaria.org`, העברה ב-USB, ופתיחת
  `otzaria://plugin/install-local` מול אוצריא אמיתית — טרם הורצו. ראו
  `plugins_manager/README.md`.
- **הורדת גרסה היסטורית של תוסף** — ה-API מחזיר `versions`, אבל המסלול
  היחיד שמומש הוא לגרסה החיה.
- פורט מלא של `RtlTextField` (ראו למעלה).
- **הפרדה בין הורדה להתקנה** בפועל: `otzaria_manager.update()` ו-
  `LibraryManager.applyUpdate()` עדיין מורידים ומתקינים בקריאה אחת, ולכן
  הכפתור אחד ("הורדה והתקנה"). מתוכנן לשלב 2 בתכנון.
- מתגי האוטומציה **נשמרים אך עדיין אינם מפעילים כלום** מלבד
  `autoMetadataCheck` ו-`autoDownloadAllPlugins` — מנוע המדיניות הוא שלב 5
  בתכנון. שני מתגי "תוספים מותקנים" מושבתים בכוונה ומסבירים למה: סנכרון
  חלקי אינו קיים (`PluginMirrorSync` מביא את כל הקטלוג), והתקנה עוברת דרך
  הפרוטוקול `otzaria://` שפותח את אוצריא לכל תוסף בנפרד.
- **ערוץ התוספים** בהגדרות אינו prerelease אלא סינון: לכל תוסף יש `status`
  משלו, ולכן `pluginsChannel` קובע רק את סינון ברירת המחדל שהחנות נפתחת בו
  (`pluginStatusFilterFor`), והמשתמש יכול לשנות אותו בחנות.
- `NetworkStatusService` אמיתי — כרגע מצב הרשת נגזר מהצלחה/כשל של בדיקת
  המטא־דאטה, ולא מבדיקת זמינות מקורות (captive portal, rate limit).
- חבילת ה-USB האחידה (`update-manifest.json` לתוכנה + ספרייה + תוספים)
  ואימות חתימות — שלבים 3 ו-6 בתכנון. כרגע קיימת רק המראה של הספרייה.
- נתיב התקנת אוצריא בהגדרות אינו מחווט ל-`OtzariaInstallationLocator`
  (שטרם נבנה). תיקיית התוספים **כן** מחווטת — היא מוזנת ל-
  `InstalledPluginsScanner`.
- בדיקות: בדיקות מודל, בדיקות רינדור לארבעת המסכים ובדיקות התאריך העברי
  (`test/widget_test.dart`, `test/screens_test.dart`,
  `test/hebrew_date_test.dart`) — 28 עוברות. אין בדיקות end-to-end של
  ניווט מקלדת, DPI גבוה או מצבי שגיאה אמיתיים.

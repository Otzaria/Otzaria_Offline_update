# launcher_app

הדשבורד המאוחד של הלאנצ'ר — אפליקציית Flutter דסקטופ (**Windows ו-macOS**)
שמוצגת למשתמש בשם **"עדכוני אוצריא"** ומחווטת יחד בממשק אחד את:

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

## חמשת המסכים

הניווט הוא סרגל צד קבוע (`NavRailItem`) עם חמישה מסכים. דף הבית מכוון
למשתמש הקצה הפשוט — שני אריחים בלבד ("יש עדכון? לחצו"); הפרטים המלאים
(גרסאות, נתיבים, "מה התחדש") יושבים במסכי "תוכנה"/"ספרייה" הנפרדים:

| מסך | קובץ | תפקיד |
| --- | --- | --- |
| דף הבית | `screens/home_screen.dart` | שני אריחים (תוכנה/ספרייה) + בדיקת עדכונים צדדית ברשת |
| תוכנה | `screens/otzaria_screen.dart` | מצב ההתקנה, "מה התחדש" (release notes מ-GitHub), בחירת מיקום ידנית |
| ספרייה | `screens/library_screen.dart` | מצב ה-DB והחלת העדכון מהתיקייה המקומית |
| תוספים | `screens/plugins/` | חנות התוספים: רשת כרטיסים, עמוד פרטים, הורדה |
| הגדרות | `screens/settings_screen.dart` | שפה ומראה, אוטומציה, מה לסנכרן, תמיכה |

מעליהם **שורת הכותרת של החלון עצמו** (`widgets/app_title_bar.dart`, פורט של
`otzaria/lib/navigation/view/custom_title_bar.dart`): סמל אוצריא
(`assets/images/otzaria_logo.png`) ושם התוכנה בהתחלה, שם המסך הפתוח באמצע,
וכפתורי החלון בסוף. מסגרת החלון של המערכת מוסתרת ב-`main.dart`
(`window_manager`, `TitleBarStyle.hidden`), ולכן השורה הזו היא גם מה שגורר
את החלון — ו**כל** מסך שמוצג במקום `AppShell` חייב לכלול אותה, אחרת החלון
נשאר בלי סגירה ובלי גרירה (ראו `SetupErrorScreen`). מחווני המצב שהיו בסרגל
הקודם (רשת, תיקיית הנתונים, "נבדק ב־", אזהרה כשאוצריא פתוחה) הוסרו — כולם
מופיעים ממילא בדף הבית ובמסכי הרכיבים, ליד הפעולה שהם מתארים; בדיקה מחדש
יושבת במסכי "תוכנה"/"ספרייה" ויומן הפעילות בהגדרות.

בבדיקות widget יש להזריק `showWindowButtons: false`: `WindowCaption` מדבר
עם ערוץ פלטפורמה שאינו קיים שם.

יש גם מסך שישי שאינו בניווט: `screens/setup_error_screen.dart`, שמוצג
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
| מלל למשתמש | `context.strings.<סעיף>.<שדה>` מ-`otzaria_l10n` — לעולם לא מחרוזת בקוד |

**אסור** `ElevatedButton`/`TextButton`/`OutlinedButton` ישירות, אסור
`ScaffoldMessenger.showSnackBar`, ואסור `.withValues(alpha:)` /
`hoverColor` / `splashColor` מחוץ ל-`lib/src/theme/` — שקיפויות וצבעי
אינטראקציה מוגדרים ב-`AppSurfaces` ו-`AppThemeData` בלבד.

מה שלא פורט (ומתועד במקום): `RtlTextField` כאן הוא עטיפה דקה — תיקוני
מקשי החיצים של Flutter Desktop לא הועברו; ו-`UiSnack` בלי תור הודעות
ובלי כפתורי פעולה. ⚠️ מאז שנוסף שדה החיפוש בחנות התוספים יש בלאנצ'ר
קלט טקסט אמיתי ראשון, ולכן פורט מלא של
`otzaria/lib/widgets/text/rtl_text_field.dart` הוא כעת חוב פתוח.

### שפה וכיווניות

הלאנצ'ר דו-לשוני (עברית כברירת מחדל, אנגלית). כל המלל יושב ב-`otzaria_l10n`
— ראו `AGENTS.md` §4 "All user-visible text" לכללים המלאים. שלוש נקודות
שנוגעות דווקא לרכיבים כאן:

- `RtlTextField` **אינו** כופה עוד RTL. הוא יורש את כיוון השפה, אחרת
  חיפוש באנגלית היה נכתב מימין לשמאל.
- `UiSnack` יושב ב-`Overlay` ולכן אינו יורש כיווניות מה-Navigator; הוא
  קורא את השפה ישירות מ-`AppL10n`. זה החריג היחיד המותר.
- לחצי "חזרה"/"קדימה" יש להשתמש ב-`context.backArrowIcon` /
  `context.forwardArrowIcon`. `RtlIcon` (שדרכו `ActionButton` מצייר כל
  אייקון) מהפך חיצים ב-RTL, ולכן העוזרים האלה מוסרים לו את הסמל ההפוך —
  והחץ שמוצג בפועל יוצא זהה בשתי השפות.

### תוספת שאינה פורט — רכיבי חנות התוספים

`screens/plugins/plugin_visuals.dart` מגדיר רכיבים שאין להם מקבילה
במערכת העיצוב של אוצריא: `PluginBadge` (גלולת מטא-דאטה), `PluginTagPill`,
`PluginInstallChip` (עוטף `StatusChip`), `PluginThumbnail` ו-
`PluginSectionEyebrow` (ה"עינית" מעל כותרת סעיף). אליהם מצטרף
ה-lightbox ב-`plugin_screenshot_lightbox.dart`. הם נדרשו כי החנות היא
המרה של ממשק אינטרנט עם רשת כרטיסים ותמונות, ולא מסך הגדרות.

**מסך התוספים הוא היחיד שאינו משתמש ב-`ScreenBody`.** במקומו
`plugin_store_body.dart`, שפורס לרוחב **מלא** ולא מגביל ל-860px
וממרכז. הסיבה: רשת הכרטיסים נגזרת מרוחב מינימלי של 300px לכרטיס (כמו
`minmax(300px, 1fr)` ב-CSS המקורי), ולכן הגבלת רוחב הייתה מקבעת אותה על
שתי עמודות גם במסך רחב.

**שלושת מסכי החנות = שלושת ה-routes של האתר** (`PluginStorePage`):

| מסך | באתר | מה יש בו |
| --- | --- | --- |
| דף בית אצור | `/plugins` | hero (כותרת/תקציר מהאתר + חיפוש), "תוספים נבחרים" עם "הצג עוד נבחרים", שורת תוספים לכל קטגוריית דף-בית עם "לכל הקטגוריה", ופס גילוי לכל התוספים |
| כל התוספים | `/plugins/all` | פירורי לחם, כרטיס סינון (חיפוש/סטטוס/תגיות), שורת סיכום והרשת |
| דף קטגוריה | `/plugins/category/<slug>` | פירורי לחם, שם ותיאור הקטגוריה, מונה, והרשת בסדר הידני מהאתר |

הניווט ביניהם הוא סרגל הצד של הקטגוריות (`plugin_store_nav.dart`) —
מעל 1080px סרגל צד קבוע, מתחת לזה שורת צ'יפים אופקית, בדיוק כמו
ה-`aside`/`nav` באתר. "כל התוספים" מוצנע בתחתית הסרגל, גם זה כמו שם.
**הסינון קיים רק במסך "כל התוספים"** — דף הבית ודף הקטגוריה מציגים
אצירה, ואין באתר סינון בתוכם. מראה שסונכרנה לפני שהאתר הכניס קטגוריות
לא מציגה ניווט כלל, ונפתחת ישר ב"כל התוספים".

**כל התוכן הגליל של החנות עובר כ-slivers**, ו-`PluginStoreBody` מקבל
`slivers` בלבד. זו לא קפדנות: `SliverList` עם רשימת ילדים קבועה בונה את
כולם מיד, וכל רשת כרטיסים כזו גוררת פענוח תמונות של כרטיסים שמחוץ למסך —
בדיוק הבעיה שבגללה הרשת הועברה בזמנו מ-`GridView(shrinkWrap: true)`.
מאותה סיבה סרגל הצד יושב **מחוץ** ל-`CustomScrollView` (הוא גם נשאר
במקומו בזמן גלילה, כמו ה-sticky באתר), ואין בתוך אזור הגלילה שום גליל
מקונן — גליל אופקי מקונן היה בולע את גלגלת העכבר ומקפיא את גלילת העמוד.

**מתג "רק מה שלא מותקן" הוא תוספת של הלאנצ'ר** שאין לה מקבילה באתר, ולכן
מקומו שונה: גלולה קטנה בקצה השמאלי של שורת הסנכרון, ולא בכרטיס הסינון.
בשונה מכל שאר הסינון הוא חל על **כל** מסכי החנות, כולל האצירה — זו המטרה
של הלאנצ'ר (לראות מה חסר), ומשתמש שנמצא בדף הבית לא אמור לעבור ל"כל
התוספים" רק כדי להפעילו. `hasCuratedHome` נמדד לכן על המבנה ולא על מה
שנשאר אחריו, וכשהמתג מרוקן דף שלם מוצג הסבר עם כפתור לכיבויו.

**הכרטיס ברשת הוא בגובה קבוע, ולכן אין בו רכיב שגובהו משתנה.** שתי שורות
הגלולות (סטטוס/גרסה/הורדות/מצב-התקנה, והתגיות) הן `Wrap`, ומספיק שבב אחד
ארוך או תגית נוספת כדי שיגלשו לשורה נוספת ויגלישו את הכרטיס. לכל אחת
מהן תקציב גובה קבוע עם `Clip.hardEdge`, השבב בכרטיס מקוצר
(`PluginInstallChip(compact: true)`) והפירוט המלא נשאר בעמוד התוסף.
`_cardContentHeight` ב-`plugins_screen.dart` הוא סכום התקציבים האלה —
שינוי באחד מהם מחייב לעדכן אותו, ובדיקת "כרטיס עמוס" תופסת את זה.

חריגה מכוונת מהמקור: סינון הסטטוס הוא תפריט נפתח ולא צ'יפים, וחיפוש
ה-hero מוביל לסינון המקומי ב"כל התוספים" ולא לדף חיפוש צד-שרת — אין
רשת במחשב היעד.

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
לשינוי. **ב-`AppSettings` אין אף שדה נתיב.** אין גם הגדרת גיבוי למסד: עותק
שני של ~1GB על כונן נייד היה מכפיל את הדרישה בלי להוסיף ביטחון, ושני מסלולי
ההחלה בטוחים בלעדיו (ראו `library_manager/README.md`). כשאין הרשאת כתיבה שם, `main()`
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
| `CFBundleDisplayName = עדכוני אוצריא` | `macos/Runner/Info.plist` | השם שהמשתמש רואה, בעברית — מופרד משם קובץ ההפעלה. |
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

## אריזה ל-Windows — exe בודד, בלי מתקין

`flutter build windows` מייצר תיקייה שלמה (exe + DLLs + `data/`) ולא קובץ
יחיד — וזו מגבלה של Flutter, לא של האריזה. לכן אין מתקין: ההפצה היא
**קובץ exe אחד שמחלץ את עצמו**, שמריצים מאיפה שהוא יושב, בלי התקנה ובלי
רישום ב-Windows. `inno_bundle` הוסר ב-`748accf`.

```bash
cd launcher_app
flutter build windows --release
# הפלט: build/windows/x64/runner/Release/
pwsh ./windows_stub/package.ps1
# הפלט: build/עדכוני אוצריא.exe — זה כל מה שמפיצים
```

### exe אחד, שמחלץ את ערמת הקבצים לידו בהרצה הראשונה

זה מה שמתקבל על הכונן אחרי ההרצה הראשונה:

```
עדכוני אוצריא.exe   ← ה-stub, וזה מה שהמשתמש לוחץ תמיד
app-files/          ← launcher_app.exe, ה-DLL, data/, ובזמן ריצה גם OtzariaData/
```

**אי אפשר פשוט להזיז את `launcher_app.exe` מעלה.** הוא תלוי ב-
`flutter_windows.dll` שנטענת ב-load time (לפני שקוד שלנו רץ, ולכן אין דרך
להפנות אותה לתיקייה אחרת), ובתיקיית `data/` שנפתרת יחסית לתיקיית ה-exe
([`main.cpp`](windows/runner/main.cpp)). לכן מה שמופץ הוא **stub**: קובץ C
זעיר ב-[`windows_stub/`](windows_stub/) שנושא את כל ערמת הקבצים כ-resource
מסוג `RCDATA`, מחלץ אותה ל-`app-files\` לידו, ואז `CreateProcessW` על
`app-files\launcher_app.exe` — עם אותו אייקון ועם `asInvoker` מפורש במניפסט.

| החלטה | למה |
| --- | --- |
| ה-stub חי ב-`windows_stub/` ולא ב-`windows/` | ה-CI מריץ `flutter create --platforms=windows .`, שדורס את תיקיית הרנר |
| מקומפל עם `/MT` (CRT סטטי) | ה-stub יושב **מחוץ** ל-`app-files`, ולכן לא רואה את `vcruntime140.dll` שהבנייה של Flutter מעתיקה לתיקיית ה-Release. עם `/MD` הוא לא היה עולה בלי VC++ Redist |
| החילוץ הוא ל-`app-files\` **ליד ה-exe**, לא ל-`%TEMP%` | `OtzariaData/` יורדת לתוך `app-files` וכוללת הורדות של ~1GB. חילוץ לזמני היה מוחק אותן בכל הרצה ושובר את כל מודל ה-USB |
| החילוץ מתבצע ב-`tar.exe` של Windows | קורא zip, קיים מ-Windows 10 1803, וחוסך ספריית דחיסה בתוך ה-stub. חלון הקונסולה שלו נשאר גלוי בכוונה — בלעדיו ההרצה הראשונה נראית תקועה |
| הסימון `app-files\.ready`, ולא בדיקת קיום ה-exe | נכתב רק אחרי חילוץ שהצליח, ולכן חילוץ שנקטע באמצע לא ייראה שלם בהרצה הבאה |
| ה-payload נשאר מוטמע ב-exe לתמיד | ה-exe מגיע לגודל של הבנייה כולה, אבל בתמורה מחיקה בטעות של `app-files` מתקנת את עצמה בהרצה הבאה |
| `OtzariaData/` נשארת בתוך `app-files` | `AppPaths` גוזרת אותה מ-`Platform.resolvedExecutable`, וזו הבחירה שנעשתה כאן — בשורש נשארים בדיוק שני פריטים. לא נדרש שינוי ב-`app_paths.dart` |
| ה-stub לא ממתין לבן | אחרת שני תהליכים היו יושבים בזיכרון לכל אורך הריצה |
| הודעת השגיאה היחידה שבו כתובה inline | קוד C לא יכול לתלות ב-`otzaria_l10n`. זהו החריג היחיד לכלל, והיא מוצגת רק כשההכנה להרצה הראשונה נכשלה |

שני ה-workflows שבונים ל-Windows (`ci.yml` ו-`build-exe.yml`) קוראים
ל-`windows_stub/package.ps1`, שמרכיב את הפריסה, דוחס אותה ל-`payload.zip`,
ואז מקמפל את ה-stub (`vswhere` → `vcvars64` → `rc` + `cl`) — בסדר הזה, כי
`rc.exe` הוא זה שמטמיע את ה-zip. הסקריפטים הם UTF-8 בלי BOM ומכילים עברית,
ולכן חייבים `pwsh` (7+) ולא Windows PowerShell 5.1.

⚠️ **מ-GitHub Actions ההורדה תמיד תהיה zip.** `upload-artifact` עוטף כל
ארטיפקט ב-zip, גם קובץ בודד; בתוכו יש כעת exe אחד ולא zip פנימי נוסף.

⚠️ אם מחזירים בעתיד מתקין, יש להחזיר קודם את התלות ל-`pubspec.yaml` —
חוסר ההתאמה הזה בין ה-workflow ל-pubspec הוא מה שהחזיק את ה-CI אדום בין
24 ביולי ל-6 באוגוסט 2026.

## ⚠️ מה אומת בפועל ומה לא

**ארבעת המסכים — אומתו ברמת רינדור בלבד.** `flutter analyze` נקי,
`flutter test` עובר (42 בדיקות, כולל pump של כל אחד מארבעת המסכים, של
חנות התוספים במצב ריק ועם תוסף בקטלוג, ושל סינון לפי קטגוריה מהמראה),
והאפליקציה נבנית ונפתחת ב-macOS
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
    │   ├── plugins_module_controller.dart   — עוטף PluginsManager כ-ChangeNotifier
    │   └── progress_notifier.dart           — דילול דיווחי התקדמות (ראו למטה)
    ├── services/
    │   ├── app_logger.dart            — לוג לקובץ תחת <dataDir>/logs
    │   ├── file_reveal.dart           — פתיחת תיקייה ב-Explorer/Finder
    │   └── hebrew_date.dart           — המרה לתאריך עברי + גימטריה
    └── screens/
        ├── app_shell.dart             — סרגל ניווט, סרגל מצב, IndexedStack מדורג
        ├── home_screen.dart, otzaria_screen.dart, library_screen.dart, settings_screen.dart
        └── plugins/                   — חנות התוספים
            ├── plugins_screen.dart          — רשימה ↔ פרטים, סנכרון
            ├── plugin_store_card.dart       — כרטיס ברשת
            ├── plugin_detail_view.dart      — עמוד פרטי תוסף
            ├── plugin_filters_bar.dart      — חיפוש, סטטוס, תגיות
            ├── plugin_screenshot_lightbox.dart
            ├── plugin_sync_overlay.dart, plugin_updates_dialog.dart
            └── plugin_visuals.dart          — רכיבים מקומיים (לא פורט)
```

## ביצועים — שלוש החלטות שאין לבטל בטעות

- **`AppShell` בונה מסך רק בכניסה הראשונה אליו** (`_builtScreens`).
  `IndexedStack` בונה את *כל* ילדיו, ולכן חנות התוספים — רשת כרטיסים עם
  `Image.file` לכל תוסף — נבנתה ופענחה את כל התמונות בעלייה, לפני שהמשתמש פתח
  את הלשונית. תוצאה נלווית מכוונת: הודעת "יש עדכונים לתוספים" מוצגת בכניסה
  הראשונה ללשונית ולא בפתיחת התוכנה. מאותו רגע המסך נשאר בעץ, ולכן ההודעה
  יכולה לצוץ (למשל אחרי סנכרון שהתחיל מדף הבית) כשהמשתמש כבר בלשונית אחרת —
  ובחירת תוסף מתוכה קוראת ל-`PluginsScreen.onRequestFocus`, שמחזיר את הניווט
  ללשונית התוספים כדי שעמוד הפרטים לא ייפתח מאחורי מסך אחר.
- **דיווחי התקדמות עוברים דרך `ProgressNotifier.notifyProgress()`.**
  `PatchDownloader` מדווח על כל צ׳אנק; בהורדת מסד של 1GB אלה עשרות אלפי
  `setState` על `AppShell`, כלומר בנייה מחדש של כל עץ ה-widgets. `notifyListeners`
  רגיל נשאר לשינויי **מצב** בלבד.
- **תמונות החנות מפוענחות בגודל התצוגה** דרך `decodeWidthFor` ב-
  `plugin_visuals.dart`, והרשת היא `SliverGrid` בתוך ה-`CustomScrollView` של
  `PluginStoreBody`. הגרסה הקודמת (`GridView(shrinkWrap: true)` בתוך `ListView`)
  ביטלה וירטואליזציה, ולכן החזיקה את כל הכרטיסים ואת כל התמונות בזיכרון בבת אחת.

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
- **אין ערוצי גרסאות במסך ההגדרות.** בחירת הגרסה של תוכנת אוצריא יושבת
  במסך "תוכנה", ליד שתי הגרסאות עצמן, ומופיעה **רק כששתיהן בתיקייה** —
  כלומר כשקיים pre-release חדש מהיציבה (ההורדה מביאה תמיד את שתיהן;
  ראו `otzaria_manager/README.md`). היא נשמרת כ-`preferAppPrerelease`
  ב-`AppSettings`. הספרייה תמיד יציבה בלבד, והחנות נפתחת מציגה את כל
  התוספים — כולל בטא וניסיוני.
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

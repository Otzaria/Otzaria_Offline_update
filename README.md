עדכוני אוצריא — Otzaria Offline Update

תוכנה לעדכון אופליין של אוצריא : התוכנה עצמה, ספריית הספרים והתוספים. מוקדשת ללומדי התורה הנמנעים משימוש באינטרנט, גם החסום.

איך זה עובד

הרשת צריכה רק להורדה. כל השאר — בדיקת גרסאות, התקנה ועדכון — קורא מתיקייה מקומית בלבד.

מקוון — מורידים את הרכיבים שנבחרו (תוכנה / ספרייה / תוספים) אל תיקיית מראה ( OtzariaData) שצמודה לקובץ ההרצה, למשל על כונן נייד.
הלא־מקוון — מריצים את הלאנצ'ר מהכונן, והוא מתקין ומעדכן מתוך המראה.

הלאנצ'ר מוצג למשתמש בשם "עדכוני אוצריא" , ותומך ב- Windows וב- macOS .

מבנה הריפו

חבילת כל תיק היאייה נפרדת עם pubspec.yamlו-README משלו.

תיקיה	תפקיד
/(שׁוֹרֶשׁ),lib/	seforim_library_updater— עדכון מסד הספרים מהפצות דלתא שלSeforimLibrary
otzaria_manager/	התקנה, עדכון והפעלה של אפליקציית אוצריא עצמה
library_manager/	חיווט עדכון המסד ( seforim.db) לתוך הלאנצ'ר
plugins_manager/	חנות התוספים האופליינית: סנכרון הקטלוג מ- otzaria.orgוהתקנה דרךotzaria://
custom_apps_manager/	רשם "תוכנות נוספות" שנוסעות על הכונן
error_reports_manager/	איסוף דיווחי טעויות במחשב הלא־מקוון והעלאתם ממחשב מקוון
otzaria_l10n/	מחרוזות ממשק (עברית ואנגלית)
launcher_app/	אפליקציית Flutter לדסקטופ שמחברת את כל המודולים לדשבורד אחד
tool/,test/	סקריפטי עזר ובדיקות של החבילה

launcher_appתלוי בשאר החבילות דרך path:יחסים, הם חייבים לשבת באותה רמה בריפו.

החבילה הראשונה:seforim_library_updater

חבילת Flutter היא צד הלקוח של פורמט ההפצה של SeforimLibrary. היא:

מגלה גרסאות ב-GitHub Releases ובוחרת עדכון מסלול — דלתא או הורדה מלאה.
מורידה ומאמתת קובצי patch-vX-vY.db.zst.
מחילה אותם אטומית על ה-DB המקומי.
מוודאת שה-hash הלוגי של התוצאה זה לזה שה-קוטלין ייצר.

צרכן, לא יצרן. מאגר ה-קוטלין מייצר את המסד והפרשים. LogicalContentHasherו- PatchApplierהם תרגום ישיר של הלוגיקה שם, וחייבים להסכים איתה בית־בית.

נקודות שכדאי לדעת:

אין כאן ממשק משתמש. ה-package הוא לוגיקה בלבד; מסכים והתקדמות באחריות האפליקציה הצורכת.
פלטפורמות מקוריות בלבד (אנדרואיד, iOS, macOS, Windows, Linux) — dart:ioאינו נתמך ב-Web.
חילוץ zstd מוזר על ידי הצרכן ( PatchDownloader.decompress).
חישוב SHA-256 עובר דרךFastSha256 (CNG ב-Windows, CommonCrypto ב-macOS, package:cryptoכגיבוי) — המסד כולו נקרא בכל התאמה, והמימוש הנייטיבי מהיר גודל מהדארטי.
⚠️ פעולות כבדות — הריצו ב-Isolate. LogicalContentHasher.compute ו- PatchApplier.applyסינכרוניות וארוכות:
חֵץ
await Isolate.run(() => const PatchApplier().apply(/* ... */));
בניה והרצאה
לַחֲבוֹט
cd launcher_app
flutter pub get
flutter run -d windows   # או: -d macos
Windows: תיקיית windows/נוצרת ב-CI; מקומית יש להריץ קודם flutter create --platforms=windows .. ההפצה היא קובץ exe בודד שמחלץ את עצמו ( windows_stub/package.ps1).
macOS: flutter build macos --release מייצר Otzaria Launcher.app. ההפצה היא ה- .appעצמו, בחתימה אד-הוק.

פרטים מלאים, כולל שחרור גרסאות ועדכון עצמי: launcher_app/README.md.

בדקות
לַחֲבוֹט
dart test                                                  # ה-package הראשי: fixtures בלבד
SEFORIM_LIBRARY_RELEASES_DIR=/path/to/releases dart test   # + בדיקות מול הפצות אמיתיות (אופציונלי)
cd launcher_app && flutter test                            # הלאנצ'ר
מסמכים נוספים
AGENTS.md— כללי עבודה וקונבנציות בפרויקט
CHANGELOG.md— שינויים היסטוריים
LICENSE

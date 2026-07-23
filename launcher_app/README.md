# launcher_app

הדשבורד המאוחד של לאנצ'ר אוצריא — אפליקציית Flutter (Windows desktop)
שמחווטת יחד בממשק אחד את:

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

## ⚠️ הגדרה נדרשת לפני הרצה — לא בוצעה כאן

הסביבה שבה זה נכתב **אינה כוללת Flutter SDK**, ולכן לא הורצו הפקודות
הבאות. יש להריץ אותן מקומית לפני הבנייה הראשונה:

```bash
cd launcher_app
flutter create --platforms=windows .   # משלים את תיקיות windows/ (וכו') החסרות
flutter pub get
flutter run -d windows
```

`flutter create .` על תיקייה קיימת **לא** אמור לדרוס את `lib/`
או את ה-`pubspec.yaml` הקיימים (הוא רק ממלא קבצי scaffolding
platform-specific חסרים) — אבל מומלץ לבדוק ב-`git diff` אחרי ההרצה
לפני commit, ליתר ביטחון.

### דברים שלא נבדקו כי לא היה כאן טולצ'יין Flutter

1. **קוד לא הורץ/קומפל** — נכתב לפי ה-API הציבורי המתועד של
   `otzaria_manager` ו-`library_manager` (barrel files + doc-comments),
   אך לא עבר `flutter analyze`/`flutter run` בפועל.
2. **גרסאות חבילות** (`file_picker`, `google_fonts`, `path_provider`) —
   נבחרו לפי מה שידוע כתואם ל-Flutter/Dart עדכניים; אם `pub get` ייכשל
   על conflict, ייתכן שצריך ליישר גרסה מדויקת מול שאר החבילות בריפו.
3. **בחירת קובץ ה-DB** (`file_picker`) — משתמש ב-
   `FileType.custom, allowedExtensions: ['db']`. יש לוודא בפועל שדיאלוג
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

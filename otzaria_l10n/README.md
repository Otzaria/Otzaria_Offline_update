# otzaria_l10n

חבילת Dart **טהורה** (בלי Flutter) שמרכזת את כל המלל שמוצג למשתמש בלאנצ'ר —
בעברית ובאנגלית.

## למה חבילה נפרדת

חלק ניכר מהמלל שהמשתמש רואה בפועל לא נוצר ב-`launcher_app` אלא בחבילות
התשתית: הודעות שגיאה של `LibraryApplyException` / `PluginStoreException`,
טקסטי השלב של הורדה וסנכרון, ותוויות הערוץ של `otzaria_manager`. הן מוצגות
כמו שהן (`errorMessage = e.toString()`), ולכן בלי מקום משותף הן היו נשארות
בעברית גם במצב אנגלית.

`otzaria_manager` ו-`plugins_manager` אינן מורשות לתלות ב-Flutter (ראו
`AGENTS.md`), ולכן החבילה הזו טהורה ובלי תלויות בכלל.

## מבנה

| קובץ | תפקיד |
| --- | --- |
| `app_language.dart` | `enum AppLanguage` — קוד ISO, `isRtl`, ומיפוי locale של המערכת. |
| `app_strings.dart` | הממשק המופשט, מחולק לסעיפים לפי מסך/חבילה. |
| `strings_he.dart` | עברית — **המקור**. |
| `strings_en.dart` | אנגלית — תרגום חופשי, לא מילה במילה. |
| `app_l10n.dart` | `AppL10n.strings` — השפה הפעילה כמצב גלובלי יחיד. |

## שימוש

בחבילות התשתית (אין `BuildContext`):

```dart
throw LibraryApplyException(AppL10n.strings.libraryDomain.updateCancelled);
```

ב-`launcher_app` — דרך `AppStringsScope` (`context.strings`), כדי שווידג'טים
`const` ייבנו מחדש בהחלפת שפה. את הערך הגלובלי מציב `SettingsController`.

## הוספת מחרוזת

1. שדה/מתודה חדשים בסעיף המתאים ב-`app_strings.dart`.
2. מימוש בשני הקבצים — האנלייזר נכשל אם שכחת אחד מהם.

עברית היא שפת המקור, אבל **השפה שמוצגת** נגזרת כברירת מחדל משפת המחשב:
`AppLanguage.forLanguageCode` ממפה את ה-locale של המערכת, ו-`AppSettings`
של הלאנצ'ר הוא שקורא לו (ראו `AppLanguagePreference`). כשאין locale מוכר —
אנגלית.

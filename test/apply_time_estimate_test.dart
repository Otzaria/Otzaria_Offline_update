import 'package:seforim_library_updater/src/services/apply_time_estimate.dart';
import 'package:test/test.dart';

/// הבדיקות האלה מקבעות את **הכיול** מול מדידות שנלקחו מלוגים אמיתיים
/// (`update() מתחיל` → `update() הסתיים`, ספטמבר 2026). הן אינן דורשות דיוק
/// לשנייה — הפיזור בין מכונות הוא פי 3–5 — אלא שהאומדן ייפול בטווח שנמדד,
/// ושההשוואה בין שני המסלולים תצא כמו בשטח.
void main() {
  const estimate = ApplyTimeEstimate();
  const mb = 1 << 20;

  group('האומדן נופל בטווח שנמדד בשטח', () {
    test('החלפת מסד מלא של 1.31GB — נמדד 129–581 שניות', () {
      final seconds = estimate.fullRouteSeconds(1373487294);
      expect(seconds, inInclusiveRange(129, 581));
    });

    test('patch של 8.5MB — נמדד 214–1,039 שניות', () {
      final seconds = estimate.deltaRouteSeconds([8503129]);
      expect(seconds, inInclusiveRange(214, 1039));
    });

    // ⚠️ המקרה שבגללו כל זה נכתב: patch של 585MB מ-v23 ל-v27.
    test('patch של 585MB — נמדד 3,864 שניות', () {
      final seconds = estimate.deltaRouteSeconds([584711742]);
      expect(seconds, closeTo(3864, 500));
    });

    // המחיר הקבוע הוא סריקת ה-hash על כל המסד, ולכן שרשרת משלמת אותו שוב
    // ושוב — זה מה שהופך "כמה קבצים קטנים" לעדכון ארוך.
    test('שרשרת של ארבעה צעדים משלמת את המחיר הקבוע ארבע פעמים', () {
      final one = estimate.deltaRouteSeconds([mb]);
      final four = estimate.deltaRouteSeconds([mb, mb, mb, mb]);
      expect(four, closeTo(one * 4, 1));
    });
  });

  group('הטווח שבו עוד כדאי להעדיף קובצי עדכון', () {
    // חודש רגיל: patch של 8.5MB מול מסד מלא של 1.31GB — כ-6 דקות מול כ-4.
    // הדלתא איטית יותר, ובכל זאת מנצחת: היא חוסכת ~1.3GB בהורדה.
    test('עדכון שוטף נשאר בטווח למרות שהוא איטי מעט יותר', () {
      final delta = estimate.deltaRouteSeconds([8503129]);
      final full = estimate.fullRouteSeconds(1373487294);
      expect(delta, greaterThan(full));
      expect(estimate.isOutOfRange(delta, full), isFalse);
    });

    test('ההרחבה של v27 יוצאת מהטווח', () {
      final delta = estimate.deltaRouteSeconds([584711742]);
      final full = estimate.fullRouteSeconds(1373487294);
      expect(estimate.isOutOfRange(delta, full), isTrue);
    });

    // שני חלקי הטווח נבדקים בנפרד: יחס בלי הפרש מוחלט היה גורר הורדה של
    // 1.3GB בשביל דקה.
    test('יחס גדול בלי הפרש מוחלט אינו יוצא מהטווח', () {
      expect(estimate.isOutOfRange(100, 10), isFalse);
    });

    test('הפרש מוחלט בלי יחס אינו יוצא מהטווח', () {
      expect(estimate.isOutOfRange(1600, 1000), isFalse);
    });
  });

  test('דקות מעוגלות כלפי מעלה, ולעולם לא אפס', () {
    expect(ApplyTimeEstimate.minutesOf(0.5), 1);
    expect(ApplyTimeEstimate.minutesOf(61), 2);
    expect(ApplyTimeEstimate.minutesOf(3864), 65);
  });
}

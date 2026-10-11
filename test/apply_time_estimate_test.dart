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

    // ה-applier מאמת hash פעם אחת לשרשרת (מקור בצעד הראשון, יעד באחרון),
    // ולכן המחיר הקבוע משולם פעם אחת, וצעדי הביניים זולים.
    test('שרשרת משלמת את המחיר הקבוע פעם אחת וצעדי ביניים זולים', () {
      final one = estimate.deltaRouteSeconds([mb]);
      final four = estimate.deltaRouteSeconds([mb, mb, mb, mb]);
      final variable = estimate.stepSecondsPerMb;
      expect(one, closeTo(estimate.stepFixedSeconds + variable, 0.001));
      expect(
          four,
          closeTo(
              estimate.stepFixedSeconds +
                  3 * estimate.stepIntermediateSeconds +
                  4 * variable,
              0.001));
      expect(four, lessThan(one * 4));
    });

    test('שרשרת של 3 patch של 8MiB אינה נפסלת מול מסד מלא של 1.73GB', () {
      final delta = estimate.deltaRouteSeconds([8 * mb, 8 * mb, 8 * mb]);
      const fullBytes = 1766 * mb;
      expect(
        estimate.isOutOfRange(delta, estimate.fullRouteSeconds(fullBytes),
            savedDownloadBytes: fullBytes - 24 * mb),
        isFalse,
      );
      // גם בלי הזיכוי: הצעדים הזולים לבדם מחזירים אותה אל הטווח.
      expect(
        estimate.isOutOfRange(delta, estimate.fullRouteSeconds(fullBytes)),
        isFalse,
      );
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

  // v31→v32: patch של 114MiB מול מסד מלא של 1.85GB. החיסכון בהורדה (~1.7GB)
  // מרחיב את השוליים, ולכן patch גדול בכמה אחוזים אינו נפסל.
  group('זיכוי חיסכון בהורדה סביב 115MiB', () {
    const fullBytes = 1894 * mb; // 1.85GB
    final fullSeconds = estimate.fullRouteSeconds(fullBytes);

    bool out(int patchMb) {
      final bytes = patchMb * mb;
      return estimate.isOutOfRange(
        estimate.deltaRouteSeconds([bytes]),
        fullSeconds,
        savedDownloadBytes: fullBytes - bytes,
      );
    }

    test('114MiB נשאר', () => expect(out(114), isFalse));
    test('119MiB (גדול ב-4%) נשאר', () => expect(out(119), isFalse));
    test('130MiB נשאר', () => expect(out(130), isFalse));
    test('patch של 600MiB נפסל', () => expect(out(600), isTrue));

    test('בלי הזיכוי patch של 130MiB היה נפסל (הרגרסיה)', () {
      final delta = estimate.deltaRouteSeconds([130 * mb]);
      expect(estimate.isOutOfRange(delta, fullSeconds), isTrue);
    });

    test('חיסכון שלילי מוגבל לאפס', () {
      final delta = estimate.deltaRouteSeconds([584711742]);
      final full = estimate.fullRouteSeconds(1373487294);
      expect(
        estimate.isOutOfRange(delta, full, savedDownloadBytes: -5 * mb),
        estimate.isOutOfRange(delta, full),
      );
    });

    // v27: patches של ~500MB שסכומם 2.15GB מול מלא 1.31GB — אין חיסכון.
    test('v27: סכום patches גדול מהמסד אינו מקבל זיכוי ונפסל', () {
      final full = estimate.fullRouteSeconds(1373487294);
      final delta =
          estimate.deltaRouteSeconds([for (var i = 0; i < 4; i++) 537 * mb]);
      expect(
        estimate.isOutOfRange(delta, full,
            savedDownloadBytes: 1373487294 - 4 * 537 * mb),
        isTrue,
      );
    });
  });

  test('דקות מעוגלות כלפי מעלה, ולעולם לא אפס', () {
    expect(ApplyTimeEstimate.minutesOf(0.5), 1);
    expect(ApplyTimeEstimate.minutesOf(61), 2);
    expect(ApplyTimeEstimate.minutesOf(3864), 65);
  });
}

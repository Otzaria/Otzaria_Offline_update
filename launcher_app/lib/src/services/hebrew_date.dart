import 'package:otzaria_l10n/otzaria_l10n.dart';

/// המרת תאריך לועזי לתאריך עברי בגימטריה — למשל `ט"ו בשבט ה'תשפ"ו`.
///
/// חנות התוספים המקורית קיבלה את זה חינם מ-`Intl` בדפדפן
/// (`he-u-ca-hebrew`), אבל ל-`package:intl` ב-Dart אין לוח שנה עברי. לכן
/// ההמרה מחושבת כאן: אלגוריתם המולד הסטנדרטי (Dershowitz & Reingold),
/// והגימטריה היא פורט ישיר של `toHebrewNumeral` מהחנות.
class HebrewDate {
  const HebrewDate(this.year, this.month, this.day);

  /// חודשים ממוספרים ניסן=1 … אדר=12, אדר ב'=13 — המספור של האלגוריתם,
  /// שבו השנה מתחילה בחודש 7 (תשרי).
  final int year;
  final int month;
  final int day;

  /// "יום חודש שנה" בעברית, למשל `ט"ו בשבט ה'תשפ"ו`.
  @override
  String toString() =>
      '${toHebrewNumeral(day)} ב$monthName ${toHebrewNumeral(year)}';

  String get monthName {
    if (month == 12 && isLeapYear(year)) return 'אדר א׳';
    if (month == 13) return 'אדר ב׳';
    return _monthNames[month]!;
  }

  static const Map<int, String> _monthNames = {
    1: 'ניסן',
    2: 'אייר',
    3: 'סיון',
    4: 'תמוז',
    5: 'אב',
    6: 'אלול',
    7: 'תשרי',
    8: 'חשון',
    9: 'כסלו',
    10: 'טבת',
    11: 'שבט',
    12: 'אדר',
    13: 'אדר ב׳',
  };

  /// היום המוחלט (Rata Die) של א' בתשרי ה'א' — עוגן החישוב.
  static const int _epoch = -1373429;

  static HebrewDate fromDateTime(DateTime date) =>
      _fromAbsolute(_absoluteFromGregorian(date.year, date.month, date.day));

  /// מפרמט מחרוזת תאריך מה-API (`YYYY-MM-DD` או ISO-8601 מלא). מחזיר את
  /// המחרוזת המקורית אם אי אפשר לפרסר אותה — עדיף על שגיאה במסך.
  /// באנגלית מוחזר תאריך לועזי: תאריך עברי בגימטריה בתוך משפט אנגלי אינו
  /// קריא, וגם אין מה לתרגם בו — שמות החודשים הם התוכן עצמו.
  static String format(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final date = DateTime.tryParse(raw);
    if (date == null) return raw;
    if (!AppL10n.language.isRtl) {
      final month = date.month.toString().padLeft(2, '0');
      final day = date.day.toString().padLeft(2, '0');
      return '${date.year}-$month-$day';
    }
    return HebrewDate.fromDateTime(date).toString();
  }

  static bool isLeapYear(int year) => ((7 * year + 1) % 19) < 7;

  static int _lastMonthOfYear(int year) => isLeapYear(year) ? 13 : 12;

  /// מספר הימים שחלפו מהעוגן עד ראש השנה של [year], כולל שלוש הדחיות
  /// (לא אד"ו ראש, גטר"ד ובט"ו תקפ"ט).
  static int _elapsedDays(int year) {
    final monthsElapsed = 235 * ((year - 1) ~/ 19) +
        12 * ((year - 1) % 19) +
        (7 * ((year - 1) % 19) + 1) ~/ 19;
    final partsElapsed = 204 + 793 * (monthsElapsed % 1080);
    final hoursElapsed = 11 +
        12 * monthsElapsed +
        793 * (monthsElapsed ~/ 1080) +
        partsElapsed ~/ 1080;
    // ה-+1 מיישר את יום המולד לעוגן [_epoch]. בלעדיו יום השבוע של המולד
    // יוצא מוסט, ולכן הדחיות למטה מופעלות על היום הלא נכון — וראש השנה
    // נופל בטעות יום או שניים מוקדם מדי בחלק מהשנים.
    final day = 29 * monthsElapsed + hoursElapsed ~/ 24 + 1;
    final parts = (hoursElapsed % 24) * 1080 + partsElapsed % 1080;

    int adjusted;
    if (parts >= 19440) {
      adjusted = day + 1;
    } else if (day % 7 == 2 && parts >= 9924 && !isLeapYear(year)) {
      adjusted = day + 1;
    } else if (day % 7 == 1 && parts >= 16789 && isLeapYear(year - 1)) {
      adjusted = day + 1;
    } else {
      adjusted = day;
    }

    // ראש השנה לא יכול לצאת ביום א', ד' או ו'.
    const notAllowed = {0, 3, 5};
    return notAllowed.contains(adjusted % 7) ? adjusted + 1 : adjusted;
  }

  static int _daysInYear(int year) =>
      _elapsedDays(year + 1) - _elapsedDays(year);

  static bool _longHeshvan(int year) => _daysInYear(year) % 10 == 5;

  static bool _shortKislev(int year) => _daysInYear(year) % 10 == 3;

  static int _daysInMonth(int year, int month) {
    if (const {2, 4, 6, 10, 13}.contains(month)) return 29;
    if (month == 12 && !isLeapYear(year)) return 29;
    if (month == 8 && !_longHeshvan(year)) return 29;
    if (month == 9 && _shortKislev(year)) return 29;
    return 30;
  }

  static int _absoluteFromHebrew(int year, int month, int day) {
    var total = day + _elapsedDays(year) + _epoch;
    if (month < 7) {
      // ניסן..אדר נופלים אחרי תשרי של אותה שנה עברית.
      for (var m = 7; m <= _lastMonthOfYear(year); m++) {
        total += _daysInMonth(year, m);
      }
      for (var m = 1; m < month; m++) {
        total += _daysInMonth(year, m);
      }
    } else {
      for (var m = 7; m < month; m++) {
        total += _daysInMonth(year, m);
      }
    }
    return total;
  }

  static int _absoluteFromGregorian(int year, int month, int day) {
    const monthDays = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    final isLeap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

    var total = day;
    for (var m = 1; m < month; m++) {
      total += monthDays[m - 1];
      if (m == 2 && isLeap) total += 1;
    }
    return total +
        365 * (year - 1) +
        (year - 1) ~/ 4 -
        (year - 1) ~/ 100 +
        (year - 1) ~/ 400;
  }

  static HebrewDate _fromAbsolute(int absolute) {
    var year = (absolute - _epoch) ~/ 366;
    while (_absoluteFromHebrew(year + 1, 7, 1) <= absolute) {
      year++;
    }

    var month = absolute < _absoluteFromHebrew(year, 1, 1) ? 7 : 1;
    while (absolute >
        _absoluteFromHebrew(year, month, _daysInMonth(year, month))) {
      month++;
    }

    return HebrewDate(
      year,
      month,
      absolute - _absoluteFromHebrew(year, month, 1) + 1,
    );
  }

  /// המרת מספר לגימטריה — פורט ישיר של `toHebrewNumeral` מהחנות המקורית,
  /// כולל טו/טז והצבת הגרש/גרשיים.
  static String toHebrewNumeral(int number) {
    const ones = ['', 'א', 'ב', 'ג', 'ד', 'ה', 'ו', 'ז', 'ח', 'ט'];
    const tens = ['', 'י', 'כ', 'ל', 'מ', 'נ', 'ס', 'ע', 'פ', 'צ'];
    const hundreds = ['', 'ק', 'ר', 'ש', 'ת'];

    if (number <= 0) return '';
    if (number > 9999) return '$number';

    var remaining = number;
    var result = '';

    final thousands = remaining ~/ 1000;
    if (thousands > 0) {
      result += "${ones[thousands]}'";
      remaining %= 1000;
    }

    final hundredsDigit = remaining ~/ 100;
    if (hundredsDigit > 0) {
      result += switch (hundredsDigit) {
        <= 4 => hundreds[hundredsDigit],
        5 => 'תק',
        6 => 'תר',
        7 => 'תש',
        8 => 'תת',
        _ => 'תתק',
      };
      remaining %= 100;
    }

    // ט"ו וט"ז נכתבים כך ולא כי"ה/י"ו, מטעמי קדושת השם.
    if (remaining == 15) {
      result += 'טו';
    } else if (remaining == 16) {
      result += 'טז';
    } else {
      final tensDigit = remaining ~/ 10;
      if (tensDigit > 0) {
        result += tens[tensDigit];
        remaining %= 10;
      }
      if (remaining > 0) result += ones[remaining];
    }

    if (result.length == 1) return "$result'";
    return '${result.substring(0, result.length - 1)}"'
        '${result.substring(result.length - 1)}';
  }
}

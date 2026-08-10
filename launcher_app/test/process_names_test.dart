import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/library_manager.dart';
import 'package:otzaria_manager/otzaria_manager.dart';

/// שני מנגנונים בשתי חבילות מזהים את **אותו תהליך**: `OtzariaProcessGuard`
/// חוסם עדכון DB כשאוצריא פתוחה, ו-`RunningOtzariaLocator` שולף מאותו
/// תהליך את מיקום ההתקנה. הן אינן תלויות זו בזו, ורק הלאנצ'ר רואה את
/// שתיהן — ולכן הבדיקה שהרשימות לא נפרדו יושבת כאן.
///
/// דריפט היה מייצר את הבאג המבלבל ביותר: "מזוהה שאוצריא פתוחה, ובכל זאת
/// לא מזוהה איפה היא מותקנת".
void main() {
  test('שמות התהליך זהים בשתי החבילות, בכל פלטפורמה', () {
    for (final os in const ['windows', 'macos', 'linux']) {
      expect(
        RunningOtzariaLocator.processNamesFor(os),
        OtzariaProcessGuard.processNamesFor(os),
        reason: os,
      );
    }
  });
}

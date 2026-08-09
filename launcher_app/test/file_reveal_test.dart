import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/services/file_reveal.dart';

/// [FileReveal] מריץ תהליך מערכת אמיתי, ולכן נבדק רק במקום שבו אפשר לעשות
/// זאת בלי לפתוח חלון על המסך: ב-macOS `open` על נתיב שאינו קיים נכשל
/// בשקט. בווינדוס `explorer.exe` פותח חלון (ואף מחזיר קוד יציאה 1 כשהצליח),
/// ולכן אין כאן בדיקה שלו — היא הייתה תופעת לוואי ולא בדיקה.
void main() {
  test('נתיב שאינו קיים מחזיר false ואינו זורק', () async {
    expect(await FileReveal.revealDirectory('/אין/כזו/תיקייה/בכלל'), isFalse);
  }, skip: !Platform.isMacOS);

  test('בפלטפורמה שאינה נתמכת התוצאה היא false, לא חריגה', () async {
    // ה-fallback שה-UI מסתמך עליו: להציג את הנתיב כטקסט להעתקה.
    expect(
      await FileReveal.revealDirectory(Directory.systemTemp.path),
      isFalse,
    );
  }, skip: Platform.isMacOS || Platform.isWindows);
}

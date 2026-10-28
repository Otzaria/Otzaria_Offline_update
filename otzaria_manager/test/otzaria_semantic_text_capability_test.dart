import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:test/test.dart';

void main() {
  _versionShapes();
  _otherExecutable();
  bool? reads({String? installed, String? declared}) =>
      OtzariaCapabilities.readsSemanticLineText4(
        installedVersion: installed,
        capabilities:
            declared == null ? null : OtzariaCapabilities(appVersion: declared),
      );

  test('אוצריא שמצרפת מנוע 6.0.0 (0.9.98.2 ומעלה) קוראת text4', () {
    expect(reads(installed: '0.9.98.2'), isTrue);
    expect(reads(installed: '0.9.98.2+807'), isTrue);
    expect(reads(installed: '0.9.99'), isTrue);
  });

  test('גרסה ידועה ישנה יותר אינה קוראת text4', () {
    expect(reads(installed: '0.9.98'), isFalse);
    expect(reads(installed: '0.9.98+801'), isFalse);
    expect(reads(installed: '0.9.97'), isFalse);
  });

  test('בלי גרסה ידועה אין הוכחה, לא תשובה שלילית ולא חיובית', () {
    expect(reads(), isNull);
    expect(reads(installed: 'לא-גרסה'), isNull);
  });

  test('הגרסה המותקנת גוברת על קובץ היכולות שנשאר מהגרסה הקודמת', () {
    expect(reads(installed: '0.9.98', declared: '0.9.98.2'), isFalse);
    expect(reads(installed: '0.9.98.2', declared: '0.9.98'), isTrue);
    expect(reads(declared: '0.9.98.2'), isTrue);
  });
}

// tags שנבדקו: 0.9.97+789 ^0.8.4, 0.9.98+801 ^3.1.0, 0.9.98.2+807 ^6.0.0;
// מעל 0.9.98.2 הנחה בלבד (מנוע אינו חוזר אחורה).
void _versionShapes() {
  bool? reads(String? installed) =>
      OtzariaCapabilities.readsSemanticLineText4(installedVersion: installed);

  group('צורות גרסה', () {
    test('מספר build אחרי + אינו משנה את ההכרעה', () {
      expect(reads('0.9.98.2+1'), isTrue);
      expect(reads('0.9.98.2+807'), isTrue);
      expect(reads('0.9.98+999'), isFalse);
      expect(reads('0.9.98+99802'), isFalse, reason: 'צורת pubspec, לא tag');
    });

    test('סיומת מקף נחתכת; הבסיס המספרי מכריע', () {
      expect(reads('0.9.98.2-beta'), isTrue);
      expect(reads('0.9.98-beta'), isFalse);
      expect(reads('v0.9.98.2'), isTrue);
    });

    test('גרסאות חדשות מעל הסף נחשבות קוראות (הנחה, לא אומתה מול tag)', () {
      expect(reads('0.9.98.3'), isTrue);
      expect(reads('0.9.99'), isTrue);
      expect(reads('0.10.0'), isTrue);
      expect(reads('1.0.0'), isTrue);
    });

    test('גרסה בלי מספרים או ריקה אינה מוכחת', () {
      expect(reads(''), isNull);
      expect(reads('dev'), isNull);
    });
  });
}

void _otherExecutable() {
  test('capabilities של executable אחר אינו מוכיח דבר, אך המותקן עדיין מכריע',
      () {
    const caps = OtzariaCapabilities(
      appVersion: '0.9.98.2',
      exePath: r'D:\other\otzaria.exe',
    );
    bool? reads({String? installed}) =>
        OtzariaCapabilities.readsSemanticLineText4(
          capabilities: caps,
          launchPath: r'C:\Otzaria\otzaria.exe',
          installedVersion: installed,
        );
    expect(reads(), isNull);
    expect(reads(installed: '0.9.98'), isFalse);
    expect(reads(installed: '0.9.98.2'), isTrue);
  });
}

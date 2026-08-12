// שומר על החוזה בין קוד ה-Dart של העדכון העצמי לבין ה-stub של Windows
// וסקריפט האריזה. אין ביניהם שום תלות בזמן קומפילציה — שם תיקייה, שם משתנה
// סביבה או שם דגל שיזוזו בצד אחד ישברו את העדכון **בלי שאף בדיקה תיכשל**,
// וזו בדיוק אותה מלכודת שבגללה קיים `process_names_test.dart`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/self_update/launcher_install_layout.dart';

void main() {
  String read(String relativePath) {
    final file = File(relativePath);
    expect(file.existsSync(), isTrue,
        reason: 'הבדיקה רצה משורש החבילה: $relativePath');
    return file.readAsStringSync();
  }

  late String stubC;
  late String packagePs1;
  late String buildStubPs1;

  setUpAll(() {
    stubC = read('windows_stub/stub.c');
    packagePs1 = read('windows_stub/package.ps1');
    buildStubPs1 = read('windows_stub/build_stub.ps1');
  });

  test('שם תיקיית ה-payload זהה בשלושת המקומות', () {
    const dir = LauncherInstallLayout.payloadDirName;
    expect(stubC, contains('kPayloadDir[] = L"$dir"'));
    expect(packagePs1, contains("payloadDirName = '$dir'"));
  });

  test('משתנה הסביבה שבו ה-stub מוסר את הנתיב שלו זהה בשני הצדדים', () {
    expect(
      stubC,
      contains(
          'kStubPathEnvVar[] = L"${LauncherInstallLayout.stubPathEnvVar}"'),
    );
    // ובלי ההצבה עצמה הוא לא יגיע לתהליך הבן.
    expect(stubC, contains('SetEnvironmentVariableW(kStubPathEnvVar'));
  });

  test('הדגל שממתין לסגירת הלאנצ\'ר הישן זהה בשני הצדדים', () {
    expect(
      stubC,
      contains(
          'kAfterUpdateFlag[] = L"${LauncherInstallLayout.afterUpdateFlag}='),
    );
  });

  test('שם ה-exe שהאריזה מייצרת הוא זה שהאיתור מחפש', () {
    expect(
      packagePs1,
      contains("appFileName = '${LauncherInstallLayout.packagedExeName}'"),
    );
  });

  test('המרקר מושווה לגרסת ה-payload, ולא רק נבדק שהוא קיים', () {
    // זה מה שהופך עדכון עצמי לחילוץ מחדש: exe חדש נושא payload חדש, והמרקר
    // הישן (או ריק, כמו זה שכתבו גרסאות קודמות) אינו תואם לו.
    expect(stubC, contains('MarkerMatchesPayload'));
    expect(stubC, contains('strcmp(buffer, PAYLOAD_VERSION_A)'));
    expect(stubC, contains('#include "version.h"'));
  });

  test('גרסת ה-payload נלקחת מ-pubspec ומיוצרת אל version.h', () {
    expect(buildStubPs1, contains('pubspec.yaml'));
    expect(buildStubPs1, contains('PAYLOAD_VERSION_A'));
    expect(buildStubPs1, contains('PAYLOAD_VERSION_COMMAS'));
    // הכותרת המיוצרת מגיעה גם ל-rc וגם ל-cl דרך תיקיית ה-build.
    expect(buildStubPs1, contains(r'rc /nologo /i "$outDir"'));
    expect(buildStubPs1, contains(r'/I"$outDir"'));
  });
}

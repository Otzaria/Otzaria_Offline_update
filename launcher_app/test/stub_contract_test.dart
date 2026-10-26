// שומר על החוזה בין קוד ה-Dart של העדכון העצמי לבין ה-stub של Windows
// וסקריפט האריזה. אין ביניהם שום תלות בזמן קומפילציה — שם תיקייה, שם משתנה
// סביבה או שם דגל שיזוזו בצד אחד ישברו את העדכון **בלי שאף בדיקה תיכשל**,
// וזו בדיוק אותה מלכודת שבגללה קיים `process_names_test.dart`.

import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/self_update/launcher_install_layout.dart';
import 'package:launcher_app/src/self_update/launcher_self_installer.dart';
import 'package:launcher_app/src/services/app_paths.dart';
import 'package:launcher_app/src/theme/theme_exports.dart';
import 'package:otzaria_manager/otzaria_manager.dart';

void main() {
  String read(String relativePath) {
    final file = File(relativePath);
    expect(file.existsSync(), isTrue,
        reason: 'הבדיקה רצה משורש החבילה: $relativePath');
    return file.readAsStringSync();
  }

  late String stubC;
  late String stubRc;
  late String packagePs1;
  late String buildStubPs1;
  late String packPayloadPs1;

  setUpAll(() {
    stubC = read('windows_stub/stub.c');
    stubRc = read('windows_stub/stub.rc');
    packagePs1 = read('windows_stub/package.ps1');
    buildStubPs1 = read('windows_stub/build_stub.ps1');
    packPayloadPs1 = read('windows_stub/pack_payload.ps1');
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

  test('השם שג\'וב הפרסום מעלה בו הוא זה שהאיתור מכיר', () {
    // גיטהאב מנקה שמות נכסים מתווים שאינם ASCII, ולכן השם שעל ה-release שונה
    // מזה שעל הכונן — ומי שמוריד ידנית נשאר איתו. אם הם ייפרדו, העדכון העצמי
    // של מי שהוריד ידנית יאבד את ה-stub שלו כששוברים תיקו.
    expect(
      read('../.github/workflows/release.yml'),
      contains('assets/${LauncherInstallLayout.publishedExeName}'),
    );
  });

  test('הלאנצ\'ר אינו מאמץ את עצמו כאוצריא — בשני שמותיו', () {
    // שני השמות מכילים "otzaria"/"אוצריא", ולכן כלל התאמת-השם ב-
    // `OtzariaAppLocator` היה בוחר בהם. הפסילה שם היא לפי שם בלי סיומת,
    // באותיות קטנות.
    for (final name in const [
      LauncherInstallLayout.packagedExeName,
      LauncherInstallLayout.publishedExeName,
    ]) {
      expect(OtzariaAppLocator.mentionsOtzaria(name), isTrue,
          reason: 'אחרת אין בכלל מה לפסול');
      expect(
        OtzariaAppLocator.isOurOwnExe(name),
        isTrue,
        reason: 'שם שהלאנצ\'ר נקרא בו חייב להיפסל באיתור אוצריא: $name',
      );
    }
  });

  test('שמות השאריות של ההחלפה זהים ב-stub ובלאנצ\'ר', () {
    expect(stubC,
        contains('kStagedExeName[] = L"${LauncherSelfInstaller.stagedName}"'));
    expect(
        stubC,
        contains(
            'kPreviousExeName[] = L"${LauncherSelfInstaller.previousName}"'));
    expect(stubC,
        contains('kTargetFileName[] = L"${LauncherSelfInstaller.targetName}"'));
  });

  test('המרקר מושווה לגרסת ה-payload, ולא רק נבדק שהוא קיים', () {
    // זה מה שהופך עדכון עצמי לחילוץ מחדש: exe חדש נושא payload חדש, והמרקר
    // הישן (או ריק, כמו זה שכתבו גרסאות קודמות) אינו תואם לו.
    expect(stubC, contains('MarkerMatchesPayload'));
    expect(stubC, contains('strcmp(buffer, PAYLOAD_MARKER_A)'));
    expect(stubC, contains('WriteFile(file, PAYLOAD_MARKER_A'));
    expect(stubC, contains('#include "version.h"'));
  });

  test('בניית בדיקה מוסיפה את הקומיט למרקר, ולא לגרסה', () {
    // בלי זה exe לבדיקה באותה גרסה כמו המותקן לא חולץ, ורץ הקוד הישן.
    expect(buildStubPs1, contains('PAYLOAD_MARKER_A'));
    expect(buildStubPs1, contains(r'$env:PAYLOAD_BUILD_ID'));
    expect(
      read('../.github/workflows/build-exe.yml'),
      contains(r'PAYLOAD_BUILD_ID: ${{ github.sha }}'),
    );
  });

  test('בניית CI שאינה release אינה נושאת את גרסת ה-release, ומסומנת בקומיט',
      () {
    final ci = read('../.github/workflows/ci.yml');
    final steps = ci.split(RegExp(r'\n(?=      - )'));
    final versionSteps =
        steps.where((step) => step.contains('set_launcher_version.sh'));

    expect(versionSteps, isNotEmpty);
    for (final step in versionSteps) {
      expect(step, contains('if: inputs.release'), reason: step);
    }
    final packageStep =
        steps.singleWhere((step) => step.contains('package.ps1'));
    expect(packageStep, contains(r'PAYLOAD_BUILD_ID: ${{ github.sha }}'));
    expect(
      read('../.github/workflows/release.yml'),
      matches(RegExp(r'uses: \./\.github/workflows/ci\.yml\s+with:\s+'
          r'release: true')),
    );
  });

  test('גרסת ה-payload נלקחת מ-pubspec ומיוצרת אל version.h', () {
    expect(buildStubPs1, contains('pubspec.yaml'));
    expect(buildStubPs1, contains('PAYLOAD_VERSION_A'));
    expect(buildStubPs1, contains('PAYLOAD_VERSION_COMMAS'));
    // הכותרת המיוצרת מגיעה גם ל-rc וגם ל-cl דרך תיקיית ה-build.
    expect(buildStubPs1, contains(r'rc /nologo /i "$outDir"'));
    expect(buildStubPs1, contains(r'/I"$outDir"'));
  });

  test('משתנה הסביבה של גרסת ה-payload זהה בשני הצדדים ומוצב בפועל', () {
    // זה מה שמאפשר ללאנצ'ר לזהות `app-files` שאינה שלו — ראו `PayloadCheck`.
    expect(
      stubC,
      contains('kPayloadVersionEnvVar[] = '
          'L"${LauncherInstallLayout.payloadVersionEnvVar}"'),
    );
    expect(stubC, contains('SetEnvironmentVariableW(kPayloadVersionEnvVar'));
    // הערך שמוצב חייב להיות אותה גרסה שבמרקר, בצורתה ה-wide.
    expect(buildStubPs1, contains('PAYLOAD_VERSION_W'));
    expect(stubC, contains('PAYLOAD_VERSION_W'));
  });

  test('ה-InternalName שב-VERSIONINFO של ה-stub הוא זה שהאיתור מחפש', () {
    expect(
      stubRc,
      contains('VALUE "InternalName", '
          '"${LauncherInstallLayout.stubInternalName}"'),
    );
  });

  test('שם המרקר שהלאנצ\'ר מוחק הוא זה שה-stub כותב', () {
    expect(
      stubC,
      contains('kReadyMarker[] = L"${LauncherInstallLayout.readyMarkerName}"'),
    );
  });

  test('תיקיית הנתונים שה-stub כותב אליה לוג היא זו של הלאנצ\'ר', () {
    // הלוג יושב ב-`<app-files>/OtzariaData/logs`, לצד `launcher.log`.
    expect(stubC, contains('kDataDirName[] = L"${AppPaths.dirName}"'));
  });

  test('ה-stub נעצר בכונן המערכת לפני שהוא יוצר קובץ כלשהו', () {
    final check = stubC.indexOf('if (IsOnSystemDrive(stub_dir))');
    expect(check, greaterThan(0));
    expect(check, lessThan(stubC.indexOf('PrepareLog(work_dir);')));
    expect(stubC, contains('L"SystemDrive"'));
  });

  test('החילוץ אינו נשען על tar.exe ולא על שום תהליך חיצוני', () {
    // התלות הזאת היא ששברה חילוץ בשטח: `tar.exe` קיים רק מ-Windows 10 1803,
    // והנתיבים עברו אליו דרך שורת פקודה ב-ANSI. אם היא חוזרת — שתיפול כאן.
    // ההשוואה היא על **קוד** ולא על כל הקובץ: ההסבר למה היא הוסרה נשאר בהערות.
    expect(stubC, isNot(contains(r'L"\\tar.exe"')));
    expect(stubC, isNot(contains('GetShortPathNameW')));
    expect(stubC, contains('CreateDecompressor'));
    // התהליך היחיד שה-stub מריץ הוא הלאנצ'ר עצמו.
    expect(RegExp(r'CreateProcessW\(').allMatches(stubC).length, 1);
  });

  test('מבנה המכל זהה באורז ובמחלץ', () {
    // כותרת שונה בין השניים = exe שלא מצליח לחלץ את עצמו, בלי שום אזהרה.
    expect(packPayloadPs1, contains('OTZPAY1'));
    expect(stubC, contains("{'O', 'T', 'Z', 'P', 'A', 'Y', '1', '\\0'}"));
    expect(packPayloadPs1, contains(r'$algorithm = 5'));
    expect(stubC, contains('COMPRESS_ALGORITHM_LZMS'));
  });

  test('ה-CRT של VC++ נארז לתוך ה-payload, והאריזה נכשלת בלעדיו', () {
    // `launcher_app.exe` ושלושה מה-DLL של ה-plugins מייבאים את אלה **בטעינה**,
    // ופלאטר אינו מעתיק אותם לתיקיית ה-Release. בלי הצעד הזה נארז exe תקין
    // לגמרי שפשוט אינו עולה על מחשב בלי VC++ Redist — והמחשב המקוון, שעליו
    // הלאנצ'ר רץ, הוא בדיוק זה שאין בו אוצריא שתביא אותו.
    for (final dll in const [
      'msvcp140.dll',
      'vcruntime140.dll',
      'vcruntime140_1.dll',
    ]) {
      expect(packagePs1, contains("'$dll'"),
          reason: 'חסר מרשימת ה-DLL שהאריזה מוודאת: $dll');
    }
    expect(packagePs1, contains('Microsoft.VC*.CRT'));
    // אזהרה לא מספיקה: בלי נפילה נפיץ exe שאינו רץ, וזה כשל שקט לחלוטין.
    expect(packagePs1, contains(r'throw "CRT DLLs missing from the payload'));
  });

  test('שם קובץ ה-payload זהה באריזה, בהטמעה ובבנייה', () {
    expect(packagePs1, contains("build\\payload.otz'"));
    expect(stubRc, contains(r'100 RCDATA "build\\payload.otz"'));
    expect(buildStubPs1, contains("'payload.otz'"));
  });

  test('צבעי חלון ההמתנה הם צבעי ערכת הנושא', () {
    // הצבעים מועתקים ידנית ל-C; שינוי בערכת הנושא בלי `stub.c` נתפס כאן.
    String rgb(Color c) {
      String hex(int shift) =>
          '0x${((c.toARGB32() >> shift) & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase()}';
      return 'RGB(${hex(16)}, ${hex(8)}, ${hex(0)})';
    }

    final cs = AppThemeData.colorScheme;
    final expected = {
      'kPageColor': AppPalette.light.page,
      'kBorderColor': AppPalette.light.titleBarBorder,
      'kPrimaryColor': cs.primary,
      'kTrackColor': cs.secondaryContainer,
      'kOnSurfaceColor': cs.onSurface,
      'kOnSurfaceVariantColor': cs.onSurfaceVariant,
    };
    expected.forEach((name, color) {
      expect(stubC, contains('$name = ${rgb(color)};'), reason: name);
    });
  });

  test('נתוני משתמש מתיקיית ה-Release אינם נארזים', () {
    // אחרת חילוץ דורס את ההגדרות והלוגים של המשתמש בשל המפתח.
    expect(
        packagePs1, contains("Join-Path \$payloadDir '${AppPaths.dirName}'"));
  });

  test('ההאטה לצילומי מסך אינה מוגדרת באף בנייה', () {
    expect(buildStubPs1, isNot(contains('STUB_SLOW_DEMO')));
    for (final file in Directory('../.github/workflows').listSync()) {
      if (file is File) {
        expect(file.readAsStringSync(), isNot(contains('STUB_SLOW_DEMO')),
            reason: file.path);
      }
    }
  });
}

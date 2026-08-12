import 'dart:io';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// exe של מערכת עם version resource תקני — משמש כתחליף ל-otzaria.exe
/// אמיתי, כדי לבדוק בפועל את מסלול ה-FFI.
const String _systemExe = r'C:\Windows\System32\notepad.exe';

void main() {
  group('installedVersionReaderFor', () {
    test('בוחר מימוש לפי פלטפורמת היעד', () {
      expect(
        installedVersionReaderFor(OtzariaTargetPlatform.windows),
        isA<WindowsExeVersionReader>(),
      );
      expect(
        installedVersionReaderFor(OtzariaTargetPlatform.macos),
        isA<MacAppVersionReader>(),
      );
    });

    // רק בשתי הפלטפורמות שהלאנצ'ר תומך בהן: בלינוקס `detect` זורק בכוונה,
    // ו-CI מריץ את החבילה הזו גם שם.
    test('currentInstalledVersionReader תואם לפלטפורמה שרצה', () {
      expect(
        currentInstalledVersionReader(),
        Platform.isWindows
            ? isA<WindowsExeVersionReader>()
            : isA<MacAppVersionReader>(),
      );
    }, testOn: 'windows || mac-os');
  });

  group('WindowsExeVersionReader', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('otzaria-verreader-');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test(
      'קורא ProductVersion מ-exe אמיתי, גם אחרי העתקה לתיקיית ההתקנה',
      () async {
        final source = File(_systemExe);
        if (!source.existsSync()) {
          markTestSkipped('אין $_systemExe במכונה הזאת');
          return;
        }

        // מדמים את מה שקורה אחרי התקנה: ה-exe יושב בתיקייה שלנו בשם אחר.
        final copied = p.join(tempDir.path, 'otzaria.exe');
        await source.copy(copied);

        final version = const WindowsExeVersionReader().readVersion(copied);

        // אין השוואה למקור: לקובצי מערכת ווינדוס מחזירה גרסת servicing
        // אחרת מזו של העותק. מה שנבדק כאן הוא שהקריאה עצמה (FFI) עובדת.
        expect(version, isNotNull);
        expect(version, matches(RegExp(r'^\d+(\.\d+)+')));
      },
      testOn: 'windows',
    );

    test(
      'null כשהקובץ לא קיים או שאין בו version resource',
      () async {
        expect(
          const WindowsExeVersionReader()
              .readVersion(p.join(tempDir.path, 'missing.exe')),
          isNull,
        );

        // "exe" שהוא בעצם טקסט — אין לו version resource, ולכן לא נזהה
        // אותו כהתקנה של אוצריא.
        final fake = File(p.join(tempDir.path, 'otzaria.exe'));
        await fake.writeAsString('not really an exe');
        expect(const WindowsExeVersionReader().readVersion(fake.path), isNull);
      },
      testOn: 'windows',
    );

    test(
      'זורק בפלטפורמה שאינה ווינדוס, עם הודעת ה-l10n',
      () {
        expect(
          () => const WindowsExeVersionReader().readVersion('/tmp/x.exe'),
          throwsA(
            isA<UnsupportedError>().having((e) => e.message, 'message',
                AppL10n.strings.appDomain.windowsOnlyReader),
          ),
        );
      },
      testOn: '!windows',
    );
  });

  group('MacAppVersionReader', () {
    test(
      'זורק בפלטפורמה שאינה macOS, עם הודעת ה-l10n',
      () {
        expect(
          () => const MacAppVersionReader().readVersion(r'C:\x\אוצריא.app'),
          throwsA(
            isA<UnsupportedError>().having((e) => e.message, 'message',
                AppL10n.strings.appDomain.macOnlyReader),
          ),
        );
        expect(
          () => const MacAppVersionReader()
              .readBundleIdentifier(r'C:\x\אוצריא.app'),
          throwsA(isA<UnsupportedError>()),
        );
      },
      testOn: '!mac-os',
    );

    test(
      'null כשהנתיב אינו בתוך חבילת \u200E.app, וכשאין Info.plist',
      () async {
        final tempDir =
            await Directory.systemTemp.createTemp('otzaria-macreader-');
        addTearDown(() => tempDir.delete(recursive: true));

        expect(const MacAppVersionReader().readVersion(tempDir.path), isNull);

        final bundle = Directory(p.join(tempDir.path, 'אוצריא.app'));
        await bundle.create(recursive: true);
        expect(const MacAppVersionReader().readVersion(bundle.path), isNull);
      },
      testOn: 'mac-os',
    );
  });
}

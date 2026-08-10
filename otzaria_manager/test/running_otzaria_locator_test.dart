import 'dart:io';

import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// הזיהוי לפי התהליך הרץ הוא המקור **הסמכותי** למיקום ההתקנה: הוא אינו
/// ניחוש של תיקייה מוכרת אלא הקובץ שהמשתמש באמת מפעיל. הבדיקות כאן
/// מכסות את הפירוק הטהור בשתי הפלטפורמות, ובווינדוס גם את מסלול ה-FFI
/// עצמו — מול תהליך הבדיקה הזה, שהנתיב שלו ידוע מראש.
void main() {
  group('parseTasklistPids', () {
    test('שולף את ה-PID מהעמודה השנייה', () {
      const line = '"otzaria.exe","1234","Console","1","309,328 K"';

      expect(RunningOtzariaLocator.parseTasklistPids(line), [1234]);
    });

    test('כמה תהליכים באותו שם — כל ה-PIDים', () {
      const output = '"otzaria.exe","1234","Console","1","309,328 K"\r\n'
          '"otzaria.exe","5678","Console","1","12,004 K"\r\n';

      expect(RunningOtzariaLocator.parseTasklistPids(output), [1234, 5678]);
    });

    test('הודעת "אין תהליך תואם" אינה מתפרשת כ-PID', () {
      const info =
          'INFO: No tasks are running which match the specified criteria.';

      expect(RunningOtzariaLocator.parseTasklistPids(info), isEmpty);
    });
  });

  group('selectMacExecutablePath', () {
    const names = ['אוצריא', 'otzaria'];

    test('מחזיר את הנתיב המלא של הבינארי שבתוך החבילה', () {
      const psOutput = [
        '/usr/libexec/secinitd',
        '/Applications/אוצריא.app/Contents/MacOS/אוצריא',
      ];

      expect(
        RunningOtzariaLocator.selectMacExecutablePath(psOutput, names),
        '/Applications/אוצריא.app/Contents/MacOS/אוצריא',
      );
    });

    // הלאנצ'ר עצמו יושב בנתיב שמכיל את המילה otzaria; התאמה על תת-מחרוזת
    // הייתה מזהה אותו כאוצריא ומדווחת על תיקיית ההתקנה של עצמנו.
    test("לא נתפס על הלאנצ'ר, שנתיבו מכיל otzaria", () {
      const psOutput = [
        '/Volumes/USB/Otzaria Launcher.app/Contents/MacOS/Otzaria Launcher',
        '/Users/x/otzaria_update/launcher_app',
      ];

      expect(
        RunningOtzariaLocator.selectMacExecutablePath(psOutput, names),
        isNull,
      );
    });

    test('שורות ריקות מדולגות', () {
      expect(
        RunningOtzariaLocator.selectMacExecutablePath(
          ['', '   ', '/Applications/Safari.app/Contents/MacOS/Safari'],
          names,
        ),
        isNull,
      );
    });
  });

  group('שמות התהליך', () {
    test('ווינדוס: שם הקובץ המדויק בלבד', () {
      expect(RunningOtzariaLocator.processNamesFor('windows'), ['otzaria.exe']);
    });

    test('macOS: השם בעברית ראשון, האנגלי כגיבוי', () {
      expect(RunningOtzariaLocator.processNamesFor('macos'),
          ['אוצריא', 'otzaria']);
    });

    test('אף שם אינו נתיב — אחרת ההתאמה הייתה תלויה במיקום ההתקנה', () {
      for (final os in const ['windows', 'macos', 'linux']) {
        for (final name in RunningOtzariaLocator.processNamesFor(os)) {
          expect(name, isNot(contains('/')));
          expect(name, isNot(contains(r'\')));
        }
      }
    });
  });

  // מסלול ה-FFI האמיתי, מול תהליך שהנתיב שלו ידוע: התהליך שמריץ את
  // הבדיקה. זו הבדיקה היחידה שמאמתת ש-OpenProcess/QueryFullProcessImageName
  // אכן מקומפלים ורצים נכון.
  group('Windows בלבד — מול תהליך אמיתי', () {
    // לא מושווה ל-`Platform.resolvedExecutable`: הוא מדווח את המפעיל
    // (`dart.exe`) ואילו התהליך שרץ בפועל הוא `dartvm.exe`. זה בדיוק
    // ההבדל שבגללו שואלים את מערכת ההפעלה ולא את התהליך על עצמו.
    test('windowsImagePathOfPid מחזיר נתיב אמיתי של התהליך הנוכחי', () {
      final path = RunningOtzariaLocator.windowsImagePathOfPid(pid);

      expect(path, isNotNull);
      expect(p.isAbsolute(path!), isTrue);
      expect(File(path).existsSync(), isTrue);
      expect(
        p.dirname(path),
        equalsIgnoringCase(p.dirname(Platform.resolvedExecutable)),
      );
    });

    test('windowsPidsOf מוצא את התהליך הנוכחי לפי שמו', () async {
      final imageName = p.basename(
        RunningOtzariaLocator.windowsImagePathOfPid(pid)!,
      );

      expect(
          await RunningOtzariaLocator.windowsPidsOf(imageName), contains(pid));
    });

    test('שם שאינו קיים מחזיר רשימה ריקה', () async {
      expect(
        await RunningOtzariaLocator.windowsPidsOf('no-such-process-xyz.exe'),
        isEmpty,
      );
    });

    test('PID שאינו קיים מחזיר null במקום לקרוס', () {
      // 0 הוא System Idle Process — OpenProcess עליו נכשל תמיד.
      expect(RunningOtzariaLocator.windowsImagePathOfPid(0), isNull);
    });

    // המסלול המלא מקצה לקצה: תהליך אמיתי בשם otzaria.exe, במיקום שאינו
    // אף אחת מתיקיות ברירת המחדל — בדיוק המקרה שהמנגנון נבנה בשבילו.
    test('מוצא נתיב של otzaria.exe אמיתי שרץ מתיקייה שרירותית', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('otzaria-locator-test-');
      final fakeOtzaria = p.join(tempDir.path, 'otzaria.exe');
      final process = await _startLongLivedCopyOfPing(fakeOtzaria);
      if (process == null) {
        markTestSkipped('לא ניתן להריץ תהליך עזר בסביבה הזו');
        return;
      }
      addTearDown(() async {
        process.kill();
        // ההרג אינו מיידי; בלי ההמתנה המחיקה נכשלת על קובץ נעול.
        await Future<void>.delayed(const Duration(milliseconds: 300));
        try {
          if (await tempDir.exists()) await tempDir.delete(recursive: true);
        } catch (_) {
          // עדיין נעול — לא מפילים את הבדיקה על ניקוי.
        }
      });

      // נבדק על **כל** ה-otzaria.exe שרצים, ולא על התוצאה היחידה של
      // findLaunchPath: במכונה שאוצריא אמיתית פתוחה בה, היא עלולה להיבחר.
      final paths = <String?>[];
      for (var i = 0; i < 20 && !paths.contains(fakeOtzaria); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        paths
          ..clear()
          ..addAll([
            for (final id
                in await RunningOtzariaLocator.windowsPidsOf('otzaria.exe'))
              RunningOtzariaLocator.windowsImagePathOfPid(id),
          ]);
      }

      expect(paths, contains(fakeOtzaria));
      expect(await const RunningOtzariaLocator().findLaunchPath(), isNotNull);
    });
  }, skip: !Platform.isWindows);
}

/// מריץ עותק של `ping.exe` תחת [destPath] — תהליך אמיתי, ארוך-חיים ובלי
/// תלויות, שמאפשר לבדוק מול שם קובץ שאנחנו קובעים. אותה תבנית כמו
/// בבדיקות של `OtzariaProcessGuard`.
Future<Process?> _startLongLivedCopyOfPing(String destPath) async {
  try {
    final source = File(p.join(
      Platform.environment['SystemRoot'] ?? r'C:\Windows',
      'System32',
      'PING.EXE',
    ));
    if (!source.existsSync()) return null;
    source.copySync(destPath);
    return await Process.start(destPath, const ['-n', '30', '127.0.0.1']);
  } catch (_) {
    return null;
  }
}

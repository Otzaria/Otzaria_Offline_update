import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// פורט של בדיקות `test/app_report/` באוצריא (מודל, הסתרה, חתימה, החלטה,
// מגבלה, זיהוי ויציאה לא נקייה, זרימה), מותאם ליומן של הלאנצ'ר.

/// קטע אמיתי מ-`launcher.log` (נתיבים הוחלפו): שגיאה שטופלה ושגיאה שלא נתפסה.
const _realLog = '''
2026-09-22T04:12:24.690626 [INFO] --- launcher started (0.21) ---
2026-09-22T04:12:24.693647 [INFO] --- log file: C:\\Users\\Moshe\\OtzariaData\\logs\\launcher.log ---
2026-09-22T04:12:24.712155 [INFO] --- machine: windows "Windows 10 Home" 10.0 (Build 26200) | process windows_x64 | cpu AMD64 x8 | view 1904x999 @1.5 ---
2026-09-22T04:12:26.593860 [INFO] הפריים הראשון נבנה אחרי 1898ms
2026-09-22T04:14:26.697515 [INFO] הפעלת חנות התוספים נכשלה: ProcessException: The system cannot find the file specified
  Command: "C:\\Users\\Moshe\\Desktop\\Otzaria-Plugin-Store.exe"
2026-09-22T04:14:49.867791 [ERROR] העתקת חנות התוספים נכשלה
error: תוכנת החנות אינה בכונן.
#0      StoreAppExporter.exportTo (package:plugins_manager/src/services/store_app_exporter.dart:141:7)
<asynchronous suspension>
#1      PluginsModuleController.exportStoreApp (package:launcher_app/src/controllers/plugins_module_controller.dart:439:14)
2026-09-22T04:15:02.000001 [ERROR] Uncaught zone error
type: StateError
error: Bad state: no element
#0      List.first (dart:core-patch/growable_array.dart:264:36)
#1      HomeScreen._build (package:launcher_app/src/screens/home_screen.dart:120:5)
<asynchronous suspension>
#2      AppShell.checkAll (package:launcher_app/src/screens/app_shell.dart:470:7)
2026-09-22T04:15:03.000000 [INFO] after
''';

AppReport _manual({String? product}) => AppReport(
      reportId: 'id-1',
      type: AppReportType.bug,
      trigger: AppReportTrigger.manual,
      title: 'כותרת',
      description: 'תיאור',
      reporterEmail: 'a@b.co',
      appVersion: '0.25',
      platform: 'windows',
      createdAt: DateTime.utc(2026, 10, 1),
      product: product,
    );

void main() {
  group('AppReport + product', () {
    test('בלי product — הגוף זהה לזה של אוצריא, בלי השדה', () {
      expect(_manual().toApiPayload().containsKey('product'), isFalse);
    });

    test('עם product — השדה בגוף, ונשמר ב-toJson/fromJson', () {
      final report = _manual(product: AppReport.offlineUpdateProduct);
      expect(report.toApiPayload()['product'], 'offline-update');
      final back = AppReport.fromJson(
        jsonDecode(jsonEncode(report.toJson())) as Map<String, dynamic>,
      );
      expect(back.product, 'offline-update');
      expect(back.copyWith(product: null).toApiPayload(),
          _manual().toApiPayload());
    });

    test('withoutAttachments ושדות התוצאה', () {
      final report = _manual().copyWith(
        diagnostics: {'a': 1},
        errorLog: 'x',
        issueNumber: 4,
        issueUrl: 'u',
        merged: true,
        sentAt: DateTime.utc(2026, 10, 2),
      );
      final stripped = report.withoutAttachments();
      expect(stripped.diagnostics, isNull);
      expect(stripped.errorLog, isNull);
      final back = AppReport.fromJson(stripped.toJson());
      expect(back.issueNumber, 4);
      expect(back.merged, isTrue);
      expect(back.sentAt, DateTime.utc(2026, 10, 2));
    });

    test('generateReportId הוא UUID v4', () {
      final id = AppReport.generateReportId();
      expect(
        id,
        matches(RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
      );
      expect(AppReport.generateReportId(), isNot(id));
    });

    test('redactedWith מסתיר בכל הטקסטים מלבד המייל', () {
      final redactor = AppReportRedactor(
        environment: const {
          'USERPROFILE': r'C:\Users\Moshe',
          'USERNAME': 'Moshe'
        },
      );
      final report = _manual()
          .copyWith(
            description: r'C:\Users\Moshe\x moshe@mail.com',
            diagnostics: {'path': r'C:\Users\Moshe\a'},
            errorLog: 'Moshe',
            signature: const CrashSignature(
              exceptionType: 'Moshe',
              frames: [r'C:\Users\Moshe\a.dart'],
            ),
          )
          .redactedWith(redactor);
      expect(report.description, r'%USERPROFILE%\x <email>');
      expect(report.diagnostics, {'path': r'%USERPROFILE%\a'});
      expect(report.errorLog, '<user>');
      expect(report.signature!.exceptionType, '<user>');
      expect(report.reporterEmail, 'a@b.co');
    });
  });

  group('mergeAppReportImages', () {
    AppReportImage image(int size) => AppReportImage(
          bytes: Uint8List(size),
          fileName: 'a.png',
          mimeType: 'image/png',
        );

    test('גדולה מדי מדולגת, ועוצרים במכסה', () {
      final big = mergeAppReportImages(const [], [
        image(AppReportImage.maxBytes + 1),
        image(10),
      ]);
      expect(big.images, hasLength(1));
      expect(big.rejection, AppReportImageRejection.tooLarge);

      final many = mergeAppReportImages(
        [for (var i = 0; i < AppReportImage.maxCount; i++) image(1)],
        [image(1)],
      );
      expect(many.images, hasLength(AppReportImage.maxCount));
      expect(many.rejection, AppReportImageRejection.tooMany);
    });

    test('mimeTypeForPath', () {
      expect(AppReportImage.mimeTypeForPath('a.PNG'), 'image/png');
      expect(AppReportImage.mimeTypeForPath('a.jpeg'), 'image/jpeg');
      expect(AppReportImage.mimeTypeForPath('a.bmp'), isNull);
    });
  });

  group('AppReportRedactor — כתובות דואר וביצועים', () {
    final redactor = AppReportRedactor(environment: const {});

    test('צורות כתובת: + % _ - ותחילת מקף', () {
      for (final (input, expected) in [
        ('a.b+c%d_e-f@sub.mail.example.co.il', '<email>'),
        ('-a@b.com', '-<email>'),
        ('x -a@b.com y', 'x -<email> y'),
        ('mail: a@b.com, c@d.org.', 'mail: <email>, <email>.'),
        ('a@b@c.com', 'a@<email>'),
        ('no at sign', 'no at sign'),
        ('a@b', 'a@b'),
        ('@b.com', '@b.com'),
      ]) {
        expect(redactor.redactText(input), expected, reason: input);
      }
    });

    test('קלט של 200KB אינו תוקע (היה ריבועי)', () {
      final inputs = [
        'a' * 200000,
        '${'a' * 200000}@',
        '\\\\${'a' * 200000}',
        '${'a' * 200000}@${'b.' * 100000}',
        'a.' * 100000,
        'a-' * 100000,
        'a@' * 100000,
        'a@b.' * 50000,
      ];
      for (final input in inputs) {
        final sw = Stopwatch()..start();
        redactor.redactText(input);
        AppReportRedactor.reducePaths(input);
        // גבול נדיב ל-CI; לפני התיקון זה לקח דקות.
        expect(sw.elapsed, lessThan(const Duration(seconds: 2)),
            reason: '${input.length} תווים');
      }
    });
  });

  group('AppReportRedactor — נתיבי פרופיל כלליים', () {
    final redactor = AppReportRedactor(environment: const {});

    test('צורת 8.3, שני הלוכסנים וגם צורת JSON', () {
      expect(
        redactor.redactText(r'C:\Users\ZEEVLE~1\AppData\Local\Temp\x'),
        r'%USERPROFILE%\AppData\Local\Temp\x',
      );
      expect(
        redactor.redactText('d:/users/Bob/proj/a.dart'),
        '%USERPROFILE%/proj/a.dart',
      );
      expect(
        redactor.redactText(r'{"p":"C:\\Users\\Bob\\x"}'),
        r'{"p":"%USERPROFILE%\\x"}',
      );
    });

    test('מק ולינוקס', () {
      expect(redactor.redactText('/Users/dani/Library/x'),
          '%USERPROFILE%/Library/x');
      expect(redactor.redactText('at /home/dani/.config/a'),
          'at %USERPROFILE%/.config/a');
      expect(
          redactor.redactText('file:///home/dani/x'), 'file://%USERPROFILE%/x');
    });

    test('פיסוק אחרי נתיב פרופיל נשאר', () {
      expect(redactor.redactText('see /home/bob, ok'), 'see %USERPROFILE%, ok');
      expect(redactor.redactText('(at /Users/bob; later)'),
          '(at %USERPROFILE%; later)');
      expect(redactor.redactText('[/home/bob)'), '[%USERPROFILE%)');
    });

    test('כתובת אינטרנט עם /home/ אינה נפגעת', () {
      const url = 'https://example.com/home/page and https://x.org/a/Users/b';
      expect(redactor.redactText(url), url);
    });

    test('שם משתמש עם רווח אינו דולף (שם משפחה)', () {
      expect(
        redactor.redactText(r'D:\Users\John Smith\Docs\a.txt'),
        r'%USERPROFILE%\Docs\a.txt',
      );
      expect(
        redactor.redactText(r'{"p":"C:\\Users\\John Smith\\x"}'),
        r'{"p":"%USERPROFILE%\\x"}',
      );
    });

    test('גבול תחילת נתיב: https://home/x/y ו-xC:\\Users אינם נפגעים', () {
      const keep = [
        'https://home/x/y',
        'https://Users/x/y',
        r'xC:\Users\b\q',
        'a/home/b',
      ];
      for (final text in keep) {
        expect(redactor.redactText(text), text);
      }
    });

    test('אידמפוטנטי', () {
      for (final text in [
        r'D:\Users\John Smith\Docs\a.txt',
        'file:///home/dani/x',
        r'C:\Users\ZEEVLE~1\x',
        '/Users/dani/x',
        r'{"p":"C:\\Users\\Bob\\x"}',
      ]) {
        final once = redactor.redactText(text);
        expect(redactor.redactText(once), once);
      }
    });
  });

  group('AppReportRedactor.reducePaths', () {
    test('נתיב מוחלט מחוץ לפרופיל מצטמצם לשם הקובץ', () {
      expect(
        AppReportRedactor.reducePaths(r'copy D:\Private\Folder\book.db failed'),
        'copy book.db failed',
      );
      expect(
        AppReportRedactor.reducePaths('mounted /Volumes/Stick/Otzaria/x.json.'),
        'mounted x.json.',
      );
      expect(
        AppReportRedactor.reducePaths(r'\\server\share\dir\f.txt'),
        'f.txt',
      );
    });

    test('שמות תיקיות עם רווחים מוסתרים גם הם', () {
      expect(
        AppReportRedactor.reducePaths(r'open C:\Program Files\Foo\bar.log now'),
        'open bar.log now',
      );
      expect(
        AppReportRedactor.reducePaths('at /Volumes/My Stick/x/y.json, done'),
        'at y.json, done',
      );
      for (final text in ['open bar.log now', 'at y.json, done']) {
        expect(AppReportRedactor.reducePaths(text), text);
      }
    });

    test('נתיב ואחריו משפט אינו בולע את המשפט', () {
      expect(
        AppReportRedactor.reducePaths(r'C:\a\b.txt and then /var/log/x.'),
        'b.txt and then x.',
      );
    });

    test('כתובות, פריימים ונתיבים יחסיים נשארים', () {
      const keep = [
        'https://otzaria.org/api/app-reports',
        '#0 A.b (package:launcher_app/src/a.dart:1:2)',
        'relative/path/x.dart',
        'הפריים/ה השני',
        r'%USERPROFILE%\AppData\x',
        '2026-09-22T04:12:24.690626 [INFO] x',
      ];
      for (final text in keep) {
        expect(AppReportRedactor.reducePaths(text), text);
      }
    });

    test('נתיב בתוך סוגריים או פסיק שומר את הפיסוק', () {
      expect(
        AppReportRedactor.reducePaths(
            '(see C:\\a\\b\\c.txt), then /var/log/x.'),
        '(see c.txt), then x.',
      );
    });
  });

  group('AppReportRedactor', () {
    final redactor = AppReportRedactor(
      environment: const {
        'USERPROFILE': r'C:\Users\Moshe',
        'USERNAME': 'Moshe'
      },
    );

    test('מחליף את תיקיית הפרופיל בכל צורות הלוכסן ובלי תלות ברישיות', () {
      expect(
        redactor.redactText(r'C:\Users\Moshe\AppData\Roaming\otzaria'),
        r'%USERPROFILE%\AppData\Roaming\otzaria',
      );
      expect(
        redactor.redactText('file:///c:/users/moshe/x.dart'),
        'file:///%USERPROFILE%/x.dart',
      );
      expect(
        redactor.redactText(r'{"path":"C:\\Users\\Moshe\\books"}'),
        r'{"path":"%USERPROFILE%\\books"}',
      );
    });

    test('פרופיל אחר שמתחיל באותן אותיות מוסתר כולו, לא למחצה', () {
      // באוצריא הוא נשאר גלוי; כאן גם פרופיל זר (8.3, כונן אחר) מוסתר.
      expect(redactor.redactText(r'C:\Users\Moshe2\x'), r'%USERPROFILE%\x');
    });

    test('שם המשתמש מוחלף רק כמילה שלמה', () {
      expect(
        redactor.redactText('owner moshe, MosheBooks, Moshe_1'),
        'owner <user>, MosheBooks, Moshe_1',
      );
    });

    test('הסתרה חוזרת אינה משנה טקסט מוסתר (שם המשתמש User)', () {
      final user = AppReportRedactor(
        environment: const {
          'USERPROFILE': r'C:\Users\User',
          'USERNAME': 'User'
        },
      );
      final once = user.redactText(r'user C:\Users\User\x a@b.com');
      expect(once, r'<user> %USERPROFILE%\x <email>');
      expect(user.redactText(once), once);
    });

    test('שם משתמש קצר משלוש אותיות אינו מוחלף', () {
      final short = AppReportRedactor(environment: const {'USERNAME': 'ab'});
      expect(short.redactText('ab cd'), 'ab cd');
    });

    test('עובד רקורסיבית על JSON, כולל מפתחות', () {
      expect(
        redactor.redactJson({
          r'C:\Users\Moshe\books': [
            'x@y.com',
            {'n': 5, 'user': 'Moshe'},
          ],
        }),
        {
          r'%USERPROFILE%\books': [
            '<email>',
            {'n': 5, 'user': '<user>'},
          ],
        },
      );
    });

    test('HOME בלינוקס ונתיב קצר מדי מדולג', () {
      final linux = AppReportRedactor(
        environment: const {'HOME': '/home/dani', 'USER': 'dani'},
      );
      expect(linux.redactText('/home/dani/.local'), '%USERPROFILE%/.local');
      final root = AppReportRedactor(environment: const {'HOME': '/'});
      expect(root.redactText('/usr/lib'), '/usr/lib');
    });
  });

  group('CrashSignature', () {
    test('normalizeFrame מסיר מספור, שורה:עמודה ונתיב מוחלט', () {
      expect(
        CrashSignature.normalizeFrame(
          '#0      Foo.bar (package:launcher_app/a/b.dart:12:5)',
        ),
        'Foo.bar (package:launcher_app/a/b.dart)',
      );
      expect(
        CrashSignature.normalizeFrame(
          '#3 main (file:///C:/Users/x/proj/test/main_test.dart:3:4)',
        ),
        'main (main_test.dart)',
      );
      expect(CrashSignature.normalizeFrame('  0x1f8e8b92bbc'), isNull);
      expect(
          CrashSignature.normalizeFrame('<asynchronous suspension>'), isNull);
    });

    test("selectFrames מעדיף את החבילות של הלאנצ'ר, לא את אוצריא", () {
      const stack = '''
#0      List.[] (dart:core-patch/growable_array.dart:264:36)
#1      Foo.a (package:otzaria/x/foo.dart:10:3)
#2      Bar.b (package:flutter/src/widgets/framework.dart:5:1)
#3      Baz.c (package:launcher_app/y/baz.dart:20:7)
#4      Qux.d (package:library_manager/z/qux.dart:30:9)
#5      Last.e (package:otzaria_manager/z/last.dart:1:1)
#6      More.f (package:launcher_app/z/more.dart:1:1)
''';
      expect(CrashSignature.selectFrames(stack), [
        'Baz.c (package:launcher_app/y/baz.dart)',
        'Qux.d (package:library_manager/z/qux.dart)',
        'Last.e (package:otzaria_manager/z/last.dart)',
      ]);
    });

    test('דטרמיניסטי: מספרי שורות שונים — אותו hash', () {
      final a = CrashSignature.fromLogText(
        exceptionMessage: 'StateError: x',
        stackText: '#0 A.b (package:launcher_app/a.dart:1:2)',
      );
      final b = CrashSignature.fromLogText(
        exceptionMessage: 'StateError: y',
        stackText: '#0 A.b (package:launcher_app/a.dart:9:9)',
      );
      expect(a, b);
      expect(a.hash, hasLength(64));
    });

    test('fromError משתמש בטיפוס בזמן ריצה', () {
      final signature = CrashSignature.fromError(
        const FormatException('x'),
        StackTrace.fromString('#0 A.b (package:launcher_app/a.dart:1:2)'),
      );
      expect(signature.exceptionType, 'FormatException');
      expect(signature.frames, ['A.b (package:launcher_app/a.dart)']);
    });

    test('exceptionTypeFromMessage', () {
      expect(
        CrashSignature.exceptionTypeFromMessage('FormatException: bad'),
        'FormatException',
      );
      expect(
        CrashSignature.exceptionTypeFromMessage(
          "Null check operator used on item 42 of 'abc'",
        ),
        "Null check operator used on item # of ''",
      );
    });
  });

  group('launcher.log', () {
    test('מפענח רשומות רב-שורתיות מהיומן האמיתי', () {
      final blocks = parseLauncherLog(_realLog);
      expect(blocks.map((b) => b.level), [
        'INFO', 'INFO', 'INFO', 'INFO', 'INFO', 'ERROR', 'ERROR', 'INFO', //
      ]);
      expect(blocks[4].text, contains('Command:'));
      expect(blocks[5].isCrashEvidence, isFalse, reason: 'שגיאה שטופלה');
      final uncaught = blocks[6];
      expect(uncaught.isUncaughtError, isTrue);
      expect(uncaught.signature.exceptionType, 'StateError');
      expect(uncaught.signature.frames, [
        'HomeScreen._build (package:launcher_app/src/screens/home_screen.dart)',
        'AppShell.checkAll (package:launcher_app/src/screens/app_shell.dart)',
      ]);
      expect(uncaught.timestamp, DateTime(2026, 9, 22, 4, 15, 2, 0, 1));
    });

    test('זנב חתוך לפני הכותרת הראשונה נזרק', () {
      final blocks = parseLauncherLog('half line\n${_realLog.trim()}');
      expect(blocks.first.message, '--- launcher started (0.21) ---');
    });

    test('FlutterError לבדו אינו ראיה; תקיעת עלייה כן', () {
      final blocks = parseLauncherLog('''
2026-09-22T04:12:24.000000 [ERROR] FlutterError: A RenderFlex overflowed
error: A RenderFlex overflowed by 4 pixels
2026-09-22T04:12:25.000000 [WARN] ${LauncherLogFormat.startupStallTag} no frame
2026-09-22T04:12:26.000000 [WARN] FlutterErrorish
''');
      expect(blocks[0].isUncaughtError, isTrue);
      expect(blocks[0].isCrashEvidence, isFalse);
      expect(blocks[0].signature.exceptionType,
          'A RenderFlex overflowed by # pixels');
      expect(blocks[1].isStartupStall, isTrue);
      expect(blocks[1].signature.exceptionType, 'Startup stall');
      expect(blocks[2].isCrashEvidence, isFalse);
    });

    test('uncaughtMessage תואם את מה שהקורא מזהה', () {
      final message = LauncherLogFormat.uncaughtMessage(
          LauncherLogFormat.zoneError, StateError('x'));
      final block = parseLauncherLog(
        '2026-09-22T04:12:24.000000 [ERROR] $message\nerror: Bad state: x\n',
      ).single;
      expect(block.isUncaughtError, isTrue);
      expect(block.signature.exceptionType, 'StateError');
    });

    test('קטע היומן: מהשבוע, החדשות בגבול, בסדר כרונולוגי', () {
      final excerpt = recentLauncherLogExcerpt(
        _realLog,
        since: DateTime(2026, 9, 22, 4, 14),
        maxBytes: 100000,
      );
      expect(excerpt, startsWith('2026-09-22T04:14:26'));
      expect(excerpt, endsWith('[INFO] after'));

      final small = recentLauncherLogExcerpt(
        _realLog,
        since: DateTime(2026),
        maxBytes: 60,
      );
      expect(small, '2026-09-22T04:15:03.000000 [INFO] after');
    });
  });

  group('ReportSystemInfo.normalizeOsVersion', () {
    final cases = <(String, bool, String)>[
      // Windows 10 אמיתי נשאר כמו שהוא.
      (
        '"Windows 10 Pro" 10.0 (Build 19045)',
        true,
        '"Windows 10 Pro" 10.0 (Build 19045)',
      ),
      (
        '"Windows 10 Home" 10.0 (Build 22000)',
        true,
        '"Windows 11 Home" 10.0 (Build 22000)',
      ),
      (
        '"Windows 10 Pro" 10.0 (Build 22631)',
        true,
        '"Windows 11 Pro" 10.0 (Build 22631)',
      ),
      (
        '"Windows 10 Enterprise" 10.0 (Build 26100)',
        true,
        '"Windows 11 Enterprise" 10.0 (Build 26100)',
      ),
      // שמות שרת אינם "Windows 10" גם ב-build גבוה.
      (
        '"Windows Server 2022 Datacenter" 10.0 (Build 20348)',
        true,
        '"Windows Server 2022 Datacenter" 10.0 (Build 20348)',
      ),
      (
        '"Windows Server 2025 Standard" 10.0 (Build 26100)',
        true,
        '"Windows Server 2025 Standard" 10.0 (Build 26100)',
      ),
      // שם מהדורה במערכת בעברית.
      (
        '"Windows 10 בית" 10.0 (Build 26200)',
        true,
        '"Windows 11 בית" 10.0 (Build 26200)',
      ),
      (
        '"Windows 10 בית" 10.0 (Build 19045)',
        true,
        '"Windows 10 בית" 10.0 (Build 19045)',
      ),
      ('Windows 10 something', true, 'Windows 10 something'),
      ('', true, ''),
      (
        'Version 14.5 (Build 23F79)',
        false,
        'Version 14.5 (Build 23F79)',
      ),
      ('Linux 6.8.0 (Build 30000)', false, 'Linux 6.8.0 (Build 30000)'),
    ];
    for (final (raw, isWindows, expected) in cases) {
      test('$raw (windows=$isWindows)', () {
        expect(
          ReportSystemInfo.normalizeOsVersion(raw, isWindows: isWindows),
          expected,
        );
      });
    }
  });

  group('CrashReportDecision', () {
    CrashCandidate candidate({CrashSignature? signature}) => CrashCandidate(
          previousSession: SessionLock(
            pid: 1,
            version: '0.24',
            startedAt: DateTime.utc(2026, 9, 16),
          ),
          entries: const [],
          signature: signature,
          hasStartupStall: false,
        );

    final cases = <(AppCrashReportMode, bool, bool, CrashReportAction)>[
      (AppCrashReportMode.never, true, true, CrashReportAction.none),
      (AppCrashReportMode.ask, true, true, CrashReportAction.prompt),
      // ההצעה למשתמש אינה כפופה למגבלה — הוא מחליט בעצמו.
      (AppCrashReportMode.ask, true, false, CrashReportAction.prompt),
      (
        AppCrashReportMode.always,
        true,
        true,
        CrashReportAction.sendAutomatically
      ),
      (AppCrashReportMode.always, true, false, CrashReportAction.none),
      (AppCrashReportMode.ask, false, true, CrashReportAction.none),
      (AppCrashReportMode.always, false, true, CrashReportAction.none),
    ];
    for (final (mode, hasCandidate, allows, expected) in cases) {
      test('${mode.name} / $hasCandidate / $allows → ${expected.name}', () {
        expect(
          CrashReportDecision.decide(
            mode: mode,
            candidate: hasCandidate ? candidate() : null,
            throttleAllows: allows,
          ),
          expected,
        );
      });
    }

    test('parse: ערך לא מוכר נופל ל-ask', () {
      expect(AppCrashReportMode.parse('always'), AppCrashReportMode.always);
      expect(AppCrashReportMode.parse(null), AppCrashReportMode.ask);
      expect(AppCrashReportMode.parse('x'), AppCrashReportMode.ask);
    });

    test('titleFor ו-throttleKeyFor', () {
      const sig = CrashSignature(exceptionType: 'StateError', frames: ['a']);
      expect(
        CrashReportDecision.titleFor(candidate(signature: sig),
            fallbackTitle: 'f'),
        'StateError',
      );
      expect(
        CrashReportDecision.titleFor(candidate(), fallbackTitle: 'f'),
        'f',
      );
      expect(CrashReportDecision.throttleKeyFor(candidate(signature: sig)),
          sig.hash);
      expect(
        CrashReportDecision.throttleKeyFor(candidate()),
        CrashReportDecision.fallbackThrottleKey,
      );
    });
  });

  group('UncleanExitDetector', () {
    late Directory tmp;
    late Directory logs;
    final previousStart = DateTime.utc(2026, 9, 16, 8);
    final thisStart = DateTime.utc(2026, 9, 17, 8);

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('launcher_unclean_exit_');
      logs = Directory(p.join(tmp.path, 'logs'))..createSync();
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    UncleanExitDetector detector({
      bool Function(int pid)? alive,
      int currentPid = 2000,
      String host = 'PC1',
    }) =>
        UncleanExitDetector(
          logsDirectory: logs.path,
          isProcessAlive: alive ?? (_) => false,
          currentPid: currentPid,
          currentHost: host,
          processStartedAt: thisStart,
        );

    void writeLock(
        {int pid = 1000, DateTime? startedAt, String? host = 'PC1'}) {
      File(p.join(logs.path, UncleanExitDetector.lockFileName))
          .writeAsStringSync(
        jsonEncode({
          'pid': pid,
          'version': '0.24',
          'startedAt': (startedAt ?? previousStart).toIso8601String(),
          if (host != null) 'host': host,
        }),
      );
    }

    String line(DateTime at, String level, String message) =>
        '${at.toLocal().toIso8601String()} [$level] $message\n';

    String uncaught(DateTime at) => line(
          at,
          'ERROR',
          '${LauncherLogFormat.zoneError}\ntype: StateError\nerror: Bad state\n'
              '#0      A.b (package:launcher_app/a.dart:1:2)',
        );

    void writeLog(String content, {String name = 'launcher.log'}) =>
        File(p.join(logs.path, name)).writeAsStringSync(content);

    test('startSession ו-markCleanExit כותבים ומוחקים את הנעילה', () async {
      final d = detector();
      await d.startSession(version: '0.25');
      final lock = SessionLock.tryParse(File(d.lockPath).readAsStringSync())!;
      expect(lock.pid, 2000);
      expect(lock.version, '0.25');
      expect(lock.startedAt, thisStart);
      expect(lock.host, 'PC1');

      await d.markCleanExit();
      expect(File(d.lockPath).existsSync(), isFalse);
      await d.markCleanExit();
      d.markCleanExitSync();
    });

    test('markCleanExit אינו מוחק נעילה של תהליך אחר', () async {
      writeLock(pid: 1000);
      detector().markCleanExitSync();
      expect(
          File(p.join(logs.path, UncleanExitDetector.lockFileName))
              .existsSync(),
          isTrue);
    });

    test('בלי נעילה אין מועמד', () async {
      writeLog(uncaught(previousStart.add(const Duration(hours: 1))));
      expect(await detector().detectPreviousCrash(), isNull);
    });

    test('נעילה של תהליך מת + ראיה → מועמד עם חתימה', () async {
      writeLock();
      writeLog(
        line(previousStart.subtract(const Duration(days: 1)), 'ERROR',
                '${LauncherLogFormat.zoneError}\ntype: Old') +
            line(previousStart.add(const Duration(minutes: 1)), 'INFO', 'x') +
            uncaught(previousStart.add(const Duration(hours: 2))) +
            uncaught(thisStart.add(const Duration(minutes: 1))),
      );
      final candidate = await detector().detectPreviousCrash();
      expect(candidate, isNotNull);
      expect(candidate!.entries, hasLength(2));
      expect(candidate.signature!.exceptionType, 'StateError');
      expect(
          candidate.signature!.frames, ['A.b (package:launcher_app/a.dart)']);
      expect(candidate.previousSession.pid, 1000);
    });

    test('הראיה נמצאת גם בקובץ שסובב ל-.1', () async {
      writeLock();
      writeLog(uncaught(previousStart.add(const Duration(hours: 1))),
          name: 'launcher.log.1');
      writeLog(line(previousStart.add(const Duration(hours: 3)), 'INFO', 'x'));
      expect(await detector().detectPreviousCrash(), isNotNull);
    });

    test('נעילה בלי ראיה (שגיאה שטופלה בלבד) אינה מועמד', () async {
      writeLock();
      writeLog(line(previousStart.add(const Duration(hours: 1)), 'ERROR',
          'העתקה נכשלה\nerror: x'));
      expect(await detector().detectPreviousCrash(), isNull);
    });

    test('תהליך שעדיין חי אינו קריסה', () async {
      writeLock();
      writeLog(uncaught(previousStart.add(const Duration(hours: 1))));
      expect(await detector(alive: (_) => true).detectPreviousCrash(), isNull);
    });

    test('נעילה של התהליך הנוכחי אינה קריסה', () async {
      writeLock(pid: 2000);
      writeLog(uncaught(previousStart.add(const Duration(hours: 1))));
      expect(await detector().detectPreviousCrash(), isNull);
    });

    test('נעילה ממחשב אחר: אין מועמד, והנעילה נדרסת בהפעלה', () async {
      writeLock(pid: 1000, host: 'OTHER');
      writeLog(uncaught(previousStart.add(const Duration(hours: 1))));
      final d = detector();
      expect(await d.detectPreviousCrash(), isNull);
      await d.startSession(version: '0.25');
      final lock = SessionLock.tryParse(File(d.lockPath).readAsStringSync())!;
      expect(lock.host, 'PC1');
    });

    test('FlutterError לבדו (שגיאת ציור) אינו קריסה', () async {
      writeLock();
      writeLog(line(
          previousStart.add(const Duration(hours: 1)),
          'ERROR',
          '${LauncherLogFormat.flutterError}\ntype: FlutterError\n'
              'error: overflow'));
      expect(await detector().detectPreviousCrash(), isNull);
    });

    test('הפעלה שנסגרה בכיבוי מערכת: נעילה + שגיאה שלא נתפסה — מועמד (מגבלה)',
        () async {
      // WM_ENDSESSION אינו מגיע ל-Dart, ולכן הנעילה שורדת; רק שגיאה קטלנית
      // בהפעלה מעוררת הצעה — ראו §5.10.
      writeLock();
      writeLog(uncaught(previousStart.add(const Duration(minutes: 5))));
      expect(await detector().detectPreviousCrash(), isNotNull);
    });

    test('בלי בדיקת תהליך: נעילה ישנה נחשבת לא-חיה', () async {
      writeLock();
      writeLog(uncaught(previousStart.add(const Duration(hours: 1))));
      final candidate = await detector(
        alive: (_) => throw UnsupportedError('x'),
      ).detectPreviousCrash();
      expect(candidate, isNotNull);
    });

    test('תקיעת עלייה מסומנת', () async {
      writeLock();
      writeLog(line(previousStart.add(const Duration(seconds: 15)), 'WARN',
          '${LauncherLogFormat.startupStallTag} no frame'));
      final candidate = await detector().detectPreviousCrash();
      expect(candidate!.hasStartupStall, isTrue);
    });

    test('נעילה פגומה מתעלמת', () async {
      File(p.join(logs.path, UncleanExitDetector.lockFileName))
          .writeAsStringSync('{not json');
      expect(await detector().detectPreviousCrash(), isNull);
    });

    test('interpretKillResult: ESRCH מת, EPERM חי, אחר זורק', () {
      expect(UncleanExitDetector.interpretKillResult(0, 0), isTrue);
      expect(UncleanExitDetector.interpretKillResult(-1, 1), isTrue);
      expect(UncleanExitDetector.interpretKillResult(-1, 3), isFalse);
      expect(
        () => UncleanExitDetector.interpretKillResult(-1, 22),
        throwsStateError,
      );
    });

    test('defaultIsProcessAlive: התהליך הנוכחי חי (מק/לינוקס)', () {
      if (!Platform.isLinux && !Platform.isMacOS) return;
      expect(UncleanExitDetector.defaultIsProcessAlive(pid), isTrue);
    });
  });

  group('AutoCrashReportThrottle', () {
    late Directory tmp;
    setUp(
        () => tmp = Directory.systemTemp.createTempSync('launcher_throttle_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('פעם אחת לחתימה בגרסה, ועד 3 ביום', () async {
      var now = DateTime(2026, 9, 17, 10);
      final throttle =
          AutoCrashReportThrottle.inLogs(tmp.path, clock: () => now);
      expect(await throttle.canReport(signatureHash: 'h1', appVersion: '1'),
          isTrue);
      await throttle.recordReported(signatureHash: 'h1', appVersion: '1');
      expect(await throttle.canReport(signatureHash: 'h1', appVersion: '1'),
          isFalse);
      expect(await throttle.canReport(signatureHash: 'h1', appVersion: '2'),
          isTrue);

      await throttle.recordReported(signatureHash: 'h2', appVersion: '1');
      await throttle.recordReported(signatureHash: 'h3', appVersion: '1');
      expect(await throttle.canReport(signatureHash: 'h4', appVersion: '1'),
          isFalse);

      now = now.add(const Duration(days: 1));
      expect(await throttle.canReport(signatureHash: 'h4', appVersion: '1'),
          isTrue);
      expect(await throttle.canReport(signatureHash: 'h2', appVersion: '1'),
          isFalse);
    });

    test('קובץ עם שדות מסוג שגוי: הרישום אינו זורק', () async {
      final file = File(p.join(tmp.path, 'throttle.json'))
        ..writeAsStringSync(
          '{"signatures":{"1":"bad"},"days":{"x":"y"}}',
        );
      final throttle = AutoCrashReportThrottle(filePath: file.path);
      await throttle.recordReported(signatureHash: 'h', appVersion: '1');
      expect(
        await throttle.canReport(signatureHash: 'h', appVersion: '1'),
        isFalse,
      );
    });

    test('קובץ פגום מתנהג כריק', () async {
      final file = File(p.join(tmp.path, 'throttle.json'))
        ..writeAsStringSync('x');
      final throttle = AutoCrashReportThrottle(filePath: file.path);
      expect(await throttle.canReport(signatureHash: 'h', appVersion: '1'),
          isTrue);
    });
  });

  group('CrashReportFlow', () {
    late Directory tmp;
    late AutoCrashReportThrottle throttle;
    late List<Map<String, dynamic>> bodies;
    late AppReportService service;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('launcher_crash_flow_');
      throttle = AutoCrashReportThrottle(
        filePath: p.join(tmp.path, 'throttle.json'),
        clock: () => DateTime.utc(2026, 9, 17, 10),
      );
      bodies = [];
      service = AppReportService(
        directory: AppReportService.dirIn(tmp.path),
        client: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response('{"issueNumber":42}', 200);
        }),
      );
    });

    tearDown(() async {
      service.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      tmp.deleteSync(recursive: true);
    });

    const signature =
        CrashSignature(exceptionType: 'StateError', frames: ['a']);

    CrashCandidate candidate({CrashSignature? sig = signature}) =>
        CrashCandidate(
          previousSession: SessionLock(
            pid: 1,
            version: '0.24',
            startedAt: DateTime.utc(2026, 9, 16),
          ),
          entries: const [],
          signature: sig,
          hasStartupStall: false,
        );

    CrashReportFlow flow({
      required AppCrashReportMode mode,
      Future<bool> Function(CrashCandidate)? showPrompt,
      String savedEmail = '',
      bool failCollect = false,
    }) =>
        CrashReportFlow(
          showPrompt: showPrompt ?? (_) async => true,
          service: service,
          collector: _FakeCollector(fail: failCollect),
          redactor: AppReportRedactor(environment: const {}),
          throttle: throttle,
          readMode: () => mode,
          savedEmail: () => savedEmail,
          appVersion: '0.25',
          fallbackTitle: 'סגירה לא צפויה',
          clock: () => DateTime.utc(2026, 9, 17, 10),
        );

    test('never: לא שולח ולא שואל', () async {
      var prompted = false;
      final outcome = await flow(
        mode: AppCrashReportMode.never,
        showPrompt: (_) async => prompted = true,
      ).handle(candidate());
      expect(outcome, CrashReportOutcome.ignored);
      expect(bodies, isEmpty);
      expect(prompted, isFalse);
    });

    test('ask: מציג את ההצעה ולא שולח בעצמו', () async {
      CrashCandidate? shown;
      final outcome = await flow(
        mode: AppCrashReportMode.ask,
        showPrompt: (c) async {
          shown = c;
          return true;
        },
      ).handle(candidate());
      expect(outcome, CrashReportOutcome.prompted);
      expect(shown, isNotNull);
      expect(bodies, isEmpty);
    });

    test('ask בלי Navigator: ההצעה לא הוצגה', () async {
      final outcome = await flow(
        mode: AppCrashReportMode.ask,
        showPrompt: (_) async => false,
      ).handle(candidate());
      expect(outcome, CrashReportOutcome.ignored);
    });

    test('always: שולח auto_crash עם product והמייל השמור, ורושם במגבלה',
        () async {
      final outcome = await flow(
        mode: AppCrashReportMode.always,
        savedEmail: 'me@x.com',
      ).handle(candidate());
      expect(outcome, CrashReportOutcome.sentAutomatically);

      final body = bodies.single;
      expect(body['product'], 'offline-update');
      expect(body['trigger'], 'auto_crash');
      expect(body['type'], 'crash');
      expect(body['title'], 'StateError');
      expect(body['reporterEmail'], 'me@x.com');
      expect(body['appVersion'], '0.25');
      expect(body['signature'], {
        'exceptionType': 'StateError',
        'frames': ['a']
      });
      expect((body['attachments'] as Map)['errorLog'], contains('boom'));
      expect(
        await throttle.canReport(
            signatureHash: signature.hash, appVersion: '0.25'),
        isFalse,
      );
    });

    test('always: מייל שמור לא תקין — נשלח בלעדיו', () async {
      await flow(mode: AppCrashReportMode.always, savedEmail: 'not-an-email')
          .handle(candidate());
      expect(bodies.single.containsKey('reporterEmail'), isFalse);
    });

    test('always: אותה חתימה פעם שנייה נחסמת במגבלה', () async {
      await flow(mode: AppCrashReportMode.always).handle(candidate());
      final outcome =
          await flow(mode: AppCrashReportMode.always).handle(candidate());
      expect(outcome, CrashReportOutcome.throttled);
      expect(bodies, hasLength(1));
    });

    test('always: בלי חתימה — הכותרת הכללית, וכשל באיסוף אינו מונע שליחה',
        () async {
      await flow(mode: AppCrashReportMode.always, failCollect: true)
          .handle(candidate(sig: null));
      expect(bodies.single['title'], 'סגירה לא צפויה');
      expect(bodies.single.containsKey('signature'), isFalse);
      expect(bodies.single.containsKey('attachments'), isFalse);
    });
  });
}

class _FakeCollector implements AppReportAttachmentsCollector {
  _FakeCollector({this.fail = false});

  final bool fail;

  @override
  Future<AppReportAttachments> collect() async {
    if (fail) throw StateError('collect failed');
    return const AppReportAttachments(
      diagnostics: {'appInfo': 'x'},
      errorLog: '2026-09-17T00:00:00.000 [ERROR] boom',
    );
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/app_report/launcher_crash_session.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late String lockPath;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('launcher_session_');
    lockPath = p.join(tmp.path, UncleanExitDetector.lockFileName);
    await LauncherCrashSession.detectAndStartSession(
      logsDirectory: tmp.path,
      version: '0.25',
    );
    expect(File(lockPath).existsSync(), isTrue);
  });

  tearDown(() {
    LauncherCrashSession.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  group('exitCleanly', () {
    test('מוחק את הנעילה ויוצא עם 0', () {
      final codes = <int>[];
      LauncherCrashSession.exitCleanly(codes.add);
      expect(File(lockPath).existsSync(), isFalse);
      expect(codes, [0]);
    });

    test('Elevation ו-LauncherSelfInstaller יוצאים רק דרכו', () {
      for (final path in [
        'lib/src/services/elevation.dart',
        'lib/src/self_update/launcher_self_installer.dart',
      ]) {
        final source = File(path).readAsStringSync();
        expect(
          source,
          contains('_defaultQuit() => LauncherCrashSession.exitCleanly()'),
          reason: path,
        );
        expect(source, isNot(contains('exit(0)')), reason: path);
      }
    });
  });

  group('closeWindow', () {
    test('מוחק את הנעילה ואז משמיד את החלון', () async {
      var destroyed = 0;
      final codes = <int>[];
      await LauncherCrashSession.closeWindow(
        destroy: () async {
          // הנעילה כבר נמחקה כשההשמדה מתחילה.
          expect(File(lockPath).existsSync(), isFalse);
          destroyed++;
        },
        exitProcess: codes.add,
      );
      expect(destroyed, 1);
      expect(codes, isEmpty);
    });

    test('השמדה שנכשלה: יוצאים מהתהליך, ה-X לא הופך לאינרטי', () async {
      final codes = <int>[];
      await LauncherCrashSession.closeWindow(
        destroy: () async => throw PlatformException(code: 'x'),
        exitProcess: codes.add,
      );
      expect(File(lockPath).existsSync(), isFalse);
      expect(codes, [0]);
    });
  });

  group('installCloseHooks', () {
    const channel = MethodChannel('window_manager');
    final calls = <String>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    Future<void> nativeClose() async {
      const codec = StandardMethodCodec();
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'window_manager',
        codec.encodeMethodCall(
          const MethodCall('onEvent', {'eventName': 'close'}),
        ),
        (_) {},
      );
    }

    test('preventClose נדלק, ואירוע close מוחק את הנעילה ומשמיד', () async {
      if (!LauncherCrashSession.isSupported) return;
      await LauncherCrashSession.installCloseHooks();
      expect(calls, contains('setPreventClose'));

      await nativeClose();
      await pumpEventQueue();
      expect(File(lockPath).existsSync(), isFalse);
      expect(calls, contains('destroy'));
    });
  });

  group('בדיקת תהליך', () {
    test('Windows: התהליך הנוכחי חי, ותהליך שהסתיים מת', () async {
      if (!Platform.isWindows) return;
      expect(LauncherCrashSession.isProcessAlive(pid), isTrue);

      // ב-Windows pid הוא כפולה של 4, ולכן 99999 אינו יכול להתקיים:
      // OpenProcess נכשל ב-ERROR_INVALID_PARAMETER.
      expect(LauncherCrashSession.isProcessAlive(99999), isFalse);

      // ותהליך שהסתיים. ב-Windows pid ממוחזר מהר, ותהליך אחר עלול לתפוס אותו
      // תחת עומס — לכן מספיק שאחד משלושה נראה מת.
      var sawDead = false;
      for (var i = 0; i < 3 && !sawDead; i++) {
        final child = await Process.start('cmd', ['/c', 'exit']);
        await child.exitCode;
        sawDead = !LauncherCrashSession.isProcessAlive(child.pid);
      }
      expect(sawDead, isTrue);
    });

    test('מק ולינוקס: kill(pid, 0) על התהליך הנוכחי', () {
      if (!Platform.isMacOS && !Platform.isLinux) return;
      expect(LauncherCrashSession.isProcessAlive(pid), isTrue);
    });
  });

  group('סגירה מסודרת לפני שהזיהוי הסתיים', () {
    setUp(() {
      LauncherCrashSession.resetForTest();
      File(lockPath).deleteSync();
    });

    test('לא נכתבת נעילה שתשרוד', () async {
      final begun = LauncherCrashSession.begin(
        logsDirectory: tmp.path,
        version: '0.25',
      );
      // הזיהוי אסינכרוני ועוד לא הסתיים; אין עדיין detector שימחק.
      LauncherCrashSession.markCleanExitSync();
      await begun;
      expect(File(lockPath).existsSync(), isFalse);
    });

    test('נעילה ישנה של קריסה נשארת, ואינה נדרסת בנעילה חדשה', () async {
      File(lockPath).writeAsStringSync(
        jsonEncode({
          'pid': 1,
          'version': '0.24',
          'startedAt': DateTime.utc(2026, 10, 1).toIso8601String(),
          'host': UncleanExitDetector.localHost(),
        }),
      );
      final begun = LauncherCrashSession.begin(
        logsDirectory: tmp.path,
        version: '0.25',
        isProcessAlive: (_) => false,
      );
      LauncherCrashSession.markCleanExitSync();
      await begun;
      final lock = SessionLock.tryParse(File(lockPath).readAsStringSync())!;
      expect(lock.pid, 1);
    });
  });

  test('נעילה ממחשב אחר נדרסת בלי הצעה', () async {
    File(lockPath).writeAsStringSync(
      jsonEncode({
        'pid': 1,
        'version': '0.24',
        'startedAt': DateTime.now()
            .subtract(const Duration(hours: 1))
            .toUtc()
            .toIso8601String(),
        'host': 'SOME-OTHER-PC',
      }),
    );
    File(p.join(tmp.path, 'launcher.log')).writeAsStringSync(
      '${DateTime.now().subtract(const Duration(minutes: 30)).toIso8601String()}'
      ' [ERROR] ${LauncherLogFormat.zoneError}\ntype: StateError\n',
    );
    final candidate = await LauncherCrashSession.detectAndStartSession(
      logsDirectory: tmp.path,
      version: '0.25',
      isProcessAlive: (_) => false,
    );
    expect(candidate, isNull);
    final lock = SessionLock.tryParse(File(lockPath).readAsStringSync())!;
    expect(lock.host, UncleanExitDetector.localHost());
  });
}

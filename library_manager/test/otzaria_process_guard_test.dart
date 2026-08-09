import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/library_manager.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

/// ה-landmine: ההתאמה חייבת להיות **מדויקת**. התאמת תת-מחרוזת (או `pgrep -f`
/// על שורת הפקודה) הייתה תופסת גם את הלאנצ'ר עצמו — הנתיב שלו מכיל את המילה
/// otzaria — וחוסמת כל עדכון מסד בגלל התהליך שמריץ אותו.
void main() {
  group('OtzariaProcessGuard.processNamesFor', () {
    test('Windows: רק שם הקובץ המדויק otzaria.exe', () {
      expect(OtzariaProcessGuard.processNamesFor('windows'), ['otzaria.exe']);
    });

    test('macOS: השם בעברית ראשון, האנגלי כגיבוי', () {
      // `אוצריא` הוא ה-CFBundleExecutable האמיתי של החבילה.
      expect(
          OtzariaProcessGuard.processNamesFor('macos'), ['אוצריא', 'otzaria']);
    });

    test('פלטפורמה אחרת: השם הפשוט, בלי סיומת', () {
      expect(OtzariaProcessGuard.processNamesFor('linux'), ['otzaria']);
    });

    test('השמות הם שמות תהליך בלבד — אף אחד מהם אינו נתיב', () {
      for (final os in const ['windows', 'macos', 'linux']) {
        for (final name in OtzariaProcessGuard.processNamesFor(os)) {
          expect(name, isNot(contains(p.separator)));
          expect(name, isNot(contains('/')));
        }
      }
    });
  });

  group('OtzariaProcessGuard (Windows בלבד)', () {
    late Directory tempDir;
    Process? fakeLauncher;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('otzaria-guard-test-');
    });

    tearDown(() async {
      fakeLauncher?.kill();
      fakeLauncher = null;
      // ההרג אינו מיידי; בלי ההמתנה מחיקת התיקייה נכשלת על קובץ נעול.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      try {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      } catch (_) {
        // קובץ עדיין נעול — לא מפיל את הבדיקה על ניקוי.
      }
    });

    test('תהליך ששמו מכיל "otzaria" אינו נחשב אוצריא רצה', () async {
      if (!Platform.isWindows) {
        markTestSkipped('בדיקת tasklist רצה רק בווינדוס');
        return;
      }

      // שם שתת-מחרוזת הייתה תופסת ("otzaria" בתוכו) אבל התאמה מדויקת לא.
      final fakePath = p.join(tempDir.path, 'otzaria-launcher-fake.exe');
      final started = await _startLongLivedCopyOfPing(fakePath);
      if (started == null) {
        markTestSkipped('לא ניתן להריץ תהליך עזר בסביבה הזו');
        return;
      }
      fakeLauncher = started;

      const guard = OtzariaProcessGuard();
      if (!await _waitUntilRunning(guard, 'otzaria-launcher-fake.exe')) {
        markTestSkipped('תהליך העזר לא הופיע ב-tasklist');
        return;
      }

      // זה הלב: הלאנצ'ר המדומה רץ, ובכל זאת "אוצריא" מדווחת כסגורה.
      expect(await guard.isRunning('otzaria.exe'), isFalse);
      expect(
        await guard
            .isAnyRunning(OtzariaProcessGuard.processNamesFor('windows')),
        isFalse,
      );
    });

    test('שם תהליך שאינו קיים כלל מדווח כלא רץ', () async {
      if (!Platform.isWindows) {
        markTestSkipped('בדיקת tasklist רצה רק בווינדוס');
        return;
      }

      const guard = OtzariaProcessGuard();
      expect(await guard.isRunning('no-such-process-9f2c.exe'), isFalse);
      expect(await guard.isAnyRunning(const []), isFalse);
    });
  });

  group('OtzariaProcessGuard (macOS/לינוקס בלבד)', () {
    test('pgrep על שם שאינו קיים מחזיר "לא רץ" (קוד יציאה 1)', () async {
      if (!Platform.isMacOS && !Platform.isLinux) {
        markTestSkipped('בדיקת pgrep רצה רק ב-macOS/לינוקס');
        return;
      }

      const guard = OtzariaProcessGuard();
      expect(await guard.isRunning('no-such-process-9f2c'), isFalse);
    });
  });

  group('OtzariaIsRunningException', () {
    tearDown(() => AppL10n.use(AppLanguage.hebrew));

    test('ההודעה מגיעה מ-otzaria_l10n ומתחלפת עם השפה', () {
      const exception = OtzariaIsRunningException();

      AppL10n.use(AppLanguage.hebrew);
      expect(
        exception.toString(),
        AppL10n.stringsFor(AppLanguage.hebrew).libraryDomain.otzariaIsRunning,
      );

      AppL10n.use(AppLanguage.english);
      expect(
        exception.toString(),
        AppL10n.stringsFor(AppLanguage.english).libraryDomain.otzariaIsRunning,
      );
    });
  });
}

/// מריץ עותק של `ping.exe` תחת [destPath] — תהליך אמיתי, ארוך-חיים ובלי
/// תלויות, שמאפשר לבדוק את `tasklist` מול שם קובץ שאנחנו קובעים.
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

Future<bool> _waitUntilRunning(OtzariaProcessGuard guard, String name) async {
  for (var i = 0; i < 20; i++) {
    if (await guard.isRunning(name)) return true;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return false;
}

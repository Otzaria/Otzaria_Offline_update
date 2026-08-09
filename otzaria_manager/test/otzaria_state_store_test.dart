import 'dart:convert';
import 'dart:io';

import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _state = OtzariaInstallState(
  installedTagName: '0.9.96+736',
  installDir: '/Applications',
  launchPath: '/Applications/אוצריא.app',
);

void main() {
  late Directory tempDir;
  late String statePath;
  late OtzariaStateStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria-state-test-');
    // תת-תיקייה שעדיין לא קיימת — save אמורה ליצור אותה בעצמה.
    statePath = p.join(tempDir.path, 'nested', 'otzaria_install_state.json');
    store = OtzariaStateStore(statePath);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('OtzariaStateStore', () {
    test('null כשעדיין לא נשמר כלום', () async {
      expect(await store.load(), isNull);
    });

    test('round-trip: מה שנשמר נקרא חזרה זהה, והתיקייה נוצרת', () async {
      await store.save(_state);

      expect(File(statePath).existsSync(), isTrue);
      expect(await store.load(), _state);
    });

    test('שמירה חוזרת דורסת את הקודמת', () async {
      await store.save(_state);
      const newer = OtzariaInstallState(
        installedTagName: '0.9.97',
        installDir: r'C:\dir',
        launchPath: r'C:\dir\otzaria.exe',
      );

      await store.save(newer);

      expect(await store.load(), newer);
    });

    // כתיבה אטומית: הקובץ הזמני לא אמור להישאר אחרי שמירה מוצלחת.
    test('לא נשאר קובץ \u200E.tmp אחרי שמירה', () async {
      await store.save(_state);

      expect(File('$statePath.tmp').existsSync(), isFalse);
      expect(
        Directory(p.dirname(statePath))
            .listSync()
            .map((e) => p.basename(e.path)),
        ['otzaria_install_state.json'],
      );
    });

    // "אין התקנה ידועה" ולא חריג — אחרת זרימת "תתקין מחדש" הייתה נחסמת.
    test('JSON פגום נקרא כ-null במקום לזרוק', () async {
      await Directory(p.dirname(statePath)).create(recursive: true);
      await File(statePath).writeAsString('{ לא JSON');

      expect(await store.load(), isNull);
    });

    test('JSON תקין שאינו אובייקט נקרא כ-null', () async {
      await Directory(p.dirname(statePath)).create(recursive: true);
      await File(statePath).writeAsString(jsonEncode([1, 2, 3]));

      expect(await store.load(), isNull);
    });

    test('אובייקט בלי השדות הנדרשים נקרא כ-null', () async {
      await Directory(p.dirname(statePath)).create(recursive: true);
      await File(statePath).writeAsString(jsonEncode({'installDir': '/x'}));

      expect(await store.load(), isNull);
    });

    // הקובץ נכתב על ידי גרסה ישנה של הלאנצ'ר, כשהמפתח נקרא exePath.
    test('פורמט ישן עם exePath עדיין נטען', () async {
      await Directory(p.dirname(statePath)).create(recursive: true);
      await File(statePath).writeAsString(jsonEncode({
        'installedTagName': '0.9.95',
        'installDir': r'C:\dir',
        'exePath': r'C:\dir\otzaria.exe',
      }));

      final loaded = await store.load();

      expect(loaded!.launchPath, r'C:\dir\otzaria.exe');
      expect(loaded.installedTagName, '0.9.95');
    });
  });
}

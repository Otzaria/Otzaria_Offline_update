import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late String root;

  setUp(() => root = tempMirrorRoot());

  CustomAppLocator locatorWith({
    Map<String, String?> versions = const {},
    List<String> registryDirs = const [],
    List<RegExp>? capturedPatterns,
  }) =>
      CustomAppLocator(
        readVersion: (exe) => versions[p.basename(exe).toLowerCase()],
        lookupUninstallDirs: (pattern) {
          capturedPatterns?.add(pattern);
          return registryDirs;
        },
      );

  test('בלי שם קובץ הרצה אין זיהוי בכלל', () async {
    final state = await locatorWith().detect(descriptor());
    expect(state, isNull);
  });

  test('מוצא את קובץ ההרצה בתיקייה המוצהרת וקורא ממנו גרסה', () async {
    final dir = p.join(root, 'Apps', 'MyApp');
    writeFile(p.join(dir, 'myapp.exe'));

    final state = await locatorWith(versions: {'myapp.exe': '1.4.2'}).detect(
      descriptor(
        detect: AppDetectRules(exeName: 'myapp.exe', dirs: [dir]),
      ),
    );

    expect(state, isNotNull);
    expect(state!.version, '1.4.2');
    expect(state.launchPath, p.join(dir, 'myapp.exe'));
    expect(state.installDir, dir);
  });

  test('מותקן בלי שדה גרסה — מזוהה, אך הגרסה null ולא "מעודכן"', () async {
    final dir = p.join(root, 'NoVersion');
    writeFile(p.join(dir, 'app.exe'));

    final state = await locatorWith().detect(
      descriptor(detect: AppDetectRules(exeName: 'app.exe', dirs: [dir])),
    );

    expect(state, isNotNull);
    expect(state!.version, isNull);
  });

  test('ההשוואה לשם הקובץ אינה תלוית רישיות', () async {
    final dir = p.join(root, 'Case');
    writeFile(p.join(dir, 'MyApp.EXE'));

    final state = await locatorWith().detect(
      descriptor(detect: AppDetectRules(exeName: 'myapp.exe', dirs: [dir])),
    );
    expect(state, isNotNull);
  });

  test('מוצא גם רמה אחת פנימה', () async {
    final dir = p.join(root, 'Outer');
    writeFile(p.join(dir, 'bin', 'app.exe'));

    final state = await locatorWith().detect(
      descriptor(detect: AppDetectRules(exeName: 'app.exe', dirs: [dir])),
    );
    expect(state!.launchPath, p.join(dir, 'bin', 'app.exe'));
  });

  // הגבול קיים כדי לא לטייל בעץ ענק, ובעיקר כדי שהתשובה תהיה זהה בכל מחשב.
  test('אינו צולל מעבר לעומק שנקבע', () async {
    final dir = p.join(root, 'Deep');
    writeFile(p.join(dir, 'a', 'b', 'c', 'app.exe'));

    final state = await locatorWith().detect(
      descriptor(detect: AppDetectRules(exeName: 'app.exe', dirs: [dir])),
    );
    expect(state, isNull);
  });

  test('הרג\'יסטרי קודם לתיקיות המוצהרות — הוא רישום ולא ניחוש', () async {
    final fromRegistry = p.join(root, 'FromRegistry');
    final declared = p.join(root, 'Declared');
    writeFile(p.join(fromRegistry, 'app.exe'));
    writeFile(p.join(declared, 'app.exe'));

    final state = await locatorWith(registryDirs: [fromRegistry]).detect(
      descriptor(
        detect: AppDetectRules(
          exeName: 'app.exe',
          registryDisplayName: 'My App',
          dirs: [declared],
        ),
      ),
    );

    expect(state!.installDir, fromRegistry);
  });

  test('תבנית ה-DisplayName נמסרת ללא תלות ברישיות', () async {
    final patterns = <RegExp>[];
    await locatorWith(capturedPatterns: patterns).detect(
      descriptor(
        detect: const AppDetectRules(
          exeName: 'app.exe',
          registryDisplayName: 'My App',
        ),
      ),
    );

    expect(patterns.single.pattern, 'My App');
    expect(patterns.single.isCaseSensitive, isFalse);
  });

  test('לא נמצא בשום מקום — null, ולא שגיאה', () async {
    final state = await locatorWith().detect(
      descriptor(
        detect: AppDetectRules(
          exeName: 'app.exe',
          dirs: [p.join(root, 'אין-כזו-תיקייה')],
        ),
      ),
    );
    expect(state, isNull);
  });

  test('מיקום ההתקנה שבתיאור משמש גם הוא כמועמד לחיפוש', () async {
    final dir = p.join(root, 'InstallDir');
    writeFile(p.join(dir, 'app.exe'));

    final state = await locatorWith().detect(
      descriptor(
        installDir: dir,
        detect: const AppDetectRules(exeName: 'app.exe'),
      ),
    );
    expect(state, isNotNull);
  });

  group('זיהוי לפי תהליך רץ — העדות החזקה ביותר', () {
    test('תהליך רץ מנצח את התיקיות, כולל מיקום שאיש לא ניחש', () async {
      final declared = p.join(root, 'Declared');
      final actual = p.join(root, 'Nobody', 'Guessed', 'This');
      writeFile(p.join(declared, 'app.exe'));
      writeFile(p.join(actual, 'app.exe'));

      final locator = CustomAppLocator(
        readVersion: (_) => '9.9',
        lookupRunningProcess: (exe) async => p.join(actual, exe),
      );

      final state = await locator.detect(
        descriptor(
          detect: AppDetectRules(exeName: 'app.exe', dirs: [declared]),
        ),
      );

      expect(state!.installDir, actual);
      expect(state.version, '9.9');
    });

    test('תהליך שהנתיב שלו כבר לא קיים אינו מנצח', () async {
      final declared = p.join(root, 'Declared');
      writeFile(p.join(declared, 'app.exe'));

      final locator = CustomAppLocator(
        readVersion: (_) => null,
        lookupRunningProcess: (_) async => p.join(root, 'gone', 'app.exe'),
      );

      final state = await locator.detect(
        descriptor(
          detect: AppDetectRules(exeName: 'app.exe', dirs: [declared]),
        ),
      );
      expect(state!.installDir, declared);
    });
  });

  group('מיקומים נלמדים', () {
    test('מיקום שנלמד נבדק לפני התיקייה המוצהרת', () async {
      final learned = p.join(root, 'Learned');
      final declared = p.join(root, 'Declared');
      writeFile(p.join(learned, 'app.exe'));
      writeFile(p.join(declared, 'app.exe'));

      final state = await locatorWith().detect(
        descriptor(
          detect: AppDetectRules(exeName: 'app.exe', dirs: [declared]),
        ),
        learnedDirs: [learned],
      );

      expect(state!.installDir, learned);
    });

    test('מיקום נלמד שאינו קיים כאן מדולג בשקט', () async {
      final declared = p.join(root, 'Declared');
      writeFile(p.join(declared, 'app.exe'));

      final state = await locatorWith().detect(
        descriptor(
          detect: AppDetectRules(exeName: 'app.exe', dirs: [declared]),
        ),
        learnedDirs: [p.join(root, 'מהמחשב-האחר')],
      );

      expect(state!.installDir, declared);
    });
  });

  group('בחירה ידנית', () {
    test('מוצא בתיקייה שהמשתמש הצביע עליה', () async {
      final dir = p.join(root, 'Picked');
      writeFile(p.join(dir, 'app.exe'));

      final state = await locatorWith().findIn(dir, 'app.exe');
      expect(state!.installDir, dir);
    });

    test('לא נמצא שם — null, והממשק יאמר "לא נמצאה שם התקנה"', () async {
      final state =
          await locatorWith().findIn(p.join(root, 'Empty'), 'app.exe');
      expect(state, isNull);
    });

    test('בלי שם קובץ הרצה אין מה לחפש', () async {
      expect(await locatorWith().findIn(root, null), isNull);
    });
  });
}

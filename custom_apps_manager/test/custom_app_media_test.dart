import 'dart:io';

import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late String root;
  late CustomAppStore store;
  late CustomAppMedia media;

  setUp(() async {
    root = tempMirrorRoot();
    store = CustomAppStore(mirrorRootDir: root);
    await store.add(descriptor());
    media = CustomAppMedia(appDir: store.dirFor('org.example.app'));
  });

  /// תמונה מדומה — התוכן אינו נקרא, רק הסיומת.
  String image(String name) => writeFile(p.join(root, 'src', name), 'png');

  group('שמירת מדיה', () {
    test('אייקון וצילומי מסך מועתקים לתיקיית התוכנה', () async {
      final saved = await media.save(
        iconSource: image('logo.png'),
        screenshotSources: [image('a.png'), image('b.jpg')],
      );

      expect(saved.icon, 'icon.png');
      expect(saved.screenshots, ['screenshot-1.png', 'screenshot-2.jpg']);
      expect(File(p.join(media.dirPath, 'icon.png')).existsSync(), isTrue);
      expect(
        File(p.join(media.dirPath, 'screenshot-2.jpg')).existsSync(),
        isTrue,
      );
    });

    // הסדר הוא השם, ולכן החלפת שתי תמונות שכבר יושבות כאן הייתה דורסת
    // אחת מהן באמצע — וזה מה שתיקיית הביניים מונעת.
    test('החלפת סדר של תמונות קיימות אינה מאבדת אף אחת', () async {
      await media.save(
        screenshotSources: [image('a.png'), image('b.png')],
      );
      final first = p.join(media.dirPath, 'screenshot-1.png');
      final second = p.join(media.dirPath, 'screenshot-2.png');
      File(first).writeAsStringSync('ראשונה');
      File(second).writeAsStringSync('שנייה');

      await media.save(screenshotSources: [second, first]);

      expect(File(first).readAsStringSync(), 'שנייה');
      expect(File(second).readAsStringSync(), 'ראשונה');
    });

    test('מה שלא נמסר נמחק — זו גם הדרך להסיר תמונה', () async {
      await media.save(
        iconSource: image('logo.png'),
        screenshotSources: [image('a.png')],
      );

      final saved = await media.save();

      expect(saved.icon, isNull);
      expect(saved.screenshots, isEmpty);
      expect(Directory(media.dirPath).listSync(), isEmpty);
    });

    test('קובץ שאינו תמונה נדחה בהודעה ששמה אותו בשם', () async {
      final exe = writeFile(p.join(root, 'src', 'setup.exe'));

      expect(
        () => media.save(iconSource: exe),
        throwsA(
          isA<AppDescriptorException>().having(
            (e) => e.message,
            'message',
            contains('setup.exe'),
          ),
        ),
      );
    });

    test('קובץ חסר נדחה, והקיים אינו נמחק', () async {
      await media.save(iconSource: image('logo.png'));

      await expectLater(
        media.save(
          iconSource: image('logo.png'),
          screenshotSources: [p.join(root, 'src', 'אין-כזה.png')],
        ),
        throwsA(isA<AppDescriptorException>()),
      );
      expect(File(p.join(media.dirPath, 'icon.png')).existsSync(), isTrue);
    });
  });

  group('נתיבים', () {
    test('נבנים משם הקובץ שברשומה', () {
      const record = AppDescriptor(
        id: 'org.example.app',
        name: 'x',
        sourceKind: AppSourceKind.manual,
        iconFile: 'icon.png',
        screenshotFiles: ['screenshot-1.png'],
      );

      expect(media.iconPathOf(record), p.join(media.dirPath, 'icon.png'));
      expect(
        media.screenshotPathsOf(record),
        [p.join(media.dirPath, 'screenshot-1.png')],
      );
    });

    test('בלי אייקון — null, ולא נתיב לקובץ שאינו קיים', () {
      expect(media.iconPathOf(descriptor()), isNull);
      expect(media.screenshotPathsOf(descriptor()), isEmpty);
    });
  });
}

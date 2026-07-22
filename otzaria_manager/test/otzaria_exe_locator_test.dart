import 'dart:io';

import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('OtzariaExeLocator', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('exe-locator-test-');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('returns null when directory does not exist', () async {
      const locator = OtzariaExeLocator();
      final result = await locator.findExeIn(p.join(tempDir.path, 'missing'));
      expect(result, isNull);
    });

    test('finds the app exe nested inside subfolders, ignoring uninstaller', () async {
      final appDir = Directory(p.join(tempDir.path, 'app'))..createSync(recursive: true);
      File(p.join(appDir.path, 'otzaria.exe')).writeAsStringSync('fake');
      File(p.join(tempDir.path, 'unins000.exe')).writeAsStringSync('fake');

      const locator = OtzariaExeLocator();
      final result = await locator.findExeIn(tempDir.path);

      expect(result, isNotNull);
      expect(p.basename(result!), 'otzaria.exe');
    });

    test('returns null when only an uninstaller exe exists', () async {
      File(p.join(tempDir.path, 'unins000.exe')).writeAsStringSync('fake');

      const locator = OtzariaExeLocator();
      final result = await locator.findExeIn(tempDir.path);

      expect(result, isNull);
    });
  });
}

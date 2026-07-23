import 'dart:io';

import 'package:library_manager/library_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('LibraryDbLocator', () {
    late Directory tempDir;
    late LibraryStateStore stateStore;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('db-locator-test-');
      stateStore = LibraryStateStore(p.join(tempDir.path, 'state.json'));
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('returns null when neither custom nor default DB exists', () async {
      final locator = LibraryDbLocator(stateStore: stateStore);
      expect(await locator.resolveDbPath(), isNull);
    });

    test('prefers a saved custom path over the default when both could exist', () async {
      final customDbPath = p.join(tempDir.path, 'my-library', 'seforim.db');
      await Directory(p.dirname(customDbPath)).create(recursive: true);
      await File(customDbPath).writeAsString('fake db');
      await stateStore.saveCustomDbPath(customDbPath);

      final locator = LibraryDbLocator(stateStore: stateStore);
      expect(await locator.resolveDbPath(), customDbPath);
    });

    test('ignores a saved custom path that no longer exists on disk', () async {
      await stateStore.saveCustomDbPath(p.join(tempDir.path, 'missing', 'seforim.db'));

      final locator = LibraryDbLocator(stateStore: stateStore);
      // אין גם default (לא בודקים אמיתית את C:\אוצריא בסביבת הטסט) —
      // אז התוצאה הצפויה היא null, לא הנתיב הישן.
      expect(await locator.resolveDbPath(), isNull);
    });
  });
}

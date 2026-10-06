import 'dart:io';

import 'package:hive_ce/hive.dart';
import 'package:library_manager/library_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late String launch, settingsRoot;
  late LibraryManager manager;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('semantic-active-path-');
    final install = p.join(temporary.path, 'application');
    launch = p.join(install, 'otzaria.exe');
    await File(launch).create(recursive: true);
    await File(p.join(install, 'portable.marker')).create();
    settingsRoot = p.join(install, 'otzaria_data');
    manager = LibraryManager(
      dataDir: p.join(temporary.path, 'drive'),
      operatingSystem: Platform.operatingSystem,
      environment: const {},
      otzariaLaunchPath: () async => launch,
    );
  });

  tearDown(() async {
    manager.dispose();
    await temporary.delete(recursive: true);
  });

  Future<void> preferences(Map<String, Object> values) async {
    await Directory(settingsRoot).create(recursive: true);
    Hive.init(settingsRoot);
    final box = await Hive.openBox<dynamic>(
      OtzariaSettingsReader.boxName,
      path: settingsRoot,
    );
    try {
      await box.putAll(values);
      await box.flush();
    } finally {
      await box.close();
    }
  }

  for (final nested in ['', 'nested', p.join('nested', 'deep')]) {
    test('active vectors use library parent with folder "$nested"', () async {
      final library = p.join(temporary.path, 'content', 'books');
      final db = p.join(library, nested, 'seforim.db');
      await preferences({
        OtzariaSettingsReader.keyLibraryPath: library,
        OtzariaSettingsReader.keyLibraryFolderName: nested,
        'unrelated-setting': 'unchanged',
      });
      final settings = File(
        p.join(settingsRoot, OtzariaSettingsReader.boxFileName),
      );
      final before = await settings.readAsBytes();
      final root = await manager.resolveSemanticVectorsRoot(db);
      expect(root, p.dirname(library));
      expect(await settings.readAsBytes(), before);
      expect(await Directory(p.join(root, 'vectors')).exists(), false);
      expect(await Directory(p.join(temporary.path, 'drive')).exists(), false);
      if (nested.isNotEmpty) {
        expect(root, isNot(p.dirname(p.dirname(db))));
      }
    });
  }

  test('effective DB path does not move the active vectors root', () async {
    final library = p.join(temporary.path, 'content', 'books');
    final externalDb = p.join(
      temporary.path,
      'elsewhere',
      'database',
      'seforim.db',
    );
    await preferences({
      OtzariaSettingsReader.keyLibraryPath: library,
      OtzariaSettingsReader.keyLibraryFolderName: 'nested',
      OtzariaSettingsReader.keyDbEffectivePath: externalDb,
    });
    expect(
      await manager.resolveSemanticVectorsRoot(externalDb),
      p.dirname(library),
    );
    expect(p.dirname(externalDb), isNot(p.dirname(library)));
  });

  for (final library in <String?>[null, '']) {
    test(
      'missing or empty library path falls back without writing settings: $library',
      () async {
        final db = p.join(temporary.path, 'content', 'books', 'seforim.db');
        if (library != null) {
          await preferences({OtzariaSettingsReader.keyLibraryPath: library});
        }
        expect(
          await manager.resolveSemanticVectorsRoot(db),
          p.dirname(p.dirname(db)),
        );
        if (library == null) {
          expect(await Directory(settingsRoot).exists(), false);
        }
      },
    );
  }
}

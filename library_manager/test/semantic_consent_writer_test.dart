import 'dart:io';

import 'package:hive_ce/hive.dart';
import 'package:library_manager/src/services/otzaria_settings_reader.dart';
import 'package:library_manager/src/services/otzaria_settings_writer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  const writer = OtzariaSettingsWriter();
  const reader = OtzariaSettingsReader();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('semantic-consent-writer-');
  });
  tearDown(() async {
    if (Hive.isBoxOpen(OtzariaSettingsReader.boxName)) {
      await Hive.box<dynamic>(OtzariaSettingsReader.boxName).close();
    }
    await tempDir.delete(recursive: true);
  });

  Future<Box<dynamic>> open(String root) async {
    await Directory(root).create(recursive: true);
    Hive.init(root);
    return Hive.openBox<dynamic>(OtzariaSettingsReader.boxName, path: root);
  }

  test(
    'finished installation enables installed int8 without granting consent',
    () async {
      final box = await open(tempDir.path);
      await box.putAll({
        'key-semantic-model-quantization': 'fp32',
        'key-semantic-data-enabled': false,
        'key-semantic-download-paused': true,
        'key-offline-mode': true,
        'key-semantic-skipped-vectors-release': 'keep-tag',
        OtzariaSettingsReader.keySearchFeedbackConsent: 'declined',
        OtzariaSettingsReader.keySearchFeedbackConsentVersion: 1,
        'unrelated': 'unchanged',
      });
      await box.close();

      expect(
        await writer.finishSemanticInstall(dataRootPath: tempDir.path),
        isTrue,
      );

      final reopened = await open(tempDir.path);
      expect(reopened.get('key-semantic-model-quantization'), 'int8');
      expect(reopened.get('key-semantic-data-enabled'), isTrue);
      expect(reopened.get('key-semantic-download-paused'), isFalse);
      expect(reopened.get('key-offline-mode'), isTrue);
      expect(reopened.get('key-semantic-skipped-vectors-release'), 'keep-tag');
      expect(
        reopened.get(OtzariaSettingsReader.keySearchFeedbackConsent),
        'declined',
      );
      expect(reopened.get('unrelated'), 'unchanged');
      await reopened.close();
      expect(
        (await reader.read(tempDir.path))!.semanticSearchReadyPreferences,
        isTrue,
      );
    },
  );

  test('finishing installation cannot create an absent data root', () async {
    final root = p.join(tempDir.path, 'absent');
    expect(await writer.finishSemanticInstall(dataRootPath: root), isFalse);
    expect(await Directory(root).exists(), isFalse);
  });

  test('explicit consent preserves unrelated preferences', () async {
    final box = await open(tempDir.path);
    await box.putAll({
      'unrelated': 'unchanged',
      OtzariaSettingsReader.keyLibraryPath: 'chosen-library',
      OtzariaSettingsReader.keySearchFeedbackConsent: 'declined',
    });
    await box.close();

    expect(
      await writer.grantSearchFeedbackConsent(dataRootPath: tempDir.path),
      isTrue,
    );
    final settings = await reader.read(tempDir.path);
    expect(settings!.searchFeedbackGranted, isTrue);
    expect(settings.searchFeedbackConsentVersion, 1);
    expect(settings.libraryPath, 'chosen-library');
    final reopened = await open(tempDir.path);
    expect(reopened.get('unrelated'), 'unchanged');
    await reopened.close();
  });

  test('corrupt preferences are not repaired or truncated', () async {
    final source = File(
      p.join(tempDir.path, OtzariaSettingsReader.boxFileName),
    );
    await source.writeAsBytes([1, 2, 3, 4, 5]);
    final before = await source.readAsBytes();
    expect(
      await writer.grantSearchFeedbackConsent(dataRootPath: tempDir.path),
      isFalse,
    );
    expect(await source.readAsBytes(), before);
    expect(
      await writer.finishSemanticInstall(dataRootPath: tempDir.path),
      isFalse,
    );
    expect(await source.readAsBytes(), before);
  });

  test('box open at another root stays open and unchanged', () async {
    final otherRoot = p.join(tempDir.path, 'other');
    final targetRoot = p.join(tempDir.path, 'target');
    await Directory(targetRoot).create();
    final box = await open(otherRoot);
    await box.put('unrelated', 'unchanged');
    await box.flush();
    final source = File(p.join(otherRoot, OtzariaSettingsReader.boxFileName));
    final before = await source.readAsBytes();

    expect(
      await writer.grantSearchFeedbackConsent(dataRootPath: targetRoot),
      isFalse,
    );
    expect(box.isOpen, isTrue);
    expect(box.get('unrelated'), 'unchanged');
    expect(box.get(OtzariaSettingsReader.keySearchFeedbackConsent), isNull);
    expect(await source.readAsBytes(), before);
    expect(await Directory(targetRoot).list().toList(), isEmpty);
    expect(
      await writer.finishSemanticInstall(dataRootPath: targetRoot),
      isFalse,
    );
    expect(box.isOpen, isTrue);
    expect(await source.readAsBytes(), before);
    await box.close();
  });

  test('missing root requires explicit creation permission', () async {
    final root = p.join(tempDir.path, 'not-started');
    expect(
      await writer.grantSearchFeedbackConsent(dataRootPath: root),
      isFalse,
    );
    expect(await Directory(root).exists(), isFalse);
    expect(
      await writer.grantSearchFeedbackConsent(
        dataRootPath: root,
        allowCreate: true,
      ),
      isTrue,
    );
    expect((await reader.read(root))!.searchFeedbackGranted, isTrue);
  });

  test('existing root can acquire a missing preferences box', () async {
    expect(
      await writer.grantSearchFeedbackConsent(dataRootPath: tempDir.path),
      isTrue,
    );
    expect((await reader.read(tempDir.path))!.searchFeedbackGranted, isTrue);
  });
}

import 'dart:io';

import 'package:hive_ce/hive.dart';
import 'package:library_manager/src/services/otzaria_settings_reader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('OtzariaSettingsReader search feedback consent', () {
    late Directory dataRoot;
    const reader = OtzariaSettingsReader();

    setUp(() async {
      dataRoot = await Directory.systemTemp.createTemp('semantic-consent-');
    });

    tearDown(() async {
      await dataRoot.delete(recursive: true);
    });

    Future<void> writeSettings(Map<String, Object> values) async {
      Hive.init(dataRoot.path);
      final box = await Hive.openBox<dynamic>(
        OtzariaSettingsReader.boxName,
        path: dataRoot.path,
      );
      try {
        await box.putAll(values);
        await box.flush();
      } finally {
        await box.close();
      }
    }

    for (final version in [1, 2]) {
      test('granted consent at version $version enables feedback', () async {
        await writeSettings({
          OtzariaSettingsReader.keySearchFeedbackConsent: 'granted',
          OtzariaSettingsReader.keySearchFeedbackConsentVersion: version,
        });

        final settings = await reader.read(dataRoot.path);

        expect(settings, isNotNull);
        expect(settings!.searchFeedbackConsent, 'granted');
        expect(settings.searchFeedbackConsentVersion, version);
        expect(settings.searchFeedbackGranted, isTrue);
      });
    }

    final deniedCases = <String, Map<String, Object>>{
      'declined': {
        OtzariaSettingsReader.keySearchFeedbackConsent: 'declined',
        OtzariaSettingsReader.keySearchFeedbackConsentVersion: 1,
      },
      'missing consent': {
        OtzariaSettingsReader.keySearchFeedbackConsentVersion: 1,
      },
      'missing version': {
        OtzariaSettingsReader.keySearchFeedbackConsent: 'granted',
      },
      'old version': {
        OtzariaSettingsReader.keySearchFeedbackConsent: 'granted',
        OtzariaSettingsReader.keySearchFeedbackConsentVersion: 0,
      },
      'boolean consent': {
        OtzariaSettingsReader.keySearchFeedbackConsent: true,
        OtzariaSettingsReader.keySearchFeedbackConsentVersion: 1,
      },
      'string version': {
        OtzariaSettingsReader.keySearchFeedbackConsent: 'granted',
        OtzariaSettingsReader.keySearchFeedbackConsentVersion: '1',
      },
      'boolean version': {
        OtzariaSettingsReader.keySearchFeedbackConsent: 'granted',
        OtzariaSettingsReader.keySearchFeedbackConsentVersion: true,
      },
    };

    for (final entry in deniedCases.entries) {
      test('${entry.key} leaves feedback disabled', () async {
        await writeSettings(entry.value);

        final settings = await reader.read(dataRoot.path);

        expect(settings, isNotNull);
        expect(settings!.searchFeedbackGranted, isFalse);
      });
    }

    test('missing preferences leave consent unavailable', () async {
      expect(await reader.read(dataRoot.path), isNull);
      expect(await dataRoot.list().toList(), isEmpty);
    });

    test('reading consent preserves the live preferences and directory',
        () async {
      await writeSettings({
        OtzariaSettingsReader.keySearchFeedbackConsent: 'granted',
        OtzariaSettingsReader.keySearchFeedbackConsentVersion: 1,
        'unrelated-preference': 'keep this value',
      });
      final source = File(
        p.join(dataRoot.path, OtzariaSettingsReader.boxFileName),
      );
      final bytesBefore = await source.readAsBytes();
      final filesBefore = (await dataRoot.list().toList())
          .map((file) => p.basename(file.path))
          .toList()
        ..sort();

      expect((await reader.read(dataRoot.path))!.searchFeedbackGranted, isTrue);

      expect(await source.readAsBytes(), bytesBefore);
      final filesAfter = (await dataRoot.list().toList())
          .map((file) => p.basename(file.path))
          .toList()
        ..sort();
      expect(filesAfter, filesBefore);
    });
  });
}

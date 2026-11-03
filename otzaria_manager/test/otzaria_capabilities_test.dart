import 'dart:io';

import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/sandbox.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('caps_'));
  tearDown(() => temp.deleteSync(recursive: true));

  void write(String text) =>
      File(p.join(temp.path, OtzariaCapabilities.fileName))
          .writeAsStringSync(text);

  test('אין קובץ או קובץ פגום — לא ידוע', () async {
    expect(await OtzariaCapabilities.read(temp.path), isNull);
    write('{not json');
    expect(await OtzariaCapabilities.read(temp.path), isNull);
    write('[1]');
    expect(await OtzariaCapabilities.read(temp.path), isNull);
  });

  test('השדות נקראים, גם אחרי BOM; מפתח חסר או מסוג אחר הוא לא ידוע', () async {
    write('\uFEFF{"formatVersion":1,"reportsQueueFormat":1,'
        '"pluginInstallResults":"1","appVersion":"0.9.98"}');

    final caps = await OtzariaCapabilities.read(temp.path);

    expect(caps?.reportsQueueFormat, 1);
    expect(caps?.pluginInstallResults, isNull);
  });

  test('C1 של exe אחר אינו קובע את הסכמה הקריאה', () {
    final exe = p.join(temp.path, 'otzaria.exe');
    int? resolve(String? exePath) =>
        OtzariaCapabilities.resolveReadableDbSchema(
          capabilities: OtzariaCapabilities(
            appVersion: '0.9.98',
            readableDbSchemaVersion: 6,
            exePath: exePath,
          ),
          launchPath: exe,
        );

    expect(resolve(exe), 6);
    expect(resolve(null), 6);
    expect(resolve(p.join(temp.path, 'other', 'otzaria.exe')), isNull);
  });

  test('משפחות הוקטורים נקראות בזהירות', () async {
    write('{"semanticVectorFamilies":["vectors-windows",3,"","vectors"]}');
    final caps = await OtzariaCapabilities.read(temp.path);
    expect(caps?.semanticVectorFamilies, ['vectors-windows', 'vectors']);
    expect(
      OtzariaCapabilities.supportsWindowsVectors(capabilities: caps),
      isTrue,
    );

    write('{"semanticVectorFamilies":"vectors-windows"}');
    final wrongType = await OtzariaCapabilities.read(temp.path);
    expect(wrongType?.semanticVectorFamilies, isNull);
    expect(
      OtzariaCapabilities.supportsWindowsVectors(capabilities: wrongType),
      isFalse,
    );

    write('{"semanticVectorFamilies":["vectors"]}');
    expect(
      OtzariaCapabilities.supportsWindowsVectors(
        capabilities: await OtzariaCapabilities.read(temp.path),
      ),
      isFalse,
    );
    expect(OtzariaCapabilities.supportsWindowsVectors(), isFalse);
  });

  test('תמיכה בחלונות מ-exe אחר אינה נחשבת', () {
    final exe = p.join(temp.path, 'otzaria.exe');
    bool supports(String? exePath) =>
        OtzariaCapabilities.supportsWindowsVectors(
          capabilities: OtzariaCapabilities(
            exePath: exePath,
            semanticVectorFamilies: const ['vectors-windows', 'vectors'],
          ),
          launchPath: exe,
        );

    expect(supports(exe), isTrue);
    expect(supports(null), isTrue);
    expect(supports(p.join(temp.path, 'other', 'otzaria.exe')), isFalse);
  });

  test('אוצריא ישנה מכותבת הקובץ אינה תומכת בחלונות', () {
    bool supports(String? installed) =>
        OtzariaCapabilities.supportsWindowsVectors(
          capabilities: const OtzariaCapabilities(
            appVersion: '0.9.99',
            semanticVectorFamilies: ['vectors-windows', 'vectors'],
          ),
          installedVersion: installed,
        );

    expect(supports('0.9.98+900'), isFalse);
    expect(supports('0.9.99+901'), isTrue);
    expect(
      supports('1.0.0'),
      isFalse,
      reason: 'a file of an older app is no proof for the installed one',
    );
    expect(supports(null), isTrue);
  });

  group('semantic support of the installed app', () {
    OtzariaCapabilities caps(String written, List<String> families,
            {int? build}) =>
        OtzariaCapabilities(
          appVersion: written,
          buildNumber: build,
          semanticVectorFamilies: families,
        );
    SemanticAppSupport support(OtzariaCapabilities? c, String? installed) =>
        OtzariaCapabilities.semanticSupport(
          capabilities: c,
          installedVersion: installed,
        );

    test('QA491 families of the app itself, with or without build metadata',
        () {
      for (final installed in ['0.9.98.3', '0.9.98.3+809']) {
        final s = support(
          caps('0.9.98.3', ['vectors-qa491-windows', 'vectors-qa491']),
          installed,
        );
        expect(s.generation, SemanticModelGeneration.qa491);
        expect(s.windows, isTrue);
        expect(s.basis, SemanticSupportBasis.declared);
      }
      final anchor = support(
        caps('0.9.98.3', ['vectors-qa491']),
        '0.9.98.3+809',
      );
      expect(anchor.windows, isFalse);
    });

    test('the Round2 file of 0.9.98.2 does not describe 0.9.98.3', () {
      final old = caps('0.9.98.2', ['vectors-windows', 'vectors']);
      final s = support(old, '0.9.98.3+809');
      expect(s.generation, SemanticModelGeneration.qa491);
      expect(s.windows, isFalse);
      expect(s.capabilitiesStale, isTrue);
      expect(s.basis, SemanticSupportBasis.appVersion);
      expect(
          support(old, '0.9.98.2').generation, SemanticModelGeneration.round2);
      expect(support(old, '0.9.98.2').windows, isTrue);
    });

    for (final written in [
      '0.9.98.3-rc1',
      'v0.9.98.3-beta+808',
      '0.9.98.3+808-rc1',
    ]) {
      test('a file of "$written" is no proof for the stable app', () {
        final old = caps(written, ['vectors-windows', 'vectors']);
        final s = support(old, '0.9.98.3+809');
        expect(s.generation, SemanticModelGeneration.qa491);
        expect(s.windows, isFalse);
        expect(s.basis, SemanticSupportBasis.appVersion);
        expect(s.capabilitiesStale, isTrue);
        expect(support(old, null).generation, isNull);
      });
    }

    for (final old in [
      caps('v0.9.98.3+808', ['vectors-windows', 'vectors']),
      caps('0.9.98.3', ['vectors-windows', 'vectors'], build: 808),
      caps('0.9.98.3', ['vectors-qa491-windows', 'vectors-qa491'], build: 808),
      caps('0.9.98.3', ['vectors-qa491-windows', 'vectors-qa491'], build: 810),
    ]) {
      test(
          'a file of another build keeps no unproven vector shape '
          '(${old.appVersion}, ${old.buildNumber})', () {
        final s = support(old, '0.9.98.3+809');
        expect(s.generation, SemanticModelGeneration.qa491);
        expect(s.windows, isFalse);
        expect(s.basis, SemanticSupportBasis.appVersion);
        expect(s.capabilitiesStale, isTrue);
      });
    }

    test('the matching build still proves the declared windows shape', () {
      final s = support(
        caps('v0.9.98.3', ['vectors-qa491-windows', 'vectors-qa491'],
            build: 809),
        '0.9.98.3+809',
      );
      expect(s.generation, SemanticModelGeneration.qa491);
      expect(s.windows, isTrue);
      expect(s.basis, SemanticSupportBasis.declared);
      expect(s.capabilitiesStale, isFalse);
    });

    test('an older file of the same generation still shows the shape', () {
      final s = support(
        caps('0.9.97', ['vectors-windows', 'vectors']),
        '0.9.98.2',
      );
      expect(s.generation, SemanticModelGeneration.round2);
      expect(s.windows, isTrue);
      expect(s.capabilitiesStale, isTrue);
    });

    test('a version beyond the verified table is not guessed', () {
      final s = support(
        caps('0.9.98.3', ['vectors-qa491-windows', 'vectors-qa491']),
        '0.9.99',
      );
      expect(s.generation, isNull);
      expect(s.proven, isFalse);
      expect(s.basis, SemanticSupportBasis.unproven);
      expect(support(null, null).generation, isNull);
      expect(support(null, 'garbage').generation, isNull);
    });

    for (final version in [
      '0.9.98.3a',
      '0.9.98.-1',
      '0.9',
      '0',
      '0.9.98.3-rc1',
      'v0.9.98.2-beta',
      '0.9.98.3.1.2',
      'latest',
    ]) {
      test('"$version" proves no generation, even with a matching file', () {
        expect(
          OtzariaCapabilities.semanticGenerationForAppVersion(version),
          isNull,
        );
        final fresh = caps('0.9.98.3', ['vectors-qa491-windows', 'vectors']);
        for (final file in [null, fresh]) {
          final s = support(file, version);
          expect(s.generation, isNull);
          expect(s.proven, isFalse);
          expect(s.basis, SemanticSupportBasis.unproven);
          expect(s.windows, isFalse);
        }
        expect(support(fresh, version).capabilitiesStale, isTrue);
      });
    }

    test('a file naming an unplaceable version proves nothing either', () {
      expect(support(caps('0.9.98.3a', []), null).generation, isNull);
      expect(support(caps('latest', []), null).generation, isNull);
      expect(
        support(caps('0.9.98.3', []), null).generation,
        SemanticModelGeneration.qa491,
      );
    });

    test('the proof key tells every input that changes the answer', () {
      final base = support(
        caps('0.9.98.3', ['vectors-qa491']),
        '0.9.98.3',
      ).proofKey;
      final stale = support(
        caps('0.9.98.2', ['vectors-windows']),
        '0.9.98.3',
      );
      expect(stale.capabilitiesStale, isTrue);
      expect(stale.proofKey, isNot(base));
      expect(
        support(
          caps('1.0.0', ['vectors-qa900', 'vectors-qa491']),
          '1.0.0',
        ).proofKey,
        isNot(support(caps('1.0.0', ['vectors-qa901']), '1.0.0').proofKey),
      );
      expect(
        const SemanticAppSupport(
          basis: SemanticSupportBasis.unproven,
          capabilitiesStale: true,
        ).proofKey,
        isNot(
          const SemanticAppSupport(basis: SemanticSupportBasis.unproven)
              .proofKey,
        ),
      );
      expect(
        const SemanticAppSupport(
          basis: SemanticSupportBasis.unproven,
          capabilitiesOfOtherApp: true,
        ).proofKey,
        isNot(
          const SemanticAppSupport(basis: SemanticSupportBasis.unproven)
              .proofKey,
        ),
      );
    });

    test('a future family listed first is unknown, not Round2', () {
      final s = support(
        caps('1.0.0', ['vectors-qa900-windows', 'vectors-qa491']),
        '1.0.0',
      );
      expect(s.generation, isNull);
      expect(s.unrecognizedFamilies, ['vectors-qa900-windows']);
    });

    test('windows is the shape of the generation the app reads', () {
      final s = support(
        caps('1.0.0', ['vectors-qa491', 'vectors-windows']),
        '1.0.0',
      );
      expect(s.generation, SemanticModelGeneration.qa491);
      expect(s.windows, isFalse);
    });
  });

  test('מחרוזת ריקה וסכמה לא חיובית הן לא ידוע', () async {
    write('{"appVersion":"","exePath":"","readableDbSchemaVersion":0}');

    final caps = await OtzariaCapabilities.read(temp.path);

    expect(caps?.appVersion, isNull);
    expect(caps?.exePath, isNull);
    expect(caps?.readableDbSchemaVersion, isNull);
  });

  test('בבדיקות, קריאה משורש הנתונים האמיתי של אוצריא נכשלת', () async {
    sandboxRealDataRoot();
    final real =
        Platform.environment['APPDATA'] ?? Platform.environment['HOME'];
    final root = Platform.environment['APPDATA'] != null
        ? p.join(real!, 'otzaria')
        : p.join(real!, 'Library', 'Application Support', 'otzaria');

    await expectLater(
      OtzariaCapabilities.read(root),
      throwsA(isA<AssertionError>()),
    );
    expect(
        OtzariaManager.defaultEnvironment()['APPDATA'],
        isNot(
          Platform.environment['APPDATA'],
        ));
  });
}

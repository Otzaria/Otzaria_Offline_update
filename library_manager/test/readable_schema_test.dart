import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/library_manager.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart' show OtzariaCapabilities;
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';

import 'support/db_fixtures.dart';

void main() {
  group('OtzariaCapabilities', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('capabilities-');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('קורא את שדות C1 ומתעלם ממפתחות חסרים או שגויים', () async {
      await File(
        p.join(tempDir.path, OtzariaCapabilities.fileName),
      ).writeAsString(
        jsonEncode({
          'formatVersion': 1,
          'appVersion': '0.9.98.2',
          'readableDbSchemaVersion': 6,
          'libraryDbPath': r'C:\books\seforim.db',
          'future': {'x': 1},
        }),
      );

      final read = (await OtzariaCapabilities.read(tempDir.path))!;
      expect(read.appVersion, '0.9.98.2');
      expect(read.readableDbSchemaVersion, 6);
      expect(read.libraryDbPath, r'C:\books\seforim.db');

      await File(
        p.join(tempDir.path, OtzariaCapabilities.fileName),
      ).writeAsString(jsonEncode({'readableDbSchemaVersion': '6'}));
      final partial = (await OtzariaCapabilities.read(tempDir.path))!;
      expect(partial.readableDbSchemaVersion, isNull);
    });

    test('קובץ חסר או פגום אינו מפיל — פשוט אין יכולות ידועות', () async {
      expect(await OtzariaCapabilities.read(tempDir.path), isNull);
      await File(
        p.join(tempDir.path, OtzariaCapabilities.fileName),
      ).writeAsString('{not json');
      expect(await OtzariaCapabilities.read(tempDir.path), isNull);
    });

    test('טבלת הגרסאות: סכמה 6 רק מאוצריא 0.9.98', () {
      int? schema(String v) =>
          OtzariaCapabilities.readableDbSchemaForAppVersion(v);
      expect(schema('0.9.97'), 5);
      expect(schema('0.9.97+99702'), 5);
      expect(schema('0.9.98'), 6);
      expect(schema('0.9.98.2'), 6);
      expect(schema('v0.9.99-beta'), 6);
      expect(schema('1.0.0'), 6);
      expect(schema('unknown'), isNull);
    });

    test('C1 קובע; גרסה מותקנת חדשה ממנו גוברת, וישנה ממנו (שנמוכה) מנצחת', () {
      int? resolve(int? declared, String? declaredFor, String? installed) =>
          OtzariaCapabilities.resolveReadableDbSchema(
            capabilities: declared == null && declaredFor == null
                ? null
                : OtzariaCapabilities(
                    readableDbSchemaVersion: declared,
                    appVersion: declaredFor,
                  ),
            installedVersion: installed,
          );

      expect(resolve(null, null, null), isNull);
      expect(resolve(null, null, '0.9.97'), 5);
      expect(resolve(7, '1.2.0', null), 7);
      expect(resolve(7, '1.2.0', '1.2.0'), 7);
      expect(resolve(5, '0.9.97', '0.9.98'), 6);
      expect(resolve(6, '0.9.98', '0.9.97'), 5);
      expect(resolve(6, null, '0.9.97'), 6);
    });
  });

  group('checkForUpdate — סכמה שאוצריא המותקנת קוראת', () {
    late Directory tempDir;
    late String dataDir;
    late String mirrorDir;
    late String home;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('readable-schema-');
      dataDir = p.join(tempDir.path, 'OtzariaData');
      mirrorDir = p.join(dataDir, 'mirror', 'library');
      home = p.join(tempDir.path, 'home');
      await Directory(dataDir).create(recursive: true);
    });

    tearDown(() async {
      AppL10n.use(AppLanguage.hebrew);
      if (await tempDir.exists()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    Future<void> writeMirror(String tag, List<String> fullDbNames) async {
      final assets = <Map<String, dynamic>>[];
      for (final name in fullDbNames) {
        final relative = p.join('assets', tag, name);
        final file = File(p.join(mirrorDir, relative));
        await file.parent.create(recursive: true);
        await file.writeAsBytes([1, 2, 3, 4]);
        assets.add({'name': name, 'downloadUrl': relative, 'size': 4});
      }
      await File(p.join(mirrorDir, 'releases.json')).writeAsString(
        jsonEncode({
          'formatVersion': 1,
          'releases': [
            {
              'tag': tag,
              'isPrerelease': false,
              'isDraft': false,
              'assets': assets,
            },
          ],
        }),
      );
    }

    Future<void> installExistingDb(int version) async {
      final dbPath = p.join(tempDir.path, 'books', 'seforim.db');
      await Directory(p.dirname(dbPath)).create(recursive: true);
      File(dbPath).writeAsBytesSync(buildVersionOnlyDb(tempDir.path, version));
      await LibraryStateStore(
        p.join(dataDir, 'library_state.json'),
      ).saveCustomDbPath(dbPath);
    }

    LibraryManager manager({String? appVersion}) => LibraryManager(
      dataDir: dataDir,
      operatingSystem: 'linux',
      environment: {'HOME': home},
      otzariaAppVersion: () async => appVersion,
    );

    Future<LibraryUpdateCheckResult> check({String? appVersion}) async {
      final m = manager(appVersion: appVersion);
      try {
        return await m.checkForUpdate();
      } finally {
        m.dispose();
      }
    }

    test('אוצריא 0.9.97 מקבלת את המסד בסכמה 5, לא את סכמה 6', () async {
      await writeMirror('v31', ['seforim.db.zst', 'seforim-schema6.db.zst']);

      final result = await check(appVersion: '0.9.97');

      expect(result.plan?.kind, LibraryUpdatePlanKind.fullDownload);
      expect(result.plan?.fullDbAsset?.name, 'seforim.db.zst');
      expect(result.readableDbSchemaVersion, 5);
      expect(result.needsNewerOtzaria, isFalse);
    });

    test('אוצריא 0.9.98 מקבלת את סכמה 6', () async {
      await writeMirror('v31', ['seforim.db.zst', 'seforim-schema6.db.zst']);

      final result = await check(appVersion: '0.9.98');

      expect(result.plan?.fullDbAsset?.name, 'seforim-schema6.db.zst');
    });

    test('אוצריא 0.9.98 אינה מקבלת את סכמה 7 גם כשהיא במראה', () async {
      await writeMirror('v33', [
        'seforim-schema6.db.zst',
        'seforim-schema7.db.zst',
      ]);

      final result = await check(appVersion: '0.9.98');

      expect(result.plan?.kind, LibraryUpdatePlanKind.fullDownload);
      expect(result.plan?.fullDbAsset?.name, 'seforim-schema6.db.zst');
      expect(result.readableDbSchemaVersion, 6);
      expect(result.needsNewerOtzaria, isFalse);
    });

    test('אוצריא לא ידועה — ההתנהגות הקודמת, הסכמה הגבוהה הנתמכת', () async {
      await writeMirror('v31', ['seforim.db.zst', 'seforim-schema6.db.zst']);

      final result = await check();

      expect(result.readableDbSchemaVersion, isNull);
      expect(result.plan?.fullDbAsset?.name, 'seforim-schema6.db.zst');
    });

    test('C1 שמצהיר על סכמה 5 גובר כשהגרסה המותקנת אינה ידועה', () async {
      await writeMirror('v31', ['seforim.db.zst', 'seforim-schema6.db.zst']);
      final root = p.join(home, '.local', 'share', 'otzaria');
      await Directory(root).create(recursive: true);
      await File(p.join(root, OtzariaCapabilities.fileName)).writeAsString(
        jsonEncode({'appVersion': '0.9.97', 'readableDbSchemaVersion': 5}),
      );

      final result = await check();

      expect(result.readableDbSchemaVersion, 5);
      expect(result.plan?.fullDbAsset?.name, 'seforim.db.zst');
    });

    test('רק סכמה 6 במראה — חסום עם הסבר לעדכן קודם את אוצריא', () async {
      await installExistingDb(30);
      await writeMirror('v31', ['seforim-schema6.db.zst']);

      final result = await check(appVersion: '0.9.97');

      expect(result.plan?.kind, LibraryUpdatePlanKind.blocked);
      expect(
        result.plan?.reason,
        AppL10n.strings.libraryDomain.planOtzariaTooOldForLibrary(5, 31),
      );
      expect(result.needsNewerOtzaria, isTrue);
    });

    test('חסימה שאינה בגלל אוצריא שומרת את הסיבה המקורית', () async {
      await installExistingDb(30);
      await writeMirror('v31', ['seforim-schema99.db.zst']);

      final result = await check(appVersion: '0.9.97');

      expect(result.plan?.kind, LibraryUpdatePlanKind.blocked);
      expect(
        result.plan?.reason,
        isNot(AppL10n.strings.libraryDomain.planOtzariaTooOldForLibrary(5, 31)),
      );
      expect(result.needsNewerOtzaria, isFalse);
    });
  });

  group('ReadableSchemaRoute.limit', () {
    PatchEdge edge(int from, int to, {int fromSchema = 5, int toSchema = 5}) =>
        PatchEdge(
          manifest: DeltaManifest(
            fromVersion: from,
            toVersion: to,
            fromSchemaVersion: fromSchema,
            toSchemaVersion: toSchema,
            fromContentHash: '0' * 64,
            toContentHash: '1' * 64,
            patchFiles: [
              PatchFileEntry(
                file: 'patch-v$from-v$to.db.zst',
                compression: 'zstd',
                sha256: '2' * 64,
                size: 10,
                uncompressedSha256: '3' * 64,
                uncompressedSize: 20,
              ),
            ],
          ),
          patchFileUrls: {'patch-v$from-v$to.db.zst': 'x'},
          manifestUrl: 'm',
        );

    OfflineLibraryDiscoveryResult discovery(List<PatchEdge> edges) =>
        OfflineLibraryDiscoveryResult(
          latestVersion: 32,
          edges: edges,
          latestFullDbAsset: null,
          fullDbReleaseTag: null,
          latestContentTag: 'v32',
        );

    test('קשת שמביאה לסכמה שאוצריא אינה קוראת אינה מוחלת לעולם', () {
      final keep = edge(30, 31);
      final cross = edge(31, 32, toSchema: 6);
      final route = ReadableSchemaRoute.limit(
        discovery: discovery([keep, cross]),
        releases: const [],
        allowPrerelease: false,
        readableSchema: 5,
      );

      expect(route.edges, [keep]);
      expect(route.excludedSchema, 6);
      expect(route.limited, isTrue);
    });

    test('בלי סכמה ידועה, או כשהיא מכסה הכול — אין שינוי', () {
      final edges = [edge(31, 32, toSchema: 6)];
      for (final readable in [null, kSupportedDbSchemaVersion]) {
        final route = ReadableSchemaRoute.limit(
          discovery: discovery(edges),
          releases: const [],
          allowPrerelease: false,
          readableSchema: readable,
        );
        expect(route.edges, edges);
        expect(route.limited, isFalse);
      }
    });

    test('אוצריא קוראת סכמה אחת פחות מהחבילה: הקשת לסכמה החדשה נחסמת', () {
      const older = kSupportedDbSchemaVersion - 1;
      final keep = edge(30, 31, fromSchema: older, toSchema: older);
      final cross = edge(
        31,
        32,
        fromSchema: older,
        toSchema: kSupportedDbSchemaVersion,
      );
      final route = ReadableSchemaRoute.limit(
        discovery: discovery([keep, cross]),
        releases: const [],
        allowPrerelease: false,
        readableSchema: older,
      );

      expect(route.edges, [keep]);
      expect(route.excludedSchema, kSupportedDbSchemaVersion);
    });
  });
}

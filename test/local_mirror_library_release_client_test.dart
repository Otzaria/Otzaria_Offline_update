import 'dart:convert';
import 'dart:io';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:seforim_library_updater/src/models/library_release.dart';
import 'package:seforim_library_updater/src/services/local_mirror_library_release_client.dart';
import 'package:test/test.dart';

/// המראה המקומית היא **המקור היחיד** במסלול הבדיקה (AGENTS §5), ולכן כל צורת
/// קלט פגומה חייבת להיכשל בהודעה ברורה ולא לקרוס/להחזיר רשימה ריקה בשקט.
void main() {
  late Directory tmp;
  late LocalMirrorLibraryReleaseClient client;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('local_mirror');
    client = LocalMirrorLibraryReleaseClient(mirrorDir: tmp.path);
  });
  tearDown(() {
    AppL10n.use(AppLanguage.hebrew); // ברירת המחדל, כדי לא לדלוף לבדיקה הבאה
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  String join(List<String> parts) => parts.join(Platform.pathSeparator);

  void writeManifest(Object? content) {
    final file = File(
      join([tmp.path, LocalMirrorLibraryReleaseClient.manifestFileName]),
    );
    file.writeAsStringSync(content is String ? content : jsonEncode(content));
  }

  /// הודעות עם ארגומנט חופשי (שגיאת ה-parse) נבדקות מול התחילית הקבועה של
  /// המחרוזת מ-otzaria_l10n — כך אין ליטרל עברי בבדיקה.
  String prefixOf(String Function(String error) template) {
    const marker = '<<ERR>>';
    return template(marker).split(marker).first;
  }

  LibraryDomainStrings strings() => AppL10n.strings.libraryDomain;

  group('fetchReleases', () {
    test('releases.json חסר → LocalMirrorException בהודעת ה-l10n', () {
      expect(
        client.fetchReleases,
        throwsA(isA<LocalMirrorException>().having(
          (e) => e.message,
          'message',
          strings().mirrorManifestMissing(
            LocalMirrorLibraryReleaseClient.manifestFileName,
            tmp.path,
          ),
        )),
      );
    });

    // ההודעות מגיעות מ-otzaria_l10n ולא מליטרל עברי — החלפת שפה מוכיחה זאת.
    test('ההודעה מתורגמת לפי השפה הפעילה', () async {
      AppL10n.use(AppLanguage.english);
      final expected = AppL10n.strings.libraryDomain.mirrorManifestMissing(
        LocalMirrorLibraryReleaseClient.manifestFileName,
        tmp.path,
      );
      await expectLater(
        client.fetchReleases(),
        throwsA(isA<LocalMirrorException>()
            .having((e) => e.message, 'message', expected)),
      );
      expect(expected, isNot(contains('מראה')));
    });

    test('releases.json פגום (JSON לא תקין) → LocalMirrorException', () {
      writeManifest('{not json at all');
      expect(
        client.fetchReleases,
        throwsA(isA<LocalMirrorException>().having(
          (e) => e.message,
          'message',
          startsWith(prefixOf((e) => strings().mirrorManifestCorrupt(
                LocalMirrorLibraryReleaseClient.manifestFileName,
                tmp.path,
                e,
              ))),
        )),
      );
    });

    test('releases.json בצורה לא צפויה (מערך בשורש) → LocalMirrorException',
        () {
      writeManifest([<String, dynamic>{}]);
      expect(
        client.fetchReleases,
        throwsA(isA<LocalMirrorException>().having(
          (e) => e.message,
          'message',
          strings().mirrorManifestUnexpectedShape(
            LocalMirrorLibraryReleaseClient.manifestFileName,
            tmp.path,
          ),
        )),
      );
    });

    test('אובייקט בלי המפתח releases → LocalMirrorException', () {
      writeManifest({'formatVersion': 1});
      expect(client.fetchReleases, throwsA(isA<LocalMirrorException>()));
    });

    test('releases ריק → רשימה ריקה, בלי זריקה', () async {
      writeManifest({'formatVersion': 1, 'releases': <Object>[]});
      expect(await client.fetchReleases(), isEmpty);
    });

    test('נתיבי assets יחסיים מומרים למוחלטים מול תיקיית המראה', () async {
      writeManifest({
        'formatVersion': 1,
        'releases': [
          {
            'tag': 'v3',
            'isPrerelease': false,
            'isDraft': false,
            'publishedAt': '2026-06-27T21:00:00.000Z',
            'assets': [
              {
                'name': 'seforim.db.zst',
                'downloadUrl': join(['assets', 'v3', 'seforim.db.zst']),
                'size': 1197000000,
                'id': 42,
                'updatedAt': '2026-06-27T21:00:00Z',
                'digest': 'sha256:abc',
              },
            ],
          },
        ],
      });

      final releases = await client.fetchReleases();
      expect(releases, hasLength(1));
      final asset = releases.single.assets.single;
      expect(
        asset.downloadUrl,
        join([tmp.path, 'assets', 'v3', 'seforim.db.zst']),
      );
      // שאר השדות נשמרים כמות שהם — resume נשען על id ועל digest.
      expect(asset.id, 42);
      expect(asset.digest, 'sha256:abc');
      expect(asset.size, 1197000000);
      expect(releases.single.publishedAt, isNotNull);
    });

    test('פריטים שאינם אובייקטים ברשימה מדולגים ולא מפילים את הקריאה',
        () async {
      writeManifest({
        'releases': [
          'garbage',
          42,
          {'tag': 'v2', 'assets': <Object>[]},
        ],
      });
      final releases = await client.fetchReleases();
      expect(releases.map((r) => r.tag), ['v2']);
    });
  });

  group('fetchManifest', () {
    test('קובץ manifest חסר → LocalMirrorException', () {
      final path = join([tmp.path, 'missing.manifest.json']);
      expect(
        () => client.fetchManifest(path),
        throwsA(isA<LocalMirrorException>().having((e) => e.message, 'message',
            strings().mirrorPatchManifestMissing(path))),
      );
    });

    test('manifest פגום → LocalMirrorException', () {
      final path = join([tmp.path, 'bad.manifest.json']);
      File(path).writeAsStringSync('][');
      expect(
        () => client.fetchManifest(path),
        throwsA(isA<LocalMirrorException>().having(
          (e) => e.message,
          'message',
          startsWith(
              prefixOf((e) => strings().mirrorPatchManifestCorrupt(path, e))),
        )),
      );
    });

    test('manifest שאינו אובייקט JSON → LocalMirrorException', () {
      final path = join([tmp.path, 'array.manifest.json']);
      File(path).writeAsStringSync('[1,2,3]');
      expect(
        () => client.fetchManifest(path),
        throwsA(isA<LocalMirrorException>().having((e) => e.message, 'message',
            strings().mirrorPatchManifestNotJson(path))),
      );
    });

    // שדה חובה חסר הוא כשל של פורמט ה-manifest עצמו, לא של המראה.
    test('manifest חסר שדה חובה → FormatException (לא LocalMirrorException)',
        () {
      final path = join([tmp.path, 'partial.manifest.json']);
      File(path).writeAsStringSync(jsonEncode({'fromVersion': 1}));
      expect(() => client.fetchManifest(path), throwsFormatException);
    });

    test('manifest תקין נקרא ומפוענח', () async {
      final path = join([tmp.path, 'patch-v1-v2.db.zst.manifest.json']);
      File(path).writeAsStringSync(jsonEncode({
        'fromVersion': 1,
        'toVersion': 2,
        'fromSchemaVersion': 2,
        'toSchemaVersion': 2,
        'fromContentHash': 'aa',
        'toContentHash': 'bb',
        'patchFiles': [
          {
            'file': 'patch-v1-v2.db.zst',
            'compression': 'zstd',
            'sha256': 'c',
            'size': 10,
            'uncompressedSha256': 'u',
            'uncompressedSize': 20,
          }
        ],
      }));
      final manifest = await client.fetchManifest(path);
      expect(manifest.fromVersion, 1);
      expect(manifest.toVersion, 2);
      expect(manifest.totalCompressedSize, 10);
    });
  });

  test('dispose אינו זורק (אין משאבים לשחרר במקור מקומי)', () {
    expect(client.dispose, returnsNormally);
  });

  test('הסריאליזציה של הייצוא נקראת חזרה כמו שהיא (round-trip)', () async {
    const release = LibraryRelease(
      tag: 'v3',
      isPrerelease: true,
      isDraft: false,
      publishedAt: null,
      assets: [
        ReleaseAsset(name: 'a.zst', downloadUrl: 'assets/v3/a.zst', size: 7),
      ],
    );
    writeManifest({
      'formatVersion': 1,
      'releases': [release.toMirrorJson()],
    });
    final loaded = (await client.fetchReleases()).single;
    expect(loaded.tag, release.tag);
    expect(loaded.isPrerelease, isTrue);
    expect(loaded.assets.single.size, 7);
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/src/models/library_release.dart';
import 'package:seforim_library_updater/src/models/split_archive_manifest.dart';
import 'package:seforim_library_updater/src/services/github_library_release_client.dart';
import 'package:seforim_library_updater/src/services/library_mirror_exporter.dart';
import 'package:seforim_library_updater/src/services/local_mirror_library_release_client.dart';
import 'package:test/test.dart';

/// ה-DB המלא יפורסם בעתיד מפוצל (`seforim.db.zst.part-NNN` + מניפסט), בפורמט
/// ש-SeforimLibrary כבר משתמש בו לאינדקס. המחשב הלא-מקוון חייב לקבל קובץ אחד.
const _archive = 'seforim.db.zst';
const _manifestName = '$_archive.manifest.json';

String _hex(List<int> bytes) => sha256.convert(bytes).toString();

Map<String, dynamic> _asset(String name, int size,
        {String? digest, String tag = 'v5'}) =>
    {
      'name': name,
      'browser_download_url': 'https://x/$tag/$name',
      'size': size,
      'id': name.hashCode.abs(),
      'state': 'uploaded',
      if (digest != null) 'digest': digest,
    };

void main() {
  group('LibraryRelease — DB מלא מפוצל', () {
    LibraryRelease parse(List<Map<String, dynamic>> assets) =>
        LibraryRelease.fromJson({
          'tag_name': 'v5',
          'prerelease': false,
          'draft': false,
          'assets': assets,
        });

    test('חלקים ומניפסט נראים כ-seforim.db.zst אחד', () {
      final release = parse([
        _asset('$_archive.part-001', 40),
        _asset('$_archive.part-000', 100),
        _asset(_manifestName, 600),
      ]);
      final full = release.fullDbAsset!;
      expect(full.name, _archive);
      expect(full.isSplit, isTrue);
      expect(full.size, 140);
      expect(full.parts.map((a) => a.name),
          ['$_archive.part-000', '$_archive.part-001']);
      expect(full.splitManifest!.name, _manifestName);
    });

    test('נכס שלם קודם לחלקים', () {
      final release = parse([
        _asset(_archive, 10),
        _asset('$_archive.part-000', 100),
        _asset(_manifestName, 600),
      ]);
      expect(release.fullDbAsset!.isSplit, isFalse);
    });

    test('חלק שעדיין עולה — אין DB מלא', () {
      final release = parse([
        _asset('$_archive.part-000', 100),
        {..._asset('$_archive.part-001', 0), 'state': 'uploading'},
        _asset(_manifestName, 600),
      ]);
      expect(release.fullDbAsset, isNull);
    });

    test('פער ברצף החלקים — אין DB מלא', () {
      final release = parse([
        _asset('$_archive.part-000', 100),
        _asset('$_archive.part-002', 100),
        _asset(_manifestName, 600),
      ]);
      expect(release.fullDbAsset, isNull);
    });

    test('בלי מניפסט — אין DB מלא', () {
      final release = parse([_asset('$_archive.part-000', 100)]);
      expect(release.fullDbAsset, isNull);
    });

    test('האינדקס המפוצל של הספרייה אינו נחשב DB', () {
      final release = parse([
        _asset('otzaria-library-index.tar.zst.part-000', 100),
        _asset('otzaria-library-index.tar.zst.manifest.json', 600),
      ]);
      expect(release.fullDbAsset, isNull);
    });
  });

  group('SplitArchiveManifest.fromJson', () {
    Map<String, dynamic> valid() => {
          'schemaVersion': 1,
          'archive': _archive,
          'size': 30,
          'sha256': 'A' * 64,
          'parts': [
            {'name': '$_archive.part-000', 'size': 20, 'sha256': 'b' * 64},
            {'name': '$_archive.part-001', 'size': 10, 'sha256': 'c' * 64},
          ],
        };

    test('מניפסט תקין, sha256 באותיות קטנות', () {
      final m = SplitArchiveManifest.fromJson(valid());
      expect(m.sha256, 'a' * 64);
      expect(m.parts.length, 2);
    });

    for (final (label, mutate)
        in <(String, void Function(Map<String, dynamic>))>[
      ('schemaVersion אחר', (j) => j['schemaVersion'] = 2),
      ('סכום חלקים שגוי', (j) => j['size'] = 31),
      (
        'שם חלק לא בסדר',
        (j) {
          (j['parts'] as List).first['name'] = '$_archive.part-001';
        }
      ),
      ('שם עם נתיב', (j) => j['archive'] = '../$_archive'),
      ('sha256 לא תקין', (j) => j['sha256'] = 'xyz'),
      ('בלי חלקים', (j) => j['parts'] = <Object>[]),
    ]) {
      test('נדחה: $label', () {
        final json = valid();
        mutate(json);
        expect(() => SplitArchiveManifest.fromJson(json),
            throwsA(isA<FormatException>()));
      });
    }
  });

  group('LibraryMirrorExporter — הרכבת DB מפוצל', () {
    late Directory tmp;
    late String destDir;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('split_full_db');
      destDir = p.join(tmp.path, 'mirror');
    });
    tearDown(() {
      AppL10n.use(AppLanguage.hebrew);
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    final part0 = Uint8List(3000)..fillRange(0, 3000, 1);
    final part1 = Uint8List(1200)..fillRange(0, 1200, 2);
    final whole = Uint8List.fromList([...part0, ...part1]);

    Map<String, dynamic> manifestJson({String? wholeSha, int? part1Size}) => {
          'schemaVersion': 1,
          'archive': _archive,
          'size': part0.length + (part1Size ?? part1.length),
          'sha256': wholeSha ?? _hex(whole),
          'partSizeLimit': 3000,
          'githubAssetLimit': 2147483648,
          'parts': [
            {
              'name': '$_archive.part-000',
              'size': part0.length,
              'sha256': _hex(part0),
            },
            {
              'name': '$_archive.part-001',
              'size': part1Size ?? part1.length,
              'sha256': _hex(part1),
            },
          ],
        };

    /// שרת מדומה: release אחד (v5) שכל תוכנו הוא DB מלא מפוצל.
    ({LibraryMirrorExporter exporter, List<String> fetched}) build({
      Map<String, dynamic>? manifest,
      Uint8List? servedPart1,
      Set<String> failOnce = const {},
      Future<void> Function(String name)? beforeAsset,
      bool withBrokenOldRelease = false,
    }) {
      final manifestBytes = Uint8List.fromList(
          utf8.encode(jsonEncode(manifest ?? manifestJson())));
      final bodies = <String, Uint8List>{
        '$_archive.part-000': part0,
        '$_archive.part-001': servedPart1 ?? part1,
        _manifestName: manifestBytes,
      };
      final releases = [
        {
          'tag_name': 'v5',
          'prerelease': false,
          'draft': false,
          'published_at': '2026-09-01T00:00:00Z',
          'assets': [
            for (final e in bodies.entries)
              _asset(e.key, e.value.length, digest: 'sha256:${_hex(e.value)}'),
          ],
        },
        // release ישן ומפוצל שהמניפסט שלו אינו נגיש — מחוץ לחלון ההיסטוריה.
        if (withBrokenOldRelease)
          {
            'tag_name': 'v1',
            'prerelease': false,
            'draft': false,
            'published_at': '2026-01-01T00:00:00Z',
            'assets': [
              for (final e in bodies.entries)
                _asset(e.key, e.value.length, tag: 'v1'),
            ],
          },
      ];
      final fetched = <String>[];
      final failed = <String>{};
      final mock = MockClient.streaming((request, _) async {
        final url = request.url.toString();
        if (url.contains('api.github.com')) {
          final body = utf8.encode(jsonEncode(
              request.url.queryParameters['page'] == '1' ? releases : []));
          return http.StreamedResponse(Stream.value(body), 200);
        }
        final name = url.split('/').last;
        if (url.contains('/v1/')) {
          fetched.add('v1:$name');
          return http.StreamedResponse(const Stream<List<int>>.empty(), 500);
        }
        fetched.add(name);
        if (failOnce.contains(name) && failed.add(name)) {
          return http.StreamedResponse(const Stream<List<int>>.empty(), 500);
        }
        if (beforeAsset != null) await beforeAsset(name);
        final body = bodies[name]!;
        return http.StreamedResponse(Stream.value(body), 200,
            contentLength: body.length);
      });
      return (
        exporter: LibraryMirrorExporter(
          client: GithubLibraryReleaseClient(httpClient: mock),
          httpClient: mock,
          historyDepth: withBrokenOldRelease ? 1 : 10,
        ),
        fetched: fetched,
      );
    }

    String assembledPath() => p.join(destDir, 'assets', 'v5', _archive);

    test('מוריד את החלקים, מרכיב קובץ אחד, והמראה רואה נכס רגיל', () async {
      final stages = <String>[];
      final (:exporter, :fetched) = build();
      expect(
          await exporter.export(destDir: destDir, onStage: stages.add), isTrue);

      expect(File(assembledPath()).readAsBytesSync(), whole);
      expect(
          Directory(LibraryMirrorExporter.splitPartsDir(assembledPath()))
              .existsSync(),
          isFalse);
      expect(
          fetched, containsAll(['$_archive.part-000', '$_archive.part-001']));
      expect(stages.any((s) => s.contains('מרכיב')), isTrue);

      final mirrored = await LocalMirrorLibraryReleaseClient(mirrorDir: destDir)
          .fetchReleases();
      final full = mirrored.single.fullDbAsset!;
      expect(full.isSplit, isFalse);
      expect(full.size, whole.length);
      expect(full.digest, 'sha256:${_hex(whole)}');
      expect(File(full.downloadUrl).existsSync(), isTrue);
      // רק הנכס המורכב נכתב — לא החלקים ולא המניפסט שלהם.
      expect(mirrored.single.assets.map((a) => a.name), [_archive]);
      exporter.dispose();
    });

    test('החלקים יורדים במקביל', () async {
      // part-000 ממתין עד שבקשת part-001 מגיעה; בהורדה סדרתית זה נתקע.
      final second = Completer<void>();
      final (:exporter, fetched: _) = build(beforeAsset: (name) async {
        if (name == '$_archive.part-001') second.complete();
        if (name == '$_archive.part-000') {
          await second.future.timeout(const Duration(seconds: 5));
        }
      });
      await exporter.export(destDir: destDir);
      expect(File(assembledPath()).lengthSync(), whole.length);
      exporter.dispose();
    });

    test('ריצה חוזרת אינה מורידה את החלקים שוב', () async {
      final first = build();
      await first.exporter.export(destDir: destDir);
      first.exporter.dispose();

      final again = build();
      await again.exporter.export(destDir: destDir);
      expect(again.fetched.where((n) => n.contains('.part-')), isEmpty);
      expect(File(assembledPath()).readAsBytesSync(), whole);
      again.exporter.dispose();
    });

    test('חלק שנכשל — החלק השלם נשמר וממשיכים ממנו', () async {
      final run = build(failOnce: {'$_archive.part-001'});
      await expectLater(
          run.exporter.export(destDir: destDir), throwsA(anything));
      expect(File(assembledPath()).existsSync(), isFalse);
      expect(
          File(p.join(LibraryMirrorExporter.splitPartsDir(assembledPath()),
                  '$_archive.part-000'))
              .existsSync(),
          isTrue);

      run.fetched.clear();
      await run.exporter.export(destDir: destDir);
      expect(run.fetched, isNot(contains('$_archive.part-000')));
      expect(File(assembledPath()).readAsBytesSync(), whole);
      run.exporter.dispose();
    });

    test('חלק שתוכנו אינו תואם למניפסט — נכשל ולא נכתבת מראה', () async {
      final bad = Uint8List(part1.length)..fillRange(0, part1.length, 9);
      final (:exporter, fetched: _) = build(servedPart1: bad);
      await expectLater(exporter.export(destDir: destDir), throwsA(anything));
      expect(File(assembledPath()).existsSync(), isFalse);
      expect(
          File(p.join(
                  destDir, LocalMirrorLibraryReleaseClient.manifestFileName))
              .existsSync(),
          isFalse);
      exporter.dispose();
    });

    test('sha256 של המורכב שגוי — נכשל בלי קובץ ובלי מראה', () async {
      final (:exporter, fetched: _) =
          build(manifest: manifestJson(wholeSha: 'f' * 64));
      await expectLater(
        exporter.export(destDir: destDir),
        throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            AppL10n.strings.libraryDomain
                .exportAssembledHashMismatch(_archive))),
      );
      expect(File(assembledPath()).existsSync(), isFalse);
      // החלקים תואמים למניפסט ולכן ייכשלו שוב — אין טעם להשאיר אותם.
      expect(
          Directory(LibraryMirrorExporter.splitPartsDir(assembledPath()))
              .existsSync(),
          isFalse);
      exporter.dispose();
    });

    test('release ישן ושבור מחוץ לחלון אינו נשלף ואינו חוסם', () async {
      final (:exporter, :fetched) = build(withBrokenOldRelease: true);
      expect(await exporter.export(destDir: destDir), isTrue);
      expect(fetched.where((n) => n.startsWith('v1:')), isEmpty);
      expect(File(assembledPath()).readAsBytesSync(), whole);
      exporter.dispose();
    });

    test('מניפסט שאינו תואם לחלקים — המסד נחשב חסר, באזהרה ובלי הורדה',
        () async {
      final manifest = manifestJson(part1Size: part1.length + 1);
      final (:exporter, :fetched) = build(manifest: manifest);
      final warnings = <String>[];
      // בלי מסד מלא אין ב-release הזה תוכן, ולכן "אין releases".
      await expectLater(
        exporter.export(destDir: destDir, onWarning: warnings.add),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            AppL10n.strings.libraryDomain.exportNoReleases)),
      );
      expect(warnings.single, contains('v5'));
      expect(fetched.where((n) => n.contains('.part-')), isEmpty);
      exporter.dispose();
    });

    test('ביטול באמצע ההרכבה — אין קובץ חצוי, והריצה הבאה משלימה', () async {
      var assembling = false;
      final run = build();
      await expectLater(
        run.exporter.export(
          destDir: destDir,
          onStage: (s) {
            if (s.contains('מרכיב')) assembling = true;
          },
          isCancelled: () => assembling,
        ),
        throwsA(isA<StateError>()),
      );
      expect(File(assembledPath()).existsSync(), isFalse);

      run.fetched.clear();
      await run.exporter.export(destDir: destDir);
      expect(run.fetched.where((n) => n.contains('.part-')), isEmpty);
      expect(File(assembledPath()).readAsBytesSync(), whole);
      run.exporter.dispose();
    });
  });
}

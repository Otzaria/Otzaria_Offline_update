import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:seforim_library_updater/src/models/library_update_plan.dart';
import 'package:seforim_library_updater/src/services/github_library_release_client.dart';
import 'package:seforim_library_updater/src/services/library_mirror_exporter.dart';
import 'package:seforim_library_updater/src/services/library_update_discovery.dart';
import 'package:seforim_library_updater/src/services/library_update_planner.dart';
import 'package:seforim_library_updater/src/services/local_mirror_library_release_client.dart';
import 'package:seforim_library_updater/src/services/patch_downloader.dart';
import 'package:test/test.dart';

typedef ReleaseSpec = ({
  String tag,
  bool prerelease,
  bool draft,
  List<String> assets,
});

ReleaseSpec release(
  String tag, {
  bool prerelease = false,
  bool draft = false,
  List<String> assets = const [],
}) =>
    (tag: tag, prerelease: prerelease, draft: draft, assets: assets);

Map<String, dynamic> manifestBody(int from, int to) => {
      'fromVersion': from,
      'toVersion': to,
      'fromSchemaVersion': 2,
      'toSchemaVersion': 2,
      'fromContentHash': 'h$from',
      'toContentHash': 'h$to',
      'patchFiles': [
        {
          'file': 'patch-v$from-v$to.db.zst',
          'compression': 'zstd',
          // הייצוא קורא מכאן רק את שם הקובץ; ה-hash/size מאומתים מול מטא-דאטה
          // של ה-asset, לא מול ה-manifest.
          'sha256': 'unused',
          'size': 1,
          'uncompressedSha256': 'u',
          'uncompressedSize': 99,
        }
      ],
    };

void main() {
  late Directory tmp;
  late String destDir;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mirror_exporter');
    destDir = '${tmp.path}${Platform.pathSeparator}mirror';
  });
  tearDown(() {
    AppL10n.use(AppLanguage.hebrew);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// שרת מדומה אחד ל-API, ל-manifests ולנכסים עצמם. הגודל וה-`digest` של כל
  /// נכס נגזרים מהגוף שמוגש בפועל, כדי שאימות ה-sha256 של [PatchDownloader]
  /// ירוץ באמת. [corruptManifests] מדמה manifest פגום; [failAsset] מחזיר
  /// שגיאת HTTP לנכס מסוים.
  ({LibraryMirrorExporter exporter, List<String> fetched}) buildExporter(
    List<ReleaseSpec> releases, {
    Set<String> corruptManifests = const {},
    String? failAsset,
    int historyDepth = LibraryMirrorExporter.defaultHistoryDepth,
  }) {
    Uint8List bodyFor(String name) {
      if (!name.endsWith('.manifest.json')) {
        return Uint8List.fromList(utf8.encode('asset:$name'));
      }
      if (corruptManifests.contains(name)) {
        return Uint8List.fromList(utf8.encode('{{{ not json'));
      }
      final match = RegExp(r'patch-v(\d+)-v(\d+)').firstMatch(name)!;
      return Uint8List.fromList(utf8.encode(jsonEncode(manifestBody(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
      ))));
    }

    final releasesJson = releases
        .map((r) => {
              'tag_name': r.tag,
              'prerelease': r.prerelease,
              'draft': r.draft,
              'published_at': '2026-06-27T21:00:00Z',
              'assets': r.assets
                  .map((name) => {
                        'name': name,
                        'browser_download_url': 'https://x/${r.tag}/$name',
                        'size': bodyFor(name).length,
                        'id': name.hashCode.abs(),
                        'digest': 'sha256:${sha256.convert(bodyFor(name))}',
                      })
                  .toList(),
            })
        .toList();

    final fetched = <String>[];
    final mock = MockClient.streaming((request, _) async {
      final url = request.url.toString();
      Uint8List body;
      if (url.contains('api.github.com')) {
        // עמוד יחיד — פחות מ-per_page עוצר את ה-pagination.
        body = Uint8List.fromList(utf8.encode(jsonEncode(
          request.url.queryParameters['page'] == '1'
              ? releasesJson
              : <Object>[],
        )));
      } else {
        final name = url.split('/').last;
        fetched.add(name);
        if (name == failAsset) {
          return http.StreamedResponse(const Stream<List<int>>.empty(), 500);
        }
        body = bodyFor(name);
      }
      return http.StreamedResponse(
        Stream.value(body),
        200,
        contentLength: body.length,
      );
    });
    return (
      exporter: LibraryMirrorExporter(
        client: GithubLibraryReleaseClient(httpClient: mock),
        httpClient: mock,
        historyDepth: historyDepth,
      ),
      fetched: fetched,
    );
  }

  List<String> mirroredTags(String dir) {
    final decoded = jsonDecode(
      File('$dir${Platform.pathSeparator}'
              '${LocalMirrorLibraryReleaseClient.manifestFileName}')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    return (decoded['releases'] as List)
        .map((r) => (r as Map<String, dynamic>)['tag'] as String)
        .toList();
  }

  bool assetOnDisk(String dir, String tag, String name) =>
      File([dir, 'assets', tag, name].join(Platform.pathSeparator))
          .existsSync();

  group('recentReleases — עומק ההיסטוריה במראה', () {
    // כמו באוצריא המקוונת, מכונה שכמה גרסאות מאחור מקבלת שרשרת patches ולא
    // הורדה מלאה — ההבדל היחיד הוא שהעומק חסום, כי המראה יושבת על כונן נייד.
    test('ה-releases האחרונים בעומק ברירת המחדל מיוצאים כולם', () async {
      final built = buildExporter([
        release('v3', assets: [
          'seforim.db.zst',
          'patch-v2-v3.db.zst',
          'patch-v2-v3.db.zst.manifest.json',
        ]),
        release('v2', assets: [
          'patch-v1-v2.db.zst',
          'patch-v1-v2.db.zst.manifest.json',
        ]),
      ]);
      await built.exporter.export(destDir: destDir);

      expect(mirroredTags(destDir), containsAll(<String>['v3', 'v2']));
      expect(assetOnDisk(destDir, 'v3', 'seforim.db.zst'), isTrue);
      expect(assetOnDisk(destDir, 'v2', 'patch-v1-v2.db.zst'), isTrue);
    });

    // מעבר לעומק — ההיסטוריה נחתכת, אחרת המראה מגיעה לכמה ג'יגה-בייט.
    test('מה שמעבר לעומק אינו מיוצא כלל', () async {
      final built = buildExporter(
        [
          release('v3', assets: [
            'seforim.db.zst',
            'patch-v2-v3.db.zst',
            'patch-v2-v3.db.zst.manifest.json',
          ]),
          release('v2', assets: [
            'seforim.db.zst',
            'patch-v1-v2.db.zst',
            'patch-v1-v2.db.zst.manifest.json',
          ]),
          release('v1', assets: ['seforim.db.zst']),
        ],
        historyDepth: 1,
      );
      await built.exporter.export(destDir: destDir);

      expect(mirroredTags(destDir), ['v3']);
      expect(assetOnDisk(destDir, 'v3', 'seforim.db.zst'), isTrue);
      expect(assetOnDisk(destDir, 'v3', 'patch-v2-v3.db.zst'), isTrue);
      // ההיסטוריה כלל לא ירדה — גם לא ה-manifests שלה.
      expect(
        Directory([destDir, 'assets', 'v2'].join(Platform.pathSeparator))
            .existsSync(),
        isFalse,
      );
      expect(built.fetched, isNot(contains('patch-v1-v2.db.zst')));
    });

    // מסלול ההורדה המלאה חייב להיות זמין תמיד, גם כשה-release האחרון הוא
    // patch-only — אחרת מחשב שנמצא כמה גרסאות מאחור נתקע.
    test('release אחרון בלי DB מלא → נשמר גם האחרון שכן נושא אותו', () async {
      final built = buildExporter(
        [
          release('v4', assets: [
            'patch-v3-v4.db.zst',
            'patch-v3-v4.db.zst.manifest.json',
          ]),
          release('v3', assets: ['seforim.db.zst']),
          release('v2', assets: ['seforim.db.zst']),
        ],
        historyDepth: 1,
      );
      await built.exporter.export(destDir: destDir);

      expect(mirroredTags(destDir), containsAll(<String>['v4', 'v3']));
      expect(mirroredTags(destDir), isNot(contains('v2')));
      expect(assetOnDisk(destDir, 'v3', 'seforim.db.zst'), isTrue);
      expect(assetOnDisk(destDir, 'v4', 'patch-v3-v4.db.zst'), isTrue);
    });

    test('כשה-release האחרון נושא DB מלא — הוא נשמר פעם אחת בלבד', () async {
      final built = buildExporter(
        [
          release('v3', assets: [
            'seforim.db.zst',
            'patch-v2-v3.db.zst',
            'patch-v2-v3.db.zst.manifest.json',
          ]),
          release('v2', assets: ['seforim.db.zst']),
        ],
        historyDepth: 1,
      );
      await built.exporter.export(destDir: destDir);
      expect(mirroredTags(destDir), ['v3']);
    });

    // ⚠️ כל release ב-SeforimLibrary נושא `seforim.db.zst` משלו (~1.5GB), אבל
    // באופליין נבחר רק זה של הגרסה הגבוהה ביותר — עותק לכל release בעומק 5
    // היה הופך הורדה של ~1.6GB להורדה של ~7.5GB.
    test('ה-DB המלא יורד רק מה-release הגבוה, לא מכל אחד בחלון', () async {
      final built = buildExporter([
        release('v3', assets: [
          'seforim.db.zst',
          'patch-v2-v3.db.zst',
          'patch-v2-v3.db.zst.manifest.json',
        ]),
        release('v2', assets: [
          'seforim.db.zst',
          'patch-v1-v2.db.zst',
          'patch-v1-v2.db.zst.manifest.json',
        ]),
        release('v1', assets: ['seforim.db.zst']),
      ]);
      await built.exporter.export(destDir: destDir);

      // שלושתם במראה — בשביל ה-patches — אך ה-DB המלא ירד פעם אחת בדיוק.
      expect(mirroredTags(destDir), containsAll(<String>['v3', 'v2', 'v1']));
      expect(
        built.fetched.where((n) => n == 'seforim.db.zst').length,
        1,
      );
      expect(assetOnDisk(destDir, 'v3', 'seforim.db.zst'), isTrue);
      expect(assetOnDisk(destDir, 'v2', 'seforim.db.zst'), isFalse);
      expect(assetOnDisk(destDir, 'v1', 'seforim.db.zst'), isFalse);
      // ה-patches עצמם כן נשמרו — זו כל מטרת חלון ההיסטוריה.
      expect(assetOnDisk(destDir, 'v2', 'patch-v1-v2.db.zst'), isTrue);

      // ומה שירד הוא הנכס שהמסלול המלא באופליין באמת יבחר.
      final result = await LibraryUpdateDiscovery(
        client: LocalMirrorLibraryReleaseClient(mirrorDir: destDir),
      ).discover(allowPrerelease: false);
      expect(result.latestReleaseTag, 'v3');
      expect(File(result.latestFullDbAsset!.downloadUrl).existsSync(), isTrue);
    });

    test('prerelease אינו נבחר כאחרון כשהערוץ יציב', () async {
      final built = buildExporter([
        release('v9', prerelease: true, assets: ['seforim.db.zst']),
        release('v3', assets: ['seforim.db.zst']),
      ]);
      await built.exporter.export(destDir: destDir, allowPrerelease: false);
      expect(mirroredTags(destDir), ['v3']);
    });

    test('draft לעולם אינו מיוצא', () async {
      final built = buildExporter([
        release('v9', draft: true, assets: ['seforim.db.zst']),
        release('v3', assets: ['seforim.db.zst']),
      ]);
      await built.exporter.export(destDir: destDir);
      expect(mirroredTags(destDir), ['v3']);
    });

    test('אין releases עם תוכן DB → StateError בהודעת ה-l10n', () {
      final built = buildExporter([
        release('v1', assets: ['README.md']),
      ]);
      expect(
        () => built.exporter.export(destDir: destDir),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            AppL10n.strings.libraryDomain.exportNoReleases)),
      );
    });
  });

  // הלב של המראה: מכונה שכמה גרסאות מאחור מקבלת **שרשרת דלתא** מהמראה, כמו
  // באוצריא המקוונת — ורק מי שרחוק מעבר לעומק ההיסטוריה נופל להורדה המלאה.
  test('שרשרת דלתא רב-שלבית נבנית מהמראה, ומעבר לעומק — הורדה מלאה', () async {
    final built = buildExporter([
      release('v3', assets: [
        'seforim.db.zst',
        'patch-v2-v3.db.zst',
        'patch-v2-v3.db.zst.manifest.json',
      ]),
      release('v2', assets: [
        'patch-v1-v2.db.zst',
        'patch-v1-v2.db.zst.manifest.json',
      ]),
    ]);
    await built.exporter.export(destDir: destDir);

    final mirror = LocalMirrorLibraryReleaseClient(mirrorDir: destDir);
    final discovery = LibraryUpdateDiscovery(client: mirror);
    final result = await discovery.discover(allowPrerelease: true);
    expect(result.latestVersion, 3);
    // שני ה-edges שרדו את הייצוא — זה בדיוק מה שהעומק החדש נותן.
    expect(
      result.edges.map((e) => '${e.fromVersion}-${e.toVersion}'),
      containsAll(<String>['1-2', '2-3']),
    );

    LibraryUpdatePlan planFrom(int localVersion) =>
        const LibraryUpdatePlanner().plan(
          localVersion: localVersion,
          hasLocalVersionMeta: true,
          latestVersion: result.latestVersion,
          edges: result.edges,
          latestFullDbAsset: result.latestFullDbAsset,
          latestReleaseTag: result.latestReleaseTag,
        );

    final chain = planFrom(1);
    expect(chain.kind, LibraryUpdatePlanKind.delta);
    expect(chain.deltaSteps.length, 2);

    // גרסה שאין אליה patch במראה — מסלול ההורדה המלאה, שקיים תמיד.
    final full = planFrom(0);
    expect(full.kind, LibraryUpdatePlanKind.fullDownload);
    expect(full.fullDbReleaseTag, 'v3');
    // ה-URL במראה הוא נתיב מוחלט על הדיסק, וקיים בפועל.
    expect(File(full.fullDbAsset!.downloadUrl).existsSync(), isTrue);
  });

  group('export — פרטי הכתיבה', () {
    test('releases.json נכתב עם formatVersion ונתיבים יחסיים בלבד', () async {
      final built = buildExporter([
        release('v3', assets: ['seforim.db.zst']),
      ]);
      await built.exporter.export(destDir: destDir);

      final decoded = jsonDecode(File([
        destDir,
        LocalMirrorLibraryReleaseClient.manifestFileName,
      ].join(Platform.pathSeparator))
          .readAsStringSync()) as Map<String, dynamic>;
      expect(decoded['formatVersion'], 1);
      expect(decoded['exportedAt'], isA<String>());
      final url = ((decoded['releases'] as List).first
          as Map<String, dynamic>)['assets'][0]['downloadUrl'] as String;
      expect(url, isNot(startsWith('http')));
      expect(url, isNot(contains(destDir)));
      expect(url, contains('seforim.db.zst'));
    });

    // חלון ההיסטוריה מסתובב: release שנפל ממנו השאיר עד עכשיו את נכסיו על
    // הכונן לעד — כולל DB מלא של ~1.5GB מריצות של גרסאות קודמות.
    test('נכסים שאינם במניפסט החדש נמחקים מהמראה', () async {
      final stale =
          Directory([destDir, 'assets', 'v1'].join(Platform.pathSeparator))
            ..createSync(recursive: true);
      File([stale.path, 'seforim.db.zst'].join(Platform.pathSeparator))
          .writeAsStringSync('גרוטאה');

      final built = buildExporter(
        [
          release('v3', assets: [
            'seforim.db.zst',
            'patch-v2-v3.db.zst',
            'patch-v2-v3.db.zst.manifest.json',
          ]),
        ],
        historyDepth: 1,
      );
      await built.exporter.export(destDir: destDir);
      // נכס מיותר בתוך תיקייה שכן נשמרת — נמחק גם הוא.
      final orphan = File([destDir, 'assets', 'v3', 'patch-v1-v2.db.zst']
          .join(Platform.pathSeparator))
        ..writeAsStringSync('גרוטאה');
      await built.exporter.export(destDir: destDir);

      expect(stale.existsSync(), isFalse);
      expect(orphan.existsSync(), isFalse);
      expect(assetOnDisk(destDir, 'v3', 'seforim.db.zst'), isTrue);
      expect(assetOnDisk(destDir, 'v3', 'patch-v2-v3.db.zst'), isTrue);
    });

    test('manifest פגום אינו מפיל את הייצוא — הנכס עדיין נשמר', () async {
      final built = buildExporter(
        [
          release('v3', assets: [
            'seforim.db.zst',
            'patch-v2-v3.db.zst',
            'patch-v2-v3.db.zst.manifest.json',
          ]),
        ],
        corruptManifests: {'patch-v2-v3.db.zst.manifest.json'},
      );
      await built.exporter.export(destDir: destDir);
      expect(assetOnDisk(destDir, 'v3', 'patch-v2-v3.db.zst.manifest.json'),
          isTrue);
      // קובץ ה-patch עצמו לא נדרש — ה-manifest שמצביע עליו לא נקרא.
      expect(assetOnDisk(destDir, 'v3', 'patch-v2-v3.db.zst'), isFalse);
    });

    test('כשל HTTP בנכס מפיל את הייצוא (לא מראה חלקית בשקט)', () {
      final built = buildExporter(
        [
          release('v3', assets: ['seforim.db.zst']),
        ],
        failAsset: 'seforim.db.zst',
      );
      expect(
        () => built.exporter.export(destDir: destDir),
        throwsA(isA<PatchDownloadException>()),
      );
    });

    test('ביטול באמצע → StateError בהודעת ה-l10n, בלי releases.json', () async {
      final built = buildExporter([
        release('v3', assets: ['seforim.db.zst']),
      ]);
      await expectLater(
        built.exporter.export(destDir: destDir, isCancelled: () => true),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            AppL10n.strings.libraryDomain.exportCancelled)),
      );
      expect(
        File([destDir, LocalMirrorLibraryReleaseClient.manifestFileName]
                .join(Platform.pathSeparator))
            .existsSync(),
        isFalse,
      );
    });

    test('onStage/onAssetProgress מדווחים מ-otzaria_l10n ומגיעים ל-100%',
        () async {
      final built = buildExporter([
        release('v3', assets: [
          'seforim.db.zst',
          'patch-v2-v3.db.zst',
          'patch-v2-v3.db.zst.manifest.json',
        ]),
      ]);
      final stages = <String>[];
      final progress = <(int, int)>[];
      await built.exporter.export(
        destDir: destDir,
        onStage: stages.add,
        onAssetProgress: (done, total) => progress.add((done, total)),
      );

      final strings = AppL10n.strings.libraryDomain;
      expect(stages.first, strings.exportLoadingReleases);
      expect(stages.last, strings.exportDone);
      expect(
        stages,
        contains(strings.exportDownloading('v3', 'seforim.db.zst')),
      );
      expect(
        stages,
        contains(strings.exportWritingManifest(
            LocalMirrorLibraryReleaseClient.manifestFileName)),
      );
      // היעד מדווח לפני הנכס הראשון, אחרת המד לא יודע לכמה לחכות.
      expect(progress.first, (0, 3));
      expect(progress.last, (3, 3));
    });

    test('תגית עם תווים אסורים בשם תיקייה מנוקה', () async {
      final built = buildExporter([
        release('v3/rc:1', assets: ['seforim.db.zst']),
      ]);
      await built.exporter.export(destDir: destDir);
      expect(assetOnDisk(destDir, 'v3_rc_1', 'seforim.db.zst'), isTrue);
      // ה-tag עצמו נשמר כפי שהוא ב-releases.json.
      expect(mirroredTags(destDir), ['v3/rc:1']);
    });

    test('נכס שכבר יושב שלם על הדיסק אינו יורד שוב', () async {
      final releases = [
        release('v3', assets: ['seforim.db.zst']),
      ];
      final first = buildExporter(releases);
      await first.exporter.export(destDir: destDir);

      final second = buildExporter(releases);
      await second.exporter.export(destDir: destDir);
      // רק ה-API נקרא; הנכס עצמו לא נמשך שוב (רק אומת).
      expect(second.fetched, isEmpty);
    });

    test('הרצה חוזרת מייצרת releases.json זהה בתוכן (חוץ מ-exportedAt)',
        () async {
      final releases = [
        release('v3', assets: ['seforim.db.zst']),
      ];
      await buildExporter(releases).exporter.export(destDir: destDir);
      final path = [destDir, LocalMirrorLibraryReleaseClient.manifestFileName]
          .join(Platform.pathSeparator);
      final firstJson =
          jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
      await buildExporter(releases).exporter.export(destDir: destDir);
      final secondJson =
          jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
      expect(secondJson['releases'], firstJson['releases']);
    });
  });
}

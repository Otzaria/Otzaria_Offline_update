import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:library_manager/library_manager.dart';
import 'package:path/path.dart' as p;

/// צד ההורדה של הקבצים הנלווים: אותם שלושה מאגרים ואותם כללי בחירת נכס
/// שאוצריא משתמשת בהם, רק שהיעד הוא המראה ולא ההתקנה.
void main() {
  late Directory tempDir;
  late String destDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('companions-mirror-');
    destDir = p.join(tempDir.path, 'companions');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Uint8List bodyOf(String name) =>
      Uint8List.fromList(utf8.encode('payload:$name'));

  Map<String, dynamic> assetJson(String name, String url) => {
        'name': name,
        'browser_download_url': url,
        'size': bodyOf(name).length,
        'id': name.hashCode.abs(),
        'updated_at': '2026-08-01T00:00:00Z',
        'digest': 'sha256:${sha256.convert(bodyOf(name))}',
      };

  /// שרת מדומה לשלושת ה-APIs ולנכסים עצמם. [omit] מסלק נכס מסוים כדי לדמות
  /// release חסר.
  ({CompanionAssetsMirror mirror, List<String> fetched}) buildMirror({
    Set<String> omit = const {},
  }) {
    final fetched = <String>[];
    final client = MockClient.streaming((request, _) async {
      final url = request.url.toString();
      Uint8List body;

      if (url.contains('/repos/Otzaria/otzaria-library/')) {
        body = Uint8List.fromList(utf8.encode(jsonEncode({
          'tag_name': 'lib-v9',
          'assets': [
            if (!omit.contains('talmud'))
              assetJson('talmud_bavli_latest.tar.zst',
                  'https://x/talmud_bavli_latest.tar.zst'),
          ],
        })));
      } else if (url.contains('/repos/Otzaria/otzar-HB_catalog/')) {
        body = Uint8List.fromList(utf8.encode(jsonEncode({
          'tag_name': 'cat-v3',
          'assets': [
            assetJson(
                'otzar-HB_catalog.db.zst', 'https://x/otzar-HB_catalog.db.zst'),
            assetJson('version.txt', 'https://x/version.txt'),
          ],
        })));
      } else if (url.contains('/repos/Otzaria/SeforimMagicIndexer/')) {
        body = Uint8List.fromList(utf8.encode(jsonEncode({
          'tag_name': 'dict-v7',
          'assets': [assetJson('lexical.db', 'https://x/lexical.db')],
        })));
      } else {
        final name = url.split('/').last;
        fetched.add(name);
        body = name == 'version.txt'
            ? Uint8List.fromList(utf8.encode('55'))
            : bodyOf(name);
      }

      return http.StreamedResponse(
        Stream.value(body),
        200,
        contentLength: body.length,
      );
    });

    return (
      mirror: CompanionAssetsMirror(httpClient: client),
      fetched: fetched
    );
  }

  test('שלושת הפריטים יורדים ונרשמים ב-companions.json', () async {
    final built = buildMirror();
    addTearDown(built.mirror.dispose);

    final manifest = await built.mirror.sync(destDir: destDir);

    expect(manifest.entries.keys, containsAll(CompanionAsset.values));
    expect(
      built.fetched,
      containsAll(<String>[
        'talmud_bavli_latest.tar.zst',
        'otzar-HB_catalog.db.zst',
        'lexical.db',
      ]),
    );
    for (final entry in manifest.entries.values) {
      expect(File(p.join(destDir, entry.fileName)).existsSync(), isTrue);
    }

    // הגרסה של הקטלוג נקראת מ-`version.txt`, כמו ב-ExternalCatalogRepository.
    expect(manifest.entries[CompanionAsset.catalog]!.version, 55);
    expect(manifest.entries[CompanionAsset.dictionary]!.tag, 'dict-v7');
    expect(manifest.entries[CompanionAsset.talmud]!.tag, 'lib-v9');

    // המניפסט נקרא חזרה מהדיסק — זה מה שהמחשב הלא-מקוון יראה.
    final reloaded = await CompanionMirrorManifest.load(destDir);
    expect(reloaded!.entries.length, 3);
  });

  test('נכס חסר ב-release אינו מפיל את השאר', () async {
    final built = buildMirror(omit: {'talmud'});
    addTearDown(built.mirror.dispose);
    final warnings = <String>[];

    final manifest = await built.mirror.sync(
      destDir: destDir,
      onWarning: (name, _) => warnings.add(name),
    );

    expect(manifest.entries.containsKey(CompanionAsset.talmud), isFalse);
    expect(manifest.entries.keys,
        containsAll([CompanionAsset.catalog, CompanionAsset.dictionary]));
    expect(warnings, isNotEmpty);
  });

  test('סנכרון חוזר שנכשל אינו מוחק מהמניפסט פריט שכבר במראה', () async {
    final first = buildMirror();
    addTearDown(first.mirror.dispose);
    await first.mirror.sync(destDir: destDir);

    // אותה מראה, הפעם בלי נכס התלמוד ב-release — הקובץ עצמו עדיין שם.
    final second = buildMirror(omit: {'talmud'});
    addTearDown(second.mirror.dispose);
    final manifest = await second.mirror.sync(destDir: destDir);

    final talmud = manifest.entries[CompanionAsset.talmud];
    expect(talmud, isNotNull, reason: 'רשומת התלמוד נדרסה במקום להישמר');
    expect(talmud!.tag, 'lib-v9');
    expect(File(p.join(destDir, talmud.fileName)).existsSync(), isTrue);

    final reloaded = await CompanionMirrorManifest.load(destDir);
    expect(reloaded!.entries.length, 3);
  });

  test('רשומה קודמת שקובצה נעלם מהמראה אינה נשמרת', () async {
    final first = buildMirror();
    addTearDown(first.mirror.dispose);
    final before = await first.mirror.sync(destDir: destDir);
    File(p.join(destDir, before.entries[CompanionAsset.talmud]!.fileName))
        .deleteSync();

    final second = buildMirror(omit: {'talmud'});
    addTearDown(second.mirror.dispose);
    final manifest = await second.mirror.sync(destDir: destDir);

    expect(manifest.entries.containsKey(CompanionAsset.talmud), isFalse);
  });
}

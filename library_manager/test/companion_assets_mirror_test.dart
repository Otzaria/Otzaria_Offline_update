import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:library_manager/library_manager.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';

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
    DownloadScheduler? scheduler,
    Future<void> Function(String assetName)? beforeAsset,
    String dictionaryTag = 'dict-v7',
    bool apiDown = false,
  }) {
    final fetched = <String>[];
    final client = MockClient.streaming((request, _) async {
      final url = request.url.toString();
      Uint8List body;

      if (apiDown && url.contains('api.github.com')) {
        return http.StreamedResponse(const Stream.empty(), 403);
      }
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
          'tag_name': dictionaryTag,
          'assets': [assetJson('lexical.db', 'https://x/lexical.db')],
        })));
      } else {
        final name = url.split('/').last;
        fetched.add(name);
        if (beforeAsset != null) await beforeAsset(name);
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
      mirror: CompanionAssetsMirror(httpClient: client, scheduler: scheduler),
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

  // שלושת הפריטים אינם תלויים זה בזה; התלמוד לבדו הוא ~450MB, ובטור השניים
  // האחרים המתינו לו בלי סיבה.
  test('שלושת הפריטים יורדים בו-זמנית', () async {
    // מחסום: כל פריט ממתין עד ששלושה נמצאים בו-זמנית. בהורדה טורית
    // הראשון נתקע עד סוף הזמן הקצוב והשיא נשאר 1.
    final barrier = Completer<void>();
    var inFlight = 0;
    var peak = 0;
    final built = buildMirror(
      beforeAsset: (name) async {
        if (name == 'version.txt') return;
        inFlight++;
        if (inFlight > peak) peak = inFlight;
        if (inFlight >= 3 && !barrier.isCompleted) barrier.complete();
        await barrier.future
            .timeout(const Duration(seconds: 2), onTimeout: () {});
        inFlight--;
      },
    );
    addTearDown(built.mirror.dispose);

    await built.mirror.sync(destDir: destDir);
    expect(peak, 3);
  });

  test('תקרת החיבורים המשותפת נשמרת גם כשהיא נמוכה משלושה', () async {
    var inFlight = 0;
    var peak = 0;
    final built = buildMirror(
      scheduler: DownloadScheduler(maxConcurrent: 1),
      beforeAsset: (name) async {
        inFlight++;
        if (inFlight > peak) peak = inFlight;
        await Future<void>.delayed(Duration.zero);
        inFlight--;
      },
    );
    addTearDown(built.mirror.dispose);

    await built.mirror.sync(destDir: destDir);
    expect(peak, 1);
  });

  test('מד הבייטים מסכם את שלושת הפריטים ואינו צונח ביניהם', () async {
    final received = <int>[];
    final built = buildMirror();
    addTearDown(built.mirror.dispose);

    await built.mirror.sync(
      destDir: destDir,
      onBytesProgress: (downloaded, _) => received.add(downloaded),
    );

    expect(received, isNotEmpty);
    for (var i = 1; i < received.length; i++) {
      expect(received[i], greaterThanOrEqualTo(received[i - 1]));
    }
  });

  test('היעד ידוע כבר בדיווח הראשון, לפני שבייט כלשהו עבר', () async {
    final totals = <int?>[];
    var firstReceived = -1;
    final built = buildMirror();
    addTearDown(built.mirror.dispose);

    await built.mirror.sync(
      destDir: destDir,
      onBytesProgress: (downloaded, total) {
        if (totals.isEmpty) firstReceived = downloaded;
        totals.add(total);
      },
    );

    // בלי זה הקורא נשאר בלי יעד עד שכל שלושת הפריטים התחילו לרדת, ומד
    // ההתקדמות מדד עד אז בסרגל אחר לגמרי.
    expect(firstReceived, 0);
    expect(totals.first, isNotNull);
    expect(totals.any((t) => t == null), isFalse);
    // ויעד שאינו זז: קפיצה בו היא בדיוק מה שהפך את האחוזים ללא אמינים.
    expect(totals.toSet(), hasLength(1));
  });

  test('קובץ נלווה שכבר על הכונן אינו נספר במד', () async {
    final first = buildMirror();
    addTearDown(first.mirror.dispose);
    await first.mirror.sync(destDir: destDir);

    // ריצה שנייה: שלושת הקבצים כבר שם, ולכן אין מה להוריד ואין מה להציג.
    var lastReceived = -1;
    int? lastTotal;
    final again = buildMirror();
    addTearDown(again.mirror.dispose);
    await again.mirror.sync(
      destDir: destDir,
      onBytesProgress: (downloaded, total) {
        lastReceived = downloaded;
        lastTotal = total;
      },
    );

    expect(lastReceived, 0);
    expect(lastTotal, 0);
  });

  // issue #33: הנלווים מתעדכנים בלי קשר למסד, ובלי בדיקה קלה משלהם כונן
  // שלא קיבל אותם פעם אחת לא הציע את ההורדה שמביאה אותם לעולם.
  group('peekPending — הבדיקה הקלה של הנלווים', () {
    test('מראה ריקה: שלושתם ממתינים, ואף נכס אינו יורד', () async {
      final built = buildMirror();
      addTearDown(built.mirror.dispose);

      final pending = await built.mirror.peekPending(destDir: destDir);

      expect(pending, CompanionAsset.values.toSet());
      // `version.txt` הוא מטא־דאטה של הקטלוג; שום נכס של ממש לא ירד.
      expect(built.fetched, ['version.txt']);
    });

    test('אחרי הורדה מלאה אין מה להביא', () async {
      final built = buildMirror();
      addTearDown(built.mirror.dispose);
      await built.mirror.sync(destDir: destDir);

      expect(await built.mirror.peekPending(destDir: destDir), isEmpty);
    });

    test('גרסה חדשה של נלווה אחד — רק הוא ממתין', () async {
      final first = buildMirror();
      addTearDown(first.mirror.dispose);
      await first.mirror.sync(destDir: destDir);

      final second = buildMirror(dictionaryTag: 'dict-v8');
      addTearDown(second.mirror.dispose);

      expect(
        await second.mirror.peekPending(destDir: destDir),
        {CompanionAsset.dictionary},
      );
    });

    test('קובץ שנעלם מהכונן ממתין, גם כשהרשומה עוד במניפסט', () async {
      final built = buildMirror();
      addTearDown(built.mirror.dispose);
      final manifest = await built.mirror.sync(destDir: destDir);
      File(p.join(destDir, manifest.entries[CompanionAsset.talmud]!.fileName))
          .deleteSync();

      expect(
        await built.mirror.peekPending(destDir: destDir),
        {CompanionAsset.talmud},
      );
    });

    test('נכס שאינו ב-release אינו נספר, והשאר כן', () async {
      final built = buildMirror(omit: {'talmud'});
      addTearDown(built.mirror.dispose);

      expect(
        await built.mirror.peekPending(destDir: destDir),
        {CompanionAsset.catalog, CompanionAsset.dictionary},
      );
    });

    test('כשל של שלושתם נזרק — "אין רשת" אינו "אין מה להוריד"', () async {
      final built = buildMirror(apiDown: true);
      addTearDown(built.mirror.dispose);

      await expectLater(
        built.mirror.peekPending(destDir: destDir),
        throwsA(anything),
      );
    });
  });
}

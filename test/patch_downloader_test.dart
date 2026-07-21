import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:seforim_library_updater/src/models/delta_manifest.dart';
import 'package:seforim_library_updater/src/services/patch_downloader.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('downloader_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  // "patch" מדומה: compressed=הבייטים שמוגשים; decompress=זהות (מחזיר אותם).
  final uncompressed = Uint8List.fromList(List.generate(64, (i) => i));
  final compressed = Uint8List.fromList(List.generate(32, (i) => 255 - i));

  PatchFileEntry entry({String? badCompressedHash, int? badSize}) =>
      PatchFileEntry(
        file: 'patch-v1-v2.db.zst',
        compression: 'zstd',
        sha256: badCompressedHash ?? sha256.convert(compressed).toString(),
        size: badSize ?? compressed.length,
        uncompressedSha256: sha256.convert(uncompressed).toString(),
        uncompressedSize: uncompressed.length,
      );

  PatchDownloader buildDownloader() {
    final mock = MockClient.streaming((request, bodyStream) async {
      return http.StreamedResponse(
        Stream.value(compressed),
        200,
        contentLength: compressed.length,
      );
    });
    return PatchDownloader(
      httpClient: mock,
      decompress: (c) async => uncompressed,
    );
  }

  test('הורדה+חילוץ מוצלחים כותבים את ה-.db המחולץ', () async {
    final path = await buildDownloader().downloadAndExtract(
      patchFile: entry(),
      downloadUrl: 'https://x/patch-v1-v2.db.zst',
      destDir: tmp,
    );
    expect(path, endsWith('patch-v1-v2.db'));
    expect(File(path).readAsBytesSync(), uncompressed);
  });

  test('sha256 דחוס שגוי → נכשל וה-.db לא נכתב', () async {
    expect(
      () => buildDownloader().downloadAndExtract(
        patchFile: entry(badCompressedHash: 'deadbeef'),
        downloadUrl: 'https://x/p',
        destDir: tmp,
      ),
      throwsA(isA<PatchDownloadException>()),
    );
    await Future<void>.delayed(Duration.zero);
    expect(File('${tmp.path}/patch-v1-v2.db').existsSync(), isFalse);
  });

  test('גודל דחוס שגוי → נכשל', () async {
    expect(
      () => buildDownloader().downloadAndExtract(
        patchFile: entry(badSize: 999),
        downloadUrl: 'https://x/p',
        destDir: tmp,
      ),
      throwsA(isA<PatchDownloadException>()),
    );
  });

  test('sha256 מחולץ שגוי → נכשל', () async {
    // decompress מחזיר בייטים שלא תואמים ל-uncompressedSha256
    final mock = MockClient.streaming((request, bodyStream) async =>
        http.StreamedResponse(Stream.value(compressed), 200,
            contentLength: compressed.length));
    final downloader = PatchDownloader(
      httpClient: mock,
      decompress: (c) async => Uint8List.fromList([9, 9, 9]),
    );
    expect(
      () => downloader.downloadAndExtract(
        patchFile: entry(),
        downloadUrl: 'https://x/p',
        destDir: tmp,
      ),
      throwsA(isA<PatchDownloadException>()),
    );
  });

  test('patch קטן: גוף תגובת שגיאה ננטש מיד ולא נצרך עד הסוף', () async {
    var chunksServed = 0;
    Stream<List<int>> countingBody() async* {
      for (var i = 0; i < 100; i++) {
        chunksServed++;
        yield [i];
      }
    }

    final downloader = PatchDownloader(
      httpClient: MockClient.streaming(
        (request, bodyStream) async =>
            http.StreamedResponse(countingBody(), 500),
      ),
      decompress: (c) async => uncompressed,
    );

    await expectLater(
      downloader.downloadAndExtract(
        patchFile: entry(),
        downloadUrl: 'https://x/p',
        destDir: tmp,
      ),
      throwsA(isA<PatchDownloadException>()),
    );
    expect(chunksServed, lessThan(10));
  });

  test('resumeSidecarPath מחזיר <dest>.resume', () {
    expect(
      PatchDownloader.resumeSidecarPath('/tmp/seforim.db.zst'),
      '/tmp/seforim.db.zst.resume',
    );
  });

  group('downloadToFile (DB מלא)', () {
    // downloadToFile אינו מחלץ, אך ה-constructor דורש decompress (חובה כעת).
    PatchDownloader fullDownloader() => PatchDownloader(
          httpClient: MockClient.streaming((request, bodyStream) async =>
              http.StreamedResponse(Stream.value(compressed), 200,
                  contentLength: compressed.length)),
          decompress: (c) async => uncompressed,
        );

    test('הורדה זורמת מצליחה וכותבת את הקובץ', () async {
      final dest = '${tmp.path}/seforim.db.zst';
      await fullDownloader().downloadToFile(
        url: 'https://x/seforim.db.zst',
        destPath: dest,
        expectedSize: compressed.length,
      );
      expect(File(dest).readAsBytesSync(), compressed);
    });

    test('expectedSize קטן מהמתקבל → עוצר וה-קובץ לא נשאר', () async {
      final dest = '${tmp.path}/seforim.db.zst';
      await expectLater(
        fullDownloader().downloadToFile(
          url: 'https://x/seforim.db.zst',
          destPath: dest,
          expectedSize: 8, // קטן מ-32 שמתקבלים
        ),
        throwsA(isA<PatchDownloadException>()),
      );
      expect(File(dest).existsSync(), isFalse);
    });

    test('expectedSize גדול מהמתקבל → נכשל באימות אורך סופי', () async {
      final dest = '${tmp.path}/seforim.db.zst';
      await expectLater(
        fullDownloader().downloadToFile(
          url: 'https://x/seforim.db.zst',
          destPath: dest,
          expectedSize: 9999, // גדול מ-32
        ),
        throwsA(isA<PatchDownloadException>()),
      );
      expect(File(dest).existsSync(), isFalse);
    });

    test('ללא expectedSize: גוף 200 קצר מ-Content-Length נדחה ונמחק', () async {
      final dest = '${tmp.path}/seforim.db.zst';
      final downloader = PatchDownloader(
        httpClient: MockClient.streaming(
          (request, bodyStream) async => http.StreamedResponse(
            Stream.value(Uint8List(50)),
            200,
            contentLength: 100,
            headers: {'etag': '"v1"'},
          ),
        ),
        decompress: (c) async => uncompressed,
      );

      await expectLater(
        downloader.downloadToFile(
          url: 'https://x/seforim.db.zst',
          destPath: dest,
          resumeToken: 'v1',
        ),
        throwsA(isA<PatchDownloadException>()),
      );
      expect(File(dest).existsSync(), isFalse);
      expect(File('$dest.resume').existsSync(), isFalse);
    });

    test('ללא expectedSize: גוף 200 שחורג מ-Content-Length נעצר ונמחק',
        () async {
      final dest = '${tmp.path}/seforim.db.zst';
      final downloader = PatchDownloader(
        httpClient: MockClient.streaming(
          (request, bodyStream) async => http.StreamedResponse(
            Stream.value(Uint8List(101)),
            200,
            contentLength: 100,
            headers: {'etag': '"v1"'},
          ),
        ),
        decompress: (c) async => uncompressed,
      );

      await expectLater(
        downloader.downloadToFile(
          url: 'https://x/seforim.db.zst',
          destPath: dest,
          resumeToken: 'v1',
        ),
        throwsA(isA<PatchDownloadException>()),
      );
      expect(File(dest).existsSync(), isFalse);
      expect(File('$dest.resume').existsSync(), isFalse);
    });
  });

  group('downloadToFile — חידוש הורדה (resume)', () {
    // קובץ מלא = 40 בייטים; מחולק ל-15 ראשונים (partial) + 25 המשך.
    final full = Uint8List.fromList(List.generate(40, (i) => i));
    final part1 = Uint8List.fromList(full.sublist(0, 15));
    final part2 = Uint8List.fromList(full.sublist(15));
    final fullHash = sha256.convert(full).toString();

    PatchDownloader downloaderThatCaptures(
      List<http.BaseRequest> captured, {
      required Future<http.StreamedResponse> Function(http.BaseRequest req)
          handler,
    }) {
      final mock = MockClient.streaming((request, bodyStream) async {
        captured.add(request);
        return handler(request);
      });
      return PatchDownloader(
        httpClient: mock,
        decompress: (c) async => full,
      );
    }

    test('קובץ חלקי קיים → נשלחת כותרת Range מהאורך הקיים; 206 מוסיף בסוף',
        () async {
      final dest = '${tmp.path}/seforim.db.zst';
      File(dest).writeAsBytesSync(part1); // partial קיים באורך 15
      File('$dest.resume').writeAsStringSync('v-1\n"e1"'); // טוקן תואם → resume
      final captured = <http.BaseRequest>[];
      final downloader = downloaderThatCaptures(
        captured,
        handler: (req) async => http.StreamedResponse(
          Stream.value(part2),
          206,
          contentLength: part2.length,
          headers: {'content-range': 'bytes 15-39/40'},
        ),
      );

      await downloader.downloadToFile(
        url: 'https://x/seforim.db.zst',
        destPath: dest,
        expectedSize: full.length,
        expectedSha256: fullHash,
        resumeToken: 'v-1',
      );

      expect(captured.single.headers['Range'], 'bytes=15-');
      expect(File(dest).readAsBytesSync(), full); // התוכן הסופי מלא ותקין
    });

    test('sha256 מחושב נכון על הורדה מחודשת (שני חלקים)', () async {
      final dest = '${tmp.path}/seforim.db.zst';
      File(dest).writeAsBytesSync(part1);
      File('$dest.resume').writeAsStringSync('v-1\n"e1"');
      final downloader = downloaderThatCaptures(
        [],
        handler: (req) async => http.StreamedResponse(
          Stream.value(part2),
          206,
          contentLength: part2.length,
          headers: {'content-range': 'bytes 15-39/40'},
        ),
      );
      // אם ה-hash היה מכסה רק את החלק שהתקבל — היה נכשל וזורק.
      await downloader.downloadToFile(
        url: 'https://x/seforim.db.zst',
        destPath: dest,
        expectedSize: full.length,
        expectedSha256: fullHash,
        resumeToken: 'v-1',
      );
      expect(File(dest).readAsBytesSync(), full);
    });

    test('השרת מחזיר 200 (מתעלם מ-Range) → התחלה מאפס עם קובץ מלא', () async {
      final dest = '${tmp.path}/seforim.db.zst';
      File(dest).writeAsBytesSync(part1);
      File('$dest.resume').writeAsStringSync('v-1\n"e1"');
      final downloader = downloaderThatCaptures(
        [],
        handler: (req) async => http.StreamedResponse(
          Stream.value(full), // הגוף המלא, לא רק ההמשך
          200,
          contentLength: full.length,
        ),
      );
      await downloader.downloadToFile(
        url: 'https://x/seforim.db.zst',
        destPath: dest,
        expectedSize: full.length,
        expectedSha256: fullHash,
        resumeToken: 'v-1',
      );
      expect(File(dest).readAsBytesSync(), full);
    });

    test('416 → הקובץ נחשב שלם ועובר לאימות', () async {
      final dest = '${tmp.path}/seforim.db.zst';
      File(dest).writeAsBytesSync(full); // כבר שלם
      File('$dest.resume')
          .writeAsStringSync('v-1\n"e1"'); // טוקן תואם → הקובץ נשמר
      final captured = <http.BaseRequest>[];
      final downloader = downloaderThatCaptures(
        captured,
        handler: (req) async =>
            http.StreamedResponse(const Stream.empty(), 416),
      );
      await downloader.downloadToFile(
        url: 'https://x/seforim.db.zst',
        destPath: dest,
        expectedSize: full.length,
        expectedSha256: fullHash,
        resumeToken: 'v-1',
      );
      // offset==expectedSize → דילוג על ההורדה לגמרי (אין אפילו בקשת רשת)
      expect(captured, isEmpty);
      expect(File(dest).readAsBytesSync(), full);
    });

    test('קובץ כבר שלם → onProgress מגיע ל-(total,total) לפני אימות ה-hash',
        () async {
      final dest = '${tmp.path}/seforim.db.zst';
      File(dest).writeAsBytesSync(full); // כבר שלם — _streamToFile לא ירוץ
      File('$dest.resume').writeAsStringSync('v-1\n"e1"');
      final progress = <(int, int?)>[];
      final downloader = downloaderThatCaptures(
        [],
        handler: (req) async =>
            http.StreamedResponse(const Stream.empty(), 416),
      );
      await downloader.downloadToFile(
        url: 'https://x/seforim.db.zst',
        destPath: dest,
        expectedSize: full.length,
        expectedSha256: fullHash,
        onProgress: (d, t) => progress.add((d, t)),
        resumeToken: 'v-1',
      );
      // בלי הדיווח הזה המד היה תקוע בזמן חישוב ה-hash הארוך (>1GB).
      expect(progress.last, (full.length, full.length));
    });

    // finding P1: 416 עם Content-Range תואם ל-offset (בלי expectedSize) — הקובץ
    // אכן שלם בצד השרת, נשמר לאימות.
    test('416 עם Content-Range תואם → נחשב שלם, הקובץ נשמר לאימות', () async {
      final dest = '${tmp.path}/seforim.db.zst';
      File(dest).writeAsBytesSync(full); // שלם בצד השרת (40 בייט)
      File('$dest.resume').writeAsStringSync('v-1\n"e1"');
      final captured = <http.BaseRequest>[];
      final downloader = downloaderThatCaptures(
        captured,
        handler: (req) async => http.StreamedResponse(
          const Stream.empty(),
          416,
          headers: {'content-range': 'bytes */40'}, // total == offset
        ),
      );
      // ללא expectedSize → לא מדלגים, שולחים Range ומקבלים 416 תואם.
      await downloader.downloadToFile(
        url: 'https://x/seforim.db.zst',
        destPath: dest,
        expectedSha256: fullHash,
        resumeToken: 'v-1',
      );
      expect(captured.single.headers['Range'], 'bytes=40-');
      expect(File(dest).readAsBytesSync(), full);
    });

    test('416 ללא בקשת Range אינו הצלחה גם כשה-total הוא אפס', () async {
      final dest = '${tmp.path}/seforim.db.zst';
      final captured = <http.BaseRequest>[];
      var calls = 0;
      final downloader = downloaderThatCaptures(
        captured,
        handler: (req) async {
          calls++;
          return http.StreamedResponse(
            const Stream.empty(),
            416,
            headers: {'content-range': 'bytes */0'},
          );
        },
      );

      await expectLater(
        downloader.downloadToFile(
          url: 'https://x/seforim.db.zst',
          destPath: dest,
          resumeToken: 'v-1',
        ),
        throwsA(isA<PatchDownloadException>()),
      );

      expect(calls, 2); // ניסיון מלא ראשון ועוד retry מלא יחיד.
      expect(captured.every((r) => !r.headers.containsKey('Range')), isTrue);
      expect(File(dest).existsSync(), isFalse);
      expect(File('$dest.resume').existsSync(), isFalse);
    });

    // finding P1: 416 עם total קטן מה-offset (חלקי מקומי גדול מהנכס המרוחק) —
    // אינו הוכחת שלמות; מוחקים ומורידים מחדש מאפס.
    test('416 עם total < offset → הקובץ נמחק, GET מלא מאפס, תוכן נכון',
        () async {
      final dest = '${tmp.path}/seforim.db.zst';
      File(dest).writeAsBytesSync(full); // חלקי מקומי 40 בייט
      File('$dest.resume').writeAsStringSync('v-1\n"e1"');
      final remote = Uint8List.fromList(full.sublist(0, 20)); // מרוחק רק 20
      final remoteHash = sha256.convert(remote).toString();
      final captured = <http.BaseRequest>[];
      final downloader = downloaderThatCaptures(
        captured,
        handler: (req) async {
          if (req.headers.containsKey('Range')) {
            return http.StreamedResponse(
              const Stream.empty(),
              416,
              headers: {'content-range': 'bytes */20'}, // total < offset (40)
            );
          }
          return http.StreamedResponse(
            Stream.value(remote),
            200,
            contentLength: remote.length,
          );
        },
      );
      await downloader.downloadToFile(
        url: 'https://x/seforim.db.zst',
        destPath: dest,
        expectedSha256: remoteHash,
        resumeToken: 'v-1',
      );
      expect(captured, hasLength(2));
      expect(captured[0].headers['Range'], 'bytes=40-');
      expect(captured[1].headers.containsKey('Range'), isFalse);
      expect(File(dest).readAsBytesSync(), remote);
    });

    // finding P1: 416 בלי Content-Range אינו הוכחת שלמות → GET מלא מאפס.
    test('416 בלי Content-Range → GET מלא מאפס, תוכן נכון', () async {
      final dest = '${tmp.path}/seforim.db.zst';
      File(dest).writeAsBytesSync(part1); // חלקי 15
      File('$dest.resume').writeAsStringSync('v-1\n"e1"');
      final captured = <http.BaseRequest>[];
      final downloader = downloaderThatCaptures(
        captured,
        handler: (req) async {
          if (req.headers.containsKey('Range')) {
            return http.StreamedResponse(const Stream.empty(), 416);
          }
          return http.StreamedResponse(
            Stream.value(full),
            200,
            contentLength: full.length,
          );
        },
      );
      await downloader.downloadToFile(
        url: 'https://x/seforim.db.zst',
        destPath: dest,
        expectedSize: full.length,
        expectedSha256: fullHash,
        resumeToken: 'v-1',
      );
      expect(captured, hasLength(2));
      expect(captured[0].headers['Range'], 'bytes=15-');
      expect(captured[1].headers.containsKey('Range'), isFalse);
      expect(File(dest).readAsBytesSync(), full);
    });

    test('hop של redirect משמר את כותרת Range', () async {
      final dest = '${tmp.path}/seforim.db.zst';
      File(dest).writeAsBytesSync(part1);
      File('$dest.resume').writeAsStringSync('v-1\n"e1"');
      final captured = <http.BaseRequest>[];
      final downloader = downloaderThatCaptures(
        captured,
        handler: (req) async {
          if (req.url.host == 'github.com') {
            return http.StreamedResponse(
              const Stream.empty(),
              302,
              headers: {'location': 'https://objects.example/signed'},
            );
          }
          return http.StreamedResponse(
            Stream.value(part2),
            206,
            contentLength: part2.length,
            headers: {'content-range': 'bytes 15-39/40'},
          );
        },
      );
      await downloader.downloadToFile(
        url: 'https://github.com/releases/seforim.db.zst',
        destPath: dest,
        expectedSize: full.length,
        expectedSha256: fullHash,
        resumeToken: 'v-1',
      );
      // שתי הבקשות (המקורית + אחרי ההפניה) נשאו את אותה כותרת Range.
      expect(captured, hasLength(2));
      expect(captured[0].headers['Range'], 'bytes=15-');
      expect(captured[1].url.host, 'objects.example');
      expect(captured[1].headers['Range'], 'bytes=15-');
      expect(File(dest).readAsBytesSync(), full);
    });

    test('הפרעה עם resumeToken אך בלי validator → החלקי וקובץ הצד נמחקים',
        () async {
      final dest = '${tmp.path}/seforim.db.zst';
      final downloader = downloaderThatCaptures(
        [],
        handler: (req) async => http.StreamedResponse(
          () async* {
            yield part1; // חלק ראשון נכתב
            throw const SocketException('connection reset');
          }(),
          200, // בלי ETag → אין validator, החלקי אינו ניתן לחידוש
          contentLength: full.length,
        ),
      );
      await expectLater(
        downloader.downloadToFile(
          url: 'https://x/seforim.db.zst',
          destPath: dest,
          expectedSize: full.length,
          resumeToken: 'v-1',
        ),
        throwsA(isA<SocketException>()),
      );
      // בלי validator החלקי אינו ניתן להמשך (כלל ה-entry ימחק אותו ממילא) —
      // נמחק מיד יחד עם קובץ הצד ולא נשאר תלוי על הדיסק.
      expect(File(dest).existsSync(), isFalse);
      expect(File('$dest.resume').existsSync(), isFalse);
    });

    test('הפרעה עם resumeToken + validator שמור → החלקי וקובץ הצד נשמרים',
        () async {
      final dest = '${tmp.path}/seforim.db.zst';
      File(dest).writeAsBytesSync(part1); // חלקי קיים באורך 15
      File('$dest.resume').writeAsStringSync('v-1\n"e1"'); // validator שמור
      final downloader = downloaderThatCaptures(
        [],
        handler: (req) async => http.StreamedResponse(
          () async* {
            yield part2.sublist(0, 5); // עוד בייטים נכתבים ואז נפילה
            throw const SocketException('connection reset');
          }(),
          206,
          headers: {'content-range': 'bytes 15-39/40', 'etag': '"e1"'},
        ),
      );
      await expectLater(
        downloader.downloadToFile(
          url: 'https://x/seforim.db.zst',
          destPath: dest,
          expectedSize: full.length,
          resumeToken: 'v-1',
        ),
        throwsA(isA<SocketException>()),
      );
      // יש validator חזק → החלקי ניתן לחידוש ונשמר יחד עם קובץ הצד.
      expect(File(dest).existsSync(), isTrue);
      expect(File('$dest.resume').readAsStringSync(), 'v-1\n"e1"');
    });

    test('הפרעה ללא resumeToken מוחקת את הקובץ החלקי', () async {
      final dest = '${tmp.path}/seforim.db.zst';
      final downloader = downloaderThatCaptures(
        [],
        handler: (req) async => http.StreamedResponse(
          () async* {
            yield part1;
            throw const SocketException('connection reset');
          }(),
          200,
          contentLength: full.length,
        ),
      );
      await expectLater(
        downloader.downloadToFile(
          url: 'https://x/seforim.db.zst',
          destPath: dest,
          expectedSize: full.length,
        ),
        throwsA(isA<SocketException>()),
      );
      expect(File(dest).existsSync(), isFalse);
      expect(File('$dest.resume').existsSync(), isFalse);
    });

    test('sha256 שגוי בקובץ שלם → הקובץ נמחק', () async {
      final dest = '${tmp.path}/seforim.db.zst';
      final downloader = downloaderThatCaptures(
        [],
        handler: (req) async => http.StreamedResponse(
          Stream.value(full),
          200,
          contentLength: full.length,
        ),
      );
      await expectLater(
        downloader.downloadToFile(
          url: 'https://x/seforim.db.zst',
          destPath: dest,
          expectedSize: full.length,
          expectedSha256: 'deadbeef',
        ),
        throwsA(isA<PatchDownloadException>()),
      );
      expect(File(dest).existsSync(), isFalse);
    });

    // P2: 206 עם Content-Range שלא מתחיל ב-offset → בקשה שנייה בלי Range מאפס.
    test('206 עם Content-Range שגוי → בקשה חוזרת בלי Range, קובץ תקין',
        () async {
      final dest = '${tmp.path}/seforim.db.zst';
      File(dest).writeAsBytesSync(part1); // partial קיים באורך 15
      File('$dest.resume').writeAsStringSync('v-1\n"e1"');
      final captured = <http.BaseRequest>[];
      final downloader = downloaderThatCaptures(
        captured,
        handler: (req) async {
          if (req.headers.containsKey('Range')) {
            // 206 מוטעה: הגוף מתחיל ב-5 (לא ב-15 שביקשנו) — אסור לצרוך אותו.
            return http.StreamedResponse(
              Stream.value(full.sublist(5)),
              206,
              contentLength: full.length - 5,
              headers: {'content-range': 'bytes 5-39/40'},
            );
          }
          // הבקשה השנייה (בלי Range) → הגוף המלא מאפס.
          return http.StreamedResponse(
            Stream.value(full),
            200,
            contentLength: full.length,
          );
        },
      );

      await downloader.downloadToFile(
        url: 'https://x/seforim.db.zst',
        destPath: dest,
        expectedSize: full.length,
        expectedSha256: fullHash,
        resumeToken: 'v-1',
      );

      expect(captured, hasLength(2));
      expect(captured[0].headers['Range'], 'bytes=15-');
      expect(captured[1].headers.containsKey('Range'), isFalse);
      expect(File(dest).readAsBytesSync(), full);
    });

    test('206 עם total שונה מהגודל הצפוי → הורדה חוזרת מאפס', () async {
      final dest = '${tmp.path}/seforim.db.zst';
      File(dest).writeAsBytesSync(part1);
      File('$dest.resume').writeAsStringSync('v-1\n"e1"');
      final captured = <http.BaseRequest>[];
      final downloader = downloaderThatCaptures(
        captured,
        handler: (req) async {
          if (req.headers.containsKey('Range')) {
            return http.StreamedResponse(
              Stream.value(part2),
              206,
              contentLength: part2.length,
              headers: {'content-range': 'bytes 15-39/50'},
            );
          }
          return http.StreamedResponse(
            Stream.value(full),
            200,
            contentLength: full.length,
          );
        },
      );

      await downloader.downloadToFile(
        url: 'https://x/seforim.db.zst',
        destPath: dest,
        expectedSize: full.length,
        resumeToken: 'v-1',
      );

      expect(captured, hasLength(2));
      expect(captured[0].headers['Range'], 'bytes=15-');
      expect(captured[1].headers.containsKey('Range'), isFalse);
      expect(File(dest).readAsBytesSync(), full);
    });

    test('206 עם end קטן מ-start → הורדה חוזרת מאפס', () async {
      final dest = '${tmp.path}/seforim.db.zst';
      File(dest).writeAsBytesSync(part1);
      File('$dest.resume').writeAsStringSync('v-1\n"e1"');
      final captured = <http.BaseRequest>[];
      final downloader = downloaderThatCaptures(
        captured,
        handler: (req) async {
          if (req.headers.containsKey('Range')) {
            return http.StreamedResponse(
              Stream.value(part2),
              206,
              headers: {'content-range': 'bytes 15-14/40'},
            );
          }
          return http.StreamedResponse(
            Stream.value(full),
            200,
            contentLength: full.length,
          );
        },
      );

      await downloader.downloadToFile(
        url: 'https://x/seforim.db.zst',
        destPath: dest,
        expectedSize: full.length,
        resumeToken: 'v-1',
      );

      expect(captured, hasLength(2));
      expect(captured[1].headers.containsKey('Range'), isFalse);
      expect(File(dest).readAsBytesSync(), full);
    });

    test('206 עם Content-Length שאינו אורך הטווח → הורדה חוזרת מאפס', () async {
      final dest = '${tmp.path}/seforim.db.zst';
      File(dest).writeAsBytesSync(part1);
      File('$dest.resume').writeAsStringSync('v-1\n"e1"');
      final captured = <http.BaseRequest>[];
      final downloader = downloaderThatCaptures(
        captured,
        handler: (req) async {
          if (req.headers.containsKey('Range')) {
            return http.StreamedResponse(
              Stream.value(part2),
              206,
              contentLength: part2.length - 1,
              headers: {'content-range': 'bytes 15-39/40'},
            );
          }
          return http.StreamedResponse(
            Stream.value(full),
            200,
            contentLength: full.length,
          );
        },
      );

      await downloader.downloadToFile(
        url: 'https://x/seforim.db.zst',
        destPath: dest,
        expectedSize: full.length,
        resumeToken: 'v-1',
      );

      expect(captured, hasLength(2));
      expect(captured[1].headers.containsKey('Range'), isFalse);
      expect(File(dest).readAsBytesSync(), full);
    });

    // P1: כבילת החלקי ל-resumeToken דרך קובץ הצד <destPath>.resume.
    group('resumeToken (כבילת גרסה)', () {
      test('טוקן שונה מקובץ הצד → התחלה מלאה מאפס בלי Range', () async {
        final dest = '${tmp.path}/seforim.db.zst';
        File(dest).writeAsBytesSync(part1); // partial מגרסה ישנה
        File('$dest.resume').writeAsStringSync('v-old');
        final captured = <http.BaseRequest>[];
        final downloader = downloaderThatCaptures(
          captured,
          handler: (req) async => http.StreamedResponse(
            Stream.value(full),
            200,
            contentLength: full.length,
          ),
        );

        await downloader.downloadToFile(
          url: 'https://x/seforim.db.zst',
          destPath: dest,
          expectedSize: full.length,
          expectedSha256: fullHash,
          resumeToken: 'v-new',
        );

        expect(captured.single.headers.containsKey('Range'), isFalse);
        expect(File(dest).readAsBytesSync(), full);
        // קובץ הצד שורד הורדה מוצלחת (חי ומת עם הקובץ) עם הטוקן החדש.
        expect(File('$dest.resume').readAsStringSync(), 'v-new');
      });

      test(
        'טוקן שונה וקובץ נעול → זורק, לא כובל תוכן ישן לטוקן החדש',
        () async {
          final dest = '${tmp.path}/seforim.db.zst';
          File(dest).writeAsBytesSync(part1);
          File('$dest.resume').writeAsStringSync('v-old');
          // handle פתוח נועל את הקובץ מפני מחיקה ב-Windows.
          final lock = File(dest).openSync();
          try {
            final downloader = downloaderThatCaptures(
              <http.BaseRequest>[],
              handler: (req) async =>
                  http.StreamedResponse(Stream.value(full), 200),
            );
            await expectLater(
              downloader.downloadToFile(
                url: 'https://x/seforim.db.zst',
                destPath: dest,
                resumeToken: 'v-new',
              ),
              throwsA(isA<PatchDownloadException>()),
            );
            // התוכן הישן לא נחתם בטוקן החדש.
            expect(File('$dest.resume').readAsStringSync(), 'v-old');
          } finally {
            lock.closeSync();
          }
        },
        skip: Platform.isWindows ? false : 'מחיקת קובץ פתוח נכשלת רק ב-Windows',
      );

      test('416 שסותר total שדווח ב-206 קודם → לא שלמות; הורדה מלאה מאפס',
          () async {
        final dest = '${tmp.path}/seforim.db.zst';
        File(dest).writeAsBytesSync(part1); // חלקי באורך 15
        File('$dest.resume').writeAsStringSync('v-1\n"e1"');
        final captured = <http.BaseRequest>[];
        var call = 0;
        final downloader =
            downloaderThatCaptures(captured, handler: (req) async {
          call++;
          if (call == 1) {
            // 206 קצר שנועל total=40 ומתקדם ל-21.
            return http.StreamedResponse(
              Stream.value(Uint8List.fromList(full.sublist(15, 21))),
              206,
              contentLength: 6,
              headers: {'content-range': 'bytes 15-20/40'},
            );
          }
          if (call == 2) {
            // 416 שטוען שהנכס בגודל 21 — סותר את ה-40 שכבר דווח.
            return http.StreamedResponse(
              const Stream<List<int>>.empty(),
              416,
              headers: {'content-range': 'bytes */21'},
            );
          }
          return http.StreamedResponse(
            Stream.value(full),
            200,
            contentLength: full.length,
          );
        });

        await downloader.downloadToFile(
          url: 'https://x/seforim.db.zst',
          destPath: dest,
          resumeToken: 'v-1',
        );

        // לא התקבלה "הצלחה" בת 21 בייט: בוצע restart מלא בלי Range.
        expect(captured, hasLength(3));
        expect(captured[2].headers.containsKey('Range'), isFalse);
        expect(File(dest).readAsBytesSync(), full);
      });

      test('גוף 206 שחורג מהטווח המוצהר נעצר מיד — לא נצרך כולו', () async {
        final dest = '${tmp.path}/seforim.db.zst';
        File(dest).writeAsBytesSync(part1);
        File('$dest.resume').writeAsStringSync('v-1\n"e1"');
        var chunksServed = 0;
        Stream<List<int>> overflowing() async* {
          for (var i = 0; i < 100; i++) {
            chunksServed++;
            yield [0];
          }
        }

        var call = 0;
        final downloader = downloaderThatCaptures(
          <http.BaseRequest>[],
          handler: (req) async {
            call++;
            if (call == 1) {
              // מצהיר על בייט אחד (15-15) אך שולח 100 chunks בלי Content-Length.
              return http.StreamedResponse(
                overflowing(),
                206,
                headers: {'content-range': 'bytes 15-15/40'},
              );
            }
            return http.StreamedResponse(
              Stream.value(full),
              200,
              contentLength: full.length,
            );
          },
        );

        await downloader.downloadToFile(
          url: 'https://x/seforim.db.zst',
          destPath: dest,
          resumeToken: 'v-1',
        );

        expect(File(dest).readAsBytesSync(), full);
        // המנוי לזרם בוטל מיד עם החריגה — לא נקראו כל 100 ה-chunks.
        expect(chunksServed, lessThan(10));
      });

      test('גוף redirect ארוך נזנח מיד וההפניה עדיין מתבצעת', () async {
        final dest = '${tmp.path}/seforim.db.zst';
        var chunksServed = 0;
        Stream<List<int>> longBody() async* {
          for (var i = 0; i < 100; i++) {
            chunksServed++;
            yield [0];
          }
        }

        final captured = <http.BaseRequest>[];
        final downloader =
            downloaderThatCaptures(captured, handler: (req) async {
          if (req.url.path == '/seforim.db.zst') {
            return http.StreamedResponse(
              longBody(),
              302,
              headers: {'location': '/real'},
            );
          }
          return http.StreamedResponse(
            Stream.value(full),
            200,
            contentLength: full.length,
          );
        });

        await downloader.downloadToFile(
          url: 'https://x/seforim.db.zst',
          destPath: dest,
          resumeToken: 'v-1',
        );

        expect(captured, hasLength(2));
        expect(captured[1].url.path, '/real');
        expect(File(dest).readAsBytesSync(), full);
        // גוף ה-redirect בוטל מיד — לא נצרכו כל 100 ה-chunks.
        expect(chunksServed, lessThan(10));
      });

      test('ביטול אחרי הצ׳אנק האחרון בלי resumeToken → הקובץ נמחק מיד',
          () async {
        final dest = '${tmp.path}/seforim.db.zst';
        var cancelled = false;
        final downloader = downloaderThatCaptures(
          <http.BaseRequest>[],
          handler: (req) async => http.StreamedResponse(
            Stream.value(full),
            200,
            contentLength: full.length,
          ),
        );

        await expectLater(
          downloader.downloadToFile(
            url: 'https://x/seforim.db.zst',
            destPath: dest,
            expectedSize: full.length,
            onProgress: (downloaded, total) {
              if (downloaded >= full.length) cancelled = true;
            },
            isCancelled: () => cancelled,
          ),
          throwsA(isA<PatchDownloadCancelled>()),
        );

        // בלי טוקן אין דרך לחדש — קובץ מלא היה נמחק בכניסה הבאה ממילא.
        expect(File(dest).existsSync(), isFalse);
        expect(File('$dest.resume').existsSync(), isFalse);
      });

      test('sidecar שהוחלף לטוקן זר במהלך ההורדה → החלקי נמחק בכשל', () async {
        final dest = '${tmp.path}/seforim.db.zst';
        File(dest).writeAsBytesSync(part1);
        File('$dest.resume').writeAsStringSync('v-1\n"e1"');
        var cancelled = false;
        final downloader = downloaderThatCaptures(
          <http.BaseRequest>[],
          handler: (req) async => http.StreamedResponse(
            Stream.value(part2),
            206,
            contentLength: part2.length,
            headers: {'content-range': 'bytes 15-39/40', 'etag': '"e1"'},
          ),
        );

        await expectLater(
          downloader.downloadToFile(
            url: 'https://x/seforim.db.zst',
            destPath: dest,
            resumeToken: 'v-1',
            onProgress: (downloaded, total) {
              // מדמה גורם חיצוני שדרס את קובץ הצד באמצע ההורדה.
              File('$dest.resume').writeAsStringSync('other-token\n"e1"');
              cancelled = true;
            },
            isCancelled: () => cancelled,
          ),
          throwsA(isA<PatchDownloadCancelled>()),
        );

        // sidecar שאינו תואם לטוקן = הקובץ לא בר-חידוש — נמחק ולא נשמר לחינם.
        expect(File(dest).existsSync(), isFalse);
      });

      test('טוקן זהה לקובץ הצד → resume עם Range', () async {
        final dest = '${tmp.path}/seforim.db.zst';
        File(dest).writeAsBytesSync(part1);
        File('$dest.resume').writeAsStringSync('v-1\n"e1"');
        final captured = <http.BaseRequest>[];
        final downloader = downloaderThatCaptures(
          captured,
          handler: (req) async => http.StreamedResponse(
            Stream.value(part2),
            206,
            contentLength: part2.length,
            headers: {'content-range': 'bytes 15-39/40'},
          ),
        );

        await downloader.downloadToFile(
          url: 'https://x/seforim.db.zst',
          destPath: dest,
          expectedSize: full.length,
          expectedSha256: fullHash,
          resumeToken: 'v-1',
        );

        expect(captured.single.headers['Range'], 'bytes=15-');
        expect(File(dest).readAsBytesSync(), full);
        // קובץ הצד שורד הורדה מוצלחת (חי ומת עם הקובץ) עם הטוקן וה-validator.
        expect(File('$dest.resume').readAsStringSync(), 'v-1\n"e1"');
      });

      test('חלקי בלי קובץ צד → נמחק ומתחילים מאפס', () async {
        final dest = '${tmp.path}/seforim.db.zst';
        File(dest).writeAsBytesSync(part1); // חלקי בלי sidecar
        final captured = <http.BaseRequest>[];
        final downloader = downloaderThatCaptures(
          captured,
          handler: (req) async => http.StreamedResponse(
            Stream.value(full),
            200,
            contentLength: full.length,
          ),
        );

        await downloader.downloadToFile(
          url: 'https://x/seforim.db.zst',
          destPath: dest,
          expectedSize: full.length,
          expectedSha256: fullHash,
          resumeToken: 'v-1',
        );

        expect(captured.single.headers.containsKey('Range'), isFalse);
        expect(File(dest).readAsBytesSync(), full);
      });

      test('resumeToken=null → חלקי קיים נמחק, GET מלא בלי Range, תוכן טרי',
          () async {
        final dest = '${tmp.path}/seforim.db.zst';
        File(dest).writeAsBytesSync(part1); // חלקי — חייב להימחק בכניסה
        File('$dest.resume').writeAsStringSync('stale'); // קובץ צד ישן — נמחק
        final captured = <http.BaseRequest>[];
        final downloader = downloaderThatCaptures(
          captured,
          handler: (req) async => http.StreamedResponse(
            Stream.value(full),
            200,
            contentLength: full.length,
          ),
        );

        await downloader.downloadToFile(
          url: 'https://x/seforim.db.zst',
          destPath: dest,
          expectedSize: full.length,
          expectedSha256: fullHash,
        );

        // בלי טוקן אין זהות יציבה: לא ממשיכים חלקי — GET מלא אחד בלי Range.
        expect(captured.single.headers.containsKey('Range'), isFalse);
        expect(File(dest).readAsBytesSync(), full);
        // בלי resumeToken לא נכתב קובץ צד, וקובץ צד ישן נמחק בכניסה.
        expect(File('$dest.resume').existsSync(), isFalse);
      });

      test(
        'resumeToken=null וקובץ נעול → זורק לפני רשת ולא ממשיך מהקובץ הישן',
        () async {
          final dest = '${tmp.path}/seforim.db.zst';
          File(dest).writeAsBytesSync(part1);
          final lock = File(dest).openSync();
          final captured = <http.BaseRequest>[];
          try {
            final downloader = downloaderThatCaptures(
              captured,
              handler: (req) async =>
                  http.StreamedResponse(Stream.value(full), 200),
            );
            await expectLater(
              downloader.downloadToFile(
                url: 'https://x/seforim.db.zst',
                destPath: dest,
              ),
              throwsA(isA<PatchDownloadException>()),
            );
            expect(captured, isEmpty);
            expect(File(dest).readAsBytesSync(), part1);
          } finally {
            lock.closeSync();
          }
        },
        skip: Platform.isWindows ? false : 'מחיקת קובץ פתוח נכשלת רק ב-Windows',
      );

      test('כשל כתיבת sidecar עוצר לפני פתיחת בקשת הרשת', () async {
        final dest = '${tmp.path}/seforim.db.zst';
        Directory('$dest.resume').createSync(); // אי אפשר לכתוב File באותו נתיב
        final captured = <http.BaseRequest>[];
        final downloader = downloaderThatCaptures(
          captured,
          handler: (req) async =>
              http.StreamedResponse(Stream.value(full), 200),
        );

        await expectLater(
          downloader.downloadToFile(
            url: 'https://x/seforim.db.zst',
            destPath: dest,
            resumeToken: 'v-1',
          ),
          throwsA(
            isA<PatchDownloadException>().having(
              (error) => error.message,
              'message',
              contains('כתיבת קובץ הזהות'),
            ),
          ),
        );
        expect(captured, isEmpty);
        expect(File(dest).existsSync(), isFalse);
      });

      test(
          'הורדה מוצלחת משאירה את קובץ הצד; כניסה חוזרת עם אותו טוקן+קובץ שלם → '
          'alreadyComplete בלי בקשת רשת, אימות עובר', () async {
        final dest = '${tmp.path}/seforim.db.zst';
        final captured = <http.BaseRequest>[];
        final downloader = downloaderThatCaptures(
          captured,
          handler: (req) async => http.StreamedResponse(
            Stream.value(full),
            200,
            contentLength: full.length,
          ),
        );

        await downloader.downloadToFile(
          url: 'https://x/seforim.db.zst',
          destPath: dest,
          expectedSize: full.length,
          expectedSha256: fullHash,
          resumeToken: 'v-1',
        );
        // ההורדה הראשונה: בקשה אחת, קובץ שלם וקובץ צד שורד.
        expect(captured, hasLength(1));
        expect(File(dest).readAsBytesSync(), full);
        expect(File('$dest.resume').readAsStringSync(), 'v-1');

        // כניסה חוזרת מיידית — אותו טוקן, הקובץ כבר שלם.
        await downloader.downloadToFile(
          url: 'https://x/seforim.db.zst',
          destPath: dest,
          expectedSize: full.length,
          expectedSha256: fullHash,
          resumeToken: 'v-1',
        );
        // אין בקשת רשת נוספת (alreadyComplete), הקובץ נשאר תקין ומאומת.
        expect(captured, hasLength(1));
        expect(File(dest).readAsBytesSync(), full);
      });

      test('כשל אימות sha256 → החלקי וקובץ הצד נמחקים', () async {
        final dest = '${tmp.path}/seforim.db.zst';
        final downloader = downloaderThatCaptures(
          [],
          handler: (req) async => http.StreamedResponse(
            Stream.value(full),
            200,
            contentLength: full.length,
          ),
        );
        await expectLater(
          downloader.downloadToFile(
            url: 'https://x/seforim.db.zst',
            destPath: dest,
            expectedSize: full.length,
            expectedSha256: 'deadbeef',
            resumeToken: 'v-1',
          ),
          throwsA(isA<PatchDownloadException>()),
        );
        expect(File(dest).existsSync(), isFalse);
        expect(File('$dest.resume').existsSync(), isFalse);
      });

      test('חריגת גודל תוך זרימה → הקובץ וקובץ הצד נמחקים', () async {
        final dest = '${tmp.path}/seforim.db.zst';
        final downloader = downloaderThatCaptures(
          [],
          handler: (req) async => http.StreamedResponse(
            Stream.value(full), // 40 בייטים
            200,
            contentLength: full.length,
          ),
        );
        await expectLater(
          downloader.downloadToFile(
            url: 'https://x/seforim.db.zst',
            destPath: dest,
            expectedSize: 8, // קטן מ-40 → חריגה מיד בזרם
            resumeToken: 'v-1',
          ),
          throwsA(isA<PatchDownloadException>()),
        );
        expect(File(dest).existsSync(), isFalse);
        expect(File('$dest.resume').existsSync(), isFalse);
      });
    });

    // P3: sha256 מחושב בזרימה (בלי קריאה חוזרת של הקובץ מהדיסק).
    group('sha256 בזרימה', () {
      test('הורדה טרייה (200) — hash תקין', () async {
        final dest = '${tmp.path}/seforim.db.zst';
        final downloader = downloaderThatCaptures(
          [],
          handler: (req) async => http.StreamedResponse(
            Stream.value(full),
            200,
            contentLength: full.length,
          ),
        );
        await downloader.downloadToFile(
          url: 'https://x/seforim.db.zst',
          destPath: dest,
          expectedSize: full.length,
          expectedSha256: fullHash,
        );
        expect(File(dest).readAsBytesSync(), full);
      });

      test('הורדה מחודשת (206) — hash מכסה תחילית+המשך', () async {
        final dest = '${tmp.path}/seforim.db.zst';
        File(dest).writeAsBytesSync(part1);
        File('$dest.resume').writeAsStringSync('v-1\n"e1"');
        final downloader = downloaderThatCaptures(
          [],
          handler: (req) async => http.StreamedResponse(
            Stream.value(part2),
            206,
            contentLength: part2.length,
            headers: {'content-range': 'bytes 15-39/40'},
          ),
        );
        await downloader.downloadToFile(
          url: 'https://x/seforim.db.zst',
          destPath: dest,
          expectedSize: full.length,
          expectedSha256: fullHash,
          resumeToken: 'v-1',
        );
        expect(File(dest).readAsBytesSync(), full);
      });

      test('restart אחרי 200 (היה partial) — hash מאופס ותקין', () async {
        final dest = '${tmp.path}/seforim.db.zst';
        File(dest).writeAsBytesSync(part1); // partial שיוזנח בגלל 200
        File('$dest.resume').writeAsStringSync('v-1\n"e1"');
        final downloader = downloaderThatCaptures(
          [],
          handler: (req) async => http.StreamedResponse(
            Stream.value(full),
            200,
            contentLength: full.length,
          ),
        );
        await downloader.downloadToFile(
          url: 'https://x/seforim.db.zst',
          destPath: dest,
          expectedSize: full.length,
          expectedSha256: fullHash,
          resumeToken: 'v-1',
        );
        expect(File(dest).readAsBytesSync(), full);
      });

      test('נתונים פגומים בזרם → hash שגוי, נזרק והקובץ נמחק', () async {
        final dest = '${tmp.path}/seforim.db.zst';
        final corrupt = Uint8List.fromList(List.generate(40, (i) => 40 - i));
        final downloader = downloaderThatCaptures(
          [],
          handler: (req) async => http.StreamedResponse(
            Stream.value(corrupt),
            200,
            contentLength: corrupt.length,
          ),
        );
        await expectLater(
          downloader.downloadToFile(
            url: 'https://x/seforim.db.zst',
            destPath: dest,
            expectedSize: full.length,
            expectedSha256: fullHash, // תואם ל-full, לא ל-corrupt
          ),
          throwsA(isA<PatchDownloadException>()),
        );
        expect(File(dest).existsSync(), isFalse);
      });
    });

    // finding 1: גוף תגובת שגיאה של הנכס נזנח מיד (המנוי מבוטל) — שרת שבור
    // שאינו סוגר את הזרם אינו תולה את הפעולה.
    test('גוף תגובת שגיאה שלא מסתיים → נכשל מיד ולא נתלה', () async {
      final dest = '${tmp.path}/seforim.db.zst';
      final controller = StreamController<List<int>>();
      addTearDown(controller.close);
      final mock = MockClient.streaming((request, bodyStream) async =>
          http.StreamedResponse(controller.stream, 500)); // גוף שלעולם לא נסגר
      final downloader = PatchDownloader(
        httpClient: mock,
        decompress: (c) async => full,
        stallTimeout: const Duration(milliseconds: 100),
      );
      await expectLater(
        downloader
            .downloadToFile(
              url: 'https://x/seforim.db.zst',
              destPath: dest,
              expectedSize: full.length,
            )
            .timeout(const Duration(seconds: 5)),
        throwsA(isA<PatchDownloadException>()),
      );
    });

    // finding 1: במסלול שגיאה של הנכס הגוף נזנח מיד ולא נצרך עד הסוף — שרת
    // ש"מדבר" 1.5GB לא יזרים הכל רק כדי לדווח כשל. כאן 500 עם גנרטור מונה
    // ארוך: המנוי מבוטל, ורק מעט chunks (אם בכלל) נמשכים.
    test('גוף תגובת שגיאה נזנח מיד — לא נצרך עד הסוף (finding 1)', () async {
      final dest = '${tmp.path}/seforim.db.zst';
      var chunksServed = 0;
      Stream<List<int>> counting() async* {
        for (var i = 0; i < 100; i++) {
          chunksServed++;
          yield [0];
        }
      }

      final downloader = downloaderThatCaptures(
        [],
        handler: (req) async => http.StreamedResponse(counting(), 500),
      );
      await expectLater(
        downloader.downloadToFile(
          url: 'https://x/seforim.db.zst',
          destPath: dest,
          expectedSize: full.length,
        ),
        throwsA(isA<PatchDownloadException>()),
      );
      // המנוי בוטל מיד — לא נמשכו כל 100 ה-chunks.
      expect(chunksServed, lessThan(10));
    });

    // finding P1: 206 קצר חוקי (subset לפי RFC 9110) אינו סיום — ממשיכים עם
    // Range נוסף עד ה-total הידוע, ולא מכריזים הצלחה על קובץ קטוע.
    group('206 קצר — לולאת המשך (finding P1)', () {
      test('206 קצר פעמיים → שתי בקשות Range, קובץ מלא, sha תקין', () async {
        final dest = '${tmp.path}/seforim.db.zst';
        File(dest).writeAsBytesSync(part1); // partial 15
        File('$dest.resume').writeAsStringSync('v-1\n"e1"');
        final mid = Uint8List.fromList(full.sublist(15, 21)); // 15..20 (6 בייט)
        final rest = Uint8List.fromList(full.sublist(21)); // 21..39 (19 בייט)
        final captured = <http.BaseRequest>[];
        final downloader = downloaderThatCaptures(
          captured,
          handler: (req) async {
            final range = req.headers['Range'];
            if (range == 'bytes=15-') {
              return http.StreamedResponse(
                Stream.value(mid),
                206,
                contentLength: mid.length,
                headers: {'content-range': 'bytes 15-20/40'},
              );
            }
            return http.StreamedResponse(
              Stream.value(rest),
              206,
              contentLength: rest.length,
              headers: {'content-range': 'bytes 21-39/40'},
            );
          },
        );

        await downloader.downloadToFile(
          url: 'https://x/seforim.db.zst',
          destPath: dest,
          expectedSize: full.length,
          expectedSha256: fullHash,
          resumeToken: 'v-1',
        );

        expect(captured, hasLength(2));
        expect(captured[0].headers['Range'], 'bytes=15-');
        expect(captured[1].headers['Range'], 'bytes=21-');
        expect(File(dest).readAsBytesSync(), full);
      });

      test('206 מכריז 6 בייט אך שולח 25 (בלי Content-Length) → נדחה, לא הצלחה',
          () async {
        final dest = '${tmp.path}/seforim.db.zst';
        File(dest).writeAsBytesSync(part1); // partial 15
        File('$dest.resume').writeAsStringSync('v-1\n"e1"');
        final captured = <http.BaseRequest>[];
        final downloader = downloaderThatCaptures(
          captured,
          handler: (req) async {
            if (req.headers.containsKey('Range')) {
              // מכריז end=20 (6 בייט) אך שולח 25 בייט, ובלי Content-Length —
              // רק בדיקת אורך-הגוף בפועל תופסת את אי-ההתאמה.
              return http.StreamedResponse(
                Stream.value(part2), // 25 בייט
                206,
                headers: {'content-range': 'bytes 15-20/40'},
              );
            }
            return http.StreamedResponse(
              Stream.value(full),
              200,
              contentLength: full.length,
            );
          },
        );

        // בלי expectedSize — כדי לבודד את בדיקת אורך-הגוף מבדיקת האורך הסופי.
        await downloader.downloadToFile(
          url: 'https://x/seforim.db.zst',
          destPath: dest,
          expectedSha256: fullHash,
          resumeToken: 'v-1',
        );

        // הקטע הלא-אמין נדחה, נמחק, וירד מחדש מאפס (GET מלא).
        expect(captured, hasLength(2));
        expect(captured[0].headers['Range'], 'bytes=15-');
        expect(captured[1].headers.containsKey('Range'), isFalse);
        expect(File(dest).readAsBytesSync(), full);
      });

      test('206 קצר שאינו מתקדם לעולם → נזרק (אין הצלחה שקטה עם קובץ קטוע)',
          () async {
        final dest = '${tmp.path}/seforim.db.zst';
        File(dest).writeAsBytesSync(part1);
        File('$dest.resume').writeAsStringSync('v-1\n"e1"');
        final stuck = Uint8List.fromList(full.sublist(15, 21)); // 6 בייט
        final downloader = downloaderThatCaptures(
          [],
          // כל בקשה (עם/בלי Range) מחזירה את אותו 206 שמתחיל ב-15 — לעולם לא
          // מכסה עד 40 ולעולם לא תואם ל-offset המבוקש בסבב ההמשך.
          handler: (req) async => http.StreamedResponse(
            Stream.value(stuck),
            206,
            contentLength: stuck.length,
            headers: {'content-range': 'bytes 15-20/40'},
          ),
        );

        await expectLater(
          downloader.downloadToFile(
            url: 'https://x/seforim.db.zst',
            destPath: dest,
            expectedSize: full.length,
            expectedSha256: fullHash,
            resumeToken: 'v-1',
          ),
          throwsA(isA<PatchDownloadException>()),
        );
      });
    });

    // finding P3: בדיקות ביטול בגבולות הפעולה.
    group('ביטול בגבולות (finding P3)', () {
      test(
          'ביטול ב-onProgress של הצ\'אנק האחרון → PatchDownloadCancelled, קובץ נשמר',
          () async {
        final dest = '${tmp.path}/seforim.db.zst';
        var cancel = false;
        final downloader = downloaderThatCaptures(
          [],
          handler: (req) async => http.StreamedResponse(
            Stream.value(full),
            200,
            contentLength: full.length,
          ),
        );
        await expectLater(
          downloader.downloadToFile(
            url: 'https://x/seforim.db.zst',
            destPath: dest,
            expectedSize: full.length,
            resumeToken: 'v-1',
            onProgress: (d, t) => cancel = true, // מבטל בצ'אנק האחרון
            isCancelled: () => cancel,
          ),
          throwsA(isA<PatchDownloadCancelled>()),
        );
        // כל הבייטים הגיעו — הקובץ שלם ונשמר (עם resumeToken) להמשך כ-no-op.
        expect(File(dest).readAsBytesSync(), full);
      });

      test(
          'isCancelled=true בכניסה → PatchDownloadCancelled לפני כל בקשה/מחיקה',
          () async {
        final dest = '${tmp.path}/seforim.db.zst';
        File(dest)
            .writeAsBytesSync(part1); // קיים — אסור שיימחק לפני בדיקת הביטול
        final captured = <http.BaseRequest>[];
        final downloader = downloaderThatCaptures(
          captured,
          handler: (req) async =>
              http.StreamedResponse(Stream.value(full), 200),
        );
        await expectLater(
          downloader.downloadToFile(
            url: 'https://x/seforim.db.zst',
            destPath: dest, // בלי resumeToken → מסלול המחיקה בכניסה
            isCancelled: () => true,
          ),
          throwsA(isA<PatchDownloadCancelled>()),
        );
        expect(captured, isEmpty); // אף בקשת רשת לא נשלחה
        expect(File(dest).readAsBytesSync(), part1); // הקובץ הקיים לא נמחק
      });
    });

    // finding P4: כותרת 416 עם זבל נלווה אינה הוכחת שלמות (פענוח מעוגן).
    test('416 עם Content-Range לא-מעוגן (זבל) → לא נחשב שלם, הורדה מלאה מאפס',
        () async {
      final dest = '${tmp.path}/seforim.db.zst';
      File(dest).writeAsBytesSync(full); // חלקי מקומי 40 בייט
      File('$dest.resume').writeAsStringSync('v-1\n"e1"');
      final captured = <http.BaseRequest>[];
      final downloader = downloaderThatCaptures(
        captured,
        handler: (req) async {
          if (req.headers.containsKey('Range')) {
            return http.StreamedResponse(
              const Stream.empty(),
              416,
              headers: {'content-range': 'garbage bytes */40 trailing'},
            );
          }
          return http.StreamedResponse(
            Stream.value(full),
            200,
            contentLength: full.length,
          );
        },
      );
      // בלי expectedSize → לא alreadyComplete; נשלח Range ומתקבל 416 עם זבל.
      await downloader.downloadToFile(
        url: 'https://x/seforim.db.zst',
        destPath: dest,
        expectedSha256: fullHash,
        resumeToken: 'v-1',
      );
      // הזבל אינו מתפענח כ-total → לא שלם → מחיקה והורדה מלאה מאפס.
      expect(captured, hasLength(2));
      expect(captured[0].headers['Range'], 'bytes=40-');
      expect(captured[1].headers.containsKey('Range'), isFalse);
      expect(File(dest).readAsBytesSync(), full);
    });

    // finding P2: ה-sink נסגר ב-finally גם כשהזרם זורק — ה-handle משוחרר
    // ומחיקת/פתיחת הקובץ החלקי מצליחה מיד (ב-Windows handle פתוח חוסם מחיקה).
    test('חריגה באמצע הזרם → ה-sink נסגר, הקובץ החלקי ניתן למחיקה מיד',
        () async {
      final dest = '${tmp.path}/seforim.db.zst';
      final downloader = downloaderThatCaptures(
        [],
        handler: (req) async => http.StreamedResponse(
          () async* {
            yield part1; // נכתב לדיסק
            throw const SocketException('connection reset');
          }(),
          200,
          contentLength: full.length,
          headers: {'etag': '"e1"'}, // validator שמור → החלקי נשמר להמשך
        ),
      );
      await expectLater(
        downloader.downloadToFile(
          url: 'https://x/seforim.db.zst',
          destPath: dest,
          expectedSize: full.length,
          resumeToken: 'v-1', // נשמר להמשך, אך ה-handle חייב להיסגר
        ),
        throwsA(isA<SocketException>()),
      );
      expect(File(dest).existsSync(), isTrue);
      // אם ה-handle היה דלוף, deleteSync היה זורק ב-Windows.
      expect(() => File(dest).deleteSync(), returnsNormally);
    });

    // finding 1: כשל flush/close במסלול ההצלחה חייב להיכשל (לא הצלחה שקטה) —
    // קובץ שאורכו מלא אך תוכנו לא נכתב לדיסק היה עובר alreadyComplete בריצה
    // הבאה. תיקיה במקום הקובץ מכשילה את openWrite בסגירה בצורה דטרמיניסטית.
    test('כשל כתיבה לדיסק במסלול ההצלחה → נכשל, קובץ הצד נמחק', () async {
      final dest = '${tmp.path}/seforim.db.zst';
      Directory(dest).createSync(); // openWrite ייכשל ב-flush/close
      final downloader = downloaderThatCaptures(
        [],
        handler: (req) async => http.StreamedResponse(
          Stream.value(full),
          200,
          contentLength: full.length,
        ),
      );
      await expectLater(
        downloader.downloadToFile(
          url: 'https://x/seforim.db.zst',
          destPath: dest,
          expectedSize: full.length,
          resumeToken: 'v-1',
        ),
        throwsA(isA<PatchDownloadException>()),
      );
      // קובץ הצד שנכתב בתחילת ההורדה נמחק — לא נשאר "resume" על קובץ פגום.
      expect(File('$dest.resume').existsSync(), isFalse);
    });

    // finding 2: total לא-עקבי בין סבבי 206 ('/40' ואז '/31') אינו הצלחה —
    // מתחילים מאפס. בלי הבדיקה, 31 בייט היו מתקבלים כהורדה שלמה.
    test('total לא-עקבי בין סבבי 206 → לא הצלחה בת 31 בייט, מוריד מלא מאפס',
        () async {
      final dest = '${tmp.path}/seforim.db.zst';
      File(dest).writeAsBytesSync(part1); // partial 15
      File('$dest.resume').writeAsStringSync('v-1\n"e1"');
      final mid = Uint8List.fromList(full.sublist(15, 21)); // 15..20 (/40)
      final captured = <http.BaseRequest>[];
      final downloader = downloaderThatCaptures(
        captured,
        handler: (req) async {
          final range = req.headers['Range'];
          if (range == 'bytes=15-') {
            return http.StreamedResponse(
              Stream.value(mid),
              206,
              contentLength: mid.length,
              headers: {'content-range': 'bytes 15-20/40'},
            );
          }
          if (range == 'bytes=21-') {
            // total השתנה ל-31 — לא אמין.
            return http.StreamedResponse(
              Stream.value(Uint8List.fromList(full.sublist(21, 31))),
              206,
              contentLength: 10,
              headers: {'content-range': 'bytes 21-30/31'},
            );
          }
          // restart מאפס → הגוף המלא (40).
          return http.StreamedResponse(
            Stream.value(full),
            200,
            contentLength: full.length,
          );
        },
      );

      // בלי expectedSize — כדי לבודד את בדיקת עקביות ה-total.
      await downloader.downloadToFile(
        url: 'https://x/seforim.db.zst',
        destPath: dest,
        expectedSha256: fullHash,
        resumeToken: 'v-1',
      );

      // לא נעצר על 31 בייט; ירד מחדש מאפס לקובץ מלא ותקין.
      expect(captured.last.headers.containsKey('Range'), isFalse);
      expect(File(dest).readAsBytesSync(), full);
    });

    // finding 3: שרת ששולח בייט אחד בכל 206 חסום ב-_maxContinuationRounds —
    // נכשל, אך החלקי (בייטים תקינים) וקובץ הצד נשמרים להמשך בריצה הבאה.
    test('בייט-לסבב מעבר לחסם → PatchDownloadException, החלקי נשמר', () async {
      final dest = '${tmp.path}/seforim.db.zst';
      final downloader = downloaderThatCaptures(
        [],
        handler: (req) async {
          final range = req.headers['Range'];
          final start = range == null
              ? 0
              : int.parse(range.substring(6, range.length - 1));
          return http.StreamedResponse(
            Stream.value(Uint8List.fromList([full[start]])),
            206,
            contentLength: 1,
            // ETag חזק → נשמר validator, ולכן החלקי ניתן לחידוש ונשמר להמשך.
            headers: {
              'content-range': 'bytes $start-$start/40',
              'etag': '"e1"'
            },
          );
        },
      );
      await expectLater(
        downloader.downloadToFile(
          url: 'https://x/seforim.db.zst',
          destPath: dest,
          expectedSize: full.length,
          resumeToken: 'v-1',
        ),
        throwsA(isA<PatchDownloadException>()),
      );
      // החלקי לא נמחק (הבייטים נכונים, ויש validator) והוא קטן מהמלא (נעצר
      // בחסם) — הריצה הבאה תמשיך; קובץ הצד שלם עם ה-validator.
      expect(File(dest).existsSync(), isTrue);
      final len = File(dest).lengthSync();
      expect(len, greaterThan(0));
      expect(len, lessThan(full.length));
      expect(File('$dest.resume').readAsStringSync(), 'v-1\n"e1"');
    });

    // finding 4: מד ההתקדמות בהורדה רב-סבבית לא מדווח 100% מוקדם — ה-total הכולל
    // (מ-Content-Range) גובר על אומדן-הסבב, ואינו קטן בין סבבים.
    test('הורדה רב-סבבית → total עקבי, בלי 100% מוקדם', () async {
      final dest = '${tmp.path}/seforim.db.zst';
      File(dest).writeAsBytesSync(part1); // partial 15
      File('$dest.resume').writeAsStringSync('v-1\n"e1"');
      final mid = Uint8List.fromList(full.sublist(15, 21)); // 15..20
      final rest = Uint8List.fromList(full.sublist(21)); // 21..39
      final progress = <(int, int?)>[];
      final downloader = downloaderThatCaptures(
        [],
        handler: (req) async {
          if (req.headers['Range'] == 'bytes=15-') {
            return http.StreamedResponse(
              Stream.value(mid),
              206,
              contentLength: mid.length,
              headers: {'content-range': 'bytes 15-20/40'},
            );
          }
          return http.StreamedResponse(
            Stream.value(rest),
            206,
            contentLength: rest.length,
            headers: {'content-range': 'bytes 21-39/40'},
          );
        },
      );

      // בלי expectedSize — כדי שה-total יגיע רק מ-Content-Range (finding 2/4).
      await downloader.downloadToFile(
        url: 'https://x/seforim.db.zst',
        destPath: dest,
        expectedSha256: fullHash,
        onProgress: (d, t) => progress.add((d, t)),
        resumeToken: 'v-1',
      );

      expect(File(dest).readAsBytesSync(), full);
      // ה-total מדווח, קבוע (40), ולעולם לא מתכווץ בין סבבים.
      final totals = progress.map((e) => e.$2).toList();
      expect(totals, everyElement(40));
      // אין דיווח 100% (n,n) לפני הבייט האחרון (40).
      final prematureFull = progress.any((e) => e.$1 == e.$2 && e.$1 < 40);
      expect(prematureFull, isFalse);
      expect(progress.last, (40, 40));
    });

    // finding P2: כבילת ה-resume לייצוג בצד השרת דרך If-Range/ETag.
    group('If-Range / ETag (finding P2)', () {
      test(
          'רגרסיה: הייצוג הוחלף (אותו גודל) + If-Range מכובד → 200 עם B, בלי תערובת',
          () async {
        final dest = '${tmp.path}/seforim.db.zst';
        final versionB = Uint8List.fromList(List.generate(40, (i) => 200 - i));
        final bHash = sha256.convert(versionB).toString();
        File(dest).writeAsBytesSync(full.sublist(0, 10)); // 10 בייט מגרסה A
        File('$dest.resume').writeAsStringSync('v-1\n"A"');
        final captured = <http.BaseRequest>[];
        final downloader = downloaderThatCaptures(
          captured,
          // השרת מכבד If-Range: הייצוג השתנה → 200 עם הגוף המלא של B.
          handler: (req) async => http.StreamedResponse(
            Stream.value(versionB),
            200,
            contentLength: versionB.length,
            headers: {'etag': '"B"'},
          ),
        );

        await downloader.downloadToFile(
          url: 'https://x/seforim.db.zst',
          destPath: dest,
          expectedSize: versionB.length,
          expectedSha256: bHash,
          resumeToken: 'v-1',
        );

        expect(captured.single.headers['If-Range'], '"A"');
        expect(captured.single.headers['Range'], 'bytes=10-');
        expect(File(dest).readAsBytesSync(), versionB); // B מלא, בלי A[0..9]
      });

      test('ETag זהה לשמור → 206 מתווסף, resume מצליח (If-Range נשלח)',
          () async {
        final dest = '${tmp.path}/seforim.db.zst';
        File(dest).writeAsBytesSync(part1);
        File('$dest.resume').writeAsStringSync('v-1\n"A"');
        final captured = <http.BaseRequest>[];
        final downloader = downloaderThatCaptures(
          captured,
          handler: (req) async => http.StreamedResponse(
            Stream.value(part2),
            206,
            contentLength: part2.length,
            headers: {'content-range': 'bytes 15-39/40', 'etag': '"A"'},
          ),
        );

        await downloader.downloadToFile(
          url: 'https://x/seforim.db.zst',
          destPath: dest,
          expectedSize: full.length,
          expectedSha256: fullHash,
          resumeToken: 'v-1',
        );

        expect(captured.single.headers['If-Range'], '"A"');
        expect(captured.single.headers['Range'], 'bytes=15-');
        expect(File(dest).readAsBytesSync(), full);
      });

      test('חלקי עם טוקן אך בלי validator → התחלה מאפס (בקשה ראשונה בלי Range)',
          () async {
        final dest = '${tmp.path}/seforim.db.zst';
        File(dest).writeAsBytesSync(part1); // partial 15
        File('$dest.resume')
            .writeAsStringSync('v-1'); // טוקן בלבד, בלי validator
        final captured = <http.BaseRequest>[];
        final downloader = downloaderThatCaptures(
          captured,
          handler: (req) async => http.StreamedResponse(
            Stream.value(full),
            200,
            contentLength: full.length,
          ),
        );

        await downloader.downloadToFile(
          url: 'https://x/seforim.db.zst',
          destPath: dest,
          expectedSize: full.length,
          expectedSha256: fullHash,
          resumeToken: 'v-1',
        );

        expect(captured.single.headers.containsKey('Range'), isFalse);
        expect(File(dest).readAsBytesSync(), full);
      });

      test('ETag חלש (W/) → לא נשמר כ-validator (הריצה הבאה תתחיל מאפס)',
          () async {
        final dest = '${tmp.path}/seforim.db.zst';
        final downloader = downloaderThatCaptures(
          [],
          handler: (req) async => http.StreamedResponse(
            Stream.value(full),
            200,
            contentLength: full.length,
            headers: {'etag': 'W/"x"'},
          ),
        );

        await downloader.downloadToFile(
          url: 'https://x/seforim.db.zst',
          destPath: dest,
          expectedSize: full.length,
          expectedSha256: fullHash,
          resumeToken: 'v-1',
        );

        // ETag חלש אינו שמיש עם If-Range — קובץ הצד מכיל רק טוקן, בלי validator.
        expect(File('$dest.resume').readAsStringSync(), 'v-1');
      });

      test('ETag חלש שכבר קיים ב-sidecar אינו נשלח ב-If-Range', () async {
        final dest = '${tmp.path}/seforim.db.zst';
        File(dest).writeAsBytesSync(part1);
        File('$dest.resume').writeAsStringSync('v-1\nW/"old"');
        final captured = <http.BaseRequest>[];
        final downloader = downloaderThatCaptures(
          captured,
          handler: (req) async => http.StreamedResponse(
            Stream.value(full),
            200,
            contentLength: full.length,
            headers: {'etag': '"new"'},
          ),
        );

        await downloader.downloadToFile(
          url: 'https://x/seforim.db.zst',
          destPath: dest,
          expectedSize: full.length,
          expectedSha256: fullHash,
          resumeToken: 'v-1',
        );

        expect(captured.single.headers.containsKey('Range'), isFalse);
        expect(captured.single.headers.containsKey('If-Range'), isFalse);
        expect(File(dest).readAsBytesSync(), full);
      });

      test('ETag מתחלף בין סבבי 206 (A→B) → restart, בלי הצלחה מעורבת',
          () async {
        final dest = '${tmp.path}/seforim.db.zst';
        File(dest).writeAsBytesSync(part1); // partial 15
        File('$dest.resume').writeAsStringSync('v-1\n"A"');
        final mid = Uint8List.fromList(full.sublist(15, 21)); // 6 בייט
        final captured = <http.BaseRequest>[];
        final downloader = downloaderThatCaptures(
          captured,
          handler: (req) async {
            final range = req.headers['Range'];
            if (range == 'bytes=15-') {
              return http.StreamedResponse(
                Stream.value(mid),
                206,
                contentLength: mid.length,
                headers: {'content-range': 'bytes 15-20/40', 'etag': '"A"'},
              );
            }
            if (range == 'bytes=21-') {
              // ETag התחלף באמצע הסבבים — מוחקים ומתחילים מאפס.
              return http.StreamedResponse(
                Stream.value(Uint8List.fromList(full.sublist(21))),
                206,
                contentLength: full.length - 21,
                headers: {'content-range': 'bytes 21-39/40', 'etag': '"B"'},
              );
            }
            // restart מאפס → הגוף המלא.
            return http.StreamedResponse(
              Stream.value(full),
              200,
              contentLength: full.length,
            );
          },
        );

        await downloader.downloadToFile(
          url: 'https://x/seforim.db.zst',
          destPath: dest,
          expectedSize: full.length,
          expectedSha256: fullHash,
          resumeToken: 'v-1',
        );

        expect(captured, hasLength(3));
        expect(captured[0].headers['Range'], 'bytes=15-');
        expect(captured[1].headers['Range'], 'bytes=21-');
        expect(captured[2].headers.containsKey('Range'), isFalse);
        expect(File(dest).readAsBytesSync(), full);
      });

      test('הורדה טרייה (200) עם ETag → קובץ הצד מכיל אותו להמשך', () async {
        final dest = '${tmp.path}/seforim.db.zst';
        final downloader = downloaderThatCaptures(
          [],
          handler: (req) async => http.StreamedResponse(
            Stream.value(full),
            200,
            contentLength: full.length,
            headers: {'etag': '"srv"'},
          ),
        );

        await downloader.downloadToFile(
          url: 'https://x/seforim.db.zst',
          destPath: dest,
          expectedSize: full.length,
          expectedSha256: fullHash,
          resumeToken: 'v-1',
        );

        // הריצה הבאה יכולה לשלוח If-Range עם ה-ETag שנשמר.
        expect(File('$dest.resume').readAsStringSync(), 'v-1\n"srv"');
      });
    });
  });
}

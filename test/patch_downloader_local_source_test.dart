import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/testing.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:seforim_library_updater/src/models/delta_manifest.dart';
import 'package:seforim_library_updater/src/services/patch_downloader.dart';
import 'package:test/test.dart';

LibraryDomainStrings get strings => AppL10n.strings.libraryDomain;

/// המסלול המקומי של [PatchDownloader] — כש-`url` הוא נתיב על הדיסק ולא כתובת
/// HTTP. זה המסלול היחיד שרץ בפועל בעדכון ממראה offline (AGENTS §5: אין נפילה
/// לרשת בזרימת הבדיקה/החלה), ולכן הוא נבדק כאן בנפרד ממסלול ה-HTTP.
void main() {
  late Directory tmp;
  final uncompressed = Uint8List.fromList(List.generate(64, (i) => i));
  final compressed = Uint8List.fromList(List.generate(32, (i) => 255 - i));

  setUp(() => tmp = Directory.systemTemp.createTempSync('local_source'));
  tearDown(() {
    AppL10n.use(AppLanguage.hebrew);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  String path(String name) => '${tmp.path}${Platform.pathSeparator}$name';

  // כל בקשת רשת כאן היא באג בפני עצמה — המסלול המקומי לא אמור לגעת ב-HTTP.
  PatchDownloader downloader({Uint8List? extracted}) => PatchDownloader(
        httpClient: MockClient((_) async =>
            throw StateError('המסלול המקומי אינו אמור לפנות לרשת')),
        decompress: (_) async => extracted ?? uncompressed,
      );

  PatchFileEntry entry() => PatchFileEntry(
        file: 'patch-v1-v2.db.zst',
        compression: 'zstd',
        sha256: sha256.convert(compressed).toString(),
        size: compressed.length,
        uncompressedSha256: sha256.convert(uncompressed).toString(),
        uncompressedSize: uncompressed.length,
      );

  group('downloadAndExtract ממקור מקומי', () {
    test('קורא מהדיסק, מאמת ומחלץ', () async {
      final src = path('patch-v1-v2.db.zst');
      File(src).writeAsBytesSync(compressed);
      final out = await downloader().downloadAndExtract(
        patchFile: entry(),
        downloadUrl: src,
        destDir: Directory(path('out')),
      );
      expect(File(out).readAsBytesSync(), uncompressed);
      expect(out, endsWith('patch-v1-v2.db'));
    });

    test('קובץ מקור חסר → PatchDownloadException בהודעת ה-l10n', () {
      final src = path('missing.zst');
      expect(
        () => downloader().downloadAndExtract(
          patchFile: entry(),
          downloadUrl: src,
          destDir: tmp,
        ),
        throwsA(isA<PatchDownloadException>().having(
            (e) => e.message, 'message', strings.localFileNotFound(src))),
      );
    });

    test('קובץ גדול מהצפוי → נדחה לפני האימות', () {
      final src = path('big.zst');
      File(src).writeAsBytesSync(Uint8List(compressed.length + 1));
      expect(
        () => downloader().downloadAndExtract(
          patchFile: entry(),
          downloadUrl: src,
          destDir: tmp,
        ),
        throwsA(isA<PatchDownloadException>().having((e) => e.message,
            'message', strings.localFileTooLarge(compressed.length, src))),
      );
    });

    test('קובץ מקומי עם תוכן שגוי → כשל sha256, בלי כתיבת .db', () async {
      final src = path('patch-v1-v2.db.zst');
      File(src).writeAsBytesSync(Uint8List(compressed.length));
      await expectLater(
        downloader().downloadAndExtract(
          patchFile: entry(),
          downloadUrl: src,
          destDir: tmp,
        ),
        throwsA(isA<PatchDownloadException>()),
      );
      expect(File(path('patch-v1-v2.db')).existsSync(), isFalse);
    });

    test('ביטול לפני הקריאה → PatchDownloadCancelled', () {
      final src = path('patch-v1-v2.db.zst');
      File(src).writeAsBytesSync(compressed);
      expect(
        () => downloader().downloadAndExtract(
          patchFile: entry(),
          downloadUrl: src,
          destDir: tmp,
          isCancelled: () => true,
        ),
        throwsA(isA<PatchDownloadCancelled>()),
      );
    });

    test('ההתקדמות מדווחת פעם אחת על הגודל המלא', () async {
      final src = path('patch-v1-v2.db.zst');
      File(src).writeAsBytesSync(compressed);
      final progress = <(int, int?)>[];
      await downloader().downloadAndExtract(
        patchFile: entry(),
        downloadUrl: src,
        destDir: tmp,
        onProgress: (d, t) => progress.add((d, t)),
      );
      expect(progress, [(compressed.length, compressed.length)]);
    });
  });

  group('downloadToFile ממקור מקומי (DB מלא במראה)', () {
    late Uint8List payload;
    late String src;

    setUp(() {
      // מעל גודל ה-chunk של openRead (64KB) — כדי שהעתקה תהיה רב-שלבית ובדיקת
      // הביטול תתפוס אותה באמצע, כמו בהעתקת ה-DB האמיתי.
      payload = Uint8List.fromList(List.generate(300000, (i) => i % 256));
      src = path('seforim.db.zst');
      File(src).writeAsBytesSync(payload);
    });

    test('מעתיק, מאמת גודל ו-sha256, ומדווח התקדמות עולה', () async {
      final dest = path('copy.zst');
      final progress = <(int, int?)>[];
      await downloader().downloadToFile(
        url: src,
        destPath: dest,
        expectedSize: payload.length,
        expectedSha256: sha256.convert(payload).toString(),
        onProgress: (d, t) => progress.add((d, t)),
      );
      expect(File(dest).readAsBytesSync(), payload);
      expect(progress.last, (payload.length, payload.length));
      expect(progress.map((p) => p.$1).toList(),
          orderedEquals(progress.map((p) => p.$1).toList()..sort()));
    });

    test('sha256 באותיות גדולות מתקבל', () async {
      final dest = path('copy.zst');
      await downloader().downloadToFile(
        url: src,
        destPath: dest,
        expectedSha256: sha256.convert(payload).toString().toUpperCase(),
      );
      expect(File(dest).existsSync(), isTrue);
    });

    test('גודל שאינו תואם → כשל לפני כל כתיבה', () async {
      final dest = path('copy.zst');
      await expectLater(
        downloader().downloadToFile(
          url: src,
          destPath: dest,
          expectedSize: payload.length + 1,
        ),
        throwsA(isA<PatchDownloadException>().having(
          (e) => e.message,
          'message',
          strings.localFileSizeMismatch(
              payload.length + 1, payload.length, src),
        )),
      );
      expect(File(dest).existsSync(), isFalse);
    });

    test('sha256 שאינו תואם → הקובץ שנכתב נמחק', () async {
      final dest = path('copy.zst');
      await expectLater(
        downloader().downloadToFile(
          url: src,
          destPath: dest,
          expectedSha256: 'deadbeef',
        ),
        throwsA(isA<PatchDownloadException>().having(
            (e) => e.message, 'message', strings.localFileHashMismatch(src))),
      );
      expect(File(dest).existsSync(), isFalse);
    });

    test('מקור חסר → PatchDownloadException בהודעת ה-l10n', () async {
      final missing = path('nope.zst');
      await expectLater(
        downloader().downloadToFile(url: missing, destPath: path('copy.zst')),
        throwsA(isA<PatchDownloadException>().having(
            (e) => e.message, 'message', strings.localSourceNotFound(missing))),
      );
    });

    test('ביטול תוך כדי העתקה → הקובץ החלקי נמחק', () async {
      final dest = path('copy.zst');
      var cancel = false;
      await expectLater(
        downloader().downloadToFile(
          url: src,
          destPath: dest,
          onProgress: (_, __) => cancel = true,
          isCancelled: () => cancel,
        ),
        throwsA(isA<PatchDownloadCancelled>()),
      );
      expect(File(dest).existsSync(), isFalse);
    });

    test('ביטול בכניסה אינו נוגע ביעד קיים', () async {
      final dest = path('copy.zst');
      File(dest).writeAsStringSync('KEEP');
      await expectLater(
        downloader().downloadToFile(
          url: src,
          destPath: dest,
          isCancelled: () => true,
        ),
        throwsA(isA<PatchDownloadCancelled>()),
      );
      expect(File(dest).readAsStringSync(), 'KEEP');
    });

    test('יעד קיים מוחלף לגמרי (גם כשהוא ארוך יותר)', () async {
      final dest = path('copy.zst');
      File(dest).writeAsBytesSync(Uint8List(payload.length * 2));
      await downloader().downloadToFile(url: src, destPath: dest);
      expect(File(dest).readAsBytesSync(), payload);
    });

    // העתקה מקומית מהירה מספיק שאין בה resume — ולכן אין קובץ צד לנקות.
    test('אין קובץ צד (.resume) במסלול המקומי', () async {
      final dest = path('copy.zst');
      await downloader().downloadToFile(
        url: src,
        destPath: dest,
        resumeToken: '12345',
      );
      expect(
          File(PatchDownloader.resumeSidecarPath(dest)).existsSync(), isFalse);
    });
  });
}

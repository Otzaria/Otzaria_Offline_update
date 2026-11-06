import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/src/services/zstd_file_decompressor.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import 'support/zstd_fixtures.dart';

/// בודק את החילוץ בזרימה מול libzstd **אמיתי**.
///
/// הבדיקה מדולגת כשאין ספריית zstd לטעינה (למשל לינוקס ב-CI, או הרצת
/// `flutter test` בלי שהפלאגין של הפלטפורמה נבנה) — בדיוק המצב שבו הקוד
/// שבייצור מסרב לחילוץ. ב-Windows יש להריץ עם התיקייה של
/// `zstandard_windows.dll` ב-PATH; ראו library_manager/README.md.
void main() {
  final bindings = nativeZstd();

  group('ZstdFileDecompressor', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('zstd-stream-test-');
    });
    tearDown(() async {
      AppL10n.use(AppLanguage.hebrew);
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('מחלץ קובץ גדול מרובה-צ׳אנקים בזהות בית-אחר-בית', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }

      // 8MB — גדול בהרבה מ-ZSTD_DStreamOutSize (~128KB), ולכן מכריח את שתי
      // הלולאות (קלט וגם פלט) לרוץ הרבה סבבים. זה בדיוק מה שהמסלול
      // ה-one-shot לא בדק.
      final original = pseudoRandomBytes(8 * 1024 * 1024);
      final compressedPath = '${tmp.path}/data.zst';
      final destPath = '${tmp.path}/data.bin';
      File(
        compressedPath,
      ).writeAsBytesSync(compressWithZstd(bindings, original));

      expect(
        await ZstdFileDecompressor.decompressFileToFile(
          compressedPath,
          destPath,
        ),
        isTrue,
      );
      expect(File(destPath).readAsBytesSync(), original);
    });

    test('מחשב sha256 ומספר בתים של הפלט על אותו מעבר', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }

      final original = pseudoRandomBytes(3 * 1024 * 1024 + 17);
      final compressed = compressWithZstd(bindings, original);
      final compressedPath = '${tmp.path}/data.zst';
      File(compressedPath).writeAsBytesSync(compressed);

      String? sourceDigest;
      String? outputDigest;
      int? written;
      expect(
        await ZstdFileDecompressor.decompressFileToFile(
          compressedPath,
          '${tmp.path}/data.bin',
          onSourceDigest: (hex) => sourceDigest = hex,
          onOutputDigest: (hex, bytes) {
            outputDigest = hex;
            written = bytes;
          },
        ),
        isTrue,
      );

      expect(sourceDigest, sha256.convert(compressed).toString());
      expect(outputDigest, sha256.convert(original).toString());
      expect(written, original.length);
    });

    test('פלט שחורג מ-maxOutputBytes נעצר לפני שנכתב מעבר לתקרה', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }

      final original = pseudoRandomBytes(4 * 1024 * 1024);
      final compressedPath = '${tmp.path}/data.zst';
      final destPath = '${tmp.path}/data.bin';
      File(
        compressedPath,
      ).writeAsBytesSync(compressWithZstd(bindings, original));
      const limit = 300 * 1024;
      final reports = <int>[];

      await expectLater(
        ZstdFileDecompressor.decompressFileToFile(
          compressedPath,
          destPath,
          onProgress: (read, _) => reports.add(read),
          maxOutputBytes: limit,
        ),
        throwsA(
          isA<ZstdOutputLimitExceeded>()
              .having((e) => e.limit, 'limit', limit)
              .having(
                (e) => e.message,
                'message',
                AppL10n.strings.libraryDomain.checksumMismatchDetailed(
                  AppL10n.strings.libraryDomain.extractedFileSizeLabel,
                  '$limit',
                  '> $limit',
                ),
              ),
        ),
      );

      expect(File(destPath).existsSync(), isFalse);
      expect(reports.last, lessThan(File(compressedPath).lengthSync()));
    });

    test('פלט בגודל maxOutputBytes בדיוק מתקבל', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }

      final original = pseudoRandomBytes(1024 * 1024 + 3);
      final compressedPath = '${tmp.path}/data.zst';
      final destPath = '${tmp.path}/data.bin';
      File(
        compressedPath,
      ).writeAsBytesSync(compressWithZstd(bindings, original));

      expect(
        await ZstdFileDecompressor.decompressFileToFile(
          compressedPath,
          destPath,
          maxOutputBytes: original.length,
        ),
        isTrue,
      );
      expect(File(destPath).readAsBytesSync(), original);
    });

    test('ביטול שכבר חל בכניסה עוצר לפני חילוץ כלשהו', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }

      final compressedPath = '${tmp.path}/data.zst';
      final destPath = '${tmp.path}/data.bin';
      File(compressedPath).writeAsBytesSync(
        compressWithZstd(bindings, pseudoRandomBytes(1 << 20)),
      );
      final reports = <int>[];

      await expectLater(
        ZstdFileDecompressor.decompressFileToFile(
          compressedPath,
          destPath,
          onProgress: (read, _) => reports.add(read),
          isCancelled: () => true,
        ),
        throwsA(
          isA<ZstdStreamException>().having(
            (e) => e.message,
            'message',
            AppL10n.strings.libraryDomain.updateCancelled,
          ),
        ),
      );

      expect(reports, isEmpty);
      expect(File(destPath).existsSync(), isFalse);
    });

    test('ביטול בתוך מקטע קלט דחוס מאוד מנקה את הפלט בלבד', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }
      const outputSize = 64 * 1024 * 1024;
      final compressed = compressWithZstd(bindings, Uint8List(outputSize));
      expect(compressed.length, lessThan(128 * 1024));
      final source = File('${tmp.path}/dense.zst')
        ..writeAsBytesSync(compressed);
      final output = File('${tmp.path}/dense.bin');
      var cancelled = false;
      var digestCalled = false;
      final latency = Stopwatch();
      final reports = <int>[];
      await expectLater(
        ZstdFileDecompressor.decompressFileToFile(
          source.path,
          output.path,
          maxOutputBytes: outputSize,
          isCancelled: () => cancelled,
          onOutputProgress: (written) {
            reports.add(written);
            if (!cancelled) {
              cancelled = true;
              latency.start();
            }
          },
          onOutputDigest: (_, _) => digestCalled = true,
        ),
        throwsA(isA<ZstdCancelledException>()),
      );
      latency.stop();
      expect(reports.first, lessThan(outputSize));
      expect(latency.elapsed, lessThan(const Duration(seconds: 5)));
      expect(digestCalled, isFalse);
      expect(output.existsSync(), isFalse);
      expect(source.readAsBytesSync(), compressed);
    });

    test('שגיאת progress מנקה פלט חלקי ושומרת את השגיאה', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }
      final source = File('${tmp.path}/dense.zst')
        ..writeAsBytesSync(compressWithZstd(bindings, Uint8List(16 << 20)));
      final output = File('${tmp.path}/dense.bin');
      final failure = StateError('progress failed');
      await expectLater(
        ZstdFileDecompressor.decompressFileToFile(
          source.path,
          output.path,
          onOutputProgress: (_) => throw failure,
        ),
        throwsA(same(failure)),
      );
      expect(output.existsSync(), isFalse);
      expect(source.existsSync(), isTrue);
    });

    test('אינו מוחק יעד קיים בביטול לפני תחילת הפעולה', () async {
      final source = File('${tmp.path}/source.zst')
        ..writeAsStringSync('source');
      final output = File('${tmp.path}/existing.bin')
        ..writeAsStringSync('keep');
      await expectLater(
        ZstdFileDecompressor.decompressFileToFile(
          source.path,
          output.path,
          isCancelled: () => true,
        ),
        throwsA(isA<ZstdCancelledException>()),
      );
      expect(output.readAsStringSync(), 'keep');
      expect(source.readAsStringSync(), 'source');
    });

    test('דוחה יעד זהה למקור בלי לשנותו', () async {
      final source = File('${tmp.path}/source.zst')..writeAsStringSync('keep');
      await expectLater(
        ZstdFileDecompressor.decompressFileToFile(source.path, source.path),
        throwsArgumentError,
      );
      expect(source.readAsStringSync(), 'keep');
    });

    test(
      'ביטול בהתקדמות הפלט האחרונה מנוקה לפני קבלת תוצאת ה-worker',
      () async {
        if (bindings == null) {
          markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
          return;
        }
        final bytes = pseudoRandomBytes((128 << 10) + 17);
        final source = File('${tmp.path}/final.zst')
          ..writeAsBytesSync(compressWithZstd(bindings, bytes));
        final output = File('${tmp.path}/final.bin');
        var cancelled = false;
        var digestDelivered = false;
        await expectLater(
          ZstdFileDecompressor.decompressFileToFile(
            source.path,
            output.path,
            isCancelled: () => cancelled,
            onOutputProgress: (written) {
              if (written == bytes.length) cancelled = true;
            },
            onOutputDigest: (_, __) => digestDelivered = true,
          ),
          throwsA(isA<ZstdCancelledException>()),
        );
        expect(cancelled, isTrue);
        expect(digestDelivered, isFalse);
        expect(output.existsSync(), isFalse);
        expect(source.existsSync(), isTrue);
      },
    );

    test('דוחה יעד שמצביע למקור דרך קישור סמלי', () async {
      if (Platform.isWindows) {
        markTestSkipped('יצירת symlink ב-Windows דורשת הרשאה נוספת');
        return;
      }
      final source = File('${tmp.path}/source.zst')..writeAsStringSync('keep');
      final alias = Link('${tmp.path}/alias.zst')..createSync(source.path);
      await expectLater(
        ZstdFileDecompressor.decompressFileToFile(source.path, alias.path),
        throwsArgumentError,
      );
      expect(source.readAsStringSync(), 'keep');
      expect(alias.existsSync(), isTrue);
    });

    test('מגבלת פלט מצטברת גם בין frames', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }
      final frame = compressWithZstd(bindings, Uint8List(1 << 20));
      final source = File('${tmp.path}/frames.zst')
        ..writeAsBytesSync([...frame, ...frame]);
      final output = File('${tmp.path}/frames.bin');
      await expectLater(
        ZstdFileDecompressor.decompressFileToFile(
          source.path,
          output.path,
          maxOutputBytes: (1 << 20) + 1,
        ),
        throwsA(isA<ZstdOutputLimitExceeded>()),
      );
      expect(output.existsSync(), isFalse);
      expect(source.lengthSync(), frame.length * 2);
    });

    test('כשל בפתיחת היעד אחרי יצירת ה-hashers זורק כרגיל', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }

      final compressedPath = '${tmp.path}/data.zst';
      File(
        compressedPath,
      ).writeAsBytesSync(compressWithZstd(bindings, pseudoRandomBytes(4096)));

      await expectLater(
        ZstdFileDecompressor.decompressFileToFile(
          compressedPath,
          '${tmp.path}/missing-dir/out.bin',
          onSourceDigest: (_) {},
          onOutputDigest: (_, _) {},
        ),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('החילוץ מדווח התקדמות עולה עד סך הקובץ הדחוס', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }

      // 8MB דחוסים מפיקים הרבה יותר מחוצץ קלט אחד (~128KB), ולכן חייבים
      // להגיע כמה דיווחים — דיווח אחד בלבד היה מד שקופץ מ-0 ל-100%.
      final original = pseudoRandomBytes(8 * 1024 * 1024);
      final compressedPath = '${tmp.path}/data.zst';
      final compressed = compressWithZstd(bindings, original);
      File(compressedPath).writeAsBytesSync(compressed);

      final reports = <(int, int)>[];
      expect(
        await ZstdFileDecompressor.decompressFileToFile(
          compressedPath,
          '${tmp.path}/data.bin',
          onProgress: (read, total) => reports.add((read, total)),
        ),
        isTrue,
      );

      expect(reports.length, greaterThan(1));
      expect(reports.every((r) => r.$2 == compressed.length), isTrue);
      // עולה מונוטונית ומגיעה לסוף: זה מה שמבדיל מד אמיתי ממד שנתקע.
      for (var i = 1; i < reports.length; i++) {
        expect(reports[i].$1, greaterThan(reports[i - 1].$1));
      }
      expect(reports.last.$1, compressed.length);
    });

    test('קובץ קטוע נדחה במקום להשאיר DB חלקי', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }

      final compressed = compressWithZstd(bindings, pseudoRandomBytes(1 << 20));
      final truncatedPath = '${tmp.path}/truncated.zst';
      // חותכים את החצי השני: הצ׳אנקים הראשונים תקינים, אבל ה-frame לא נסגר.
      File(truncatedPath).writeAsBytesSync(
        Uint8List.sublistView(compressed, 0, compressed.length ~/ 2),
      );

      await expectLater(
        ZstdFileDecompressor.decompressFileToFile(
          truncatedPath,
          '${tmp.path}/out.bin',
        ),
        throwsA(isA<ZstdStreamException>()),
      );
      expect(File('${tmp.path}/out.bin').existsSync(), isFalse);
    });

    test('קובץ ריק נדחה', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }

      final emptyPath = '${tmp.path}/empty.zst';
      File(emptyPath).writeAsBytesSync(Uint8List(0));

      await expectLater(
        ZstdFileDecompressor.decompressFileToFile(
          emptyPath,
          '${tmp.path}/out.bin',
        ),
        throwsA(isA<ZstdStreamException>()),
      );
      expect(File('${tmp.path}/out.bin').existsSync(), isFalse);
    });

    test('קובץ שאינו zstd כלל נדחה עם הודעת השגיאה של libzstd', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }

      final junkPath = '${tmp.path}/junk.zst';
      File(junkPath).writeAsBytesSync(pseudoRandomBytes(4096));

      await expectLater(
        ZstdFileDecompressor.decompressFileToFile(
          junkPath,
          '${tmp.path}/out.bin',
        ),
        throwsA(isA<ZstdStreamException>()),
      );
      expect(File('${tmp.path}/out.bin').existsSync(), isFalse);
    });

    test(
      'frame תקין שתוכנו ריק מפיק קובץ באורך אפס — הקורא הוא שדוחה אותו',
      () async {
        if (bindings == null) {
          markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
          return;
        }

        // חשוב להבחנה: זה לא "קובץ ריק" (אין קלט) אלא frame תקין בלי תוכן.
        // `LibraryUpdateApplier` הוא שבודק אורך-אפס וזורק fullDbExtractionFailed.
        final compressedPath = '${tmp.path}/empty-frame.zst';
        final destPath = '${tmp.path}/out.bin';
        File(
          compressedPath,
        ).writeAsBytesSync(compressWithZstd(bindings, Uint8List(0)));

        expect(
          await ZstdFileDecompressor.decompressFileToFile(
            compressedPath,
            destPath,
          ),
          isTrue,
        );
        expect(File(destPath).lengthSync(), 0);
      },
    );

    test('מקור שאינו קיים זורק ולא מחזיר false בשקט', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }

      // `false` פירושו שאין backend טבעי; קובץ חסר אינו מצב כזה.
      // קובץ חסר הוא שגיאה אמיתית וחייב להישאר כזו.
      await expectLater(
        ZstdFileDecompressor.decompressFileToFile(
          '${tmp.path}/missing.zst',
          '${tmp.path}/out.bin',
        ),
        throwsA(isA<FileSystemException>()),
      );
    });

    test(
      'הודעות השגיאה מגיעות מ-otzaria_l10n בשפה שהועברה ל-isolate',
      () async {
        if (bindings == null) {
          markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
          return;
        }

        // הבדיקה האמיתית של ה-landmine: `AppL10n` הוא סטטי פר-isolate, ולכן
        // בלי העברת השפה פנימה ההודעה הייתה יוצאת בעברית גם בממשק באנגלית.
        AppL10n.use(AppLanguage.english);
        final emptyPath = '${tmp.path}/empty.zst';
        File(emptyPath).writeAsBytesSync(Uint8List(0));

        await expectLater(
          ZstdFileDecompressor.decompressFileToFile(
            emptyPath,
            '${tmp.path}/out.bin',
          ),
          throwsA(
            isA<ZstdStreamException>().having(
              (e) => e.message,
              'message',
              AppL10n.stringsFor(
                AppLanguage.english,
              ).libraryDomain.zstdEmptyInput,
            ),
          ),
        );
      },
    );
  });
}

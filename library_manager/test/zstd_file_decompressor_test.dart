import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/src/services/zstd_file_decompressor.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import 'support/zstd_fixtures.dart';

/// בודק את החילוץ בזרימה מול libzstd **אמיתי**.
///
/// הבדיקה מדולגת כשאין ספריית zstd לטעינה (למשל לינוקס ב-CI, או הרצת
/// `flutter test` בלי שהפלאגין של הפלטפורמה נבנה) — בדיוק המצב שבו הקוד
/// שבייצור נופל למסלול הזיכרון. ב-Windows יש להריץ עם התיקייה של
/// `zstandard_windows.dll` ב-PATH; ראו library_manager/README.md.
void main() {
  final bindings = ZstdFileDecompressor.bindingsOrNull();

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
      File(compressedPath)
          .writeAsBytesSync(compressWithZstd(bindings, original));

      expect(
        await ZstdFileDecompressor.decompressFileToFile(
          compressedPath,
          destPath,
        ),
        isTrue,
      );
      expect(File(destPath).readAsBytesSync(), original);
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
    });

    test('frame תקין שתוכנו ריק מפיק קובץ באורך אפס — הקורא הוא שדוחה אותו',
        () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }

      // חשוב להבחנה: זה לא "קובץ ריק" (אין קלט) אלא frame תקין בלי תוכן.
      // `LibraryUpdateApplier` הוא שבודק אורך-אפס וזורק fullDbExtractionFailed.
      final compressedPath = '${tmp.path}/empty-frame.zst';
      final destPath = '${tmp.path}/out.bin';
      File(compressedPath)
          .writeAsBytesSync(compressWithZstd(bindings, Uint8List(0)));

      expect(
        await ZstdFileDecompressor.decompressFileToFile(
            compressedPath, destPath),
        isTrue,
      );
      expect(File(destPath).lengthSync(), 0);
    });

    test('מקור שאינו קיים זורק ולא מחזיר false בשקט', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }

      // `false` פירושו "אין streaming בפלטפורמה" ומפעיל את מסלול הזיכרון;
      // קובץ חסר הוא שגיאה אמיתית וחייב להישאר כזו.
      await expectLater(
        ZstdFileDecompressor.decompressFileToFile(
          '${tmp.path}/missing.zst',
          '${tmp.path}/out.bin',
        ),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('הודעות השגיאה מגיעות מ-otzaria_l10n בשפה שהועברה ל-isolate',
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
        throwsA(isA<ZstdStreamException>().having(
          (e) => e.message,
          'message',
          AppL10n.stringsFor(AppLanguage.english).libraryDomain.zstdEmptyInput,
        )),
      );
    });
  });
}

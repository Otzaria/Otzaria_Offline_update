import 'dart:io';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:test/test.dart';

class _PatchDownloadException implements Exception {
  _PatchDownloadException(this.message);
  final String message;
  @override
  String toString() => 'PatchDownloadException: $message';
}

void main() {
  tearDown(() => AppL10n.use(AppLanguage.hebrew));

  // כך upstream (809ce54) עוטף: saveDownloadedFileFailed('$error') בלי cause.
  _PatchDownloadException saveFailed(int errno) => _PatchDownloadException(
        AppL10n.strings.libraryDomain.saveDownloadedFileFailed(
          FileSystemException(
            'Writing failed',
            r'D:\mirror\asset.zst.part',
            OSError('There is not enough space on the disk.\r\n', errno),
          ).toString(),
        ),
      );

  test('PatchDownloadException עם errno של כונן מלא מזוהה, עם התיקייה', () {
    for (final language in AppLanguage.values) {
      AppL10n.use(language);
      final found = storageFullFromUpstream(saveFailed(112), windows: true);
      expect(found, isNotNull, reason: '$language');
      expect(found!.dir, r'D:\mirror');
      expect(found.neededBytes, isNull);
    }
  });

  test('גישה נדחתה ושגיאות כתיבה אחרות אינן חוסר מקום', () {
    expect(storageFullFromUpstream(saveFailed(5), windows: true), isNull);
    expect(storageFullFromUpstream(saveFailed(1006), windows: true), isNull);
    expect(storageFullFromUpstream(Exception('אין רשת')), isNull);
  });

  test('StateError עם התבניות המתורגמות מזוהה בכל שפה', () {
    for (final language in AppLanguage.values) {
      AppL10n.use(language);
      final strings = AppL10n.strings.libraryDomain;
      for (final text in [
        strings.mirrorNotEnoughDiskSpace('D:', '1.6 GB', '10 MB'),
        strings.notEnoughDiskSpace('D:', '1.6 GB', '10 MB'),
      ]) {
        AppL10n.use(AppLanguage.values.firstWhere((l) => l != language));
        expect(storageFullFromUpstream(StateError(text)), isNotNull);
        AppL10n.use(language);
      }
    }
  });

  test('סיבה מובנית נשמרת כמות שהיא', () {
    const structured = StorageFullException(dir: 'D:', neededBytes: 5);
    expect(storageFullFromUpstream(structured), same(structured));
  });
  test('Windows: 1117 ו-483 (גם בשליפה באמצע) אינם "כונן פגום"', () {
    for (final errno in [1117, 483]) {
      expect(isStorageCorruptErrno(errno, windows: true), isFalse);
      expect(isStorageCorruptErrno(errno, windows: false), isFalse);
    }
    for (final errno in [1392, 1393, 23]) {
      expect(isStorageCorruptErrno(errno, windows: true), isTrue);
    }
    expect(isStorageCorruptErrno(5, windows: false), isTrue);
    expect(isStorageCorruptErrno(117, windows: false), isTrue);
  });

  // issue #159: errno 1392 בקריאת patch אחרי שליפת האונקי.
  test('errno 1392 בטקסט של המנוע הוא קובץ פגום, לא כונן מלא', () {
    final error = _PatchDownloadException(
      AppL10n.strings.libraryDomain.saveDownloadedFileFailed(
        FileSystemException(
          'readSync failed',
          r'E:\mirror\library\assets\patch-v34-v35.db.zst',
          OSError('The file or directory is corrupted and unreadable.', 1392),
        ).toString(),
      ),
    );
    final found = storageCorruptFromUpstream(error, windows: true);
    expect(found, isNotNull);
    expect(found!.dir, r'E:\mirror\library\assets');
    expect(storageFullFromUpstream(error, windows: true), isNull);
    expect(found.toString(), contains('chkdsk'));
  });

  test('טקסט מעורב: errno של רשת לפני errno של קובץ אינו מסתיר אותו', () {
    const error =
        'SocketException: reset (OS Error: Connection reset, errno = 10054) '
        "then FileSystemException: Cannot write (OS Error: corrupted, errno = 1392), path = 'E:/m/x.bin'";
    final found = storageCorruptFromUpstream(error, windows: true);
    expect(found, isNotNull);
    expect(found!.errno, 1392);
    expect(found.dir, 'E:/m');
    expect(
      storageCorruptFromUpstream(
        'SocketException: (OS Error: reset, errno = 10054)',
        windows: true,
      ),
      isNull,
    );
  });

  test('רשת, מקום חסר וגישה נדחתה אינם קובץ פגום', () {
    expect(
      storageCorruptFromUpstream(
        _PatchDownloadException(
          'ClientException with SocketException: (OS Error: x, errno = 11001)',
        ),
        windows: true,
      ),
      isNull,
    );
    for (final errno in [112, 5, 32]) {
      expect(
        storageCorruptFromUpstream(
          FileSystemException('w', r'D:\x', OSError('x', errno)),
          windows: true,
        ),
        isNull,
        reason: '$errno',
      );
    }
    expect(
      storageCorruptFromUpstream(
        FileSystemException('r', '/m/x', OSError('x', 5)),
        windows: false,
      ),
      isNotNull,
    );
  });

  test('כיתוב אימות והרכבה מזוהה כעבודה מקומית בכל שפה; הורדה לא', () {
    for (final language in AppLanguage.values) {
      AppL10n.use(language);
      final strings = AppL10n.strings.libraryDomain;
      for (final text in [
        strings.exportVerifying('v35-2026', 'patch.db.zst', 42),
        strings.exportAssembling('v35-2026', 'patch.db.zst', 7),
        strings.companionVerifying('Talmud', 100),
        strings.companionAssembling('Talmud', 30),
      ]) {
        AppL10n.use(AppLanguage.values.firstWhere((l) => l != language));
        expect(isLocalWorkStage(text), isTrue, reason: text);
        AppL10n.use(language);
      }
      expect(
        isLocalWorkStage(strings.exportDownloading('v35', 'patch.db.zst')),
        isFalse,
      );
      expect(isLocalWorkStage(strings.semanticDownloading), isFalse);
      expect(
        isLocalWorkStage(strings.companionDownloading('Talmud')),
        isFalse,
      );
    }
  });

  test('ההנחיה והקוד מתאימים למערכת ולכשל בפועל, בשתי השפות', () {
    for (final language in AppLanguage.values) {
      AppL10n.use(language);
      for (final (windows, macos, errno, tool, hint, absent) in [
        (
          true,
          false,
          1392,
          DriveCheckTool.chkdsk,
          'chkdsk',
          [
            'fsck',
            'Disk Utility',
          ]
        ),
        (true, false, 23, DriveCheckTool.chkdsk, 'chkdsk', ['fsck']),
        (false, false, 5, DriveCheckTool.fsck, 'fsck', ['chkdsk', '1392']),
        (false, false, 117, DriveCheckTool.fsck, 'fsck', ['chkdsk', '1392']),
        (
          false,
          true,
          5,
          DriveCheckTool.diskUtility,
          'Disk Utility',
          [
            'chkdsk',
            'fsck',
          ]
        ),
      ]) {
        final found = storageCorruptFromUpstream(
          FileSystemException('read', '/m/x', OSError('x', errno)),
          windows: windows,
          macos: macos,
        )!;
        expect(found.errno, errno);
        expect(found.tool, tool);
        expect(
            DriveCheckTool.forPlatform(windows: windows, macos: macos), tool);
        final text = found.toString();
        expect(text, contains(hint), reason: '$language $errno');
        expect(text, contains('$errno'), reason: '$language');
        for (final other in absent) {
          expect(text, isNot(contains(other)), reason: '$language $errno');
        }
      }
      final mac = StorageCorruptException(
        dir: '/Volumes/X',
        errno: 5,
        tool: DriveCheckTool.diskUtility,
      ).toString();
      expect(mac, contains('Disk Utility'));
      expect(mac, isNot(contains('chkdsk')));
      final strings = AppL10n.strings.task;
      final body = strings.driveDamagedBodyFor(DriveCheckTool.fsck, 117);
      expect(body, contains('117'));
      expect(body, isNot(contains('1392')));
      expect(body, isNot(contains('chkdsk')));
    }
  });

  test('האיתור מהטקסט של המנוע מעביר את ה-errno האמיתי', () {
    final found = storageCorruptFromUpstream(
      _PatchDownloadException(
        FileSystemException(
          'readSync failed',
          '/m/p.zst',
          OSError('Input/output error', 5),
        ).toString(),
      ),
      windows: false,
    )!;
    expect(found.errno, 5);
    expect(found.toString(), isNot(contains('1392')));
  });

  group('isLocalWorkStage', () {
    // שם נכס שנראה כמו כיתוב אימות בשתי השפות.
    const verifyLookalikes = ['מאמת x — 5%', 'Verifying x — 5%'];

    test('מזהה כל תבנית ושורות מרובות, בכל שפת מקור ויעד', () {
      for (final source in AppLanguage.values) {
        final s = AppL10n.stringsFor(source).libraryDomain;
        final lines = [
          s.exportVerifying('v35', 'a.zst', 100),
          s.exportAssembling('v35', 'b.zst', 0),
          s.companionVerifying('Talmud', 7),
          s.companionAssembling('Talmud', 30),
        ];
        for (final target in AppLanguage.values) {
          AppL10n.use(target);
          for (final line in lines) {
            expect(isLocalWorkStage(line), isTrue, reason: line);
          }
          expect(isLocalWorkStage(lines.join('\n')), isTrue);
        }
      }
    });

    test('שם נכס שמכיל תבנית אימות אינו הופך הורדה לעבודה מקומית', () {
      for (final language in AppLanguage.values) {
        final s = AppL10n.stringsFor(language).libraryDomain;
        for (final name in verifyLookalikes) {
          for (final text in [
            s.companionDownloading(name),
            s.exportDownloading('v35', name),
            s.exportDownloading(name, 'a.zst'),
            'prefix ${s.companionVerifying('x', 5)}',
            '${s.companionVerifying('x', 5)} suffix',
          ]) {
            expect(isLocalWorkStage(text), isFalse, reason: text);
          }
        }
        expect(isLocalWorkStage(''), isFalse);
        expect(
          isLocalWorkStage(
              '${s.semanticDownloading}\n${s.exportVerifying('v', 'a', 5)}'),
          isFalse,
        );
      }
    });

    test('שם נכס כזה בתוך כיתוב אימות אמיתי עדיין מזוהה', () {
      for (final language in AppLanguage.values) {
        final s = AppL10n.stringsFor(language).libraryDomain;
        expect(isLocalWorkStage(s.companionVerifying('Verifying x — 5%', 9)),
            isTrue);
      }
    });
  });
}

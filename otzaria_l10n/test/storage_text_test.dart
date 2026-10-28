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
}

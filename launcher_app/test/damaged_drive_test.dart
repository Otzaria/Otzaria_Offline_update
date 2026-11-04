import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/download_plan.dart';
import 'package:launcher_app/src/shell/download_failure.dart';
import 'package:launcher_app/src/shell/shell_tasks.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

// issue #159: errno 1392 בקריאת patch אחרי שליפת האונקי.
void main() {
  const path = r'E:\mirror\library\assets\patch-v34-v35.db.zst';
  final errno = Platform.isWindows ? 1392 : 5;
  final error = FileSystemException(
    'readSync failed',
    path,
    OSError('The file or directory is corrupted and unreadable.', errno),
  );
  final text =
      AppL10n.strings.libraryDomain.saveDownloadedFileFailed(error.toString());

  DownloadFailure classify(String error, [Object? cause]) =>
      classifyDownloadFailure(
        failed: const [MirrorComponent.library],
        errors: {MirrorComponent.library: error},
        causes: {MirrorComponent.library: cause},
        shabbat: false,
      );

  test('קוד נזק בטקסט של המנוע: כונן פגום, לא רשת ולא מקום', () {
    final failure = classify(text);
    expect(failure.kind, DownloadFailureKind.driveDamaged);
    expect(failure.dir, r'E:\mirror\library\assets');
    expect(failure.tool, DriveCheckTool.forPlatform());
  });

  test('errno והכלי של המערכת עוברים כמו שהם', () {
    final failure = classify(
      'whatever',
      StorageCorruptException(errno: 5, tool: DriveCheckTool.diskUtility),
    );
    expect(failure.errno, 5);
    expect(failure.tool, DriveCheckTool.diskUtility);
    expect(classify(text).errno, errno);
  });

  test('סיבה מובנית קודמת לטקסט, גם בתוך שרשרת', () {
    final cause = StorageCorruptException(dir: r'E:\x');
    expect(
      classify('whatever', cause).kind,
      DownloadFailureKind.driveDamaged,
    );
  });

  test('ניתוק רשת וכונן מלא נשארים כפי שהיו', () {
    expect(
      classify('ClientException with SocketException: (errno = 11001)').kind,
      DownloadFailureKind.network,
    );
    expect(
      classify(
        AppL10n.strings.libraryDomain
            .mirrorNotEnoughDiskSpace('E:', '2 GB', '1 GB'),
      ).kind,
      DownloadFailureKind.diskSpace,
    );
  });

  group('קדימות הסיווג: דיסק מלא > פגום > מסנן > רשת > שבת', () {
    final damaged = StorageCorruptException(dir: r'E:\x', errno: 1392);
    const full = StorageFullException(dir: r'E:\x');
    const blocked = 'CERTIFICATE_VERIFY_FAILED';
    const network = 'SocketException: Failed host lookup';

    DownloadFailureKind kind(
      Map<MirrorComponent, String> errors, {
      Map<MirrorComponent, Object?> causes = const {},
      bool shabbat = false,
    }) =>
        classifyDownloadFailure(
          failed: errors.keys.toList(),
          errors: errors,
          causes: causes,
          shabbat: shabbat,
        ).kind;

    const lib = MirrorComponent.library;
    const app = MirrorComponent.app;
    const plugins = MirrorComponent.plugins;

    test('דיסק מלא גובר על פגום, גם ברכיבים שונים', () {
      expect(
        kind({lib: 'x', app: 'y'}, causes: {lib: damaged, app: full}),
        DownloadFailureKind.diskSpace,
      );
    });

    test('פגום גובר על מסנן ועל רשת', () {
      expect(
        kind({lib: blocked, app: network}, causes: {app: damaged}),
        DownloadFailureKind.driveDamaged,
      );
    });

    test('מסנן גובר על רשת', () {
      expect(
        kind({lib: network, app: blocked}),
        DownloadFailureKind.blocked,
      );
    });

    test('רשת גוברת על שבת; שבת לבדה היא שבת', () {
      expect(
        kind({lib: network, plugins: 'closed'}, shabbat: true),
        DownloadFailureKind.network,
      );
      expect(
        kind({plugins: 'closed'}, shabbat: true),
        DownloadFailureKind.shabbat,
      );
    });
  });
}

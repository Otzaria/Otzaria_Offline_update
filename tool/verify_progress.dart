// אימות end-to-end של דיווח ההתקדמות ב-compute על DB אמיתי: מדפיס את זרם
// הדיווחים ואת הסך הסופי (לזריעת verify_total_bytes.txt). כלי זמני.
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart'
    show LogicalContentHasher;

void main(List<String> args) {
  final dbPath = args.isNotEmpty
      ? args[0]
      : r'C:\Users\User\AppData\Roaming\otzaria\Downloads\seforim.db';

  if (!File(dbPath).existsSync()) {
    print('שגיאה: קובץ ה-DB לא נמצא בנתיב: $dbPath');
    print('שימוש: dart tool/verify_progress.dart <path_to_seforim.db>');
    exitCode = 1;
    return;
  }

  final db = sqlite3.open(dbPath, mode: OpenMode.readOnly);

  var reports = 0;
  var last = 0;
  final sw = Stopwatch()..start();
  final hash = const LogicalContentHasher().compute(db, onProgress: (bytes) {
    reports++;
    last = bytes;
    if (reports % 20 == 0) {
      print('  report #$reports: ${(bytes / (1 << 20)).toStringAsFixed(0)}MB '
          '(${sw.elapsed.inSeconds}s)');
    }
  });
  sw.stop();

  print('hash=$hash');
  print('reports=$reports');
  print('TOTAL_BYTES=$last');
  print('elapsed=${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s');
  db.close();
}

import 'dart:io';

import 'package:seforim_library_updater/src/services/logical_content_hasher.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// כלי עזר: מחשב את ה-logical content hash של DB נתון ומדפיס אותו.
void main(List<String> args) {
  final db = sqlite3.sqlite3.open(args.single, mode: sqlite3.OpenMode.readOnly);
  try {
    final sw = Stopwatch()..start();
    final hash = const LogicalContentHasher().compute(db);
    stdout.writeln('$hash  ${args.single}  (${sw.elapsed})');
  } finally {
    db.close();
  }
}

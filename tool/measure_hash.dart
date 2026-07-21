// כלי אבחון זמני: מודד לכל טבלה ב-hash את תוכנית השאילתה (מיון?), מספר השורות,
// הבתים והזמן — לזיהוי הטבלה שתוקעת את verifyToHash. אינו חלק מה-API.
import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart'
    show kHashTableOrder;

void main(List<String> args) {
  final dbPath = args.isNotEmpty
      ? args[0]
      : r'C:\Users\User\AppData\Roaming\otzaria\Downloads\seforim.db';

  if (!File(dbPath).existsSync()) {
    print('שגיאה: קובץ ה-DB לא נמצא בנתיב: $dbPath');
    print('שימוש: dart tool/measure_hash.dart <path_to_seforim.db>');
    exitCode = 1;
    return;
  }

  final db = sqlite3.open(dbPath, mode: OpenMode.readOnly);

  print('DB: $dbPath\n');

  // שלב 1 — תוכניות שאילתה (מיידי): מי עושה TEMP B-TREE (מיון).
  print('== EXPLAIN QUERY PLAN (מיון = TEMP B-TREE) ==');
  final sorters = <String>[];
  for (final table in kHashTableOrder) {
    final cols = _cols(db, table);
    if (cols == null) {
      print('  $table: (לא קיימת)');
      continue;
    }
    final sql = _buildSql(table, cols);
    final plan = db.select('EXPLAIN QUERY PLAN $sql');
    final detail = plan.map((r) => r['detail'].toString()).join(' | ');
    final sorts = detail.toUpperCase().contains('B-TREE');
    if (sorts) sorters.add(table);
    print('  ${sorts ? "★ מיון" : "       "}  $table  →  $detail');
  }
  print('\nטבלאות עם מיון: ${sorters.isEmpty ? "אין" : sorters.join(", ")}\n');

  // שלב 2 — timing per-table (קורא את כל הנתונים כמו ה-hash האמיתי).
  print('== TIMING (קריאה מלאה כמו verifyToHash) ==');
  final total = Stopwatch()..start();
  for (final table in kHashTableOrder) {
    final cols = _cols(db, table);
    if (cols == null) continue;
    final sql = _buildSql(table, cols);
    final sw = Stopwatch()..start();
    var rows = 0;
    var bytes = 0;
    final stmt = db.prepare(sql);
    final cursor = stmt.selectCursor(const []);
    while (cursor.moveNext()) {
      final values = cursor.current.values;
      for (var i = 0; i < values.length; i += 2) {
        final v = values[i + 1];
        if (v is Uint8List) {
          bytes += v.length;
        } else if (v != null) {
          bytes += v.toString().length;
        }
      }
      rows++;
    }
    stmt.close();
    sw.stop();
    final mb = (bytes / (1 << 20)).toStringAsFixed(1);
    print('  ${sw.elapsedMilliseconds.toString().padLeft(7)}ms  '
        'rows=${rows.toString().padLeft(9)}  ${mb.padLeft(8)}MB  $table');
  }
  total.stop();
  print('\nסה"כ: ${(total.elapsedMilliseconds / 1000).toStringAsFixed(1)}s');
  db.close();
}

List<String>? _cols(Database db, String table) {
  final r = db.select('PRAGMA table_info("$table")');
  if (r.isEmpty) return null;
  final names = r.map((e) => e['name'] as String).toList()..sort();
  return names;
}

String _buildSql(String table, List<String> cols) {
  final selectCols = cols
      .map((c) => 'typeof("$c"),CASE WHEN typeof("$c")=\'text\' '
          'THEN CAST("$c" AS BLOB) ELSE "$c" END')
      .join(',');
  final orderBy =
      cols.contains('id') ? 'id' : cols.map((c) => '"$c"').join(',');
  return 'SELECT $selectCols FROM "$table" ORDER BY $orderBy';
}

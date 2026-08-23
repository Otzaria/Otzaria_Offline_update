// כלי אבחון זמני: בונה מסד סינתטי בפרופורציות המסד האמיתי ומודד את קצב
// `LogicalContentHasher.compute`. אינו חלק מה-API.
// ignore_for_file: avoid_print — כלי CLI אבחוני; ההדפסה היא הפלט המיועד שלו.
import 'dart:io';

import 'package:seforim_library_updater/src/services/logical_content_hasher.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main(List<String> args) {
  final rows = args.isNotEmpty ? int.parse(args[0]) : 400000;
  final path = '${Directory.systemTemp.path}/bench_hash_$rows.db';
  final file = File(path);
  if (!file.existsSync()) {
    print('בונה מסד סינתטי ($rows שורות ב-line)...');
    final db = sqlite3.sqlite3.open(path);
    db.execute('PRAGMA journal_mode=OFF');
    db.execute('PRAGMA synchronous=OFF');
    db.execute('CREATE TABLE line (id INTEGER PRIMARY KEY, bookId INTEGER, '
        'lineIndex INTEGER, charStart INTEGER, charEnd INTEGER, text TEXT)');
    db.execute('CREATE TABLE link_coverage (lineId INTEGER, linkId INTEGER, '
        'side INTEGER)');
    db.execute('CREATE TABLE line_toc (lineId INTEGER, tocEntryId INTEGER)');
    db.execute('BEGIN');
    final line = db.prepare('INSERT INTO line VALUES (?,?,?,?,?,?)');
    final cov = db.prepare('INSERT INTO link_coverage VALUES (?,?,?)');
    final toc = db.prepare('INSERT INTO line_toc VALUES (?,?)');
    // טקסט עברי באורך משתנה — כמו שורות גמרא/מפרשים אמיתיות.
    const base = 'אמר רבי יוחנן משום רבי שמעון בן יוחאי כל המקיים את התורה ';
    for (var i = 1; i <= rows; i++) {
      line.execute(
          [i, i % 5000, i % 900, i * 7, i * 7 + 120, base * (1 + i % 4)]);
      cov.execute([i, i * 3, i % 2]);
      toc.execute([i, i % 100000]);
    }
    db.execute('COMMIT');
    line.close();
    cov.close();
    toc.close();
    db.close();
  }
  print('מסד: $path (${(file.lengthSync() / (1 << 20)).toStringAsFixed(0)}MB)');

  const hasher = LogicalContentHasher();
  for (var round = 1; round <= 3; round++) {
    final db = sqlite3.sqlite3.open(path, mode: sqlite3.OpenMode.readOnly);
    var bytes = 0;
    final sw = Stopwatch()..start();
    final hash = hasher.compute(db, onProgress: (b) => bytes = b);
    sw.stop();
    db.close();
    final mb = bytes / (1 << 20);
    print('סבב $round: ${sw.elapsedMilliseconds}ms  '
        '${mb.toStringAsFixed(0)}MB לוגיים  '
        '${(mb / (sw.elapsedMilliseconds / 1000)).toStringAsFixed(1)} MB/s  '
        'hash=${hash.substring(0, 16)}');
  }
}

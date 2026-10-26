// החלטת המשתמש: אין "התקנת גרסה ישנה יותר" בשום מקום. כשהמחשב מעודכן יותר
// מהכונן — מצב רגוע בלי פעולה (ראו screens_test), וגם החלפת ערוץ אינה מורידה
// גרסה (otzaria_controller_test). כאן: שום שריד בקוד ובמלל.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _olderPhrase = r'(?:להתקין גרסה ישנה|התקנת גרסה ישנה|לחזור לגרסה'
    r'|install (?:an |the )?older|Install the folder version)';

/// שמות קוד, ומחרוזת שמציעה להתקין גרסה ישנה — לא הערה שמזכירה זאת.
final _forbidden = RegExp(
  r'installOlder|_Install\.older'
  "|'[^'\\n]*$_olderPhrase[^'\\n]*'"
  '|"[^"\\n]*$_olderPhrase[^"\\n]*"',
  caseSensitive: false,
);

void main() {
  final appLib = Directory('lib');
  final l10nLib = Directory(p.join('..', 'otzaria_l10n', 'lib'));

  Iterable<File> dartFiles(Directory dir) => dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  test('אין מסלול התקנה של גרסה ישנה — לא בקוד ולא במחרוזות', () {
    final files = [...dartFiles(appLib), ...dartFiles(l10nLib)];
    expect(files, isNotEmpty);
    final offenders = [
      for (final file in files)
        if (_forbidden.hasMatch(file.readAsStringSync())) file.path,
    ];
    expect(offenders, isEmpty);
  });

  test('הבדיקה תופסת ניסוח חדש, ולא הערה תמימה', () {
    expect(_forbidden.hasMatch("  String get x => 'התקנת גרסה ישנה יותר';"),
        isTrue);
    expect(
      _forbidden.hasMatch("  String get x => 'Install an older version';"),
      isTrue,
    );
    expect(
      _forbidden.hasMatch("  String get x => 'Install older version';"),
      isTrue,
    );
    expect(
      _forbidden.hasMatch('  String get x => "להתקין גרסה ישנה";'),
      isTrue,
    );
    expect(_forbidden.hasMatch('  void installOlder() {}'), isTrue);
    expect(_forbidden.hasMatch('// אין נסיגת גרסה, גם לא במעבר ערוץ'), isFalse);
  });
}

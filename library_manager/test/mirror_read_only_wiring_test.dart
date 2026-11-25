import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// סריקת מקור: בדיקה התנהגותית באתרים הסמנטיים דורשת קבצי מודל בגודל ייצור.
/// ה-applier נבדק גם בהתנהגות ב-`library_manager_test.dart`.
void main() {
  final source = File('lib/src/library_manager.dart').readAsStringSync();

  List<String> constructions(String type) {
    final found = <String>[];
    var from = 0;
    while (true) {
      final start = source.indexOf('$type(', from);
      if (start < 0) break;
      var depth = 0;
      var end = start + type.length;
      for (; end < source.length; end++) {
        final c = source[end];
        if (c == '(') depth++;
        if (c == ')' && --depth == 0) break;
      }
      found.add(source.substring(start, end + 1));
      from = end;
    }
    return found;
  }

  test('כל בנייה של SemanticSearchAssets מעבירה mirrorReadOnly', () {
    final all = constructions('SemanticSearchAssets');
    expect(all.length, 4);
    for (final construction in all) {
      expect(construction, contains('mirrorReadOnly: mirrorReadOnly'));
    }
  });

  test('בניית ה-applier ברירת המחדל מעבירה mirrorReadOnly', () {
    final all = constructions('LibraryUpdateApplier');
    expect(all, hasLength(1));
    expect(all.single, contains('mirrorReadOnly: mirrorReadOnly'));
  });
}

import 'dart:io';

import 'package:seforim_library_updater/src/models/patch_table_spec.dart';
import 'package:seforim_library_updater/src/services/patch_applier.dart';
import 'package:test/test.dart';

/// מסדר את חוזה טבלאות ה-patch לצורתו הקנונית — זהה בייצור (Kotlin) ובחבילה.
/// סדר מפתחות קבוע, שמירה על סדר ה-FK/hash (בלי מיון), UTF-8, שורה חדשה בסוף.
String canonicalContract(
  List<PatchTableSpec> fkOrder,
  List<String> hashOrder,
  int schemaVersion,
) {
  final b = StringBuffer();
  b.write('{\n');
  b.write('  "schemaVersion": $schemaVersion,\n');
  b.write('  "fkOrder": [\n');
  for (var i = 0; i < fkOrder.length; i++) {
    final t = fkOrder[i];
    final pk = t.primaryKey.map((c) => '"$c"').join(', ');
    b.write('    { "table": "${t.name}", "pk": [$pk], '
        '"updatable": ${t.updatable} }');
    if (i != fkOrder.length - 1) b.write(',');
    b.write('\n');
  }
  b.write('  ],\n');
  b.write('  "hashOrder": [\n');
  for (var i = 0; i < hashOrder.length; i++) {
    b.write('    "${hashOrder[i]}"');
    if (i != hashOrder.length - 1) b.write(',');
    b.write('\n');
  }
  b.write('  ]\n');
  b.write('}\n');
  return b.toString();
}

void main() {
  group('חוזה טבלאות ה-patch', () {
    const fixturePath = 'test/patch_tables_contract.json';

    // ה-fixture מתאר את החוזה הנוכחי (סכמה-2): hashOrder = 34 הטבלאות.
    // kHashTableOrderSchema1 (33) הוא היסטוריה קפואה של Dart בלבד — לא נכנס
    // ל-fixture ואין לו תאום Kotlin.
    test('הסריאליזציה הקנונית תואמת ל-fixture המקומי', () {
      final expected = File(fixturePath).readAsStringSync();
      final actual = canonicalContract(
        kPatchTablesInFkOrder,
        kHashTableOrder,
        const PatchApplier().supportedSchemaVersion,
      );
      expect(actual, expected,
          reason: 'הרשימות סטו מה-fixture — הרץ מחדש את מחולל החוזה');
    });

    // גשר בין המאגרים: משווה בתים מול ה-fixture של Kotlin. מדולג ללא ה-env,
    // באותה תבנית של בדיקות ה-E2E שדורשות SEFORIM_LIBRARY_RELEASES_DIR.
    test('ה-fixture זהה בתים ל-fixture של SeforimLibrary', () {
      final repo = Platform.environment['SEFORIM_LIBRARY_REPO'];
      if (repo == null || repo.isEmpty) {
        markTestSkipped('הגדר SEFORIM_LIBRARY_REPO להשוואה מול צד ה-Kotlin');
        return;
      }
      final kotlinFixture = File('$repo/generator/common/src/jvmTest/'
          'resources/patch_tables_contract.json');
      if (!kotlinFixture.existsSync()) {
        markTestSkipped('fixture של Kotlin לא נמצא ב-$repo');
        return;
      }
      final local = File(fixturePath).readAsBytesSync();
      final remote = kotlinFixture.readAsBytesSync();
      expect(remote, local, reason: 'שני עותקי ה-fixture חייבים להיות זהים בתים');
    });
  });
}

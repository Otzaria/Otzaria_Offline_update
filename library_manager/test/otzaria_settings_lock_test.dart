import 'dart:async';

import 'package:library_manager/library_manager.dart';
import 'package:test/test.dart';

void main() {
  test('התור של קופסאות אוצריא: אזור שנעצר אחרי שהפעולה שלו הסתיימה אינו '
      'חוסם את מי שבא אחריו', () async {
    // כמו זמן מדומה של בדיקה שהסתיימה: אחרי "מוות" אף microtask שלו לא רץ.
    var dead = false;
    final zone = Zone.current.fork(
      specification: ZoneSpecification(
        scheduleMicrotask: (self, parent, zone, task) {
          if (!dead) parent.scheduleMicrotask(zone, task);
        },
      ),
    );
    await zone.run(() => OtzariaSettingsReader.runExclusively(() async => 1));
    // שהשחרור יושלם קודם — ההמשך הבא נרשם על עתיד שכבר הושלם.
    await Future<void>.delayed(Duration.zero);
    dead = true;

    final next = await OtzariaSettingsReader.runExclusively(
      () async => 2,
    ).timeout(const Duration(seconds: 5));
    expect(next, 2);
  });
}

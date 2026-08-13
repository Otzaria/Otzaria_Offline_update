import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late String root;
  late KnownLocationsStore store;

  setUp(() {
    root = tempMirrorRoot();
    store = KnownLocationsStore(KnownLocationsStore.pathIn(root));
  });

  group('דירוג המיקומים', () {
    test('המיקום שחוזר על עצמו בהכי הרבה מחשבים מוביל', () {
      final ranked = KnownLocationsStore.rank(const {
        'PC-1': r'C:\Program Files\MyApp',
        'PC-2': r'C:\Program Files\MyApp',
        'PC-3': r'C:\Program Files\MyApp',
        'PC-4': r'D:\Apps\MyApp',
      });

      expect(ranked.first, r'C:\Program Files\MyApp');
      expect(ranked, hasLength(2));
    });

    test('שוויון נשבר אלפביתית — אותה תשובה בכל מחשב', () {
      final ranked = KnownLocationsStore.rank(const {
        'PC-1': r'D:\Second',
        'PC-2': r'C:\First',
      });
      expect(ranked, [r'C:\First', r'D:\Second']);
    });

    test('ריק מחזיר רשימה ריקה', () {
      expect(KnownLocationsStore.rank(const {}), isEmpty);
    });
  });

  group('שמירה וטעינה', () {
    test('קובץ שאינו קיים אינו שגיאה', () async {
      expect(await store.load(), isEmpty);
    });

    test('רישום נשמר תחת שם המחשב', () async {
      await store.record(r'C:\Apps\X', hostName: 'PC-1');
      expect(await store.load(), {'PC-1': r'C:\Apps\X'});
    });

    test('כל מחשב שורה אחת — רישום חוזר מעדכן ולא מוסיף', () async {
      await store.record(r'C:\Apps\X', hostName: 'PC-1');
      await store.record(r'D:\Apps\X', hostName: 'PC-1');
      expect(await store.load(), {'PC-1': r'D:\Apps\X'});
    });

    test('כמה מחשבים נצברים', () async {
      await store.record(r'C:\Apps\X', hostName: 'PC-1');
      await store.record(r'C:\Apps\X', hostName: 'PC-2');
      await store.record(r'D:\Apps\X', hostName: 'PC-3');

      final seen = await store.load();
      expect(seen, hasLength(3));
      expect(KnownLocationsStore.rank(seen).first, r'C:\Apps\X');
    });

    test('קובץ פגום אינו שובר את הזיהוי', () async {
      writeFile(KnownLocationsStore.pathIn(root), 'לא JSON');
      expect(await store.load(), isEmpty);
    });

    test('הקובץ יושב בתוך תיקיית התוכנה', () {
      expect(
        KnownLocationsStore.pathIn(r'C:\mirror\apps\demo'),
        p.join(r'C:\mirror\apps\demo', 'locations.json'),
      );
    });
  });
}

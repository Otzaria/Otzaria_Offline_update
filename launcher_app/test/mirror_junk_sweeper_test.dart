import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/services/mirror_junk_sweeper.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  String data(String relative) =>
      p.joinAll([temp.path, ...relative.split('/')]);

  /// קובץ בגודל נתון — הגודל הוא מה שהניקוי סופר.
  void file(String relative, {int bytes = 10}) {
    final target = File(data(relative));
    target.parent.createSync(recursive: true);
    target.writeAsBytesSync(List.filled(bytes, 0));
  }

  void json(String relative, Map<String, dynamic> content) {
    final target = File(data(relative));
    target.parent.createSync(recursive: true);
    target.writeAsStringSync(jsonEncode(content));
  }

  bool exists(String relative) =>
      File(data(relative)).existsSync() ||
      Directory(data(relative)).existsSync();

  Future<int> sweep() => MirrorJunkSweeper(dataDir: temp.path).sweep();

  /// `releases.json` שמכיר נכס אחד בלבד, תחת התג [tag].
  void libraryManifest({String tag = 'v27', String asset = 'patch.db.zst'}) =>
      json('mirror/library/releases.json', {
        'formatVersion': 1,
        'releases': [
          {
            'tag': tag,
            'isPrerelease': false,
            'isDraft': false,
            'assets': [
              {
                'name': asset,
                'downloadUrl': 'assets/$tag/$asset',
                'size': 10,
              },
            ],
          },
        ],
      });

  setUp(() => temp = Directory.systemTemp.createTempSync('junk_sweeper_test'));
  tearDown(() => temp.deleteSync(recursive: true));

  group('ספרייה', () {
    test('גרסה שנפלה מהמניפסט נמחקת, והנוכחית — על קובץ הצד שלה — נשארת',
        () async {
      libraryManifest();
      file('mirror/library/assets/v27/patch.db.zst', bytes: 30);
      file('mirror/library/assets/v27/patch.db.zst.resume', bytes: 5);
      // המסד המלא של גרסה ישנה — בדיוק מה שדווח בפורום (#310).
      file('mirror/library/assets/v20/seforim.db.zst', bytes: 100);

      expect(await sweep(), 100);
      expect(exists('mirror/library/assets/v27/patch.db.zst'), isTrue);
      expect(exists('mirror/library/assets/v27/patch.db.zst.resume'), isTrue);
      expect(exists('mirror/library/assets/v20'), isFalse);
    });

    test('נכס עודף בתוך תג שכן במניפסט נמחק לבדו', () async {
      libraryManifest();
      file('mirror/library/assets/v27/patch.db.zst');
      file('mirror/library/assets/v27/seforim.db.zst', bytes: 70);

      expect(await sweep(), 70);
      expect(exists('mirror/library/assets/v27/patch.db.zst'), isTrue);
      expect(exists('mirror/library/assets/v27/seforim.db.zst'), isFalse);
    });

    test('בלי מניפסט קריא — לא נוגעים בכלום', () async {
      file('mirror/library/assets/v20/seforim.db.zst', bytes: 100);

      expect(await sweep(), 0);
      expect(exists('mirror/library/assets/v20/seforim.db.zst'), isTrue);

      // וגם מניפסט פגום אינו "קבוצת שמירה ריקה".
      File(data('mirror/library/releases.json'))
          .writeAsStringSync('{ not json');
      expect(await sweep(), 0);
      expect(exists('mirror/library/assets/v20/seforim.db.zst'), isTrue);
    });
  });

  group('תוכנת אוצריא', () {
    void appManifest() => json('mirror/app/latest-release.json', {
          'schemaVersion': 2,
          'stable': {
            'tagName': 'v0.9.97',
            'installerPath': 'installers/v0.9.97/OtzariaSetup.exe',
          },
        });

    test('תג ישן נמחק, וחבילת FULL שנשארה לצד המתקין הנוכחי איתו', () async {
      appManifest();
      file('mirror/app/installers/v0.9.97/OtzariaSetup.exe', bytes: 70);
      file('mirror/app/installers/v0.9.97/OtzariaFullSetup.exe', bytes: 2000);
      file('mirror/app/installers/v0.9.90/OtzariaSetup.exe', bytes: 60);

      expect(await sweep(), 2060);
      expect(exists('mirror/app/installers/v0.9.97/OtzariaSetup.exe'), isTrue);
      expect(exists('mirror/app/installers/v0.9.90'), isFalse);
    });

    test('הפורמט הישן (רשומה בודדת בשורש) נקרא גם הוא', () async {
      json('mirror/app/latest-release.json', {
        'tagName': 'v0.9.97',
        'installerPath': 'installers/v0.9.97/OtzariaSetup.exe',
      });
      file('mirror/app/installers/v0.9.97/OtzariaSetup.exe');
      file('mirror/app/installers/v0.9.90/OtzariaSetup.exe', bytes: 60);

      expect(await sweep(), 60);
      expect(exists('mirror/app/installers/v0.9.97/OtzariaSetup.exe'), isTrue);
    });
  });

  group('תוספים', () {
    void catalog() => json('mirror/plugins/catalog.json', {
          'plugins': [
            {
              'id': 'a',
              'version': '1.1',
              'image': 'files/a/image.png',
              'localFiles': {
                '1.1': {'path': 'files/a/plugin-1.1.otzplugin'},
              },
            },
          ],
        });

    test('תוסף שהוסר מהחנות, ובילד ישן של תוסף שנשאר', () async {
      catalog();
      file('mirror/plugins/files/a/plugin-1.1.otzplugin');
      file('mirror/plugins/files/a/image.png');
      file('mirror/plugins/files/a/plugin-1.0.otzplugin', bytes: 40);
      file('mirror/plugins/files/b/plugin-2.0.otzplugin', bytes: 80);

      expect(await sweep(), 120);
      expect(exists('mirror/plugins/files/a/plugin-1.1.otzplugin'), isTrue);
      expect(exists('mirror/plugins/files/a/image.png'), isTrue);
      expect(exists('mirror/plugins/files/a/plugin-1.0.otzplugin'), isFalse);
      expect(exists('mirror/plugins/files/b'), isFalse);
    });

    test('קטלוג ריק אינו עילה למחוק את כל החנות', () async {
      json('mirror/plugins/catalog.json', {'plugins': <Object>[]});
      file('mirror/plugins/files/a/plugin-1.1.otzplugin', bytes: 40);

      expect(await sweep(), 0);
      expect(exists('mirror/plugins/files/a/plugin-1.1.otzplugin'), isTrue);
    });
  });

  test('נכס נלווה שהוחלף נמחק, והמניפסט עצמו נשאר', () async {
    json('mirror/companions/companions.json', {
      'formatVersion': 1,
      'catalog': {'fileName': 'otzar-HB_catalog.db.zst', 'size': 10},
    });
    file('mirror/companions/otzar-HB_catalog.db.zst');
    file('mirror/companions/otzar-HB_catalog.db', bytes: 500);

    expect(await sweep(), 500);
    expect(exists('mirror/companions/companions.json'), isTrue);
    expect(exists('mirror/companions/otzar-HB_catalog.db.zst'), isTrue);
    expect(exists('mirror/companions/otzar-HB_catalog.db'), isFalse);
  });

  test("גרסת לאנצ'ר ישנה נמחקת", () async {
    json('mirror/launcher/latest-release.json', {
      'schemaVersion': 1,
      'release': {'tagName': 'v0.19'},
      'filePath': 'files/v0.19/launcher.exe',
    });
    file('mirror/launcher/files/v0.19/launcher.exe');
    file('mirror/launcher/files/v0.17/launcher.exe', bytes: 90);

    expect(await sweep(), 90);
    expect(exists('mirror/launcher/files/v0.19/launcher.exe'), isTrue);
    expect(exists('mirror/launcher/files/v0.17'), isFalse);
  });

  test('תוכנות שהמשתמש הוסיף והתקנה ישנה על הכונן אינן נגעות לעולם', () async {
    libraryManifest();
    file('mirror/library/assets/v20/seforim.db.zst', bytes: 100);
    file('mirror/apps/something/installer.exe', bytes: 300);
    file('otzaria-app/otzaria.exe', bytes: 400);
    file('launcher.log', bytes: 20);

    expect(await sweep(), 100);
    expect(exists('mirror/apps/something/installer.exe'), isTrue);
    expect(exists('otzaria-app/otzaria.exe'), isTrue);
    expect(exists('launcher.log'), isTrue);
  });

  test('דיווחי טעויות שטרם נשלחו אינם נגעים — הם מחוץ ל-mirror/', () async {
    libraryManifest();
    file('reports/outbox/r1.json', bytes: 50);

    await sweep();
    expect(exists('reports/outbox/r1.json'), isTrue);
  });

  test('תיקיית נתונים ריקה אינה שגיאה', () async {
    expect(await sweep(), 0);
  });
}

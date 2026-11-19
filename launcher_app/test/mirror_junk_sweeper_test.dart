import 'dart:async';
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
    test('רשומת גרסה ללא נכסים אינה מתירה מחיקת כל הספרייה', () async {
      json('mirror/library/releases.json', {
        'releases': [
          {'tag': 'v27'}
        ],
      });
      file('mirror/library/assets/v27/seforim.db.zst', bytes: 100);

      expect(await sweep(), 0);
      expect(exists('mirror/library/assets/v27/seforim.db.zst'), isTrue);
    });

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
    for (final invalidPath in [null, '', 42]) {
      test('נתיב מתקין פגום ($invalidPath) אינו מתיר מחיקה', () async {
        json('mirror/app/latest-release.json', {
          'latest': {'tagName': 'v0.9.97', 'installerPath': invalidPath},
        });
        file('mirror/app/installers/v0.9.97/OtzariaSetup.exe');
        file('mirror/app/installers/v0.9.90/OtzariaSetup.exe');

        expect(await sweep(), 0);
        expect(
            exists('mirror/app/installers/v0.9.97/OtzariaSetup.exe'), isTrue);
        expect(
            exists('mirror/app/installers/v0.9.90/OtzariaSetup.exe'), isTrue);
      });
    }

    test('ערוץ פגום לצד ערוץ תקין אינו מתיר מחיקת המתקין שלו', () async {
      json('mirror/app/latest-release.json', {
        'latest': {
          'tagName': 'v0.9.97',
          'installerPath': 'installers/v0.9.97/OtzariaSetup.exe',
        },
        'prerelease': 'damaged',
      });
      file('mirror/app/installers/v0.9.97/OtzariaSetup.exe');
      file('mirror/app/installers/v0.9.98/OtzariaSetup.exe');

      expect(await sweep(), 0);
      expect(exists('mirror/app/installers/v0.9.98/OtzariaSetup.exe'), isTrue);
    });

    void appManifest() => json('mirror/app/latest-release.json', {
          'schemaVersion': 3,
          'source': 'github-latest',
          'latest': {
            'tagName': 'v0.9.97',
            'installerPath': 'installers/v0.9.97/OtzariaSetup.exe',
          },
        });

    test(
      'sweep measures each stale file once without a recursive pre-scan',
      () async {
        appManifest();
        file('mirror/app/installers/v0.9.97/OtzariaSetup.exe', bytes: 70);
        file('mirror/app/installers/v0.9.90/setup.exe', bytes: 11);
        file('mirror/app/installers/v0.9.90/nested/one.bin', bytes: 23);
        file('mirror/app/installers/v0.9.90/nested/deep/two.bin', bytes: 37);
        final counts = _ScanCounts(data('mirror/app/installers/v0.9.90'));

        final freed = await IOOverrides.runWithIOOverrides(sweep, counts);

        expect(freed, 71);
        expect(counts.recursiveLists, 0);
        expect(counts.lengths, {
          data('mirror/app/installers/v0.9.90/setup.exe'): 1,
          data('mirror/app/installers/v0.9.90/nested/one.bin'): 1,
          data('mirror/app/installers/v0.9.90/nested/deep/two.bin'): 1,
        });
        expect(exists('mirror/app/installers/v0.9.90'), isFalse);
        expect(
          exists('mirror/app/installers/v0.9.97/OtzariaSetup.exe'),
          isTrue,
        );
      },
    );

    test('sweep completes discovery before deleting from the directory',
        () async {
      appManifest();
      const tag = 'mirror/app/installers/v0.9.97';
      file('$tag/OtzariaSetup.exe');
      file('$tag/stale-a.exe', bytes: 3);
      file('$tag/stale-b.exe', bytes: 5);
      final counts =
          _ScanCounts(data(tag), mutationSensitiveListing: data(tag));

      expect(await IOOverrides.runWithIOOverrides(sweep, counts), 8);
      expect(exists('$tag/OtzariaSetup.exe'), isTrue);
      expect(exists('$tag/stale-a.exe'), isFalse);
      expect(exists('$tag/stale-b.exe'), isFalse);
    });

    test(
      'find still reports complete directory sizes without deleting',
      () async {
        appManifest();
        file('mirror/app/installers/v0.9.97/OtzariaSetup.exe', bytes: 70);
        file('mirror/app/installers/v0.9.90/setup.exe', bytes: 11);
        file('mirror/app/installers/v0.9.90/nested/data.bin', bytes: 23);
        final sweeper = MirrorJunkSweeper(dataDir: temp.path);

        final junk = await sweeper.find();

        expect(junk, hasLength(1));
        expect(junk.single.path, data('mirror/app/installers/v0.9.90'));
        expect(junk.single.bytes, 34);
        expect(exists('mirror/app/installers/v0.9.90/setup.exe'), isTrue);
        expect(exists('mirror/app/installers/v0.9.90/nested/data.bin'), isTrue);
        expect(await sweeper.sweep(), 34);
      },
    );

    test('a discovery error keeps earlier candidates and stays best effort',
        () async {
      libraryManifest();
      file('mirror/library/assets/v20/seforim.db.zst', bytes: 100);
      appManifest();
      file('mirror/app/installers/v0.9.90/setup.exe', bytes: 11);
      final counts = _ScanCounts(
        data('mirror/app/installers/v0.9.90'),
        failListing: data('mirror/app/installers'),
      );
      final sweeper = MirrorJunkSweeper(dataDir: temp.path);

      final junk = await IOOverrides.runWithIOOverrides(sweeper.find, counts);
      expect(
          junk.map((item) => item.path), [data('mirror/library/assets/v20')]);
      expect(junk.single.bytes, 100);
      expect(exists('mirror/library/assets/v20/seforim.db.zst'), isTrue);

      expect(await IOOverrides.runWithIOOverrides(sweep, counts), 100);
      expect(exists('mirror/library/assets/v20'), isFalse);
      expect(exists('mirror/app/installers/v0.9.90/setup.exe'), isTrue);
    });

    test(
      'sweep leaves lock-only ancestors and does not count their bytes',
      () async {
        appManifest();
        file('mirror/app/installers/v0.9.90/setup.exe', bytes: 11);
        file('mirror/app/installers/v0.9.90/nested/data.bin', bytes: 23);
        file('mirror/app/installers/v0.9.90/nested/asset.LOCK', bytes: 5);

        expect(await sweep(), 34);
        expect(
          exists('mirror/app/installers/v0.9.90/nested/asset.LOCK'),
          isTrue,
        );
        expect(exists('mirror/app/installers/v0.9.90/setup.exe'), isFalse);
        expect(
          exists('mirror/app/installers/v0.9.90/nested/data.bin'),
          isFalse,
        );
        expect(await sweep(), 0);
      },
    );

    test(
      'sweep unlinks stale symlinks without traversing their targets',
      () async {
        appManifest();
        file('outside-mirror/keep.bin', bytes: 101);
        file('mirror/app/installers/v0.9.90/setup.exe', bytes: 11);
        final link = Link(data('mirror/app/installers/v0.9.90/external'));
        await link.create(data('outside-mirror'));

        expect(await sweep(), 11);
        expect(await link.exists(), isFalse);
        expect(exists('outside-mirror/keep.bin'), isTrue);
        expect(exists('mirror/app/installers/v0.9.90'), isFalse);
      },
      skip:
          Platform.isWindows ? 'Creating symlinks requires privileges.' : false,
    );

    test('תג ישן נמחק, וחבילת FULL שנשארה לצד המתקין הנוכחי איתו', () async {
      appManifest();
      file('mirror/app/installers/v0.9.97/OtzariaSetup.exe', bytes: 70);
      file('mirror/app/installers/v0.9.97/OtzariaFullSetup.exe', bytes: 2000);
      file('mirror/app/installers/v0.9.90/OtzariaSetup.exe', bytes: 60);

      expect(await sweep(), 2060);
      expect(exists('mirror/app/installers/v0.9.97/OtzariaSetup.exe'), isTrue);
      expect(exists('mirror/app/installers/v0.9.90'), isFalse);
    });

    test('סימון האימות של המתקין הנוכחי נשמר', () async {
      appManifest();
      file('mirror/app/installers/v0.9.97/OtzariaSetup.exe', bytes: 70);
      file('mirror/app/installers/v0.9.97/OtzariaSetup.exe.verified', bytes: 9);
      file('mirror/app/installers/v0.9.97/Old.exe.verified', bytes: 9);

      expect(await sweep(), 9);
      expect(
        exists('mirror/app/installers/v0.9.97/OtzariaSetup.exe.verified'),
        isTrue,
      );
    });

    test("another platform's installers are kept", () async {
      json('mirror/app/latest-release.json', {
        'schemaVersion': 3,
        'source': 'github-latest',
        'latest': {
          'tagName': 'v0.9.97',
          'installerPath': 'installers/v0.9.97/otzaria-macos.zip',
        },
        'platforms': {
          'macos': {
            'latest': {
              'tagName': 'v0.9.97',
              'installerPath': 'installers/v0.9.97/otzaria-macos.zip',
            },
          },
          'windows': {
            'latest': {
              'tagName': 'v0.9.97',
              'installerPath': 'installers/v0.9.97/otzaria-windows.exe',
            },
            'prerelease': {
              'tagName': 'v0.9.98',
              'installerPath': 'installers/v0.9.98/otzaria-windows.exe',
            },
          },
        },
      });
      file('mirror/app/installers/v0.9.97/otzaria-macos.zip');
      file('mirror/app/installers/v0.9.97/otzaria-windows.exe');
      file('mirror/app/installers/v0.9.98/otzaria-windows.exe');
      file('mirror/app/installers/v0.9.90/otzaria-windows.exe', bytes: 60);

      expect(await sweep(), 60);
      expect(
          exists('mirror/app/installers/v0.9.97/otzaria-windows.exe'), isTrue);
      expect(
          exists('mirror/app/installers/v0.9.98/otzaria-windows.exe'), isTrue);
      expect(exists('mirror/app/installers/v0.9.97/otzaria-macos.zip'), isTrue);
    });

    test('a damaged platform entry blocks deletion', () async {
      json('mirror/app/latest-release.json', {
        'latest': {
          'tagName': 'v0.9.97',
          'installerPath': 'installers/v0.9.97/otzaria-macos.zip',
        },
        'platforms': {'windows': 'damaged'},
      });
      file('mirror/app/installers/v0.9.97/otzaria-macos.zip');
      file('mirror/app/installers/v0.9.90/otzaria-windows.exe');

      expect(await sweep(), 0);
      expect(
          exists('mirror/app/installers/v0.9.90/otzaria-windows.exe'), isTrue);
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

  test('sweep skips companions from an incomplete directory listing', () async {
    const companions = 'mirror/companions';
    json('$companions/companions.json', {
      'formatVersion': 1,
      'catalog': {'fileName': 'catalog.db.zst', 'size': 10},
    });
    file('$companions/catalog.db.zst');
    file('$companions/catalog.db');
    final counts = _ScanCounts(
      data('$companions/catalog.db'),
      lateFailListing: data(companions),
    );

    expect(await IOOverrides.runWithIOOverrides(sweep, counts), 0);
    expect(exists('$companions/catalog.db'), isTrue);
  });

  test('שארית .new של נלווה שהוחלף נמחקת יחד עם קובץ הצד שלה', () async {
    json('mirror/companions/companions.json', {
      'formatVersion': 1,
      'dictionary': {'fileName': 'lexical.db', 'size': 10},
    });
    file('mirror/companions/lexical.db');
    file('mirror/companions/lexical.db.new', bytes: 300);
    file('mirror/companions/lexical.db.new.resume', bytes: 20);

    expect(await sweep(), 320);
    expect(exists('mirror/companions/lexical.db'), isTrue);
    expect(exists('mirror/companions/lexical.db.new'), isFalse);
    expect(exists('mirror/companions/lexical.db.new.resume'), isFalse);
  });

  test('רשומת נכס נלווה ללא שם אינה מתירה מחיקת הנכסים', () async {
    json('mirror/companions/companions.json', {
      'formatVersion': 1,
      'catalog': {'size': 10},
    });
    file('mirror/companions/otzar-HB_catalog.db.zst');

    expect(await sweep(), 0);
    expect(exists('mirror/companions/otzar-HB_catalog.db.zst'), isTrue);
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

  test("another platform's launcher is kept", () async {
    json('mirror/launcher/latest-release.json', {
      'schemaVersion': 1,
      'release': {'tagName': 'v0.19'},
      'filePath': 'files/v0.19/launcher.zip',
      'platforms': {
        'macos': {
          'release': {'tagName': 'v0.19'},
          'filePath': 'files/v0.19/launcher.zip',
        },
        'windows': {
          'release': {'tagName': 'v0.18'},
          'filePath': 'files/v0.18/launcher.exe',
        },
      },
    });
    file('mirror/launcher/files/v0.19/launcher.zip');
    file('mirror/launcher/files/v0.19/launcher.exe', bytes: 30);
    file('mirror/launcher/files/v0.18/launcher.exe');
    file('mirror/launcher/files/v0.17/launcher.exe', bytes: 90);

    expect(await sweep(), 120);
    expect(exists('mirror/launcher/files/v0.19/launcher.zip'), isTrue);
    expect(exists('mirror/launcher/files/v0.18/launcher.exe'), isTrue);
  });

  test('נתיב לאנצ\'ר חסר אינו מתיר מחיקת קובצי ההרצה', () async {
    json('mirror/launcher/latest-release.json', {
      'release': {'tagName': 'v0.19'},
    });
    file('mirror/launcher/files/v0.19/launcher.exe');
    file('mirror/launcher/files/v0.17/launcher.exe');

    expect(await sweep(), 0);
    expect(exists('mirror/launcher/files/v0.19/launcher.exe'), isTrue);
    expect(exists('mirror/launcher/files/v0.17/launcher.exe'), isTrue);
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

  test('ניקוי כללי שומר חלקי תוסף שהורדתו טרם הושלמה', () async {
    json('mirror/plugins/catalog.json', {
      'plugins': [
        {
          'id': 'a',
          'version': '1.0',
          'remoteDownloadUrl': 'https://example.test/plugin',
        }
      ],
    });
    file('mirror/plugins/files/a/plugin-1.0.download.part', bytes: 3);
    json('mirror/plugins/files/a/plugin-1.0.download.resume', {
      'url': 'https://example.test/plugin',
      'etag': '"v1"',
      'total': 6,
    });
    expect(await sweep(), 0);
    expect(exists('mirror/plugins/files/a/plugin-1.0.download.part'), isTrue);
    expect(exists('mirror/plugins/files/a/plugin-1.0.download.resume'), isTrue);
  });
}

final class _ScanCounts extends IOOverrides {
  _ScanCounts(
    this.root, {
    this.failListing,
    this.lateFailListing,
    this.mutationSensitiveListing,
  });

  final String root;
  final String? failListing;
  final String? lateFailListing;
  final String? mutationSensitiveListing;
  final Map<String, int> lengths = {};
  int recursiveLists = 0;

  bool contains(String path) => p.equals(root, path) || p.isWithin(root, path);

  FileSystemEntity wrap(FileSystemEntity entity) => switch (entity) {
        Directory() => _CountedDirectory(entity, this),
        File() when contains(entity.path) => _CountedFile(entity, this),
        _ => entity,
      };

  @override
  Directory createDirectory(String path) =>
      _CountedDirectory(Zone.root.run(() => Directory(path)), this);

  @override
  File createFile(String path) => wrap(Zone.root.run(() => File(path))) as File;
}

class _CountedDirectory implements Directory {
  _CountedDirectory(this.inner, this.counts);

  final Directory inner;
  final _ScanCounts counts;

  @override
  String get path => inner.path;

  @override
  Future<bool> exists() => inner.exists();

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) async* {
    if (path == counts.failListing) {
      throw FileSystemException('Drive removed', path);
    }
    if (recursive && counts.contains(path)) counts.recursiveLists++;
    await for (final entity
        in inner.list(recursive: recursive, followLinks: followLinks)) {
      yield counts.wrap(entity);
      // Simulate a listing that loses entries after deletion advances its cursor.
      if (path == counts.mutationSensitiveListing && !entity.existsSync()) {
        return;
      }
    }
    if (path == counts.lateFailListing) {
      throw FileSystemException('Drive removed while listing', path);
    }
  }

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      inner.delete(recursive: recursive);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CountedFile implements File {
  _CountedFile(this.inner, this.counts);

  final File inner;
  final _ScanCounts counts;

  @override
  String get path => inner.path;

  @override
  Future<int> length() {
    counts.lengths.update(path, (count) => count + 1, ifAbsent: () => 1);
    return inner.length();
  }

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      inner.delete(recursive: recursive);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

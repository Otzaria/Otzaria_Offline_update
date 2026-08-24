import 'package:plugins_manager/plugins_manager.dart';
import 'package:test/test.dart';

/// בילד אחד, כפי שהוא מגיע ב-`versions[]` של `/api/plugins`.
Map<String, dynamic> build(
  String version, {
  String? compatibleWith,
  String? maxAppVersion,
  String status = 'stable',
  bool isLatest = false,
}) =>
    {
      'version': version,
      'status': status,
      'compatibleWith': compatibleWith ?? '',
      'maxAppVersion': maxAppVersion,
      'downloadUrl': isLatest
          ? '/api/plugins/a/download'
          : '/api/plugins/a@$version/download',
      'isLatest': isLatest,
    };

StorePlugin plugin(
  List<Map<String, dynamic>> versions, {
  String live = '',
  String liveCompatibleWith = '',
}) =>
    StorePlugin.fromApi(
      {
        'id': 'a',
        'name': 'תוסף',
        'version': live.isEmpty ? versions.first['version'] : live,
        'compatibleWith': liveCompatibleWith,
        'downloadUrl': '/api/plugins/a/download',
        'versions': versions,
      },
      'https://otzaria.test',
    );

void main() {
  group('isCompatibleWithApp', () {
    final entry = PluginVersionEntry.fromApi(
      build('2.0.0', compatibleWith: '0.9.95', maxAppVersion: '0.9.99'),
      '',
    )!;

    test('בתוך הטווח — תואם', () {
      for (final version in ['0.9.95', '0.9.97', '0.9.99']) {
        expect(isCompatibleWithApp(entry, version), isTrue, reason: version);
      }
    });

    test('מתחת לרצפה או מעל התקרה — לא תואם', () {
      expect(isCompatibleWithApp(entry, '0.9.94'), isFalse);
      expect(isCompatibleWithApp(entry, '1.0.0'), isFalse);
    });

    test('שדה חסר = גבול פתוח, ולא פסילה', () {
      final open = PluginVersionEntry.fromApi(build('1.0.0'), '')!;
      expect(isCompatibleWithApp(open, '0.1.0'), isTrue);
      expect(isCompatibleWithApp(open, '9.9.9'), isTrue);
    });

    test('גרסת אוצריא לא ידועה אינה פוסלת דבר', () {
      expect(isCompatibleWithApp(entry, null), isTrue);
      expect(isCompatibleWithApp(entry, ''), isTrue);
    });

    test('סיומת build של תג אוצריא אינה משתתפת בהשוואה', () {
      // תגי אוצריא נראים כך: `0.9.96+736`.
      expect(isCompatibleWithApp(entry, '0.9.96+736'), isTrue);
      expect(isCompatibleWithApp(entry, '0.9.94+686'), isFalse);
    });
  });

  group('resolveCompatibleVersion', () {
    final p = plugin([
      build('2.8.1', compatibleWith: '0.9.97', isLatest: true),
      build('2.3.1', compatibleWith: '0.9.95'),
      build('1.7.0', compatibleWith: '0.9.89'),
    ]);

    test('הגבוה ביותר שנופל בטווח — לא בהכרח האחרון שפורסם', () {
      expect(p.compatibleFor('0.9.97')?.version, '2.8.1');
      expect(p.compatibleFor('0.9.96')?.version, '2.3.1');
      expect(p.compatibleFor('0.9.90')?.version, '1.7.0');
    });

    test('אוצריא ישנה מכל הבילדים — אין תואם', () {
      expect(p.compatibleFor('0.9.80'), isNull);
    });

    test('בלי גרסה ידועה מוחזר הבילד החי', () {
      expect(p.compatibleFor(null)?.version, '2.8.1');
    });

    test('הכתובת שמוחזרת היא של אותו בילד בדיוק', () {
      expect(
        p.compatibleFor('0.9.96')?.downloadUrl,
        'https://otzaria.test/api/plugins/a@2.3.1/download',
      );
    });

    test('סדר לא ממוין מהאתר עדיין מוכרע נכון', () {
      final unsorted = plugin([
        build('1.7.0', compatibleWith: '0.9.89'),
        build('2.8.1', compatibleWith: '0.9.97'),
        build('2.3.1', compatibleWith: '0.9.95'),
      ]);

      expect(unsorted.compatibleFor('0.9.97')?.version, '2.8.1');
      expect(unsorted.compatibleFor('0.9.96')?.version, '2.3.1');
    });

    test('אתר בלי versions — הבילד החי נבנה מהשדות העליונים', () {
      final legacy = StorePlugin.fromApi(
        {
          'id': 'a',
          'name': 'תוסף',
          'version': '1.0.0',
          'compatibleWith': '0.9.95',
          'downloadUrl': '/api/plugins/a/download',
        },
        'https://otzaria.test',
      );

      expect(legacy.compatibleFor('0.9.96')?.version, '1.0.0');
      expect(legacy.compatibleFor('0.9.90'), isNull);
    });
  });

  group('resolveTargets — מה יורד לכונן', () {
    final p = plugin([
      build('2.8.1', compatibleWith: '0.9.97', isLatest: true),
      build('2.3.1', compatibleWith: '0.9.95'),
    ]);

    test('שתי גרסאות אוצריא שנפתרות שונה — שני בילדים', () {
      expect(
        p.targetsFor(['0.9.96', '0.9.97']).map((e) => e.version),
        ['2.3.1', '2.8.1'],
      );
    });

    test('שתיהן נפתרות לאותו בילד — הוא יורד פעם אחת', () {
      expect(
          p.targetsFor(['0.9.97', '0.9.98']).map((e) => e.version), ['2.8.1']);
    });

    test('בלי גרסאות (מראת תוכנה ריקה) יורד הבילד החי', () {
      expect(p.targetsFor(const []).map((e) => e.version), ['2.8.1']);
    });

    test('אין אף בילד תואם — לא יורד כלום', () {
      expect(p.targetsFor(['0.9.80']), isEmpty);
    });

    test('גרסה שאין לה תואם אינה מבטלת את זו שכן', () {
      expect(
          p.targetsFor(['0.9.80', '0.9.97']).map((e) => e.version), ['2.8.1']);
    });
  });

  group('lowestSupportedAppVersion', () {
    test('הרצפה הנמוכה מכל הבילדים, לא של החי', () {
      final p = plugin([
        build('2.8.1', compatibleWith: '0.9.97', isLatest: true),
        build('1.7.0', compatibleWith: '0.9.89'),
      ]);

      expect(p.lowestSupportedApp, '0.9.89');
    });

    test('בילד בלי רצפה = אין מינימום בכלל', () {
      final p = plugin([
        build('2.0.0', compatibleWith: '0.9.97', isLatest: true),
        build('1.0.0'),
      ]);

      expect(p.lowestSupportedApp, isNull);
    });
  });

  group('installTarget — מה מותקן בפועל', () {
    StorePlugin withFiles(Map<String, String> files) => plugin([
          build('2.8.1', compatibleWith: '0.9.97', isLatest: true),
          build('2.3.1', compatibleWith: '0.9.95'),
        ]).copyWith(
          localFiles: {
            for (final entry in files.entries)
              entry.key: PluginLocalFile(
                relativePath: entry.value,
                fileName: 'plugin.otzplugin',
                ext: '.otzplugin',
                size: 1,
              ),
          },
        );

    test('הבילד התואם שהקובץ שלו במראה', () {
      final p = withFiles({'2.3.1': 'files/a/plugin-2.3.1.otzplugin'});

      expect(p.installTarget('0.9.96')?.version, '2.3.1');
    });

    test('שני בילדים במראה — כל מחשב מקבל את שלו', () {
      final p = withFiles({
        '2.8.1': 'files/a/plugin-2.8.1.otzplugin',
        '2.3.1': 'files/a/plugin-2.3.1.otzplugin',
      });

      expect(p.installTarget('0.9.97')?.version, '2.8.1');
      expect(p.installTarget('0.9.96')?.version, '2.3.1');
    });

    test('אין קובץ לאף בילד — עדיין מוחזר התואם, כדי שיהיה מה להשלים', () {
      expect(withFiles({}).installTarget('0.9.96')?.version, '2.3.1');
    });

    test('אין בילד תואם — null, וזה מצב incompatible', () {
      final p = withFiles({'2.3.1': 'files/a/plugin-2.3.1.otzplugin'});

      expect(p.installTarget('0.9.80'), isNull);
      expect(
        p.statusAgainst(const {}, appVersion: '0.9.80'),
        PluginInstallStatus.incompatible,
      );
    });
  });

  group('statusAgainst מול הבילד שיותקן', () {
    final p = plugin([
      build('2.8.1', compatibleWith: '0.9.97', isLatest: true),
      build('2.3.1', compatibleWith: '0.9.95'),
    ]).copyWith(manifestId: 'real-a');

    test('"מעודכן" נמדד מול הבילד התואם, לא מול האחרון שפורסם', () {
      // מותקן 2.3.1 על אוצריא 0.9.96: 2.8.1 לא תרוץ כאן, ולכן אין עדכון.
      expect(
        p.statusAgainst({'real-a': '2.3.1'}, appVersion: '0.9.96'),
        PluginInstallStatus.upToDate,
      );
      // אותה התקנה על אוצריא חדשה — עכשיו כן יש עדכון.
      expect(
        p.statusAgainst({'real-a': '2.3.1'}, appVersion: '0.9.97'),
        PluginInstallStatus.updateAvailable,
      );
    });

    test('לא מותקן נשאר לא מותקן', () {
      expect(
        p.statusAgainst(const {}, appVersion: '0.9.96'),
        PluginInstallStatus.notInstalled,
      );
    });
  });
}

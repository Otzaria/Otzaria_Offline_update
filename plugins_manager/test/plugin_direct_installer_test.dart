import 'dart:io';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;
import 'package:plugins_manager/plugins_manager.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late Directory temp;
  final strings = AppL10n.strings.pluginsDomain;

  setUp(() => temp = createTempDir());
  tearDown(() => deleteTempDir(temp));

  group('installLocalUrl', () {
    test('הצורה היא install-local עם הנתיב המקומי בלבד', () {
      final url = PluginDirectInstaller.installLocalUrl(
        p.join(temp.path, 'plugin.otzplugin'),
      );

      expect(url, startsWith('otzaria://plugin/install-local?path='));
      // `install?url=` הישן דורש רשת — אסור שיחזור לכאן.
      expect(url.contains('install?url='), isFalse);
      expect(url.contains('http'), isFalse);
    });

    test('נתיב ווינדוס עם רווחים ועברית מקודד ומפוענח חזרה במדויק', () {
      const path =
          r'C:\OtzariaData\mirror\plugins\files\a\תוסף מפרשים.otzplugin';
      final url = PluginDirectInstaller.installLocalUrl(path);

      expect(url, contains('%5C')); // הבקסלאש של ווינדוס
      expect(url, contains('%20')); // רווח, ולא '+'
      expect(url.contains(' '), isFalse);
      expect(url.contains(r'\'), isFalse);
      // מה שאוצריא תקבל בסוף חייב להיות בדיוק הנתיב המקורי.
      expect(Uri.parse(url).queryParameters['path'], path);
    });

    test('נתיב macOS עם עברית שורד את הקידוד', () {
      const path =
          '/Volumes/On Key/OtzariaData/mirror/plugins/מפרשים.otzplugin';
      final url = PluginDirectInstaller.installLocalUrl(path);

      expect(Uri.parse(url).queryParameters['path'], path);
      final uri = Uri.parse(url);
      expect(uri.scheme, 'otzaria');
      expect(uri.host, 'plugin');
      expect(uri.path, '/install-local');
    });

    test('תווים בעלי משמעות ב-URL אינם שוברים את הפרמטר', () {
      const path = r'C:\a&b=c?d#e\plugin.otzplugin';
      final url = PluginDirectInstaller.installLocalUrl(path);

      expect(Uri.parse(url).queryParameters['path'], path);
      expect(Uri.parse(url).queryParameters.length, 1);
    });
  });

  group('deliveryTargetFor', () {
    test('קובץ הרצה קיים — ה-URL נמסר אליו ולא למטפל הפרוטוקול', () {
      final exe = p.join(temp.path, 'otzaria.exe');
      File(exe).writeAsStringSync('');

      expect(PluginDirectInstaller.deliveryTargetFor(exe), exe);
    });

    test('חבילת .app היא תיקייה — נבדקת ככזו', () {
      final bundle = p.join(temp.path, 'אוצריא.app');
      Directory(bundle).createSync(recursive: true);

      expect(PluginDirectInstaller.deliveryTargetFor(bundle), bundle);
      // קובץ בשם .app שאינו חבילה אינו קיים כתיקייה — אין למי למסור.
      expect(
        PluginDirectInstaller.deliveryTargetFor(p.join(temp.path, 'אין.app')),
        isNull,
      );
    });

    test('בלי נתיב, או נתיב שכבר לא קיים — נפילה חזרה למטפל הפרוטוקול', () {
      expect(PluginDirectInstaller.deliveryTargetFor(null), isNull);
      expect(PluginDirectInstaller.deliveryTargetFor(''), isNull);
      expect(
        PluginDirectInstaller.deliveryTargetFor(
          p.join(temp.path, 'נמחקה', 'otzaria.exe'),
        ),
        isNull,
      );
    });
  });

  group('PluginDirectInstaller.install', () {
    test('קובץ חסר מוחזר ככשל, לא כחריג', () async {
      final result = await PluginDirectInstaller.install(
        p.join(temp.path, 'nope.otzplugin'),
      );

      expect(result.success, isFalse);
      expect(result.error, strings.localPluginFileMissing);
    });

    test('סיומת שאינה otzplugin נדחית', () async {
      final path = p.join(temp.path, 'file.zip');
      File(path).writeAsBytesSync(pluginBytes('{"id":"x"}'));

      final result = await PluginDirectInstaller.install(path);

      expect(result.success, isFalse);
      expect(result.error, strings.badPluginExtension);
    });

    test('סיומת בשמה גדולה מתקבלת (הבדיקה אינה תלוית רישיות)', () async {
      // רק עד שלב בניית ה-URL — אין כאן הרצה של מטפל הפרוטוקול.
      final path = p.join(temp.path, 'Plugin.OTZPLUGIN');
      File(path).writeAsBytesSync(pluginBytes('{"id":"x"}'));

      expect(
        PluginDirectInstaller.installLocalUrl(path),
        contains('install-local'),
      );
      expect(path.toLowerCase().endsWith('.otzplugin'), isTrue);
    });

    test('דחייה אינה מחלצת את ה-ZIP ואינה נוגעת בדיסק', () async {
      final path = p.join(temp.path, 'file.zip');
      File(path).writeAsBytesSync(pluginBytes('{"id":"x"}'));

      await PluginDirectInstaller.install(path);
      await PluginDirectInstaller.install(
          p.join(temp.path, 'missing.otzplugin'));

      // אוצריא מנהלת רישום פנימי — פרישה ידנית של הארכיון עוקפת אותו,
      // ולכן החבילה הזו לא פורשת כלום בשום מסלול.
      expect(
        temp.listSync().map((e) => p.basename(e.path)),
        ['file.zip'],
      );
    });
  });
}

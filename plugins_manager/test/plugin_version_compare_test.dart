import 'package:plugins_manager/plugins_manager.dart';
import 'package:test/test.dart';

void main() {
  group('comparePluginVersions', () {
    test('משווה לפי מקטעים מספריים', () {
      expect(comparePluginVersions('1.2.0', '1.1.9'), 1);
      expect(comparePluginVersions('1.1.9', '1.2.0'), -1);
      expect(comparePluginVersions('2.0.0', '2.0.0'), 0);
      expect(comparePluginVersions('1.10.0', '1.9.0'), 1);
    });

    test('ההשוואה מספרית ולא לקסיקוגרפית', () {
      expect(comparePluginVersions('0.10.0', '0.9.0'), 1);
      expect(comparePluginVersions('10.0.0', '9.9.9'), 1);
      expect(comparePluginVersions('1.0.100', '1.0.99'), 1);
    });

    test('אורך שונה מרופד באפסים', () {
      expect(comparePluginVersions('1.2', '1.2.0'), 0);
      expect(comparePluginVersions('1.2.1', '1.2'), 1);
      expect(comparePluginVersions('1', '1.0.0.0'), 0);
      expect(comparePluginVersions('1.0.0.1', '1'), 1);
      expect(comparePluginVersions('2', '1.9.9'), 1);
    });

    test('אפסים מובילים ורווחים אינם משנים', () {
      expect(comparePluginVersions('1.02.0', '1.2.0'), 0);
      expect(comparePluginVersions(' 1 . 2 . 0 ', '1.2.0'), 0);
    });

    test('null, מחרוזת ריקה ומקטע לא-מספרי נחשבים אפס', () {
      expect(comparePluginVersions(null, '0'), 0);
      expect(comparePluginVersions(null, null), 0);
      expect(comparePluginVersions('', ''), 0);
      expect(comparePluginVersions('', '0.0.0'), 0);
      expect(comparePluginVersions('1.x.0', '1.0.0'), 0);
      expect(comparePluginVersions('1.0', null), 1);
      expect(comparePluginVersions('אבג', '0'), 0);
      expect(comparePluginVersions('1.0.0', ''), 1);
    });

    test('סיומת prerelease אינה מדרגת, אבל המספר שלפניה כן', () {
      // הסיומת עצמה אינה משתתפת בדירוג — '1.2.0-beta' שקול ל-'1.2.0'.
      expect(comparePluginVersions('1.2.0-beta', '1.2.0'), 0);
      expect(comparePluginVersions('1.2.0-beta', '1.2.0-rc'), 0);
      // אבל הספרה שלפני המקף נשמרת: '1-beta' הוא 1, לא 0.
      expect(comparePluginVersions('1.2.1-beta', '1.2.0'), 1);
      expect(comparePluginVersions('1.3.0-beta', '1.2.0'), 1);
    });

    test('קידומת v ומטא-דאטה של build מנורמלות לפני ההשוואה', () {
      // בלי זה תוסף שהאתר מתייג עם 'v' לא היה מסומן כ"עדכון זמין" לעולם.
      expect(comparePluginVersions('v1.2.0', '1.2.0'), 0);
      expect(comparePluginVersions('v2.0.0', 'v1.0.0'), 1);
      expect(comparePluginVersions('V1.0.0', 'v1.0.1'), -1);
      expect(comparePluginVersions('1.0.1+7', '1.0.1'), 0);
    });

    test('אנטי-סימטריה: היפוך הסדר הופך את הסימן', () {
      const pairs = [
        ['1.0.0', '2.0.0'],
        ['1.2', '1.2.3'],
        ['0.0.1', '0.0.2'],
      ];
      for (final pair in pairs) {
        expect(
          comparePluginVersions(pair[0], pair[1]),
          -comparePluginVersions(pair[1], pair[0]),
          reason: '${pair[0]} מול ${pair[1]}',
        );
      }
    });
  });
}

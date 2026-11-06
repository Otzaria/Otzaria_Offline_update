import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:test/test.dart';

void main() {
  for (final count in [1, 2, 5]) {
    test('missing programs are installations, not updates ($count)', () {
      final he = const HebrewStrings().guide;
      final en = const EnglishStrings().guide;
      expect(he.chipAppsPending(count), contains('להתקנה'));
      expect(he.chipAppsPending(count), isNot(contains('עדכון')));
      expect(en.chipAppsPending(count), contains('install'));
      expect(en.chipAppsPending(count), isNot(contains('update')));
      expect(he.chipAppsUpdates(count), contains('עדכו'));
      expect(en.chipAppsUpdates(count), contains('update'));
    });
  }
}

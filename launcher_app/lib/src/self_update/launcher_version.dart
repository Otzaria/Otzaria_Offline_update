/// גרסת הלאנצ'ר עצמו. **חייבת להיות זהה ל-`version` שב-`pubspec.yaml`** —
/// `launcher_version_test.dart` נכשל אחרת, וה-stub של Windows מקבל את אותה
/// גרסה מ-`build_stub.ps1` (ראו `windows_stub/README` שבתוך `package.ps1`).
const String launcherVersion = '0.1.15';

/// השוואת גרסאות של הלאנצ'ר. תג ב-GitHub נראה `v1.2.3`, ה-pubspec מדווח
/// `1.2.3`, ובנייה מקומית עשויה להוסיף `+build` — ולכן משווים אחרי נרמול.
///
/// מדוע "חדש יותר" ולא "שונה" (בניגוד ל-`OtzariaUpdateCheckResult`): את
/// הלאנצ'ר אנחנו מפרסמים בעצמנו, ו-release שנמשך חזרה אינו סיבה להציע
/// למשתמש לרדת גרסה.
abstract final class LauncherVersion {
  /// תג של release שה-CI פרסם: `v0.1.7` בדיוק (עם `+build` אופציונלי).
  ///
  /// ⚠️ תג שאינו בצורה הזאת **נפסל**, ולא מנוסה "בערך": בריפו יש release
  /// ידני ותיק בשם `V1`, וכל השוואה מספרית תראה בו גרסה 1 — כלומר חדשה
  /// לנצח מכל 0.x. תגים ידניים אינם מה שהעדכון העצמי אמור למצוא.
  static final RegExp _releaseTag = RegExp(r'^[vV]?\d+\.\d+\.\d+(\+\d+)?$');

  /// `true` אם [tag] הוא תג גרסה בצורה שה-CI מפרסם.
  static bool isReleaseTag(String tag) => _releaseTag.hasMatch(tag.trim());

  /// מוריד `v` מוביל ואת ה-build שאחרי `+`.
  static String normalize(String raw) {
    var value = raw.trim();
    if (value.startsWith('v') || value.startsWith('V')) {
      value = value.substring(1);
    }
    final plus = value.indexOf('+');
    return plus == -1 ? value : value.substring(0, plus);
  }

  /// שלילי אם [a] קודמת ל-[b], חיובי אם היא אחריה, 0 כשהן שוות.
  ///
  /// משווים את המספרים המופרדים בנקודות; חלק חסר נחשב 0, ולכן `1.2` שווה
  /// ל-`1.2.0`. סיומת `-beta` נחשבת **קודמת** לאותה גרסה בלעדיה, כמו
  /// ב-semver — כך גרסת ניסיון לא מוצגת כחדשה מהיציבה שיצאה ממנה.
  static int compare(String a, String b) {
    final left = _Parsed(normalize(a));
    final right = _Parsed(normalize(b));

    final length = left.numbers.length > right.numbers.length
        ? left.numbers.length
        : right.numbers.length;
    for (var i = 0; i < length; i++) {
      final diff = left.numberAt(i) - right.numberAt(i);
      if (diff != 0) return diff < 0 ? -1 : 1;
    }

    if (left.suffix == right.suffix) return 0;
    if (left.suffix.isEmpty) return 1;
    if (right.suffix.isEmpty) return -1;
    return left.suffix.compareTo(right.suffix);
  }

  /// `true` כש-[candidate] חדשה מ-[current].
  static bool isNewer(String candidate, String current) =>
      compare(candidate, current) > 0;
}

class _Parsed {
  _Parsed(String normalized)
      : numbers = _numbersOf(normalized),
        suffix = _suffixOf(normalized);

  final List<int> numbers;
  final String suffix;

  int numberAt(int index) => index < numbers.length ? numbers[index] : 0;

  static String _core(String normalized) {
    final dash = normalized.indexOf('-');
    return dash == -1 ? normalized : normalized.substring(0, dash);
  }

  static List<int> _numbersOf(String normalized) => [
        for (final part in _core(normalized).split('.'))
          int.tryParse(part.trim()) ?? 0,
      ];

  static String _suffixOf(String normalized) {
    final dash = normalized.indexOf('-');
    return dash == -1 ? '' : normalized.substring(dash + 1);
  }
}

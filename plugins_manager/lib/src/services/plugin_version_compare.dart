/// השוואת גרסאות תוסף — semver בסיסי (`major.minor.patch`), מחזיר 1 / 0 / -1.
///
/// אורך שונה מרופד באפסים, כך ש-`1.2` ו-`1.2.0` שקולים. קידומת `v` וסיומת
/// prerelease/build (`-beta`, `+7`) מוסרות לפני ההשוואה — הן אינן משתתפות
/// בדירוג, אבל **המספר שלפניהן כן**.
///
/// **למה לא לקרוא את המקטע כמו שהוא:** `int.tryParse('1-beta')` מחזיר null,
/// והנפילה ל-0 בלעה את הספרה עצמה — `v2.0.0` יצא שווה ל-`v1.0.0`, ותוסף
/// שהאתר מתייג עם קידומת `v` לא היה מסומן כ"עדכון זמין" לעולם.
int comparePluginVersions(String? a, String? b) {
  final pa = _parts(a);
  final pb = _parts(b);
  final length = pa.length > pb.length ? pa.length : pb.length;

  for (var i = 0; i < length; i++) {
    final diff = (i < pa.length ? pa[i] : 0) - (i < pb.length ? pb[i] : 0);
    if (diff != 0) return diff > 0 ? 1 : -1;
  }
  return 0;
}

/// מקטע ראשון של ספרות בלבד; מה שאחריו (`-beta`, `+7`) אינו משתתף בדירוג.
final _leadingDigits = RegExp(r'^\d+');

List<int> _parts(String? version) {
  var text = (version ?? '0').trim();
  if (text.startsWith('v') || text.startsWith('V')) text = text.substring(1);

  return text.split('.').map((segment) {
    final digits = _leadingDigits.firstMatch(segment.trim());
    return digits == null ? 0 : int.parse(digits.group(0)!);
  }).toList();
}

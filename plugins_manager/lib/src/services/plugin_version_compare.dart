/// השוואת גרסאות תוסף — semver בסיסי (`major.minor.patch`), פורט מדויק של
/// `compareVersions` בחנות ה-Electron. מחזיר 1 / 0 / -1.
///
/// מקטע לא-מספרי נחשב 0, ואורך שונה מרופד באפסים — כך ש-`1.2` ו-`1.2.0`
/// שקולים. סיומות prerelease (`1.2.0-beta`) לא נתמכות בכוונה: זה בדיוק
/// ההתנהגות של החנות המקורית, ושינוי כאן ישנה אילו תוספים מסומנים כ"עדכון
/// זמין".
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

List<int> _parts(String? version) => (version ?? '0')
    .split('.')
    .map((segment) => int.tryParse(segment.trim()) ?? 0)
    .toList();

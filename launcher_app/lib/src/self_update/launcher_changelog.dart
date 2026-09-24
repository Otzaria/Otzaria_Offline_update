import 'launcher_version.dart';

/// יומן השינויים למשתמש, כמו `assets/יומן שינויים.md` של אוצריא. נארז כנכס
/// (למסך ההגדרות) ונשלף מהתג ב-GitHub (לגרסה החדשה, שעוד לא רצה כאן).
const String launcherChangelogAsset = 'assets/יומן שינויים.md';

/// כותרת גרסה: `* **0.23**`, `## 0.23`, `v0.23` — אותה תבנית כמו באוצריא.
final RegExp _headingPattern = RegExp(
  r'^\s*(?:(?:#{1,6}|[*-])\s*)?\*{0,2}v?(\d+(?:\.\d+){1,2}(?:[-+][^\s*]+)?)\*{0,2}\s*$',
);

/// הגרסה שבשורה, אם השורה היא כותרת גרסה.
String? changelogHeadingVersion(String line) =>
    _headingPattern.firstMatch(line)?.group(1);

/// הפריטים של הגרסאות שאחרי [currentVersion] ועד [latestVersion] כולל, עם
/// הכותרות. `null` כשאין ביניהן כלום — ה-UI מציג אז את הדיאלוג בלי הקטע.
///
/// פריטים שלפני הכותרת הראשונה נדלגים: הם עוד לא יצאו בשום גרסה.
String? changelogBetweenVersions({
  required String changelog,
  required String currentVersion,
  required String latestVersion,
}) {
  if (LauncherVersion.compare(latestVersion, currentVersion) <= 0) return null;

  final selected = <String>[];
  var include = false;
  for (final line in changelog.split(RegExp(r'\r?\n'))) {
    final version = changelogHeadingVersion(line);
    if (version != null) {
      include = LauncherVersion.compare(version, currentVersion) > 0 &&
          LauncherVersion.compare(version, latestVersion) <= 0;
      if (include && selected.isNotEmpty && selected.last.trim().isNotEmpty) {
        selected.add('');
      }
    }
    if (include) selected.add(line);
  }

  final result = selected.join('\n').trim();
  return result.isEmpty ? null : result;
}

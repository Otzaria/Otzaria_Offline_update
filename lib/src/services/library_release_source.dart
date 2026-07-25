import '../models/delta_manifest.dart';
import '../models/library_release.dart';

/// מקור נתונים למידע ה-releases של ספריית הספרים: או ה-cloud (GitHub, דרך
/// [GithubLibraryReleaseClient]) או מראה מקומית (offline, דרך
/// [LocalMirrorLibraryReleaseClient]). [LibraryUpdateDiscovery] תלוי רק
/// בממשק הזה, כך שהוא אגנוסטי לחלוטין למקור בפועל.
abstract class LibraryReleaseSource {
  /// שולף את כל ה-releases הזמינים (מ-GitHub או מ-`releases.json` מקומי).
  Future<List<LibraryRelease>> fetchReleases();

  /// מוריד ומפענח manifest דלתאי. [url] הוא כתובת HTTP במקור ה-cloud, או
  /// נתיב קובץ מקומי במקור ה-mirror — כל מקור יודע לפרש את הצורה שלו.
  Future<DeltaManifest> fetchManifest(String url);

  /// סוגר משאבים פנימיים (למשל חיבור HTTP). לא כל מקור צריך ניקוי.
  void dispose() {}
}

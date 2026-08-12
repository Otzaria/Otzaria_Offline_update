import 'dart:convert';
import 'dart:io' show Platform;

import 'package:http/http.dart' as http;
import 'package:otzaria_l10n/otzaria_l10n.dart';

import 'launcher_release.dart';
import 'launcher_version.dart';

/// שולף את ה-releases של **הריפו הזה** — הלאנצ'ר עצמו, לא אוצריא ולא
/// SeforimLibrary. זו הפעולה היחידה כאן שנוגעת ברשת, ותמיד מטא-דאטה בלבד:
/// ההורדה עצמה היא של [LauncherUpdateMirror].
class LauncherReleaseClient {
  LauncherReleaseClient({
    http.Client? httpClient,
    String? operatingSystem,
    this.timeout = const Duration(seconds: 20),
  })  : _httpClient = httpClient ?? http.Client(),
        _operatingSystem = operatingSystem ?? Platform.operatingSystem;

  /// זמן קצוב לבקשה — חובה, בדיוק כמו ב-`OtzariaReleaseClient`: בלעדיו מחשב
  /// שמחובר לרשת בלי מסלול לאינטרנט היה תולה את הבדיקה בלי הגבלה.
  Duration timeout;

  static const _owner = 'Otzaria';
  static const _repo = 'Otzaria_Offline_update';
  static const _apiBase = 'https://api.github.com';

  /// דף אחד מספיק: מחפשים את ה-release היציב האחרון, ולא את כל ההיסטוריה.
  static const int _pageSize = 30;

  final http.Client _httpClient;
  final String _operatingSystem;

  /// הגרסה היציבה **הגבוהה ביותר** שיש בה קובץ הרצה לפלטפורמה הזאת, או
  /// `null` אם אין כזו בדף הראשון.
  ///
  /// pre-release ו-draft נפסלים: את הלאנצ'ר מפיצים למחשבים מנותקים, ושם גרסת
  /// ניסיון היא בדיוק מה שאין איך לתקן. נפסל גם כל תג שאינו בצורת
  /// `vX.Y.Z` — ראו [LauncherVersion.isReleaseTag].
  ///
  /// הבחירה היא לפי הגרסה ולא לפי הסדר שבו GitHub החזיר: סדר הפרסום אינו
  /// סדר הגרסאות (release שנערך ידנית, תג ותיק שפורסם מחדש), ובחירת
  /// "הראשון ברשימה" הייתה הופכת את זה לתלוי־מזל.
  Future<LauncherRelease?> fetchLatestStable() async {
    final uri = Uri.parse(
      '$_apiBase/repos/$_owner/$_repo/releases?per_page=$_pageSize',
    );
    final response = await _httpClient.get(
      uri,
      headers: const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        // ⚠️ חובה — GitHub מחזיר 403 לכל בקשה בלי User-Agent.
        'User-Agent': 'otzaria-launcher',
      },
    ).timeout(timeout);

    if (response.statusCode != 200) {
      throw LauncherUpdateException(
        AppL10n.strings.appDomain.githubStatus(response.statusCode, '$uri'),
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw LauncherUpdateException(
        AppL10n.strings.appDomain.noReleasesAtAll('$_owner/$_repo'),
      );
    }

    LauncherRelease? best;
    for (final entry in decoded) {
      if (entry is! Map<String, dynamic>) continue;
      if (entry['draft'] as bool? ?? false) continue;
      if (entry['prerelease'] as bool? ?? false) continue;

      final release = _parse(entry);
      if (release == null) continue;
      if (best == null ||
          LauncherVersion.isNewer(release.tagName, best.tagName)) {
        best = release;
      }
    }
    return best;
  }

  /// `null` כשה-release אינו מתאים (תג שאינו גרסה, או אין אסט לפלטפורמה) —
  /// ממשיכים לשאר במקום להפיל את הבדיקה כולה.
  LauncherRelease? _parse(Map<String, dynamic> json) {
    final tagName = json['tag_name'];
    if (tagName is! String || !LauncherVersion.isReleaseTag(tagName)) {
      return null;
    }

    final assets = json['assets'];
    if (assets is! List) return null;

    for (final asset in assets) {
      if (asset is! Map<String, dynamic>) continue;
      final name = asset['name'];
      final url = asset['browser_download_url'];
      final size = asset['size'];
      if (name is! String || url is! String || size is! int) continue;
      if (!matchesPlatform(name, _operatingSystem)) continue;

      return LauncherRelease(
        tagName: tagName,
        name: json['name'] is String && (json['name'] as String).isNotEmpty
            ? json['name'] as String
            : tagName,
        assetName: name,
        downloadUrl: url,
        sizeBytes: size,
        publishedAt: json['published_at'] is String
            ? DateTime.tryParse(json['published_at'] as String)
            : null,
        releaseNotes: json['body'] is String ? json['body'] as String : null,
      );
    }
    return null;
  }

  /// התאמה **לפי סיומת בלבד**: בווינדוס מופץ exe בודד ושמו עברי (גיטהאב גם
  /// מחליף בו רווחים בנקודות), וב-macOS חבילת `.app` ארוזה ל-zip. התאמה לפי
  /// שם הייתה נשברת בכל שינוי ניסוח.
  static bool matchesPlatform(String assetName, String operatingSystem) {
    final name = assetName.toLowerCase();
    return switch (operatingSystem) {
      'windows' => name.endsWith('.exe'),
      'macos' => name.endsWith('.zip'),
      _ => false,
    };
  }

  void dispose() => _httpClient.close();
}

/// שגיאה בעדכון העצמי. טיפוס נפרד כדי שה-UI יבחין בין "אין רשת" (נבלע
/// בשקט) לבין תקלה אמיתית שראוי להציג.
class LauncherUpdateException implements Exception {
  const LauncherUpdateException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// תג של release שה-CI של `otzaria-plugin-store` מפרסם: `v1`, `v2`, …
///
/// ⚠️ תג שאינו בצורה הזאת **נפסל** — ובכללו `bundle`, התג של החבילה המלאה
/// (109MB). אנחנו מביאים את התוכנה הבסיסית בלבד ואורזים את התוספים בעצמנו
/// מהמראה, ולכן התג הזה אסור להיבחר גם אם יתווסף לו קובץ `.exe`.
final RegExp _releaseTag = RegExp(r'^v?\d+$');

/// `true` אם [tag] הוא תג גרסה בצורה שה-CI של החנות מפרסם.
bool isStoreAppReleaseTag(String tag) => _releaseTag.hasMatch(tag.trim());

/// המספר שבתוך התג, או `null` כשאינו תג גרסה.
int? storeAppVersionOf(String tag) {
  final trimmed = tag.trim();
  if (!isStoreAppReleaseTag(trimmed)) return null;
  return int.tryParse(
    trimmed.startsWith('v') || trimmed.startsWith('V')
        ? trimmed.substring(1)
        : trimmed,
  );
}

/// גרסה של **תוכנת** חנות התוספים — קובץ ההרצה לווינדוס בלבד, בלי התוספים
/// שבתוכו: את אלה `StoreAppExporter` אורז מהמראה שכבר על הכונן.
class StoreAppRelease {
  const StoreAppRelease({
    required this.tagName,
    required this.version,
    required this.assetName,
    required this.downloadUrl,
    required this.sizeBytes,
    this.publishedAt,
    this.pageUrl = '',
  });

  final String tagName;

  /// המספר שבתג — `v6` → 6. ההשוואה היא לפיו ולא לפי סדר הפרסום.
  final int version;
  final String assetName;
  final String downloadUrl;
  final int sizeBytes;
  final DateTime? publishedAt;

  /// דף ה-release בגיטהאב, לתצוגה בלבד.
  final String pageUrl;

  Map<String, dynamic> toJson() => {
        'tagName': tagName,
        'version': version,
        'assetName': assetName,
        'downloadUrl': downloadUrl,
        'sizeBytes': sizeBytes,
        'publishedAt': publishedAt?.toIso8601String(),
        'pageUrl': pageUrl,
      };

  /// `null` על רשומה פגומה — הקורא מתייחס לזה כ"אין מה להתקין", בדיוק כמו
  /// ל"אין קובץ מטא-דאטה".
  static StoreAppRelease? fromJson(Object? json) {
    if (json is! Map) return null;
    final tagName = json['tagName'];
    final assetName = json['assetName'];
    final downloadUrl = json['downloadUrl'];
    final sizeBytes = json['sizeBytes'];
    if (tagName is! String || tagName.isEmpty) return null;
    if (assetName is! String || assetName.isEmpty) return null;
    if (downloadUrl is! String || sizeBytes is! int) return null;

    return StoreAppRelease(
      tagName: tagName,
      version: json['version'] is int
          ? json['version'] as int
          : storeAppVersionOf(tagName) ?? 0,
      assetName: assetName,
      downloadUrl: downloadUrl,
      sizeBytes: sizeBytes,
      publishedAt: json['publishedAt'] is String
          ? DateTime.tryParse(json['publishedAt'] as String)
          : null,
      pageUrl: json['pageUrl'] is String ? json['pageUrl'] as String : '',
    );
  }
}

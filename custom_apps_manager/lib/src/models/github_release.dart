/// קובץ בודד בתוך release. **זה מה שהמשתמש בוחר מתוכו** — ראו
/// [GithubSource].
class GithubAsset {
  const GithubAsset({
    required this.name,
    required this.downloadUrl,
    required this.sizeBytes,
  });

  final String name;
  final String downloadUrl;
  final int sizeBytes;

  factory GithubAsset.fromJson(Map<String, dynamic> json) => GithubAsset(
        name: json['name'] as String,
        downloadUrl: json['browser_download_url'] as String,
        sizeBytes: json['size'] as int? ?? 0,
      );
}

/// גרסה שפורסמה בריפו.
class GithubRelease {
  const GithubRelease({
    required this.tagName,
    required this.isPrerelease,
    required this.assets,
    this.publishedAt,
  });

  final String tagName;
  final bool isPrerelease;
  final DateTime? publishedAt;
  final List<GithubAsset> assets;

  /// מספר הגרסה בלי `v` מוביל ובלי חלק ה-build — כך היא מושווית למה
  /// שמותקן בפועל. בלי הנרמול הזה `v1.4.2` מול `1.4.2` היה נראה כמו עדכון
  /// בכל בדיקה, בדיוק כמו שקרה ב-`OtzariaUpdateCheckResult`.
  String get version => normalizeVersion(tagName);

  static String normalizeVersion(String raw) {
    var text = raw.trim();
    if (text.startsWith('v') || text.startsWith('V')) {
      text = text.substring(1);
    }
    final plus = text.indexOf('+');
    return plus < 0 ? text : text.substring(0, plus);
  }

  factory GithubRelease.fromJson(Map<String, dynamic> json) => GithubRelease(
        tagName: json['tag_name'] as String,
        isPrerelease: json['prerelease'] as bool? ?? false,
        publishedAt: DateTime.tryParse(json['published_at'] as String? ?? ''),
        assets: (json['assets'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(GithubAsset.fromJson)
            .toList(growable: false),
      );
}

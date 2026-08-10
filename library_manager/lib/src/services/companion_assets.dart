import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// שלושת הקבצים הנלווים לספרייה שאוצריא מרעננת בכל עדכון
/// (`CompanionAssetsService.verifyAndUpdate`). בלעדיהם מחשב לא-מקוון מקבל
/// מסד מעודכן אבל תלמוד/קטלוג/מילון ישנים.
enum CompanionAsset { talmud, catalog, dictionary }

/// רשומה אחת ב-`companions.json` של המראה: הקובץ שהורד ומה שמזהה את
/// הגרסה שלו. [version] מאוכלס לקטלוג בלבד (מספר מתוך `version.txt`),
/// [tag]/[sha256] לשני האחרים.
class CompanionMirrorEntry {
  const CompanionMirrorEntry({
    required this.fileName,
    required this.size,
    this.tag,
    this.sha256,
    this.version,
    this.compressed = false,
  });

  final String fileName;
  final int size;
  final String? tag;
  final String? sha256;
  final int? version;

  /// `true` כשהקובץ במראה דחוס ב-zstd ויש לחלץ אותו בהתקנה.
  final bool compressed;

  /// הערך שנכתב לסימון הגרסה אצל אוצריא — digest אם יש, אחרת התג. זהה
  /// לכלל ב-`CompanionAssetsService._ensureTalmud`.
  String? get versionMarker => sha256 ?? tag;

  Map<String, dynamic> toJson() => {
        'fileName': fileName,
        'size': size,
        if (tag != null) 'tag': tag,
        if (sha256 != null) 'sha256': sha256,
        if (version != null) 'version': version,
        if (compressed) 'compressed': true,
      };

  factory CompanionMirrorEntry.fromJson(Map<String, dynamic> json) {
    return CompanionMirrorEntry(
      fileName: (json['fileName'] as String?) ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      tag: json['tag'] as String?,
      sha256: json['sha256'] as String?,
      version: (json['version'] as num?)?.toInt(),
      compressed: (json['compressed'] as bool?) ?? false,
    );
  }
}

/// תוכן `companions.json` — מה שיושב במראה ומוכן להתקנה במחשב הלא-מקוון.
class CompanionMirrorManifest {
  const CompanionMirrorManifest({required this.entries, this.exportedAt});

  static const String fileName = 'companions.json';
  static const int formatVersion = 1;

  final Map<CompanionAsset, CompanionMirrorEntry> entries;
  final DateTime? exportedAt;

  bool get isEmpty => entries.isEmpty;

  Map<String, dynamic> toJson() => {
        'formatVersion': formatVersion,
        'exportedAt': (exportedAt ?? DateTime.now()).toIso8601String(),
        for (final e in entries.entries) e.key.name: e.value.toJson(),
      };

  factory CompanionMirrorManifest.fromJson(Map<String, dynamic> json) {
    final entries = <CompanionAsset, CompanionMirrorEntry>{};
    for (final asset in CompanionAsset.values) {
      final raw = json[asset.name];
      if (raw is Map<String, dynamic>) {
        entries[asset] = CompanionMirrorEntry.fromJson(raw);
      }
    }
    return CompanionMirrorManifest(
      entries: entries,
      exportedAt: DateTime.tryParse((json['exportedAt'] as String?) ?? ''),
    );
  }

  /// קורא את המניפסט מתיקיית המראה, או `null` אם עוד לא בוצעה הורדה (או
  /// שהקובץ פגום — מצב שקול ל"אין מראה", לא שגיאה חוסמת).
  static Future<CompanionMirrorManifest?> load(String mirrorDir) async {
    final file = File(p.join(mirrorDir, fileName));
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      return CompanionMirrorManifest.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }
}

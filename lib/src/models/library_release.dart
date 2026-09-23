import 'package:equatable/equatable.dart';

import 'split_archive_manifest.dart';

/// קובץ מצורף בודד ב-release של GitHub.
class ReleaseAsset extends Equatable {
  final String name;
  final String downloadUrl;
  final int size;

  /// מזהה הנכס אצל GitHub — יציב לאורך חיי הנכס ומשתנה בהעלאה מחדש.
  final int? id;

  /// חותמת עדכון הנכס (`updated_at`) — משתנה בהעלאה מחדש תחת אותו tag.
  final String? updatedAt;

  /// digest של התוכן (`sha256:<hex>`) כשה-API מספק; null כשחסר.
  final String? digest;

  /// נכס מפוצל: החלקים לפי הסדר, והנכס עצמו וירטואלי (אין לו [downloadUrl]).
  /// ריק בנכס רגיל ובמראה המקומית, שנושאת תמיד את הנכס המורכב.
  final List<ReleaseAsset> parts;

  /// ה-`<name>.manifest.json` של נכס מפוצל — sha256 של החלקים ושל המורכב.
  final ReleaseAsset? splitManifest;

  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
    this.id,
    this.updatedAt,
    this.digest,
    this.parts = const [],
    this.splitManifest,
  });

  /// שם ה-DB המלא הדחוס — גם כשהוא מגיע מפוצל.
  static const String fullDbArchiveName = 'seforim.db.zst';

  /// האם הנכס מורכב מחלקים ויורד דרכם — ראו [LibraryRelease.fromJson].
  bool get isSplit => parts.isNotEmpty;

  factory ReleaseAsset.fromJson(Map<String, dynamic> json) {
    return ReleaseAsset(
      name: (json['name'] as String?) ?? '',
      downloadUrl: (json['browser_download_url'] as String?) ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      id: (json['id'] as num?)?.toInt(),
      updatedAt: json['updated_at'] as String?,
      digest: json['digest'] as String?,
    );
  }

  /// סריאליזציה לפורמט המראה המקומית (offline) — לא זהה ל-JSON של GitHub
  /// (משתמש במפתחות פשוטים), ולכן יש [fromMirrorJson] תואם בצד השני.
  Map<String, dynamic> toMirrorJson() => {
        'name': name,
        'downloadUrl': downloadUrl,
        'size': size,
        if (id != null) 'id': id,
        if (updatedAt != null) 'updatedAt': updatedAt,
        if (digest != null) 'digest': digest,
      };

  factory ReleaseAsset.fromMirrorJson(Map<String, dynamic> json) {
    return ReleaseAsset(
      name: (json['name'] as String?) ?? '',
      downloadUrl: (json['downloadUrl'] as String?) ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      id: (json['id'] as num?)?.toInt(),
      updatedAt: json['updatedAt'] as String?,
      digest: json['digest'] as String?,
    );
  }

  /// `true` אם זהו manifest של patch דלתאי
  /// (`patch-vX-vY.db.zst.manifest.json`).
  bool get isDeltaManifest =>
      name.startsWith('patch-') && name.endsWith('.db.zst.manifest.json');

  /// `true` אם זהו ה-DB המלא הדחוס (`seforim.db.zst`).
  bool get isFullDbArchive => name == fullDbArchiveName;

  @override
  List<Object?> get props =>
      [name, downloadUrl, size, id, updatedAt, digest, parts, splitManifest];
}

/// מייצג release אחד מ-GitHub עם כל ה-assets שלו.
class LibraryRelease extends Equatable {
  final String tag;
  final bool isPrerelease;
  final bool isDraft;
  final DateTime? publishedAt;
  final List<ReleaseAsset> assets;

  const LibraryRelease({
    required this.tag,
    required this.isPrerelease,
    required this.isDraft,
    required this.publishedAt,
    required this.assets,
  });

  /// ה-`state` שנחשב נכס מוכן להורדה. GitHub יוצר את אובייקט ה-release לפני
  /// שהנכסים עולים, וכל release של הספרייה נושא ~3.6GB — כלומר יש חלון של
  /// דקות ארוכות שבו הנכסים קיימים ברשימה אך אינם שלמים (`starting`,
  /// `uploading`, בדרך כלל `size: 0` ובלי `digest`). נכס כזה מסונן כאן, כדי
  /// שהחלון הזה יהיה no-op ולא הורדה שנכשלת.
  static const String uploadedAssetState = 'uploaded';

  factory LibraryRelease.fromJson(Map<String, dynamic> json) {
    final assetsRaw = json['assets'];
    return LibraryRelease(
      tag: (json['tag_name'] as String?) ?? '',
      isPrerelease: (json['prerelease'] as bool?) ?? false,
      isDraft: (json['draft'] as bool?) ?? false,
      publishedAt: DateTime.tryParse((json['published_at'] as String?) ?? ''),
      assets: assetsRaw is List
          ? _withAssembledFullDb(
              assetsRaw
                  .whereType<Map<String, dynamic>>()
                  .where(_isUploaded)
                  .map(ReleaseAsset.fromJson)
                  .toList(growable: false),
              pending: {
                for (final e in assetsRaw.whereType<Map<String, dynamic>>())
                  if (!_isUploaded(e)) (e['name'] as String?) ?? '',
              },
            )
          : const [],
    );
  }

  // שדה חסר = API ישן או מראה מקומית; לא פוסלים על היעדרו.
  static bool _isUploaded(Map<String, dynamic> e) {
    final state = e['state'] as String?;
    return state == null || state == uploadedAssetState;
  }

  /// מוסיף נכס `seforim.db.zst` וירטואלי כשה-DB פורסם מפוצל, כדי שכל
  /// ה-planning יראה DB מלא רגיל. חלק חסר (עוד עולה) = אין DB מלא, כמו היום.
  static List<ReleaseAsset> _withAssembledFullDb(
    List<ReleaseAsset> assets, {
    required Set<String> pending,
  }) {
    const archive = ReleaseAsset.fullDbArchiveName;
    final byName = {for (final a in assets) a.name: a};
    if (byName.containsKey(archive)) return assets;
    // חלק או מניפסט שעדיין עולים: החלקים שכבר עלו אינם הקובץ כולו.
    if (pending.any((name) => name.startsWith('$archive.'))) return assets;
    final manifest = byName['$archive${SplitArchiveManifest.fileSuffix}'];
    if (manifest == null) return assets;

    final parts = <ReleaseAsset>[];
    for (var i = 0;; i++) {
      final part = byName[SplitArchiveManifest.partName(archive, i)];
      if (part == null) break;
      parts.add(part);
    }
    final partCount =
        assets.where((a) => a.name.startsWith('$archive.part-')).length;
    // פער ברצף (חלק שעדיין עולה) — הרכבה הייתה חסרה, ולכן אין DB מלא.
    if (parts.isEmpty || parts.length != partCount) return assets;
    if (parts.any((part) => part.size <= 0)) return assets;

    return List.unmodifiable([
      ...assets,
      ReleaseAsset(
        name: archive,
        downloadUrl: '',
        size: parts.fold<int>(0, (sum, part) => sum + part.size),
        updatedAt: manifest.updatedAt,
        parts: List.unmodifiable(parts),
        splitManifest: manifest,
      ),
    ]);
  }

  /// סריאליזציה לפורמט המראה המקומית (offline) — ראו
  /// [ReleaseAsset.toMirrorJson] להסבר על ההבדל מ-[fromJson]/JSON של GitHub.
  Map<String, dynamic> toMirrorJson() => {
        'tag': tag,
        'isPrerelease': isPrerelease,
        'isDraft': isDraft,
        if (publishedAt != null) 'publishedAt': publishedAt!.toIso8601String(),
        'assets': assets.map((a) => a.toMirrorJson()).toList(),
      };

  factory LibraryRelease.fromMirrorJson(Map<String, dynamic> json) {
    final assetsRaw = json['assets'];
    return LibraryRelease(
      tag: (json['tag'] as String?) ?? '',
      isPrerelease: (json['isPrerelease'] as bool?) ?? false,
      isDraft: (json['isDraft'] as bool?) ?? false,
      publishedAt: DateTime.tryParse((json['publishedAt'] as String?) ?? ''),
      assets: assetsRaw is List
          ? assetsRaw
              .map(
                  (e) => ReleaseAsset.fromMirrorJson(e as Map<String, dynamic>))
              .toList(growable: false)
          : const [],
    );
  }

  /// ה-manifests של patches דלתאיים ב-release זה.
  List<ReleaseAsset> get deltaManifestAssets =>
      assets.where((a) => a.isDeltaManifest).toList(growable: false);

  /// ה-DB המלא הדחוס ב-release זה, אם קיים.
  ReleaseAsset? get fullDbAsset {
    for (final asset in assets) {
      if (asset.isFullDbArchive) return asset;
    }
    return null;
  }

  /// מאתר asset לפי שם מדויק.
  ReleaseAsset? assetByName(String name) {
    for (final asset in assets) {
      if (asset.name == name) return asset;
    }
    return null;
  }

  @override
  List<Object?> get props => [tag, isPrerelease, isDraft, publishedAt, assets];
}

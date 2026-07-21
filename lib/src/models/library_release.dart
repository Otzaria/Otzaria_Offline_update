import 'package:equatable/equatable.dart';

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

  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
    this.id,
    this.updatedAt,
    this.digest,
  });

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

  /// `true` אם זהו manifest של patch דלתאי
  /// (`patch-vX-vY.db.zst.manifest.json`).
  bool get isDeltaManifest =>
      name.startsWith('patch-') && name.endsWith('.db.zst.manifest.json');

  /// `true` אם זהו ה-DB המלא הדחוס (`seforim.db.zst`).
  bool get isFullDbArchive => name == 'seforim.db.zst';

  @override
  List<Object?> get props => [name, downloadUrl, size, id, updatedAt, digest];
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

  factory LibraryRelease.fromJson(Map<String, dynamic> json) {
    final assetsRaw = json['assets'];
    return LibraryRelease(
      tag: (json['tag_name'] as String?) ?? '',
      isPrerelease: (json['prerelease'] as bool?) ?? false,
      isDraft: (json['draft'] as bool?) ?? false,
      publishedAt: DateTime.tryParse((json['published_at'] as String?) ?? ''),
      assets: assetsRaw is List
          ? assetsRaw
              .map((e) => ReleaseAsset.fromJson(e as Map<String, dynamic>))
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

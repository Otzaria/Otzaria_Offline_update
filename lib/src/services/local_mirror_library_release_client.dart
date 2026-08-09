import 'dart:convert';
import 'dart:io';

import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../models/delta_manifest.dart';
import '../models/library_release.dart';
import 'library_release_source.dart';

/// נזרק כשתיקיית המראה המקומית (offline) חסרה או פגומה — למשל אם המשתמש
/// הצביע על תיקייה שאינה מראה תקינה (נבנתה על-ידי [LibraryMirrorExporter]).
class LocalMirrorException implements Exception {
  final String message;
  const LocalMirrorException(this.message);
  @override
  String toString() => 'LocalMirrorException: $message';
}

/// מקור [LibraryReleaseSource] שקורא מתיקייה מקומית (USB / תיקייה משותפת)
/// במקום מ-GitHub — מיועד למחשבים בלי אינטרנט בכלל. התיקייה חייבת להיבנות
/// מראש (במחשב עם אינטרנט) על-ידי [LibraryMirrorExporter], ולהכיל קובץ
/// `releases.json` בפורמט [LibraryRelease.toMirrorJson] וכן את כל קובצי
/// ה-assets בנתיבים היחסיים ש-`releases.json` מצביע עליהם.
///
/// כל `downloadUrl` בתוך `releases.json` הוא נתיב **יחסי** לתיקיית המראה —
/// כאן הם מומרים לנתיבים מוחלטים לפני שהם מוחזרים החוצה, כך ש-
/// [PatchDownloader] (שמצפה למחרוזת URL/נתיב מוחלט אחת) יכול להשתמש בהם
/// ישירות בלי לדעת דבר על מבנה התיקייה.
class LocalMirrorLibraryReleaseClient implements LibraryReleaseSource {
  LocalMirrorLibraryReleaseClient({required this.mirrorDir});

  /// תיקיית המראה המקומית — הנתיב שהמשתמש בחר (USB / תיקייה משותפת).
  final String mirrorDir;

  static const String manifestFileName = 'releases.json';

  String get _releasesJsonPath =>
      '$mirrorDir${Platform.pathSeparator}$manifestFileName';

  @override
  Future<List<LibraryRelease>> fetchReleases() async {
    final strings = AppL10n.strings.libraryDomain;
    final file = File(_releasesJsonPath);
    if (!await file.exists()) {
      throw LocalMirrorException(
        strings.mirrorManifestMissing(manifestFileName, mirrorDir),
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(await file.readAsString());
    } catch (error) {
      throw LocalMirrorException(
        strings.mirrorManifestCorrupt(manifestFileName, mirrorDir, '$error'),
      );
    }
    if (decoded is! Map<String, dynamic> || decoded['releases'] is! List) {
      throw LocalMirrorException(
        strings.mirrorManifestUnexpectedShape(manifestFileName, mirrorDir),
      );
    }

    final releases = (decoded['releases'] as List)
        .whereType<Map<String, dynamic>>()
        .map(LibraryRelease.fromMirrorJson)
        .map(_resolveReleaseAssetPaths)
        .toList(growable: false);
    return releases;
  }

  /// ממיר את ה-`downloadUrl` היחסי של כל asset בתוך release למוחלט, יחסית
  /// ל-[mirrorDir], כדי ש-[fetchManifest] ו-[PatchDownloader] יוכלו להשתמש
  /// בו ישירות בלי הקשר נוסף.
  LibraryRelease _resolveReleaseAssetPaths(LibraryRelease release) {
    return LibraryRelease(
      tag: release.tag,
      isPrerelease: release.isPrerelease,
      isDraft: release.isDraft,
      publishedAt: release.publishedAt,
      assets: release.assets
          .map((a) => ReleaseAsset(
                name: a.name,
                downloadUrl: _absolutePath(a.downloadUrl),
                size: a.size,
                id: a.id,
                updatedAt: a.updatedAt,
                digest: a.digest,
              ))
          .toList(growable: false),
    );
  }

  String _absolutePath(String relative) =>
      '$mirrorDir${Platform.pathSeparator}$relative';

  @override
  Future<DeltaManifest> fetchManifest(String url) async {
    // url כאן הוא כבר נתיב מוחלט (הומר ב-_resolveReleaseAssetPaths למעלה).
    final strings = AppL10n.strings.libraryDomain;
    final file = File(url);
    if (!await file.exists()) {
      throw LocalMirrorException(strings.mirrorPatchManifestMissing(url));
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(await file.readAsString());
    } catch (error) {
      throw LocalMirrorException(
        strings.mirrorPatchManifestCorrupt(url, '$error'),
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw LocalMirrorException(strings.mirrorPatchManifestNotJson(url));
    }
    return DeltaManifest.fromJson(decoded);
  }

  @override
  void dispose() {}
}

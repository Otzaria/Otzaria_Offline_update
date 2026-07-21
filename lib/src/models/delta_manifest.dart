import 'package:equatable/equatable.dart';

/// מתאר קובץ patch בודד בתוך manifest, כולל פרטי הדחיסה וה-hashes
/// לאימות הקובץ הדחוס והמחולץ.
class PatchFileEntry extends Equatable {
  /// שם הקובץ הדחוס, למשל `patch-v1-v2.db.zst`.
  final String file;

  /// סוג הדחיסה. נתמך כרגע `zstd` בלבד.
  final String compression;

  /// sha256 של הקובץ הדחוס (hex).
  final String sha256;

  /// גודל הקובץ הדחוס בבייטים.
  final int size;

  /// sha256 של הקובץ אחרי חילוץ (hex).
  final String uncompressedSha256;

  /// גודל הקובץ אחרי חילוץ בבייטים.
  final int uncompressedSize;

  const PatchFileEntry({
    required this.file,
    required this.compression,
    required this.sha256,
    required this.size,
    required this.uncompressedSha256,
    required this.uncompressedSize,
  });

  /// סוגי הדחיסה הנתמכים. patch בעל דחיסה אחרת ייכשל ב-parse.
  static const Set<String> supportedCompressions = {'zstd'};

  /// בונה [PatchFileEntry] מ-JSON. זורק [FormatException] אם חסר שדה חובה
  /// או אם סוג הדחיסה אינו נתמך.
  factory PatchFileEntry.fromJson(Map<String, dynamic> json) {
    final compression = _requireString(json, 'compression');
    if (!supportedCompressions.contains(compression)) {
      throw FormatException('דחיסה לא נתמכת ב-patch: $compression');
    }
    return PatchFileEntry(
      file: _requireString(json, 'file'),
      compression: compression,
      sha256: _requireString(json, 'sha256'),
      size: _requireInt(json, 'size'),
      uncompressedSha256: _requireString(json, 'uncompressedSha256'),
      uncompressedSize: _requireInt(json, 'uncompressedSize'),
    );
  }

  @override
  List<Object?> get props =>
      [file, compression, sha256, size, uncompressedSha256, uncompressedSize];
}

/// מייצג manifest של patch דלתאי (`patch-vX-vY.db.zst.manifest.json`).
///
/// כל apply מאומת מול ה-hashes כאן: לפני apply משווים את ה-hash המקומי
/// ל-[fromContentHash], ואחרי apply משווים ל-[toContentHash].
class DeltaManifest extends Equatable {
  final int fromVersion;
  final int toVersion;
  final int fromSchemaVersion;
  final int toSchemaVersion;

  /// logical content hash צפוי של ה-DB *לפני* החלת ה-patch.
  final String fromContentHash;

  /// logical content hash צפוי של ה-DB *אחרי* החלת ה-patch.
  final String toContentHash;

  /// קבצי ה-patch להורדה והחלה (כרגע תמיד קובץ אחד).
  final List<PatchFileEntry> patchFiles;

  /// שדות אופציונליים עתידיים — נשמרים אם קיימים, אך אינם חובה.
  final List<int> booksTouched;
  final String? catalogBlobName;

  const DeltaManifest({
    required this.fromVersion,
    required this.toVersion,
    required this.fromSchemaVersion,
    required this.toSchemaVersion,
    required this.fromContentHash,
    required this.toContentHash,
    required this.patchFiles,
    this.booksTouched = const [],
    this.catalogBlobName,
  });

  /// בונה [DeltaManifest] מ-JSON. זורק [FormatException] אם חסר שדה חובה.
  /// שדות לא מוכרים מתעלמים מהם בשקט (תאימות קדימה).
  factory DeltaManifest.fromJson(Map<String, dynamic> json) {
    final patchFilesRaw = json['patchFiles'];
    if (patchFilesRaw is! List || patchFilesRaw.isEmpty) {
      throw const FormatException('שדה חובה חסר או ריק ב-manifest: patchFiles');
    }
    final booksTouchedRaw = json['booksTouched'];
    return DeltaManifest(
      fromVersion: _requireInt(json, 'fromVersion'),
      toVersion: _requireInt(json, 'toVersion'),
      fromSchemaVersion: _requireInt(json, 'fromSchemaVersion'),
      toSchemaVersion: _requireInt(json, 'toSchemaVersion'),
      fromContentHash: _requireString(json, 'fromContentHash'),
      toContentHash: _requireString(json, 'toContentHash'),
      patchFiles: patchFilesRaw
          .map((e) => PatchFileEntry.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      booksTouched: booksTouchedRaw is List
          ? booksTouchedRaw.map((e) => (e as num).toInt()).toList()
          : const [],
      catalogBlobName: json['catalogBlobName'] as String?,
    );
  }

  /// סכום הגדלים הדחוסים של כל קבצי ה-patch (לתצוגת גודל הורדה).
  int get totalCompressedSize =>
      patchFiles.fold<int>(0, (sum, f) => sum + f.size);

  @override
  List<Object?> get props => [
        fromVersion,
        toVersion,
        fromSchemaVersion,
        toSchemaVersion,
        fromContentHash,
        toContentHash,
        patchFiles,
        booksTouched,
        catalogBlobName,
      ];
}

String _requireString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('שדה חובה חסר או לא תקין ב-manifest: $key');
  }
  return value;
}

int _requireInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num) {
    throw FormatException('שדה חובה חסר או לא תקין ב-manifest: $key');
  }
  return value.toInt();
}

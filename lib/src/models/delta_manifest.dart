import 'package:equatable/equatable.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

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

  /// סוגי הדחיסה הנתמכים. דחיסה אחרת נקראת בסלחנות והקשת נפסלת בתכנון
  /// ([DeltaManifest.hasSupportedCompression]) — כשל בפענוח היה מעלים גרסה.
  static const Set<String> supportedCompressions = {'zstd'};

  /// בונה [PatchFileEntry] מ-JSON. זורק [FormatException] אם חסר שדה חובה.
  factory PatchFileEntry.fromJson(Map<String, dynamic> json) {
    final compression = _requireString(json, 'compression');
    return PatchFileEntry(
      file: _requireFileName(json, 'file'),
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

  /// גרסת פורמט `patch.db` (`patch_meta.schema_version`) שהיצרן מפרסם. ציר
  /// נפרד מסכמת ה-DB — ראו `kSupportedPatchFormatVersion`. `null` במניפסט
  /// שאינו מצהיר עליו (סכמות 1–3 קדמו לשדה), ואז הפסילה נשארת ב-preflight
  /// של `PatchApplier` במקום בתכנון.
  final int? patchFormatVersion;

  /// logical content hash צפוי של ה-DB *לפני* החלת ה-patch.
  final String fromContentHash;

  /// logical content hash צפוי של ה-DB *אחרי* החלת ה-patch.
  final String toContentHash;

  /// קבצי ה-patch להורדה והחלה (כרגע תמיד קובץ אחד).
  final List<PatchFileEntry> patchFiles;

  /// מניפסט "מחסום" של מעבר סכמה: אינו patch אמיתי ולעולם אינו שלב במסלול
  /// דלתא — המעבר מ-[fromVersion] מחייב מסד מלא.
  final bool fullRebase;

  /// שדות אופציונליים עתידיים — נשמרים אם קיימים, אך אינם חובה.
  final List<int> booksTouched;
  final String? catalogBlobName;

  const DeltaManifest({
    required this.fromVersion,
    required this.toVersion,
    required this.fromSchemaVersion,
    required this.toSchemaVersion,
    this.patchFormatVersion,
    required this.fromContentHash,
    required this.toContentHash,
    required this.patchFiles,
    this.fullRebase = false,
    this.booksTouched = const [],
    this.catalogBlobName,
  });

  factory DeltaManifest.fromJson(Map<String, dynamic> json) {
    final patchFilesRaw = json['patchFiles'];
    if (patchFilesRaw is! List ||
        patchFilesRaw.isEmpty ||
        patchFilesRaw.any((e) => e is! Map<String, dynamic>)) {
      throw FormatException(
        AppL10n.strings.libraryDomain.manifestMissingPatchFiles,
      );
    }
    final booksTouchedRaw = json['booksTouched'];
    final catalogBlobName = json['catalogBlobName'];
    final patchFormatVersion = _optionalInt(json, 'patchFormatVersion');
    return DeltaManifest(
      fromVersion: _requireInt(json, 'fromVersion'),
      toVersion: _requireInt(json, 'toVersion'),
      fromSchemaVersion: _requireInt(json, 'fromSchemaVersion'),
      toSchemaVersion: _requireInt(json, 'toSchemaVersion'),
      patchFormatVersion: patchFormatVersion,
      fromContentHash: _requireString(json, 'fromContentHash'),
      toContentHash: _requireString(json, 'toContentHash'),
      patchFiles: patchFilesRaw
          .cast<Map<String, dynamic>>()
          .map(PatchFileEntry.fromJson)
          .toList(growable: false),
      fullRebase: _optionalBool(json, 'fullRebase') ?? false,
      booksTouched: booksTouchedRaw is List
          ? booksTouchedRaw.whereType<num>().map((e) => e.toInt()).toList()
          : const [],
      catalogBlobName: catalogBlobName is String ? catalogBlobName : null,
    );
  }

  /// האם כל קבצי ה-patch בדחיסה שאנו יודעים לחלץ.
  bool get hasSupportedCompression => patchFiles.every(
      (f) => PatchFileEntry.supportedCompressions.contains(f.compression));

  /// סכום הגדלים הדחוסים של כל קבצי ה-patch (לתצוגת גודל הורדה).
  int get totalCompressedSize =>
      patchFiles.fold<int>(0, (sum, f) => sum + f.size);

  @override
  List<Object?> get props => [
        fromVersion,
        toVersion,
        fromSchemaVersion,
        toSchemaVersion,
        patchFormatVersion,
        fromContentHash,
        toContentHash,
        patchFiles,
        fullRebase,
        booksTouched,
        catalogBlobName,
      ];
}

String _requireString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException(
      AppL10n.strings.libraryDomain.manifestMissingField(key),
    );
  }
  return value;
}

String _requireFileName(Map<String, dynamic> json, String key) {
  final value = _requireString(json, key);
  if (value.contains('/') ||
      value.contains(r'\') ||
      value == '.' ||
      value == '..') {
    throw FormatException(
      AppL10n.strings.libraryDomain.manifestMissingField(key),
    );
  }
  return value;
}

int _requireInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num) {
    throw FormatException(
      AppL10n.strings.libraryDomain.manifestMissingField(key),
    );
  }
  return value.toInt();
}

/// שדה בוליאני אופציונלי; ערך מסוג אחר הוא מניפסט פגום.
bool? _optionalBool(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key) || json[key] == null) return null;
  final value = json[key];
  if (value is! bool) {
    throw FormatException(
      AppL10n.strings.libraryDomain.manifestMissingField(key),
    );
  }
  return value;
}

/// שדה מספרי אופציונלי: חסר או `null` ⇒ `null`, אך ערך מסוג אחר הוא מניפסט
/// פגום ולא "שדה שאיננו מכירים".
int? _optionalInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! num) {
    throw FormatException(
      AppL10n.strings.libraryDomain.manifestMissingField(key),
    );
  }
  return value.toInt();
}

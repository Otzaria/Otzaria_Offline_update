import 'package:equatable/equatable.dart';

/// חלק בודד של נכס מפוצל (`<archive>.part-NNN`).
class SplitArchivePart extends Equatable {
  final String name;
  final int size;

  /// sha256 של החלק (hex, אותיות קטנות).
  final String sha256;

  const SplitArchivePart({
    required this.name,
    required this.size,
    required this.sha256,
  });

  @override
  List<Object?> get props => [name, size, sha256];
}

/// המניפסט שמלווה נכס שפוצל בגלל מגבלת 2GiB לנכס ב-GitHub
/// (`<archive>.manifest.json`, הפורמט של `split_release_asset.sh` באוצריא).
class SplitArchiveManifest extends Equatable {
  /// הגרסה היחידה של הפורמט שידועה לנו; אחרת עדיף להיכשל מלהרכיב לא נכון.
  static const int supportedSchemaVersion = 1;

  /// סיומת קובץ המניפסט, לצד שם הנכס המקורי.
  static const String fileSuffix = '.manifest.json';

  final String archive;
  final int size;

  /// sha256 של הנכס המורכב (hex, אותיות קטנות).
  final String sha256;
  final List<SplitArchivePart> parts;

  const SplitArchiveManifest({
    required this.archive,
    required this.size,
    required this.sha256,
    required this.parts,
  });

  static final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');

  /// זורק [FormatException] על כל חריגה מהחוזה — הרכבה חלקית גרועה מכשל.
  /// ההודעות טכניות: הן פרט בתוך הודעה מתורגמת, כמו ב-`_splitMismatch`.
  factory SplitArchiveManifest.fromJson(Map<String, dynamic> json) {
    final schema = json['schemaVersion'];
    if (schema != supportedSchemaVersion) {
      throw FormatException('unsupported schemaVersion: $schema');
    }
    final archive = _safeName(json['archive'], 'archive');
    final size = _positiveInt(json['size'], 'size');
    final digest = _sha(json['sha256'], 'sha256');
    final rawParts = json['parts'];
    if (rawParts is! List || rawParts.isEmpty) {
      throw const FormatException('parts missing or empty');
    }
    final parts = <SplitArchivePart>[];
    var total = 0;
    for (final (index, raw) in rawParts.indexed) {
      if (raw is! Map<String, dynamic>) {
        throw FormatException('parts[$index] is not an object');
      }
      final name = _safeName(raw['name'], 'parts[$index].name');
      // הסדר קובע את התוכן המורכב, ולכן שם שאינו במקומו הוא מניפסט שבור.
      if (name != partName(archive, index)) {
        throw FormatException(
            'parts[$index] is not ${partName(archive, index)}');
      }
      final partSize = _positiveInt(raw['size'], 'parts[$index].size');
      total += partSize;
      parts.add(SplitArchivePart(
        name: name,
        size: partSize,
        sha256: _sha(raw['sha256'], 'parts[$index].sha256'),
      ));
    }
    if (total != size) {
      throw FormatException('parts total $total != size $size');
    }
    return SplitArchiveManifest(
      archive: archive,
      size: size,
      sha256: digest,
      parts: List.unmodifiable(parts),
    );
  }

  /// שם החלק ה-[index] של [archive], בשלוש ספרות כמו אצל היצרן.
  static String partName(String archive, int index) =>
      '$archive.part-${index.toString().padLeft(3, '0')}';

  static String _safeName(Object? value, String field) {
    if (value is! String ||
        value.isEmpty ||
        value.contains('/') ||
        value.contains(r'\') ||
        value == '.' ||
        value == '..') {
      throw FormatException('$field is not a plain file name');
    }
    return value;
  }

  static int _positiveInt(Object? value, String field) {
    if (value is! int || value <= 0) {
      throw FormatException('$field is not a positive integer');
    }
    return value;
  }

  static String _sha(Object? value, String field) {
    final lower = value is String ? value.toLowerCase() : null;
    if (lower == null || !_hex64.hasMatch(lower)) {
      throw FormatException('$field is not a sha256');
    }
    return lower;
  }

  @override
  List<Object?> get props => [archive, size, sha256, parts];
}

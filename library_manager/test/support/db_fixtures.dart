import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:zstandard_native/zstandard_native_bindings.dart';

import 'zstd_fixtures.dart';

const String dummyContentHash =
    '0000000000000000000000000000000000000000000000000000000000000001';

var _fixtureSeq = 0;

Uint8List buildVersionOnlyDb(String dir, int dbVersion) {
  final path = p.join(dir, 'built-$dbVersion-${_fixtureSeq++}.db');
  final db = sqlite3.sqlite3.open(path);
  db.execute('CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT)');
  db.execute(
    "INSERT INTO schema_meta VALUES ('db_version', '$dbVersion'), "
    "('db_schema_version', '1')",
  );
  db.close();
  return File(path).readAsBytesSync();
}

String writeSchema2Db(
  String path, {
  required int version,
  required List<List> rows,
}) {
  final db = sqlite3.sqlite3.open(path);
  db.execute('CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT)');
  db.execute(
    "INSERT INTO schema_meta VALUES ('db_version','$version'),"
    "('db_schema_version','2')",
  );
  db.execute('CREATE TABLE source (id INTEGER PRIMARY KEY, name TEXT)');
  for (final row in rows) {
    db.execute('INSERT INTO source VALUES (?,?)', [row[0], row[1]]);
  }
  db.close();
  return path;
}

Uint8List buildSchema2Db(String dir, int version, List<List> rows) => File(
  writeSchema2Db(
    p.join(dir, 'schema2-$version-${_fixtureSeq++}.db'),
    version: version,
    rows: rows,
  ),
).readAsBytesSync();

PatchEdge buildSchema2PatchEdge(
  ZstandardNativeBindings zstd,
  String dir, {
  required int from,
  required int to,
  required List<List> upsertRows,
  String fromHash = dummyContentHash,
  String toHash = dummyContentHash,
  String? urlOverride,
  int toSchemaVersion = 2,
  String? sha256Override,
  String? uncompressedSha256Override,
  int? uncompressedSizeOverride,
}) {
  final raw = p.join(dir, 'patch_${from}_${to}_${_fixtureSeq++}.db');
  final db = sqlite3.sqlite3.open(raw);
  db.execute('CREATE TABLE patch_meta (key TEXT PRIMARY KEY, value TEXT)');
  db.execute(
    "INSERT INTO patch_meta VALUES ('schema_version','2'),"
    "('from_version','$from'),('to_version','$to')",
  );
  db.execute('CREATE TABLE migrations (version INTEGER PRIMARY KEY, sql TEXT)');
  db.execute(
    'CREATE TABLE upsert_schema_meta (key TEXT PRIMARY KEY, value TEXT)',
  );
  db.execute("INSERT INTO upsert_schema_meta VALUES ('db_version','$to')");
  db.execute('CREATE TABLE upsert_source (id INTEGER PRIMARY KEY, name TEXT)');
  for (final row in upsertRows) {
    db.execute('INSERT INTO upsert_source VALUES (?,?)', [row[0], row[1]]);
  }
  db.close();

  final rawBytes = File(raw).readAsBytesSync();
  final compressed = compressWithZstd(zstd, rawBytes);
  final zstPath = '$raw.zst';
  File(zstPath).writeAsBytesSync(compressed);
  final fileName = 'patch_$from-$to.db.zst';

  return PatchEdge(
    manifest: DeltaManifest(
      fromVersion: from,
      toVersion: to,
      fromSchemaVersion: 2,
      toSchemaVersion: toSchemaVersion,
      fromContentHash: fromHash,
      toContentHash: toHash,
      patchFiles: [
        PatchFileEntry(
          file: fileName,
          compression: 'zstd',
          sha256: sha256Override ?? sha256.convert(compressed).toString(),
          size: compressed.length,
          uncompressedSha256: uncompressedSha256Override ??
              sha256.convert(rawBytes).toString(),
          uncompressedSize: uncompressedSizeOverride ?? rawBytes.length,
        ),
      ],
    ),
    patchFileUrls: {fileName: urlOverride ?? zstPath},
    manifestUrl: 'manifest.json',
  );
}

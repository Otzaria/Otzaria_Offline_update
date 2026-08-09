import 'dart:io';
import 'dart:isolate';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:seforim_library_updater/src/models/delta_manifest.dart';
import 'package:seforim_library_updater/src/services/library_db_recovery_service.dart';
import 'package:seforim_library_updater/src/services/logical_content_hasher.dart';
import 'package:seforim_library_updater/src/services/patch_applier.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:test/test.dart';

/// נקודת כניסה top-level ל-isolate: מקבלת נתיב בלבד ופותחת את ה-DB בפנים.
/// חיבור sqlite פתוח **אינו** ניתן לשליחה — ראו הבדיקה "מלכודת ה-unsendable".
String hashDbAtPath(String dbPath) {
  final db = sqlite3.sqlite3.open(dbPath, mode: sqlite3.OpenMode.readOnly);
  try {
    return const LogicalContentHasher().compute(db);
  } finally {
    db.close();
  }
}

/// נקודת כניסה top-level שמקבלת גם את השפה: `Isolate.run` אינו יורש את
/// ה-static של [AppL10n], ולכן חובה לקרוא ל-`use` בתוך ה-isolate.
String applyExpectingFailure(String dbPath, String patchPath,
    DeltaManifest manifest, AppLanguage language) {
  AppL10n.use(language);
  try {
    const PatchApplier()
        .apply(dbPath: dbPath, patchPath: patchPath, manifest: manifest);
    return '';
  } on PatchApplyException catch (e) {
    return e.message;
  }
}

class _CapturesDb {
  _CapturesDb(this.db);
  final sqlite3.Database db;
  int rows() => db.select('SELECT 1').length;
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('isolate_contract'));
  tearDown(() {
    AppL10n.use(AppLanguage.hebrew);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  String buildDb(String name, {required int version, List<List>? rows}) {
    final path = '${tmp.path}${Platform.pathSeparator}$name';
    final db = sqlite3.sqlite3.open(path);
    db.execute('CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT)');
    db.execute("INSERT INTO schema_meta VALUES ('db_version','$version'),"
        "('db_schema_version','2')");
    db.execute('CREATE TABLE source (id INTEGER PRIMARY KEY, name TEXT)');
    for (final row in rows ?? const []) {
      db.execute('INSERT INTO source VALUES (?,?)', [row[0], row[1]]);
    }
    db.close();
    return path;
  }

  String buildPatch(String name, {required int from, required int to}) {
    final path = '${tmp.path}${Platform.pathSeparator}$name';
    final db = sqlite3.sqlite3.open(path);
    db.execute('CREATE TABLE patch_meta (key TEXT PRIMARY KEY, value TEXT)');
    db.execute("INSERT INTO patch_meta VALUES ('schema_version','2'),"
        "('from_version','$from'),('to_version','$to')");
    db.execute(
        'CREATE TABLE migrations (version INTEGER PRIMARY KEY, sql TEXT)');
    db.execute(
        'CREATE TABLE upsert_schema_meta (key TEXT PRIMARY KEY, value TEXT)');
    db.execute("INSERT INTO upsert_schema_meta VALUES ('db_version','$to')");
    db.execute(
        'CREATE TABLE upsert_source (id INTEGER PRIMARY KEY, name TEXT)');
    db.execute("INSERT INTO upsert_source VALUES (2,'bet')");
    db.close();
    return path;
  }

  DeltaManifest manifestFor(String fromHash, String toHash) => DeltaManifest(
        fromVersion: 1,
        toVersion: 2,
        fromSchemaVersion: 2,
        toSchemaVersion: 2,
        fromContentHash: fromHash,
        toContentHash: toHash,
        patchFiles: const [
          PatchFileEntry(
            file: 'p.db.zst',
            compression: 'zstd',
            sha256: 'x',
            size: 1,
            uncompressedSha256: 'y',
            uncompressedSize: 1,
          ),
        ],
      );

  // ⚠️ המלכודת שגרמה כבר לקריסה ולגלגול-אחור: closure שנוגע בשדה מופע לוכד
  // את `this` (ואיתו חיבורים חיים), וההודעה ל-isolate נכשלת.
  test('מלכודת ה-unsendable: לכידת חיבור sqlite חי נכשלת', () async {
    final db = sqlite3.sqlite3.openInMemory();
    db.execute('CREATE TABLE t (id INTEGER)');
    final holder = _CapturesDb(db);
    await expectLater(
      Isolate.run(() => holder.rows()),
      throwsA(isA<ArgumentError>().having(
        (e) => '$e',
        'message',
        contains('unsendable'),
      )),
    );
    db.close();
  });

  test('cloneOrCopyFile (top-level, מחרוזות בלבד) עובר ב-Isolate.run',
      () async {
    final src = '${tmp.path}${Platform.pathSeparator}src.bin';
    final dst = '${tmp.path}${Platform.pathSeparator}dst.bin';
    File(src).writeAsBytesSync(List.generate(4096, (i) => i % 251));

    await Isolate.run(() => cloneOrCopyFile(src, dst));
    expect(File(dst).readAsBytesSync(), File(src).readAsBytesSync());
  });

  test('LogicalContentHasher רץ ב-isolate כשמעבירים נתיב בלבד', () async {
    final path = buildDb('hash.db', version: 1, rows: [
      [1, 'aleph'],
    ]);
    final expected = hashDbAtPath(path);
    final inIsolate = await Isolate.run(() => hashDbAtPath(path));
    expect(inIsolate, expected);
  });

  // הדוגמה שב-README: apply שלם בתוך Isolate.run. הארגומנטים (נתיבים ו-
  // DeltaManifest) ניתנים לשליחה, וגם התוצאה חוזרת שלמה.
  test('PatchApplier.apply רץ ב-Isolate.run והתוצאה חוזרת', () async {
    final base = buildDb('base.db', version: 1, rows: [
      [1, 'aleph'],
    ]);
    final expectedDb = buildDb('expected.db', version: 2, rows: [
      [1, 'aleph'],
      [2, 'bet'],
    ]);
    final patch = buildPatch('patch.db', from: 1, to: 2);
    final manifest = manifestFor(hashDbAtPath(base), hashDbAtPath(expectedDb));

    final result = await Isolate.run(() => const PatchApplier()
        .apply(dbPath: base, patchPath: patch, manifest: manifest));

    expect(result.resultHash, manifest.toContentHash);
    expect(result.upserts, isNotEmpty);
    expect(hashDbAtPath(base), manifest.toContentHash);
  });

  group('AppL10n ב-isolate', () {
    // `Isolate.run` אינו יורש statics — בלי העברת השפה ההודעה תחזור לעברית.
    test('השפה אינה נורשת ל-isolate', () async {
      AppL10n.use(AppLanguage.english);
      final inside = await Isolate.run(() => AppL10n.language);
      expect(AppL10n.language, AppLanguage.english);
      expect(inside, AppLanguage.hebrew);
    });

    test('העברת השפה + AppL10n.use מחזירה הודעת שגיאה בשפה הנכונה', () async {
      final base = buildDb('lang_base.db', version: 5);
      final patch = buildPatch('lang_patch.db', from: 1, to: 2);
      final manifest = manifestFor('irrelevant', 'irrelevant');

      AppL10n.use(AppLanguage.english);
      final english = await Isolate.run(() =>
          applyExpectingFailure(base, patch, manifest, AppLanguage.english));
      final hebrew = await Isolate.run(() =>
          applyExpectingFailure(base, patch, manifest, AppLanguage.hebrew));

      expect(
          english,
          AppL10n.stringsFor(AppLanguage.english)
              .libraryDomain
              .localVersionMismatch(5, 1));
      expect(
          hebrew,
          AppL10n.stringsFor(AppLanguage.hebrew)
              .libraryDomain
              .localVersionMismatch(5, 1));
      expect(english, isNot(hebrew));
    });
  });
}

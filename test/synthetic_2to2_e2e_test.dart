import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:seforim_library_updater/src/models/delta_manifest.dart';
import 'package:seforim_library_updater/src/services/patch_applier.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// E2E אמיתי לדלתא סינתטית schema 2 → schema 2 דרך ה-updater האמיתי
/// (PatchApplier של החבילה, כולל verifyFromHash), באותה תבנית של בדיקות ה-E2E
/// הקיימות שדורשות SEFORIM_LIBRARY_RELEASES_DIR. שלא כמו בדיקות v14/v15 שה-
/// hashes שלהן קבועים בקוד, כאן ה-manifest נקרא מהקובץ שהמפיק הקוטליני ייצר,
/// כך שהבדיקה נשארת נכונה גם כשה-hasher מתעדכן.
///
/// המבנה הנדרש תחת `$SEFORIM_LIBRARY_RELEASES_DIR` (ניתן להרכיב כ-symlinks
/// לארטיפקטים שבתיקיית `build/` של מאגר SeforimLibrary):
///   synth-prev/seforim.db                          ← build/seforim.db (סכמה 2, db_version=1)
///   synth-next/patch-synth-2to2.db                 ← build/patch-synth-2to2.db (הלא-דחוס)
///   synth-next/patch-synth-2to2.db.zst.manifest.json ← build/patch-synth-2to2.db.zst.manifest.json
/// בהיעדר אחד מהקבצים הבדיקה מדולגת (אותה תבנית כמו שאר בדיקות ה-E2E).
void main() {
  group('PatchApplier synthetic 2->2 (real E2E via SEFORIM_LIBRARY_RELEASES_DIR)',
      () {
    final dir =
        Platform.environment['SEFORIM_LIBRARY_RELEASES_DIR'] ?? '/nonexistent';
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('synth_2to2'));
    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('apply synthetic 2->2 מגיע ל-toContentHash, מקפיץ db_version ומחיל את השינויים',
        () {
      final prevSrc = '$dir/synth-prev/seforim.db';
      final patchPath = '$dir/synth-next/patch-synth-2to2.db';
      final manifestPath =
          '$dir/synth-next/patch-synth-2to2.db.zst.manifest.json';
      if (!File(prevSrc).existsSync() ||
          !File(patchPath).existsSync() ||
          !File(manifestPath).existsSync()) {
        markTestSkipped('הגדר SEFORIM_LIBRARY_RELEASES_DIR עם ארטיפקטי synth-*');
        return;
      }

      // clonefile על APFS (מיידי, ללא מקום נוסף); fallback ל-copy רגיל.
      final dbPath = '${tmp.path}/seforim.db';
      final r = Process.runSync('cp', ['-c', prevSrc, dbPath]);
      if (r.exitCode != 0) Process.runSync('cp', [prevSrc, dbPath]);

      final manifest = DeltaManifest.fromJson(
          jsonDecode(File(manifestPath).readAsStringSync())
              as Map<String, dynamic>);
      // ה-plumbing מקומיט 8: הסכמה נחתמת ל-manifest מה-DBs (2 → 2).
      expect(manifest.fromSchemaVersion, 2);
      expect(manifest.toSchemaVersion, 2);
      expect(manifest.fromVersion, 1);
      expect(manifest.toVersion, 2);

      // verifyFromHash=true (ברירת מחדל) → מאמת גם שה-hasher הדארטי מסכים עם
      // ה-Kotlin על fromContentHash לפני apply. apply זורק אם toContentHash
      // אחרי ההחלה לא תואם, אז חזרה תקינה כבר מוכיחה את השער.
      final result = const PatchApplier()
          .apply(dbPath: dbPath, patchPath: patchPath, manifest: manifest);
      expect(result.resultHash, manifest.toContentHash);
      // book_base_text נכללת ב-kBooksTouchedTables בשני הצדדים.
      expect(result.booksTouched, containsAll(<int>[1, 2, 242, 255]));

      final db = sqlite3.sqlite3.open(dbPath, mode: sqlite3.OpenMode.readOnly);
      String meta(String k) => db
          .select("SELECT value FROM schema_meta WHERE key=?", [k])
          .first['value'] as String;
      int scalar(String sql) => db.select(sql).first.values.first as int;
      try {
        expect(meta('db_version'), '2');
        expect(meta('db_schema_version'), '2');
        // השינויים הסינתטיים חלו בפועל:
        expect(
            scalar('SELECT COUNT(*) FROM book_base_text '
                'WHERE bookId=1 AND baseBookId=2'),
            1); // הזוג החדש קיים
        expect(
            scalar('SELECT COUNT(*) FROM book_base_text '
                'WHERE bookId=242 AND baseBookId=255'),
            0); // הזוג שנמחק אינו
        expect(scalar('SELECT baseProvenance FROM link WHERE id=3'), 2);
        expect(
            scalar("SELECT COUNT(*) FROM line "
                "WHERE id=1 AND content LIKE '%<!--SYNTH-->'"),
            1);
        expect(
            scalar('SELECT COUNT(*) FROM link_anchor '
                'WHERE linkId=292 AND side=1 AND charStart=5'),
            1);
        expect(
            scalar('SELECT COUNT(*) FROM link_anchor '
                'WHERE linkId=292 AND side=0 AND charStart=61'),
            0);
      } finally {
        db.close();
      }
    }, timeout: const Timeout(Duration(minutes: 10)));
  });
}

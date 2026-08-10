import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'companion_assets.dart';
import 'zstd_file_decompressor.dart';

/// תוצאת התקנה של פריט נלווה אחד.
enum CompanionInstallOutcome { alreadyUpToDate, installed, failed, missing }

class CompanionInstallReport {
  const CompanionInstallReport(this.outcomes, this.errors);

  final Map<CompanionAsset, CompanionInstallOutcome> outcomes;
  final Map<CompanionAsset, Object> errors;

  bool get anyInstalled =>
      outcomes.values.any((o) => o == CompanionInstallOutcome.installed);
}

/// מתקין מהמראה את הקבצים הנלווים אל תיקיית הספרייה של אוצריא — אותם
/// יעדים, אותם סימוני-גרסה ואותו סדר כמו `CompanionAssetsService` באוצריא,
/// רק בלי רשת.
///
/// כל פריט הוא best-effort: כשל באחד נרשם ולא מפיל את השאר, בדיוק כמו שם.
class CompanionAssetsInstaller {
  const CompanionAssetsInstaller();

  /// שם תיקיית ה-PDF של התלמוד בתוך תיקיית הספרייה
  /// (`DatabaseConstants.talmudBavliFolderName`).
  static const String talmudFolderName = 'תלמוד בבלי';

  /// סימון הגרסה בתוך תיקיית התלמוד, והערך שנכתב בו לפני החילוץ —
  /// חילוץ שנקטע משאיר אותו, וכך אוצריא מתעלמת מההתקנה החלקית.
  static const String talmudVersionFileName = '.version';
  static const String talmudInstallingMarker = 'installing';

  static const String catalogDatabaseFileName = 'otzar-HB_catalog.db';
  static const String dictionaryFileName = 'lexical.db';

  /// מתקין את מה שיש במראה [mirrorDir] לתיקייה שבה יושב [dbPath].
  ///
  /// [dbPath] הוא הנתיב ל-`seforim.db` — כל שלושת הפריטים יושבים לצידו,
  /// כפי ש-`DatabaseConstants.getDatabaseDirectoryPath` מגדיר.
  ///
  /// [onWarning] מקבל כשל בפריט בודד. הכשל אינו מפיל את השאר, אבל הוא כן
  /// צריך להגיע ללוג — אחרת "התלמוד לא הותקן" נשאר בלתי נראה לחלוטין.
  Future<CompanionInstallReport> install({
    required String mirrorDir,
    required String dbPath,
    void Function(String stage)? onStage,
    void Function(String assetName, Object error)? onWarning,
    bool Function()? isCancelled,
  }) async {
    final manifest = await CompanionMirrorManifest.load(mirrorDir);
    final outcomes = <CompanionAsset, CompanionInstallOutcome>{};
    final errors = <CompanionAsset, Object>{};
    if (manifest == null || manifest.isEmpty) {
      return const CompanionInstallReport({}, {});
    }

    final libraryDir = p.dirname(dbPath);
    final strings = AppL10n.strings.libraryDomain;

    Future<void> run(
      CompanionAsset asset,
      String name,
      Future<bool> Function(CompanionMirrorEntry entry) body,
    ) async {
      if (isCancelled?.call() ?? false) return;
      final entry = manifest.entries[asset];
      if (entry == null) {
        outcomes[asset] = CompanionInstallOutcome.missing;
        return;
      }
      onStage?.call(strings.companionChecking(name));
      try {
        final installed = await body(entry);
        outcomes[asset] = installed
            ? CompanionInstallOutcome.installed
            : CompanionInstallOutcome.alreadyUpToDate;
      } catch (error) {
        outcomes[asset] = CompanionInstallOutcome.failed;
        errors[asset] = error;
        onWarning?.call(name, error);
      }
    }

    await run(
      CompanionAsset.talmud,
      strings.companionTalmudName,
      (entry) => _installTalmud(mirrorDir, libraryDir, entry, onStage),
    );
    await run(
      CompanionAsset.catalog,
      strings.companionCatalogName,
      (entry) => _installCatalog(mirrorDir, libraryDir, entry, onStage),
    );
    await run(
      CompanionAsset.dictionary,
      strings.companionDictionaryName,
      (entry) => _installDictionary(mirrorDir, libraryDir, entry, onStage),
    );

    return CompanionInstallReport(outcomes, errors);
  }

  /// `true` אם משהו במראה חדש ממה שמותקן — כדי שהבדיקה תוכל להציע עדכון גם
  /// כשהמסד עצמו מעודכן.
  Future<bool> hasPendingWork({
    required String mirrorDir,
    required String dbPath,
  }) async {
    final manifest = await CompanionMirrorManifest.load(mirrorDir);
    if (manifest == null || manifest.isEmpty) return false;
    final libraryDir = p.dirname(dbPath);

    final talmud = manifest.entries[CompanionAsset.talmud];
    if (talmud != null && !_talmudUpToDate(libraryDir, talmud)) return true;

    final catalog = manifest.entries[CompanionAsset.catalog];
    if (catalog != null && !_catalogUpToDate(libraryDir, catalog)) return true;

    final dictionary = manifest.entries[CompanionAsset.dictionary];
    if (dictionary != null && !_dictionaryUpToDate(libraryDir, dictionary)) {
      return true;
    }
    return false;
  }

  // ── תלמוד בבלי ────────────────────────────────────────────────────────

  bool _talmudUpToDate(String libraryDir, CompanionMirrorEntry entry) {
    final dir = Directory(p.join(libraryDir, talmudFolderName));
    if (!dir.existsSync()) return false;
    final marker = File(p.join(dir.path, talmudVersionFileName));
    if (!marker.existsSync()) return false;
    final installed = marker.readAsStringSync().trim();
    if (installed.isEmpty || installed == talmudInstallingMarker) return false;
    return installed == entry.versionMarker;
  }

  Future<bool> _installTalmud(
    String mirrorDir,
    String libraryDir,
    CompanionMirrorEntry entry,
    void Function(String stage)? onStage,
  ) async {
    if (_talmudUpToDate(libraryDir, entry)) return false;
    final strings = AppL10n.strings.libraryDomain;
    final archive = File(p.join(mirrorDir, entry.fileName));
    if (!await archive.exists()) {
      throw StateError(strings.companionsMirrorMissing);
    }

    onStage?.call(strings.companionInstalling(strings.companionTalmudName));
    final targetDir = Directory(p.join(libraryDir, talmudFolderName));
    await targetDir.create(recursive: true);
    final marker = File(p.join(targetDir.path, talmudVersionFileName));
    // הסימון נכתב לפני החילוץ: קטיעה באמצע משאירה התקנה חלקית **מסומנת**,
    // ואוצריא מתעלמת ממנה במקום להציג ספרים חסרים.
    marker.writeAsStringSync(talmudInstallingMarker);
    for (final entity in targetDir.listSync()) {
      if (entity is File && p.basename(entity.path) != talmudVersionFileName) {
        entity.deleteSync();
      }
    }

    // הארכיון מכיל את התיקייה 'תלמוד בבלי/' עצמה — מחולץ לתיקיית האב.
    final tarPath = p.join(libraryDir, '${entry.fileName}.tar');
    try {
      if (!await ZstdFileDecompressor.decompressFileToFile(
        archive.path,
        tarPath,
      )) {
        throw StateError(
          strings.companionExtractionFailed(strings.companionTalmudName),
        );
      }
      await extractFileToDisk(tarPath, libraryDir);
    } finally {
      _deleteQuietly(tarPath);
    }

    marker.writeAsStringSync(entry.versionMarker ?? '');
    return true;
  }

  // ── קטלוג otzar-HB ────────────────────────────────────────────────────

  bool _catalogUpToDate(String libraryDir, CompanionMirrorEntry entry) {
    final target = File(p.join(libraryDir, catalogDatabaseFileName));
    if (!target.existsSync()) return false;
    final mirrored = entry.version;
    if (mirrored == null) return true; // אין מול מה להשוות — לא נוגעים.
    final installed = _readCatalogVersion(target.path);
    return installed != null && installed >= mirrored;
  }

  Future<bool> _installCatalog(
    String mirrorDir,
    String libraryDir,
    CompanionMirrorEntry entry,
    void Function(String stage)? onStage,
  ) async {
    if (_catalogUpToDate(libraryDir, entry)) return false;
    final strings = AppL10n.strings.libraryDomain;
    final source = File(p.join(mirrorDir, entry.fileName));
    if (!await source.exists()) {
      throw StateError(strings.companionsMirrorMissing);
    }

    onStage?.call(strings.companionInstalling(strings.companionCatalogName));
    final target = p.join(libraryDir, catalogDatabaseFileName);
    final staged = '$target.new';
    _deleteQuietly(staged);
    try {
      if (entry.compressed) {
        if (!await ZstdFileDecompressor.decompressFileToFile(
          source.path,
          staged,
        )) {
          throw StateError(
            strings.companionExtractionFailed(strings.companionCatalogName),
          );
        }
      } else {
        await source.copy(staged);
      }
      _deleteQuietly(target);
      File(staged).renameSync(target);
    } catch (_) {
      _deleteQuietly(staged);
      rethrow;
    }

    // אוצריא קוראת את הגרסה מ-`db_meta`; בלי החתמה היא הייתה מורידה מחדש.
    final version = entry.version;
    if (version != null) _stampCatalogVersion(target, version);
    return true;
  }

  int? _readCatalogVersion(String path) {
    try {
      final db = sqlite3.sqlite3.open(path, mode: sqlite3.OpenMode.readOnly);
      try {
        final rows = db.select(
          'SELECT value FROM db_meta WHERE key = ?',
          const ['version'],
        );
        if (rows.isEmpty) return null;
        return int.tryParse('${rows.first.values.first}');
      } finally {
        db.close();
      }
    } catch (_) {
      return null;
    }
  }

  void _stampCatalogVersion(String path, int version) {
    try {
      final db = sqlite3.sqlite3.open(path);
      try {
        db.execute('CREATE TABLE IF NOT EXISTS db_meta '
            '(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
        db.execute(
          'INSERT OR REPLACE INTO db_meta (key, value) VALUES (?, ?)',
          ['version', '$version'],
        );
      } finally {
        db.close();
      }
    } catch (_) {
      // best-effort, כמו `_ensureVersionStamped` באוצריא.
    }
  }

  // ── מילון החיפוש ──────────────────────────────────────────────────────

  bool _dictionaryUpToDate(String libraryDir, CompanionMirrorEntry entry) {
    final target = File(p.join(libraryDir, dictionaryFileName));
    if (!target.existsSync() || target.lengthSync() == 0) return false;
    final marker = File('${target.path}.version');
    if (!marker.existsSync()) return false;
    return marker.readAsStringSync().trim() == (entry.tag ?? '');
  }

  Future<bool> _installDictionary(
    String mirrorDir,
    String libraryDir,
    CompanionMirrorEntry entry,
    void Function(String stage)? onStage,
  ) async {
    if (_dictionaryUpToDate(libraryDir, entry)) return false;
    final strings = AppL10n.strings.libraryDomain;
    final source = File(p.join(mirrorDir, entry.fileName));
    if (!await source.exists()) {
      throw StateError(strings.companionsMirrorMissing);
    }

    onStage?.call(strings.companionInstalling(strings.companionDictionaryName));
    final target = p.join(libraryDir, dictionaryFileName);
    final staged = '$target.new';
    _deleteQuietly(staged);
    try {
      await source.copy(staged);
      _deleteQuietly(target);
      File(staged).renameSync(target);
    } catch (_) {
      _deleteQuietly(staged);
      rethrow;
    }
    File('$target.version').writeAsStringSync(entry.tag ?? '');
    return true;
  }

  void _deleteQuietly(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }
}

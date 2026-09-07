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
  const CompanionInstallReport(this.outcomes, this.errors, this.delivered);

  final Map<CompanionAsset, CompanionInstallOutcome> outcomes;
  final Map<CompanionAsset, Object> errors;

  /// מזהה הגרסה שבמראה שהפריט הזה אכן קיבל כאן. נרשם ב-state, וזה מה שמונע
  /// הצעה חוזרת על מראה שכבר נמסרה — ראו [CompanionAssetsInstaller.pendingWork].
  /// **רק פריטים שהצליחו**: רישום של כשל היה מבליע עבודה אמיתית.
  final Map<CompanionAsset, String> delivered;

  bool get anyInstalled =>
      outcomes.values.any((o) => o == CompanionInstallOutcome.installed);
}

/// מה שבדיקת העדכון מצאה בקבצים הנלווים. **לא bool** — הצעה שאינה יודעת
/// לומר על מה היא מדברת מוצגת כ"יש עדכון לספרייה" ליד "גרסה 27 → 27",
/// והמשתמש קורא אותה כתקלה גם כשהיא מוצדקת.
class CompanionPendingReport {
  const CompanionPendingReport({
    this.pending = const {},
    this.unavailable = const {},
  });

  /// יש מה להתקין, והקובץ במראה שלם — הצעה שאפשר להשלים.
  final Set<CompanionAsset> pending;

  /// רשומה במניפסט שהקובץ שלה חסר או קטוע במראה. **אינה נספרת כהצעה**: היא
  /// אינה ניתנת להשלמה במחשב הזה, וכהצעה היא הייתה חוזרת בכל פתיחה לנצח.
  /// מדווחת בנפרד כדי שתגיע ללוג במקום להיעלם.
  final Set<CompanionAsset> unavailable;

  bool get hasPending => pending.isNotEmpty;
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
    final delivered = <CompanionAsset, String>{};
    if (manifest == null || manifest.isEmpty) {
      return const CompanionInstallReport({}, {}, {});
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
        // הפרדיקט הוא בדיוק מה שהבדיקה הבאה תשאל. התקנה שדיווחה הצלחה ולא
        // סיפקה אותו תציע את עצמה שוב בכל פתיחה בלי שדבר ישתנה — ולכן זה כשל
        // שחייב להישמע, ולא הצלחה שקטה.
        if (installed && !_isUpToDate(asset, libraryDir, entry)) {
          throw StateError(strings.companionStillPendingAfterInstall(name));
        }
        outcomes[asset] = installed
            ? CompanionInstallOutcome.installed
            : CompanionInstallOutcome.alreadyUpToDate;
        // **רק בהצלחה.** זו הראיה שהמראה הזו כבר נמסרה כאן, ובלעדיה כשל
        // חוזר היה נרשם כאילו הושלם ומעלים עבודה אמיתית.
        delivered[asset] = mirrorMarkerOf(asset, entry);
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

    return CompanionInstallReport(outcomes, errors, delivered);
  }

  /// מה שממתין בקבצים הנלווים, כדי שהבדיקה תוכל להציע עדכון גם כשהמסד עצמו
  /// מעודכן — ותדע **לומר על מה** היא מדברת.
  ///
  /// [delivered] הוא מה שהתקנה קודמת של הלאנצ'ר כבר מסרה למחשב הזה, לפי
  /// [mirrorMarkerOf]. בלעדיו ההצעה אינה נגמרת: סימוני התלמוד והמילון הם
  /// digest/תג ואין ביניהם סדר, ולכן "שונה ממה שבמראה" אינו "ישן ממה
  /// שבמראה" — קובץ שאוצריא עצמה רעננה מהרשת נראה כאן בדיוק כמו קובץ ישן,
  /// ההצעה חזרה בכל פתיחה, ולחיצה עליה הייתה מורידה אותו אחורה.
  Future<CompanionPendingReport> pendingWork({
    required String mirrorDir,
    required String dbPath,
    Map<CompanionAsset, String> delivered = const {},
  }) async {
    final manifest = await CompanionMirrorManifest.load(mirrorDir);
    if (manifest == null || manifest.isEmpty) {
      return const CompanionPendingReport();
    }
    final libraryDir = p.dirname(dbPath);
    final pending = <CompanionAsset>{};
    final unavailable = <CompanionAsset>{};

    for (final e in manifest.entries.entries) {
      if (_isUpToDate(e.key, libraryDir, e.value)) continue;
      // המראה הזו כבר נמסרה כאן ומשהו אחר יושב במקומה — לא מציעים שוב.
      // התנאי השני הוא מה שמבדיל בין "הוחלף בגרסה אחרת" לבין "נמחק": פריט
      // שנעלם לגמרי כן צריך לחזור.
      if (delivered[e.key] == mirrorMarkerOf(e.key, e.value) &&
          _isInstalledLocally(e.key, libraryDir)) {
        continue;
      }
      // **קיום אינו שלמות.** רשומה שהקובץ שלה חסר או קטוע במראה אינה הצעה
      // שאפשר להשלים — כהצעה היא הייתה חוזרת בכל פתיחה ונכשלת בכל לחיצה.
      if (!_mirrorFileReady(mirrorDir, e.value)) {
        unavailable.add(e.key);
        continue;
      }
      pending.add(e.key);
    }
    return CompanionPendingReport(pending: pending, unavailable: unavailable);
  }

  /// מזהה הגרסה של הפריט **במראה** — המחרוזת שנרשמת כ"נמסר" ונבדקת מולה.
  static String mirrorMarkerOf(
    CompanionAsset asset,
    CompanionMirrorEntry entry,
  ) {
    switch (asset) {
      case CompanionAsset.talmud:
        return entry.versionMarker ?? '';
      case CompanionAsset.catalog:
        return entry.version?.toString() ?? '';
      case CompanionAsset.dictionary:
        return entry.tag ?? '';
    }
  }

  /// הקובץ שהרשומה מצביעה עליו קיים במראה ובאורך שהיא מבטיחה. גודל 0
  /// ברשומה (מקור שלא הצהיר על גודל) נבדק כ"לא ריק" בלבד.
  bool _mirrorFileReady(String mirrorDir, CompanionMirrorEntry entry) {
    if (entry.fileName.isEmpty) return false;
    final file = File(p.join(mirrorDir, entry.fileName));
    if (!file.existsSync()) return false;
    final length = file.lengthSync();
    return entry.size > 0 ? length == entry.size : length > 0;
  }

  /// האם הפריט קיים כאן בכלל, בלי לשאול באיזו גרסה. מבדיל בין "מישהו אחר
  /// החליף אותו" (לא מציעים שוב) לבין "נמחק" (כן מציעים).
  bool _isInstalledLocally(CompanionAsset asset, String libraryDir) {
    switch (asset) {
      case CompanionAsset.talmud:
        final marker =
            File(p.join(libraryDir, talmudFolderName, talmudVersionFileName));
        return marker.existsSync() &&
            marker.readAsStringSync().trim() != talmudInstallingMarker;
      case CompanionAsset.catalog:
        return File(p.join(libraryDir, catalogDatabaseFileName)).existsSync();
      case CompanionAsset.dictionary:
        final file = File(p.join(libraryDir, dictionaryFileName));
        return file.existsSync() && file.lengthSync() > 0;
    }
  }

  /// הפרדיקט של פריט בודד. **נקודה אחת בלבד**, כי [pendingWork] וההתקנה
  /// חייבים לשאול בדיוק את אותה שאלה: פרדיקט שנענה "לא מעודכן" אחרי התקנה
  /// שהצליחה הוא הצעת עדכון שחוזרת בכל פתיחה.
  bool _isUpToDate(
    CompanionAsset asset,
    String libraryDir,
    CompanionMirrorEntry entry,
  ) {
    switch (asset) {
      case CompanionAsset.talmud:
        return _talmudUpToDate(libraryDir, entry);
      case CompanionAsset.catalog:
        return _catalogUpToDate(libraryDir, entry);
      case CompanionAsset.dictionary:
        return _dictionaryUpToDate(libraryDir, entry);
    }
  }

  // ── תלמוד בבלי ────────────────────────────────────────────────────────

  bool _talmudUpToDate(String libraryDir, CompanionMirrorEntry entry) {
    final dir = Directory(p.join(libraryDir, talmudFolderName));
    if (!dir.existsSync()) return false;
    final marker = File(p.join(dir.path, talmudVersionFileName));
    if (!marker.existsSync()) return false;
    final installed = marker.readAsStringSync().trim();
    if (installed == talmudInstallingMarker) return false;
    // מושווה מול `?? ''` בדיוק כמו שההתקנה כותבת. מניפסט בלי digest ובלי תג
    // אינו נושא מידע גרסה כלל, ופסילת הסימון הריק שנכתב עבורו הייתה מחלצת
    // ~450MB מחדש בכל פתיחה — בלי שדבר ישתנה.
    return installed == (entry.versionMarker ?? '');
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

    // הארכיון מכיל את התיקייה 'תלמוד בבלי/' עצמה — מחולץ לתיקיית האב.
    final tarPath = p.join(libraryDir, '${entry.fileName}.tar');
    try {
      // **הפרישה קודמת למחיקה.** ארכיון קטוע או כונן מלא נכשלים בשלב הזה,
      // ומחיקה לפניו הותירה את המשתמש בלי התלמוד שכבר היה לו — ועם סימון
      // 'installing' שמזמין את אותו כשל בכל פתיחה. המחיר הוא שיא אחסון גבוה
      // יותר לרגע: ה-tar לצד הקבצים הישנים.
      if (!await ZstdFileDecompressor.decompressFileToFile(
        archive.path,
        tarPath,
      )) {
        throw StateError(
          strings.companionExtractionFailed(strings.companionTalmudName),
        );
      }
      // הסימון נכתב לפני החילוץ: קטיעה באמצע משאירה התקנה חלקית **מסומנת**,
      // ואוצריא מתעלמת ממנה במקום להציג ספרים חסרים.
      marker.writeAsStringSync(talmudInstallingMarker);
      for (final entity in targetDir.listSync()) {
        if (entity is File &&
            p.basename(entity.path) != talmudVersionFileName) {
          entity.deleteSync();
        }
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

  /// **זורק בכשל, ובכוונה.** הנכס שיורד אינו נושא `db_meta.version` בעצמו —
  /// הגרסה מגיעה מ-`version.txt` נפרד — ולכן ההחתמה היא הראיה היחידה לגרסה
  /// שהותקנה. בליעה שקטה שלה השאירה קטלוג "ממתין" לנצח: העתקה מלאה בכל
  /// פתיחה, והצעת עדכון שלא נגמרת.
  void _stampCatalogVersion(String path, int version) {
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

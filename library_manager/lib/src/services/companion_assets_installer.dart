import 'dart:convert';
import 'dart:io';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart'
    show DiskSpaceProbe, kDefaultMaxExtractedBytes, withFileOperationLock;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'companion_assets.dart';
import 'companion_file_operations.dart';
import 'zstd_file_decompressor.dart';

/// תוצאת התקנה של פריט נלווה אחד.
enum CompanionInstallOutcome { alreadyUpToDate, installed, failed, missing }

typedef CompanionInstallProgress =
    void Function(String stage, int bytesDone, int? bytesTotal);

class CompanionInstallReport {
  const CompanionInstallReport(this.outcomes, this.errors, this.delivered);

  final Map<CompanionAsset, CompanionInstallOutcome> outcomes;
  final Map<CompanionAsset, Object> errors;

  /// מזהה הגרסה שבמראה שהפריט הזה אכן קיבל כאן. נרשם ב-state, וזה מה שמונע
  /// הצעה חוזרת על מראה שכבר נמסרה — ראו [CompanionAssetsInstaller.pendingWork].
  /// **רק פריטים שהצליחו**: רישום של כשל היה מבליע עבודה אמיתית.
  final Map<CompanionAsset, String> delivered;

  /// The first full-drive failure among [errors]; later items never started.
  StorageFullException? get storageFailure {
    for (final error in errors.values) {
      if (error is StorageFullException) return error;
    }
    return null;
  }

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
    this.mirrored = const {},
  });

  /// יש מה להתקין, והקובץ במראה שלם — הצעה שאפשר להשלים.
  final Set<CompanionAsset> pending;

  /// רשומה במניפסט שהקובץ שלה חסר או קטוע במראה. **אינה נספרת כהצעה**: היא
  /// אינה ניתנת להשלמה במחשב הזה, וכהצעה היא הייתה חוזרת בכל פתיחה לנצח.
  /// מדווחת בנפרד כדי שתגיע ללוג במקום להיעלם.
  final Set<CompanionAsset> unavailable;

  /// כל מה שרשום במניפסט — ריק כשהכונן לא נשא קובץ נלווה אחד.
  final Set<CompanionAsset> mirrored;

  bool get hasPending => pending.isNotEmpty;
}

/// מתקין מהמראה את הקבצים הנלווים אל תיקיית הספרייה של אוצריא — אותם
/// יעדים, אותם סימוני-גרסה ואותו סדר כמו `CompanionAssetsService` באוצריא,
/// רק בלי רשת.
///
/// כל פריט הוא best-effort: כשל באחד נרשם ולא מפיל את השאר, בדיוק כמו שם.
class CompanionAssetsInstaller {
  const CompanionAssetsInstaller({
    this.freeBytesFor,
    this.maxOutputBytes = kDefaultMaxExtractedBytes,
  }) : assert(maxOutputBytes > 0);

  /// Replaces the disk probe, for tests.
  final int? Function(String path)? freeBytesFor;

  final int maxOutputBytes;

  /// שם תיקיית ה-PDF של התלמוד בתוך תיקיית הספרייה
  /// (`DatabaseConstants.talmudBavliFolderName`).
  static const String talmudFolderName = 'תלמוד בבלי';

  /// סימון הגרסה של אוצריא; `installing` נשמר לזיהוי התקנות ישנות שנקטעו.
  static const String talmudVersionFileName = '.version';
  static const String talmudInstallingMarker = 'installing';

  /// מפרט מה שחולץ לכאן בפועל — **קובץ שלנו**, לא של אוצריא. `.version`
  /// חייב להישאר בדיוק ה-digest שאוצריא משווה אליו, ולכן מספר הקבצים
  /// והבייטים יושבים לצידו. נושא את הסימון שעבורו נכתב, כך שמפרט שנשאר
  /// מהתקנה קודמת אינו נבדק מול תוכן של גרסה אחרת.
  static const String talmudContentsFileName = '.version.contents';

  /// מתחת לגודל הזה הארכיון קטן מדי מכדי שיחס הגדלים יעיד על משהו: תקורת
  /// ה-tar (512 בייט לכל קובץ) יכולה לבדה לעבור את המרווח. ראו
  /// [_talmudContentsComplete].
  static const int talmudFloorMinArchiveBytes = 1 << 20;

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
    Map<CompanionAsset, String> delivered = const {},
    void Function(String stage)? onStage,
    CompanionInstallProgress? onProgress,
    void Function(String assetName, Object error)? onWarning,
    bool Function()? isCancelled,
    Future<void> Function()? beforeCommit,
  }) async {
    final manifest = await CompanionMirrorManifest.load(mirrorDir);
    final outcomes = <CompanionAsset, CompanionInstallOutcome>{};
    final errors = <CompanionAsset, Object>{};
    final deliveredNow = <CompanionAsset, String>{};
    final libraryDir = p.dirname(dbPath);
    final strings = AppL10n.strings.libraryDomain;
    var storageFailed = false;
    final recoveryFailed = <CompanionAsset>{};
    void recordFailure(CompanionAsset asset, Object error) {
      if (!recoveryFailed.add(asset)) return;
      final full = storageFullFromUpstream(error);
      outcomes[asset] = CompanionInstallOutcome.failed;
      errors[asset] = full ?? error;
      storageFailed = storageFailed || full != null;
      onWarning?.call(_nameForAsset(asset), full ?? error);
    }

    final sources = {
      if (manifest != null)
        for (final entry in manifest.entries.entries)
          entry.key: p.join(mirrorDir, entry.value.fileName),
    };
    void guardSourcesFor(CompanionAsset asset) {
      final target = _targetForAsset(libraryDir, asset);
      for (final source in sources.values) {
        guardCompanionSource(source, _ownedPathsForAsset(target, asset));
      }
    }

    // A source for one asset can be inside another asset's backup/staging.
    // Reject both conflicting jobs before any cleanup, including recovery for
    // an asset absent from the manifest. Unrelated assets remain best-effort.
    for (final source in sources.entries) {
      if (isCancelled?.call() == true) break;
      for (final owner in CompanionAsset.values) {
        final target = _targetForAsset(libraryDir, owner);
        try {
          guardCompanionSource(
            source.value,
            _ownedPathsForAsset(target, owner),
          );
        } catch (error) {
          recordFailure(source.key, error);
          recordFailure(owner, error);
        }
      }
    }
    for (final asset in CompanionAsset.values) {
      if (isCancelled?.call() == true || storageFailed) break;
      if (recoveryFailed.contains(asset)) continue;
      final target = _targetForAsset(libraryDir, asset);
      if (!Directory(companionBackupPath(target)).existsSync()) continue;
      try {
        guardSourcesFor(asset);
        await withFileOperationLock(target, () async {
          guardSourcesFor(asset);
          checkCompanionCancelled(isCancelled);
          await beforeCommit?.call();
          checkCompanionCancelled(isCancelled);
          recoverCompanionInstall(target, _pathsForAsset(target, asset));
        });
        outcomes[asset] = CompanionInstallOutcome.installed;
      } catch (error) {
        recordFailure(asset, error);
      }
    }
    if (manifest == null || manifest.isEmpty) {
      return CompanionInstallReport(outcomes, errors, deliveredNow);
    }
    final talmudBefore = _talmudStatsMemo(libraryDir);
    Future<void> run(
      CompanionAsset asset,
      String name,
      Future<bool> Function(CompanionMirrorEntry entry) body,
    ) async {
      if (isCancelled?.call() ?? false) return;
      // A full drive stops the writes that have not started; the rest of the
      // report stays.
      if (storageFailed || recoveryFailed.contains(asset)) return;
      final entry = manifest.entries[asset];
      if (entry == null) {
        outcomes.putIfAbsent(asset, () => CompanionInstallOutcome.missing);
        return;
      }
      onStage?.call(strings.companionChecking(name));
      try {
        final target = _targetForAsset(libraryDir, asset);
        if (!Directory(companionBackupPath(target)).existsSync() &&
            _wasDelivered(asset, libraryDir, entry, delivered, talmudBefore)) {
          outcomes[asset] = CompanionInstallOutcome.alreadyUpToDate;
          return;
        }
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
        deliveredNow[asset] = mirrorMarkerOf(asset, entry);
      } catch (error) {
        final full = storageFullFromUpstream(error);
        outcomes[asset] = CompanionInstallOutcome.failed;
        errors[asset] = full ?? error;
        storageFailed = storageFailed || full != null;
        onWarning?.call(name, full ?? error);
      }
    }

    await run(
      CompanionAsset.talmud,
      strings.companionTalmudName,
      (entry) => _installTalmud(
        mirrorDir,
        libraryDir,
        entry,
        onStage,
        onProgress,
        isCancelled,
        beforeCommit,
        () => guardSourcesFor(CompanionAsset.talmud),
      ),
    );
    await run(
      CompanionAsset.catalog,
      strings.companionCatalogName,
      (entry) => _installCatalog(
        mirrorDir,
        libraryDir,
        entry,
        onStage,
        onProgress,
        isCancelled,
        beforeCommit,
        () => guardSourcesFor(CompanionAsset.catalog),
      ),
    );
    await run(
      CompanionAsset.dictionary,
      strings.companionDictionaryName,
      (entry) => _installDictionary(
        mirrorDir,
        libraryDir,
        entry,
        onStage,
        onProgress,
        isCancelled,
        beforeCommit,
        () => guardSourcesFor(CompanionAsset.dictionary),
      ),
    );

    return CompanionInstallReport(outcomes, errors, deliveredNow);
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
    final libraryDir = p.dirname(dbPath);
    final pending = <CompanionAsset>{
      for (final asset in CompanionAsset.values)
        if (Directory(
          companionBackupPath(_targetForAsset(libraryDir, asset)),
        ).existsSync())
          asset,
    };
    final manifest = await CompanionMirrorManifest.load(mirrorDir);
    if (manifest == null || manifest.isEmpty) {
      return CompanionPendingReport(pending: pending);
    }
    final unavailable = <CompanionAsset>{};
    final talmudStats = _talmudStatsMemo(libraryDir);

    for (final e in manifest.entries.entries) {
      if (pending.contains(e.key)) continue;
      if (_isUpToDate(e.key, libraryDir, e.value, talmudStats)) continue;
      // המראה הזו כבר נמסרה כאן ומשהו אחר יושב במקומה — לא מציעים שוב.
      // התנאי השני הוא מה שמבדיל בין "הוחלף בגרסה אחרת" לבין "נמחק": פריט
      // שנעלם לגמרי כן צריך לחזור.
      if (_wasDelivered(e.key, libraryDir, e.value, delivered, talmudStats)) {
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
    return CompanionPendingReport(
      pending: pending,
      unavailable: unavailable,
      mirrored: manifest.entries.keys.toSet(),
    );
  }

  String _targetForAsset(String libraryDir, CompanionAsset asset) =>
      p.join(libraryDir, switch (asset) {
        CompanionAsset.talmud => talmudFolderName,
        CompanionAsset.catalog => catalogDatabaseFileName,
        CompanionAsset.dictionary => dictionaryFileName,
      });

  List<String> _pathsForAsset(String target, CompanionAsset asset) =>
      switch (asset) {
        CompanionAsset.talmud => [target],
        CompanionAsset.catalog => [
          target,
          '$target-wal',
          '$target-shm',
          '$target-journal',
        ],
        CompanionAsset.dictionary => [
          target,
          '$target.version',
          '$target.next',
          '$target.next.version',
        ],
      };

  List<String> _ownedPathsForAsset(String target, CompanionAsset asset) => [
    ..._pathsForAsset(target, asset),
    '$target.lock',
    '$target.offline-staging',
    companionBackupPath(target),
  ];

  String _nameForAsset(CompanionAsset asset) => switch (asset) {
    CompanionAsset.talmud => AppL10n.strings.libraryDomain.companionTalmudName,
    CompanionAsset.catalog =>
      AppL10n.strings.libraryDomain.companionCatalogName,
    CompanionAsset.dictionary =>
      AppL10n.strings.libraryDomain.companionDictionaryName,
  };

  bool _wasDelivered(
    CompanionAsset asset,
    String libraryDir,
    CompanionMirrorEntry entry,
    Map<CompanionAsset, String> delivered, [
    _TalmudStatsMemo? talmudStats,
  ]) {
    final recorded = delivered[asset];
    if (recorded == null) return false;
    final matches =
        recorded == mirrorMarkerOf(asset, entry) ||
        (asset == CompanionAsset.dictionary &&
            entry.sha256 != null &&
            recorded.endsWith('|${entry.sha256}'));
    return matches &&
        _isInstalledLocally(asset, libraryDir, entry, talmudStats);
  }

  static String mirrorMarkerOf(
    CompanionAsset asset,
    CompanionMirrorEntry entry,
  ) {
    switch (asset) {
      case CompanionAsset.talmud:
      case CompanionAsset.dictionary:
        return entry.versionMarker ?? '';
      case CompanionAsset.catalog:
        return entry.version?.toString() ?? '';
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
  bool _isInstalledLocally(
    CompanionAsset asset,
    String libraryDir,
    CompanionMirrorEntry entry, [
    _TalmudStatsMemo? talmudStats,
  ]) {
    switch (asset) {
      case CompanionAsset.talmud:
        final marker = File(
          p.join(libraryDir, talmudFolderName, talmudVersionFileName),
        );
        if (!marker.existsSync()) return false;
        final installed = marker.readAsStringSync().trim();
        if (installed == talmudInstallingMarker) return false;
        // תיקייה שתוכנה נמחק היא "נמחק", לא "הוחלף" — בלי זה המשמר של
        // `delivered` בולע בדיוק את המקרה של issue #33.
        return _talmudContentsComplete(
          libraryDir,
          entry,
          installed,
          talmudStats,
        );
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
    CompanionMirrorEntry entry, [
    _TalmudStatsMemo? talmudStats,
  ]) {
    switch (asset) {
      case CompanionAsset.talmud:
        return _talmudUpToDate(libraryDir, entry, talmudStats);
      case CompanionAsset.catalog:
        return _catalogUpToDate(libraryDir, entry);
      case CompanionAsset.dictionary:
        return _dictionaryUpToDate(libraryDir, entry);
    }
  }

  // ── תלמוד בבלי ────────────────────────────────────────────────────────

  _TalmudStatsMemo _talmudStatsMemo(String libraryDir) => _TalmudStatsMemo(
    () => _talmudFolderStats(Directory(p.join(libraryDir, talmudFolderName))),
  );

  bool _talmudUpToDate(
    String libraryDir,
    CompanionMirrorEntry entry, [
    _TalmudStatsMemo? talmudStats,
  ]) {
    final dir = Directory(p.join(libraryDir, talmudFolderName));
    if (!dir.existsSync()) return false;
    final marker = File(p.join(dir.path, talmudVersionFileName));
    if (!marker.existsSync()) return false;
    final installed = marker.readAsStringSync().trim();
    if (installed == talmudInstallingMarker) return false;
    // מושווה מול `?? ''` בדיוק כמו שההתקנה כותבת. מניפסט בלי digest ובלי תג
    // אינו נושא מידע גרסה כלל, ופסילת הסימון הריק שנכתב עבורו הייתה מחלצת
    // ~450MB מחדש בכל פתיחה — בלי שדבר ישתנה.
    if (installed != (entry.versionMarker ?? '')) return false;
    // הסימון תואם, והקבצים עדיין עשויים להיות חסרים מתחתיו.
    return _talmudContentsComplete(libraryDir, entry, installed, talmudStats);
  }

  /// האם תוכן תיקיית התלמוד שלם, ולא רק הסימון שמעליו. בלי זה תיקייה שנשאר
  /// בה PDF אחד מתוך כל הש"ס נקראת "מעודכנת" לנצח (issue #33).
  ///
  /// **אסור לו לטעות לחומרה.** "לא שלם" פירושו הצעה לחלץ ~450MB מחדש, והצעה
  /// כזו שחוזרת בכל פתיחה גרועה מהבאג עצמו. לכן שני מדרגים: מפרט מדויק
  /// שאנחנו כתבנו בהתקנה, ורק בהיעדרו רצפה גסה שהתקנה שלמה אינה יכולה
  /// ליפול מתחתיה.
  bool _talmudContentsComplete(
    String libraryDir,
    CompanionMirrorEntry entry,
    String marker, [
    _TalmudStatsMemo? talmudStats,
  ]) {
    final dir = Directory(p.join(libraryDir, talmudFolderName));
    final stats = talmudStats?.value ?? _talmudFolderStats(dir);
    final recorded = _readTalmudContents(dir, marker);
    // `>=` ולא `==`: קובץ שנוסף לתיקייה אינו חוסר.
    if (recorded != null) {
      return stats.files >= recorded.files && stats.bytes >= recorded.bytes;
    }
    // התקנה שלא אנחנו עשינו (אוצריא עצמה, או לאנצ'ר ישן) — אין מפרט. ה-PDF
    // כבר דחוס, ולכן חילוץ שלם שוקל בערך כמו הארכיון; רבע ממנו הוא חוסר
    // שאי אפשר לטעות בו, וכל דחיסה אמיתית רק מרחיבה את המרווח.
    if (entry.size < talmudFloorMinArchiveBytes) return true;
    return stats.bytes >= entry.size ~/ 4;
  }

  /// כמה קבצים ובכמה בייטים יושבים בתיקייה, בלי שני קובצי הסימון.
  ({int files, int bytes}) _talmudFolderStats(Directory dir) {
    if (!dir.existsSync()) return (files: 0, bytes: 0);
    var files = 0;
    var bytes = 0;
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name == talmudVersionFileName || name == talmudContentsFileName) {
        continue;
      }
      files++;
      try {
        bytes += entity.lengthSync();
      } catch (_) {}
    }
    return (files: files, bytes: bytes);
  }

  /// המפרט שנכתב כאן, ורק אם הוא נכתב עבור [marker] הנוכחי — מפרט שנשאר
  /// מגרסה קודמת מתאר תוכן אחר, והשוואה אליו הייתה הצעה שאינה נגמרת.
  ({int files, int bytes})? _readTalmudContents(Directory dir, String marker) {
    try {
      final file = File(p.join(dir.path, talmudContentsFileName));
      if (!file.existsSync()) return null;
      final json = jsonDecode(file.readAsStringSync());
      if (json is! Map<String, dynamic> || json['marker'] != marker) {
        return null;
      }
      final files = (json['files'] as num?)?.toInt();
      final bytes = (json['bytes'] as num?)?.toInt();
      if (files == null || bytes == null) return null;
      return (files: files, bytes: bytes);
    } catch (_) {
      return null;
    }
  }

  void _writeTalmudContents(
    Directory dir,
    String marker,
    ({int files, int bytes}) stats,
  ) {
    File(p.join(dir.path, talmudContentsFileName)).writeAsStringSync(
      jsonEncode({
        'marker': marker,
        'files': stats.files,
        'bytes': stats.bytes,
      }),
      flush: true,
    );
  }

  Future<bool> _installTalmud(
    String mirrorDir,
    String libraryDir,
    CompanionMirrorEntry entry,
    void Function(String stage)? onStage,
    CompanionInstallProgress? onProgress,
    bool Function()? isCancelled,
    Future<void> Function()? beforeCommit,
    void Function() guardSources,
  ) async {
    final strings = AppL10n.strings.libraryDomain;
    final target = p.join(libraryDir, talmudFolderName);
    final source = File(p.join(mirrorDir, entry.fileName));
    return _stageInstall(
      source,
      target,
      [target],
      isCancelled,
      beforeCommit,
      guardSources,
      (work) async {
        if (_talmudUpToDate(libraryDir, entry)) return false;
        _readyMirrorFile(mirrorDir, entry);
        final type = FileSystemEntity.typeSync(target, followLinks: false);
        if (type != FileSystemEntityType.notFound &&
            type != FileSystemEntityType.directory) {
          throw FileSystemException(
            strings.companionExtractionFailed(talmudFolderName),
            target,
          );
        }
        final stage = strings.companionInstalling(strings.companionTalmudName);
        onStage?.call(stage);
        final tarPath = p.join(work.path, 'talmud.tar');
        String? digest;
        if (!await ZstdFileDecompressor.decompressFileToFile(
          source.path,
          tarPath,
          maxOutputBytes: maxOutputBytes,
          isCancelled: isCancelled,
          onOutputProgress: (written) => onProgress?.call(stage, written, null),
          onSourceDigest: entry.sha256 == null ? null : (hex) => digest = hex,
        )) {
          throw StateError(
            strings.companionExtractionFailed(strings.companionTalmudName),
          );
        }
        _verifyDigest(entry, digest, strings.companionTalmudName);
        checkCompanionCancelled(isCancelled);
        final expected = await readCompanionTar(
          tarPath,
          rootName: talmudFolderName,
          ignoredNames: {talmudVersionFileName, talmudContentsFileName},
          maxOutputBytes: maxOutputBytes,
          isCancelled: isCancelled,
        );
        final expectedBytes = expected.fold<int>(
          0,
          (sum, file) => sum + file.size,
        );
        final preserved = await _talmudSubdirectories(
          Directory(target),
          isCancelled,
        );
        final preservedBytes = preserved.fold<int>(
          0,
          (sum, file) => sum + (file.size ?? 0),
        );
        final total = expectedBytes + preservedBytes;
        if (total > maxOutputBytes) {
          throw FormatException(
            strings.localFileTooLarge(maxOutputBytes, target),
          );
        }
        // Staging keeps the old tree intact, so none of its bytes are free space.
        _ensureSpaceForTalmud(libraryDir, total);
        final staged = Directory(p.join(work.path, talmudFolderName));
        await staged.create();
        var written = 0;
        onProgress?.call(stage, 0, total);
        for (final file in preserved) {
          checkCompanionCancelled(isCancelled);
          final destination = p.join(
            staged.path,
            p.relative(file.path, from: target),
          );
          if (file.size == null) {
            await Directory(destination).create(recursive: true);
          } else {
            await File(destination).parent.create(recursive: true);
            written += await copyCompanionFile(
              source: File(file.path),
              destination: destination,
              expectedSize: file.size!,
              maxOutputBytes: maxOutputBytes - written,
              isCancelled: isCancelled,
              onProgress: (bytes) =>
                  onProgress?.call(stage, written + bytes, total),
            );
          }
        }
        for (final file in expected) {
          checkCompanionCancelled(isCancelled);
          final destination = p.joinAll([
            work.path,
            ...p.posix.split(file.path),
          ]);
          await File(destination).parent.create(recursive: true);
          written += await copyCompanionFile(
            source: File(tarPath),
            destination: destination,
            start: file.offset,
            end: file.offset + file.size,
            expectedSize: file.size,
            maxOutputBytes: maxOutputBytes - written,
            isCancelled: isCancelled,
            onProgress: (bytes) =>
                onProgress?.call(stage, written + bytes, total),
          );
        }
        final installed = entry.versionMarker ?? '';
        _writeTalmudContents(staged, installed, (
          files: expected.length,
          bytes: expectedBytes,
        ));
        await File(
          p.join(staged.path, talmudVersionFileName),
        ).writeAsString(installed, flush: true);
        checkCompanionCancelled(isCancelled);
        await beforeCommit?.call();
        checkCompanionCancelled(isCancelled);
        commitCompanionInstall(target, {target: staged.path});
        return true;
      },
    );
  }

  Future<List<({String path, int? size})>> _talmudSubdirectories(
    Directory target,
    bool Function()? isCancelled,
  ) async {
    final preserved = <({String path, int? size})>[];
    if (!await target.exists()) return preserved;
    void add(FileSystemEntity entity) {
      checkCompanionCancelled(isCancelled);
      if (preserved.length >= 10000 || entity is Link) {
        throw FormatException(
          AppL10n.strings.libraryDomain.companionExtractionFailed(
            talmudFolderName,
          ),
        );
      }
      preserved.add((
        path: entity.path,
        size: entity is File ? entity.lengthSync() : null,
      ));
    }

    await for (final child in target.list(followLinks: false)) {
      checkCompanionCancelled(isCancelled);
      if (child is Link) add(child);
      if (child is! Directory) continue;
      add(child);
      await for (final entity in child.list(
        recursive: true,
        followLinks: false,
      )) {
        add(entity);
      }
    }
    return preserved;
  }

  void _ensureSpaceForTalmud(String libraryDir, int needed) {
    if (needed <= 0) return;
    final free = (freeBytesFor ?? DiskSpaceProbe.freeBytesFor)(libraryDir);
    if (!DiskSpaceProbe.lacksSpace(free, needed)) return;
    throw StorageFullException(
      dir: libraryDir,
      neededBytes: needed,
      freeBytes: free,
      message: AppL10n.strings.libraryDomain.notEnoughDiskSpace(
        libraryDir,
        DiskSpaceProbe.formatBytes(needed),
        DiskSpaceProbe.formatBytes(free!),
      ),
    );
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
    CompanionInstallProgress? onProgress,
    bool Function()? isCancelled,
    Future<void> Function()? beforeCommit,
    void Function() guardSources,
  ) async {
    final strings = AppL10n.strings.libraryDomain;
    final source = File(p.join(mirrorDir, entry.fileName));
    final target = p.join(libraryDir, catalogDatabaseFileName);
    final paths = _pathsForAsset(target, CompanionAsset.catalog);
    return _stageInstall(
      source,
      target,
      paths,
      isCancelled,
      beforeCommit,
      guardSources,
      (work) async {
        if (_catalogUpToDate(libraryDir, entry)) return false;
        _readyMirrorFile(mirrorDir, entry);
        final stage = strings.companionInstalling(strings.companionCatalogName);
        onStage?.call(stage);
        final staged = p.join(work.path, catalogDatabaseFileName);
        if (entry.compressed) {
          String? digest;
          if (!await ZstdFileDecompressor.decompressFileToFile(
            source.path,
            staged,
            maxOutputBytes: maxOutputBytes,
            isCancelled: isCancelled,
            onOutputProgress: (written) =>
                onProgress?.call(stage, written, null),
            onSourceDigest: entry.sha256 == null ? null : (hex) => digest = hex,
          )) {
            throw StateError(
              strings.companionExtractionFailed(strings.companionCatalogName),
            );
          }
          _verifyDigest(entry, digest, strings.companionCatalogName);
        } else {
          await _copyVerified(
            source,
            staged,
            entry,
            stage,
            onProgress,
            isCancelled,
          );
        }
        checkCompanionCancelled(isCancelled);
        // Opening an empty output in write mode would create a fresh database
        // with only db_meta, which quick_check would then accept. Validate the
        // original SQLite header before version stamping can modify it.
        await _verifyCatalogHeader(staged);
        checkCompanionCancelled(isCancelled);
        final version = entry.version;
        if (version != null) _stampCatalogVersion(staged, version);
        _verifyCatalog(staged);
        for (final path in paths) {
          final type = FileSystemEntity.typeSync(path, followLinks: false);
          if (type != FileSystemEntityType.notFound &&
              type != FileSystemEntityType.file) {
            throw FileSystemException(
              strings.companionExtractionFailed(strings.companionCatalogName),
              path,
            );
          }
        }
        checkCompanionCancelled(isCancelled);
        await beforeCommit?.call();
        checkCompanionCancelled(isCancelled);
        commitCompanionInstall(target, {
          target: staged,
          for (final path in paths.skip(1)) path: null,
        });
        return true;
      },
    );
  }

  Future<void> _verifyCatalogHeader(String path) async {
    final file = await File(path).open();
    try {
      final header = await file.read(16);
      if (await file.length() < 100 ||
          latin1.decode(header) != 'SQLite format 3\u0000') {
        throw FormatException(
          AppL10n.strings.libraryDomain.companionExtractionFailed(
            AppL10n.strings.libraryDomain.companionCatalogName,
          ),
        );
      }
    } finally {
      await file.close();
    }
  }

  void _verifyCatalog(String path) {
    final db = sqlite3.sqlite3.open(path, mode: sqlite3.OpenMode.readOnly);
    try {
      final result = db.select('PRAGMA quick_check');
      if (result.length != 1 || result.first.values.single != 'ok') {
        throw StateError(
          AppL10n.strings.libraryDomain.companionExtractionFailed(
            AppL10n.strings.libraryDomain.companionCatalogName,
          ),
        );
      }
    } finally {
      db.close();
    }
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
      db.execute('PRAGMA journal_mode = DELETE');
      db.execute(
        'CREATE TABLE IF NOT EXISTS db_meta '
        '(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
      db.execute('INSERT OR REPLACE INTO db_meta (key, value) VALUES (?, ?)', [
        'version',
        '$version',
      ]);
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
    final installed = marker.readAsStringSync().trim();
    return installed == (entry.versionMarker ?? '');
  }

  Future<bool> _installDictionary(
    String mirrorDir,
    String libraryDir,
    CompanionMirrorEntry entry,
    void Function(String stage)? onStage,
    CompanionInstallProgress? onProgress,
    bool Function()? isCancelled,
    Future<void> Function()? beforeCommit,
    void Function() guardSources,
  ) async {
    final strings = AppL10n.strings.libraryDomain;
    final source = File(p.join(mirrorDir, entry.fileName));
    final target = p.join(libraryDir, dictionaryFileName);
    final paths = _pathsForAsset(target, CompanionAsset.dictionary);
    return _stageInstall(
      source,
      target,
      paths,
      isCancelled,
      beforeCommit,
      guardSources,
      (work) async {
        if (_dictionaryUpToDate(libraryDir, entry)) return false;
        _readyMirrorFile(mirrorDir, entry);
        final stage = strings.companionInstalling(
          strings.companionDictionaryName,
        );
        onStage?.call(stage);
        final staged = p.join(work.path, dictionaryFileName);
        await _copyVerified(
          source,
          staged,
          entry,
          stage,
          onProgress,
          isCancelled,
        );
        final marker = '$staged.version';
        await File(
          marker,
        ).writeAsString(entry.versionMarker ?? '', flush: true);
        for (final path in paths) {
          final type = FileSystemEntity.typeSync(path, followLinks: false);
          if (type != FileSystemEntityType.notFound &&
              type != FileSystemEntityType.file) {
            throw FileSystemException(
              strings.companionExtractionFailed(
                strings.companionDictionaryName,
              ),
              path,
            );
          }
        }
        checkCompanionCancelled(isCancelled);
        await beforeCommit?.call();
        checkCompanionCancelled(isCancelled);
        commitCompanionInstall(target, {
          target: staged,
          '$target.version': marker,
          '$target.next': null,
          '$target.next.version': null,
        });
        return true;
      },
    );
  }

  Future<bool> _stageInstall(
    File source,
    String target,
    List<String> paths,
    bool Function()? isCancelled,
    Future<void> Function()? beforeCommit,
    void Function() guardSources,
    Future<bool> Function(Directory work) body,
  ) async {
    final work = Directory('$target.offline-staging');
    final owned = [
      ...paths,
      '$target.lock',
      companionBackupPath(target),
      work.path,
    ];
    guardSources();
    guardCompanionSource(source.path, owned);
    return withFileOperationLock(target, () async {
      guardSources();
      guardCompanionSource(source.path, owned);
      checkCompanionCancelled(isCancelled);
      if (Directory(companionBackupPath(target)).existsSync()) {
        await beforeCommit?.call();
        checkCompanionCancelled(isCancelled);
        recoverCompanionInstall(target, paths);
      }
      if (await work.exists()) await work.delete(recursive: true);
      await work.create();
      try {
        checkCompanionCancelled(isCancelled);
        return await body(work);
      } finally {
        try {
          await work.delete(recursive: true);
        } on FileSystemException {
          // Keep the original failure if the drive has disappeared.
        }
      }
    });
  }

  File _readyMirrorFile(String mirrorDir, CompanionMirrorEntry entry) {
    if (!_mirrorFileReady(mirrorDir, entry)) {
      throw StateError(AppL10n.strings.libraryDomain.companionsMirrorMissing);
    }
    return File(p.join(mirrorDir, entry.fileName));
  }

  Future<void> _copyVerified(
    File source,
    String destination,
    CompanionMirrorEntry entry,
    String stage,
    CompanionInstallProgress? onProgress,
    bool Function()? isCancelled,
  ) async {
    final expectedSize = entry.size > 0 ? entry.size : await source.length();
    await copyCompanionFile(
      source: source,
      destination: destination,
      maxOutputBytes: maxOutputBytes,
      expectedSize: expectedSize,
      expectedSha256: entry.sha256,
      isCancelled: isCancelled,
      onProgress: (written) => onProgress?.call(stage, written, expectedSize),
    );
  }

  void _verifyDigest(CompanionMirrorEntry entry, String? actual, String name) {
    final expected = entry.sha256;
    if (expected == null) return;
    if (actual == null || actual.toLowerCase() != expected.toLowerCase()) {
      throw StateError(
        AppL10n.strings.libraryDomain.checksumMismatchDetailed(
          name,
          expected,
          actual ?? '',
        ),
      );
    }
  }
}

class _TalmudStatsMemo {
  _TalmudStatsMemo(this._scan);

  final ({int files, int bytes}) Function() _scan;
  ({int files, int bytes})? _value;

  ({int files, int bytes}) get value => _value ??= _scan();
}

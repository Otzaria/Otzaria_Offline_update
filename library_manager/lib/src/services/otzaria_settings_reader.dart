import 'dart:async';
import 'dart:io';

import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

/// ההגדרות של אוצריא שרלוונטיות לאיתור מסד הספרים, כפי שהן שמורות בקופסת
/// ה-Hive שלה. `null` בשדה = המפתח לא קיים בקופסה.
class OtzariaSettings {
  const OtzariaSettings({
    this.libraryPath,
    this.libraryFolderName,
    this.dbEffectivePath,
    this.databasesPath,
    this.searchFeedbackConsent,
    this.searchFeedbackConsentVersion,
    this.semanticDataEnabled,
    this.semanticDownloadPaused,
    this.semanticModelQuantization,
  });

  final String? libraryPath;
  final String? libraryFolderName;
  final String? dbEffectivePath;

  /// תיקיית המסדים האישיים (`key-databases-path`) — שם יושב `user_state.db`.
  final String? databasesPath;

  final String? searchFeedbackConsent;
  final int? searchFeedbackConsentVersion;
  final bool? semanticDataEnabled;
  final bool? semanticDownloadPaused;
  final String? semanticModelQuantization;

  bool get semanticSearchReadyPreferences =>
      semanticDataEnabled == true &&
      semanticDownloadPaused != true &&
      (semanticModelQuantization == null ||
          semanticModelQuantization == 'int8');

  bool get searchFeedbackGranted =>
      searchFeedbackConsent == 'granted' &&
      (searchFeedbackConsentVersion ?? 0) >= 1;

  bool get isEmpty =>
      (libraryPath == null || libraryPath!.isEmpty) &&
      (dbEffectivePath == null || dbEffectivePath!.isEmpty);

  /// נתיב ה-`seforim.db` לפי ההגדרות — תרגום מדויק של
  /// `DatabaseConstants.getDatabasePath` באוצריא: דריסת ה-Android מנצחת,
  /// ואחרת `<libraryPath>/<folderName>/seforim.db` (בלי `folderName` כשהוא ריק).
  String? resolveDbPath({
    required p.Context path,
    String fileName = 'seforim.db',
  }) {
    final effective = dbEffectivePath;
    if (effective != null && effective.isNotEmpty) return effective;

    final base = libraryPath;
    if (base == null || base.isEmpty) return null;
    final folder = libraryFolderName ?? '';
    return folder.isEmpty
        ? path.join(base, fileName)
        : path.join(base, folder, fileName);
  }
}

/// קורא את קופסת ההגדרות של אוצריא (`app_preferences.hive`) שיושבת בשורש
/// הנתונים שלה.
///
/// **קורא מעותק.** פתיחת הקופסה במקומה הייתה יוצרת קובץ נעילה בתיקייה של
/// אוצריא ומתנגשת איתה כשהיא פתוחה; העתקה לתיקייה זמנית מבטיחה שהקריאה
/// לעולם לא נוגעת בהגדרות של המשתמש. כל כשל מוחזר כ-`null` — זו קריאה
/// אופציונלית שנועדה לשפר את האיתור, לא תנאי לפעולה.
class OtzariaSettingsReader {
  const OtzariaSettingsReader();

  static const String boxName = 'app_preferences';
  static const String boxFileName = '$boxName.hive';

  /// שמות המפתחות ב-`SettingsRepository` של אוצריא — חייבים להישאר זהים.
  static const String keyLibraryPath = 'key-library-path';
  static const String keyLibraryFolderName = 'key-library-folder-name';
  static const String keyDbEffectivePath = 'key-db-effective-path';
  static const String keyDatabasesPath = 'key-databases-path';
  static const String keySearchFeedbackConsent = 'key-search-feedback-consent';
  static const String keySearchFeedbackConsentVersion =
      'key-search-feedback-consent-version';
  static const String keySemanticDataEnabled = 'key-semantic-data-enabled';
  static const String keySemanticDownloadPaused =
      'key-semantic-download-paused';
  static const String keySemanticModelQuantization =
      'key-semantic-model-quantization';

  /// Hive מזהה קופסה פתוחה לפי **שם בלבד** ומתעלם מה-`path` — שתי קריאות
  /// מקבילות על שורשי נתונים שונים היו מקבלות את אותה קופסה, כלומר את
  /// ההגדרות של השורש הלא-נכון. מונה + מנעול מבטיחים שם ייחודי וריצה בטור.
  static int _readCounter = 0;
  static Future<void> _lock = Future<void>.value();

  /// התור שכל גישה לקופסאות של אוצריא עוברת בו — קריאה **וכתיבה**
  /// (`OtzariaSettingsWriter`) גם יחד, מאותה סיבה: `Hive.init` והמזהה לפי
  /// שם הם מצב גלובלי.
  static Future<T> runExclusively<T>(Future<T> Function() action) {
    final previous = _lock;
    final completer = Completer<void>();
    _lock = completer.future;
    return previous.then((_) => action()).whenComplete(completer.complete);
  }

  Future<OtzariaSettings?> read(String dataRootPath) =>
      runExclusively(() => _readExclusively(dataRootPath));

  Future<OtzariaSettings?> _readExclusively(String dataRootPath) async {
    final source = File(p.join(dataRootPath, boxFileName));
    if (!await source.exists()) return null;

    // שם ייחודי לכל קריאה: גם אם קופסה קודמת לא נסגרה כראוי, אין התנגשות.
    final uniqueName = '$boxName-${_readCounter++}';
    Directory? scratch;
    try {
      scratch = await Directory.systemTemp.createTemp('otzaria-settings-');
      await source.copy(p.join(scratch.path, '$uniqueName.hive'));

      Hive.init(scratch.path);
      final box = await Hive.openBox<dynamic>(uniqueName, path: scratch.path);
      try {
        return OtzariaSettings(
          libraryPath: _stringOrNull(box.get(keyLibraryPath)),
          libraryFolderName: _stringOrNull(box.get(keyLibraryFolderName)),
          dbEffectivePath: _stringOrNull(box.get(keyDbEffectivePath)),
          databasesPath: _stringOrNull(box.get(keyDatabasesPath)),
          searchFeedbackConsent: _stringOrNull(
            box.get(keySearchFeedbackConsent),
          ),
          searchFeedbackConsentVersion:
              box.get(keySearchFeedbackConsentVersion) is int
              ? box.get(keySearchFeedbackConsentVersion) as int
              : null,
          semanticDataEnabled: box.get(keySemanticDataEnabled) is bool
              ? box.get(keySemanticDataEnabled) as bool
              : null,
          semanticDownloadPaused: box.get(keySemanticDownloadPaused) is bool
              ? box.get(keySemanticDownloadPaused) as bool
              : null,
          semanticModelQuantization: _stringOrNull(
            box.get(keySemanticModelQuantization),
          ),
        );
      } finally {
        await box.close();
      }
    } catch (_) {
      return null;
    } finally {
      try {
        await scratch?.delete(recursive: true);
      } catch (_) {}
    }
  }

  static String? _stringOrNull(Object? value) =>
      (value is String && value.isNotEmpty) ? value : null;
}

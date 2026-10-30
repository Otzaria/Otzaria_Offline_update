import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';

import 'byte_size.dart';

/// לוגר פשוט מבוסס-קובץ: כל שורה נכתבת (append) ל-`<dataDir>/logs/launcher.log`
/// עם timestamp ורמה, כדי שאפשר יהיה לראות מה קרה בפועל אחרי שהאפליקציה
/// כבר נסגרה — בלי צורך בדיבאגר או בחיבור מסוף.
///
/// כשל בכתיבה ללוג עצמו **לא** מפיל את שאר האפליקציה — הלוג הוא כלי עזר, לא
/// חלק מהלוגיקה.
///
/// שתי תכונות שאינן מובנות מאליהן:
/// * **הכתיבות מוסדרות בטור**, דרך sink אחד פתוח, באצוות: השורות שהצטברו
///   נכתבות יחד ובסדר.
/// * **יש רוטציה.** הקובץ יושב על אותו כונן נייד שנוסע עם התוכנה, ובלי גבול
///   הוא היה גדל לנצח.
class AppLogger {
  AppLogger._(this._file);

  static AppLogger? _instance;

  /// מעל הגודל הזה הקובץ מוזז ל-`launcher.log.1` ומתחיל חדש.
  static const int maxBytes = 2 * 1024 * 1024;

  /// יש לקרוא פעם אחת, מוקדם ב-`main()`, לפני שנעשה שימוש ב-[instance].
  ///
  /// [version] ו-[payloadVersion] נכתבים בשורת הפתיחה — ראו [startLine].
  static Future<AppLogger> init(
    String dataDir, {
    String? version,
    String? payloadVersion,
  }) async {
    final file = File(p.join(await _resolveLogDir(dataDir), 'launcher.log'));
    final logger = AppLogger._(file);
    _instance = logger;
    logger.info(startLine(version: version, payloadVersion: payloadVersion));
    // **הנתיב, בכל הרצה.** הלוג נודד לתיקיית המחשב כשהכונן מוגן מכתיבה, ואז
    // התיקייה שעל הכונן קופאת בלי שדבר יעיד על כך — משתמש שנשאל "שלח לוג"
    // שולח קובץ בן חודשיים ומדווח בצדק "התוכנה לא כותבת ללוג".
    logger.info('--- log file: ${file.path} ---');
    return logger;
  }

  /// **לעולם אינו זורק.** [init] רץ ב-`main` לפני `runApp`, וחריגה ממנו
  /// בורחת ומונעת את הפריים הראשון — תהליך בלי חלון *ובלי* שורת לוג אחת
  /// להסביר למה. תיקייה שאי אפשר ליצור נופלת ל-temp, וכשל גם שם משאיר נתיב
  /// שהכתיבות אליו נבלעות בשקט, כמו כל כתיבה אחרת כאן.
  static Future<String> _resolveLogDir(String dataDir) async {
    final preferred = p.join(dataDir, 'logs');
    try {
      final dir = Directory(preferred);
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir.path;
    } catch (_) {}
    try {
      final fallback =
          Directory(p.join(Directory.systemTemp.path, 'OtzariaOfflineUpdate'));
      if (!await fallback.exists()) await fallback.create(recursive: true);
      return fallback.path;
    } catch (_) {}
    return preferred;
  }

  /// שורת הפתיחה נושאת את הגרסה שרצה בפועל: בלעדיה אי אפשר לדעת מהלוג אם
  /// עדכון שהותקן באמת עלה — וזו השאלה הראשונה בכל דיווח על עדכון שנתקע.
  /// גרסת ה-payload נוספת רק כשהיא שונה, וזו כבר עדות לתקלה (`PayloadCheck`).
  static String startLine({String? version, String? payloadVersion}) {
    if (version == null) return '--- launcher started ---';
    if (payloadVersion == null || payloadVersion == version) {
      return '--- launcher started ($version) ---';
    }
    return '--- launcher started ($version, stub carries $payloadVersion) ---';
  }

  /// זורק [StateError] אם [init] עוד לא נקרא — עדיף להיכשל מוקדם וברור
  /// מאשר לאבד שקט שורות לוג.
  static AppLogger get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('AppLogger.init() לא נקרא עדיין');
    }
    return i;
  }

  /// כמו [instance] אך בלי לזרוק — לקוד שרץ בעלייה ועלול להקדים את [init]
  /// (למשל טעינת הגדרות שנכשלת על קובץ פגום). קריאה שמגיעה מוקדם מדי מוטב
  /// שתאבד שורת לוג מלהפיל את האתחול כולו.
  static AppLogger? get maybeInstance => _instance;

  final File _file;

  String get filePath => _file.path;
  String get logDir => p.dirname(_file.path);

  void info(String message) => _write('INFO', message);

  void warn(String message) => _write('WARN', message);

  /// [error]/[stackTrace] אופציונליים — אם קיימים, ה-stack trace המלא
  /// נכתב ללוג.
  void error(String message, [Object? error, StackTrace? stackTrace]) {
    final buffer = StringBuffer(message);
    if (error != null) buffer.write('\nerror: $error');
    if (error is LibraryHttpException) {
      buffer.write('\nhttp: ${jsonEncode(error.diagnostics)}');
    }
    if (stackTrace != null) buffer.write('\n$stackTrace');
    _write('ERROR', buffer.toString());
  }

  /// חסם עליון על השורות שממתינות לדיסק. כונן שנשלף לא ינפח את התהליך;
  /// מה שנזרק נספר ונרשם בשורה אחת כשהכתיבה חוזרת.
  static const int _maxPendingLines = 512;

  final List<String> _pending = [];
  int _dropped = 0;
  Future<void>? _drain;
  IOSink? _sink;

  void _write(String level, String message) {
    final line = '${DateTime.now().toIso8601String()} [$level] '
        '${withoutBidiMarks(message)}\n';
    if (kDebugMode) {
      // ignore: avoid_print
      print(line);
    }
    if (_pending.length >= _maxPendingLines) {
      _dropped++;
      return;
    }
    _pending.add(line);
    _drain ??= _drainPending().whenComplete(() => _drain = null);
  }

  /// sink פתוח אחד ובדיקת גודל אחת לכל אצווה, ולא פתיחה ובדיקה לכל שורה.
  Future<void> _drainPending() async {
    while (_pending.isNotEmpty) {
      final batch = StringBuffer();
      if (_dropped > 0) {
        batch.write('${DateTime.now().toIso8601String()} [WARN] '
            '$_dropped log lines were dropped\n');
      }
      final lines = List.of(_pending);
      _pending.clear();
      lines.forEach(batch.write);
      final dropped = _dropped;
      try {
        await _rotateIfNeeded();
        final sink = _sink ??= _file.openWrite(mode: FileMode.append);
        sink.write(batch);
        await sink.flush();
        _dropped -= dropped;
      } catch (_) {
        _dropped += lines.length;
        await _closeSink();
      }
    }
  }

  Future<void> _closeSink() async {
    final sink = _sink;
    _sink = null;
    try {
      await sink?.close();
    } catch (_) {}
  }

  Future<void> _rotateIfNeeded() async {
    try {
      if (!await _file.exists()) return;
      if (await _file.length() < maxBytes) return;
      await _closeSink();
      final previous = File('${_file.path}.1');
      if (await previous.exists()) await previous.delete();
      await _file.rename(previous.path);
    } catch (_) {
      // אם הרוטציה נכשלה, ממשיכים לכתוב לקובץ הקיים — עדיף לוג גדול מבלי לוג.
    }
  }

  /// מוודא שכל מה שנרשם עד כה כבר על הדיסק. נחוץ רק בבדיקות ובנקודות סגירה
  /// מסודרת; הקוד הרגיל לא ממתין ללוג.
  Future<void> flush() async {
    for (var drain = _drain; drain != null; drain = _drain) {
      await drain;
    }
    // משחרר את הקובץ (יציאה, או בדיקה שמוחקת את התיקייה); השורה הבאה
    // פותחת אותו מחדש.
    if (_drain == null) await _closeSink();
  }

  /// חשוף לבדיקות: מאפס את ה-singleton כדי שכל בדיקה תתחיל מקובץ נקי.
  @visibleForTesting
  static void resetForTest() => _instance = null;
}

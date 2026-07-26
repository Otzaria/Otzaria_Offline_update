import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// לוגר פשוט מבוסס-קובץ: כל שורה נכתבת (append) ל-`<dataDir>/logs/launcher.log`
/// עם timestamp ורמה, כדי שאפשר יהיה לראות מה קרה בפועל אחרי שהאפליקציה
/// כבר נסגרה — בלי צורך בדיבאגר או בחיבור מסוף.
///
/// כשל בכתיבה ללוג עצמו **לא** אמור להפיל את שאר האפליקציה (ה-`catchError`
/// בולע שגיאות כתיבה בשקט) — הלוג הוא כלי עזר, לא חלק מהלוגיקה.
class AppLogger {
  AppLogger._(this._file);

  static AppLogger? _instance;

  /// יש לקרוא פעם אחת, מוקדם ב-`main()`, לפני שנעשה שימוש ב-[instance].
  static Future<AppLogger> init(String dataDir) async {
    final dir = Directory(p.join(dataDir, 'logs'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(p.join(dir.path, 'launcher.log'));
    final logger = AppLogger._(file);
    _instance = logger;
    logger.info('--- launcher started ---');
    return logger;
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

  final File _file;

  String get filePath => _file.path;
  String get logDir => p.dirname(_file.path);

  void info(String message) => _write('INFO', message);

  void warn(String message) => _write('WARN', message);

  /// [error]/[stackTrace] אופציונליים — אם קיימים, ה-stack trace המלא
  /// נכתב ללוג. זה בדיוק מה שהיה חסר קודם: בלי זה, שגיאות "מוזרות" (כמו
  /// unsendable-isolate) נראות רק ב-UI כטקסט קצר, ולא ניתן לשחזר מאיפה
  /// זה הגיע.
  void error(String message, [Object? error, StackTrace? stackTrace]) {
    final buffer = StringBuffer(message);
    if (error != null) buffer.write('\nerror: $error');
    if (stackTrace != null) buffer.write('\n$stackTrace');
    _write('ERROR', buffer.toString());
  }

  void _write(String level, String message) {
    final line = '${DateTime.now().toIso8601String()} [$level] $message\n';
    if (kDebugMode) {
      // ignore: avoid_print
      print(line);
    }
    // fire-and-forget בכוונה: לא רוצים לחכות לכתיבת דיסק בכל קריאת לוג
    // בודדת, ולא רוצים שכשל כתיבה (למשל דיסק מלא) יזרוק לקורא.
    unawaited(
      _file.writeAsString(line, mode: FileMode.append).catchError((_) {
        return _file;
      }),
    );
  }
}

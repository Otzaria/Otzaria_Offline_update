import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// לוגר פשוט מבוסס-קובץ: כל שורה נכתבת (append) ל-`<dataDir>/logs/launcher.log`
/// עם timestamp ורמה, כדי שאפשר יהיה לראות מה קרה בפועל אחרי שהאפליקציה
/// כבר נסגרה — בלי צורך בדיבאגר או בחיבור מסוף.
///
/// כשל בכתיבה ללוג עצמו **לא** מפיל את שאר האפליקציה — הלוג הוא כלי עזר, לא
/// חלק מהלוגיקה.
///
/// שתי תכונות שאינן מובנות מאליהן:
/// * **הכתיבות מוסדרות בטור.** קודם כל קריאה שיגרה `writeAsString` נפרד ולא
///   מחכה לו; כמה שורות שנכתבו באותו tick (למשל שגיאה עם stack trace ומיד
///   אחריה עוד אחת) יכלו להיכנס לקובץ מעורבבות או לדרוס זו את זו, כי כל
///   קריאה פותחת handle משלה. כאן יש תור: שרשרת Future אחת, שורה אחרי שורה.
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
    final dir = Directory(p.join(dataDir, 'logs'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(p.join(dir.path, 'launcher.log'));
    final logger = AppLogger._(file);
    _instance = logger;
    logger.info(startLine(version: version, payloadVersion: payloadVersion));
    return logger;
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

  /// תור הכתיבה — ראו ה-doc של המחלקה.
  Future<void> _queue = Future<void>.value();
  int _pendingLines = 0;

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

  /// חסם עליון על תור הכתיבה. דיסק שנתקע (כונן USB שנשלף) לא יגרום לצבירת
  /// שורות בזיכרון בלי גבול — עדיף לאבד שורות לוג מלנפח את התהליך.
  static const int _maxPendingLines = 512;

  void _write(String level, String message) {
    final line = '${DateTime.now().toIso8601String()} [$level] $message\n';
    if (kDebugMode) {
      // ignore: avoid_print
      print(line);
    }
    if (_pendingLines >= _maxPendingLines) return;
    _pendingLines++;
    // fire-and-forget בכוונה — הקורא לא מחכה לדיסק — אבל דרך תור, כדי
    // שהשורות ייכתבו בסדר ולא יתנגשו על אותו קובץ.
    _queue = _queue.then((_) => _append(line)).whenComplete(() {
      _pendingLines--;
    });
  }

  Future<void> _append(String line) async {
    try {
      await _rotateIfNeeded();
      await _file.writeAsString(line, mode: FileMode.append, flush: false);
    } catch (_) {
      // כשל כתיבה (דיסק מלא / כונן שנשלף) נבלע — הלוג לא יפיל את התוכנה.
    }
  }

  Future<void> _rotateIfNeeded() async {
    try {
      if (!await _file.exists()) return;
      if (await _file.length() < maxBytes) return;
      final previous = File('${_file.path}.1');
      if (await previous.exists()) await previous.delete();
      await _file.rename(previous.path);
    } catch (_) {
      // אם הרוטציה נכשלה, ממשיכים לכתוב לקובץ הקיים — עדיף לוג גדול מבלי לוג.
    }
  }

  /// מוודא שכל מה שנרשם עד כה כבר על הדיסק. נחוץ רק בבדיקות ובנקודות סגירה
  /// מסודרת; הקוד הרגיל לא ממתין ללוג.
  Future<void> flush() => _queue;

  /// חשוף לבדיקות: מאפס את ה-singleton כדי שכל בדיקה תתחיל מקובץ נקי.
  @visibleForTesting
  static void resetForTest() => _instance = null;
}

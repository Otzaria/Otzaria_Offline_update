import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/widgets.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

import '../services/app_logger.dart';

/// נעילת ההפעלה שמזהה יציאה לא נקייה: נכתבת אחרי הפריים הראשון ונמחקת
/// בסגירה מסודרת. נקודת הכניסה היחידה — העלייה וכל מסלולי הסגירה פונים לכאן.
abstract final class LauncherCrashSession {
  static UncleanExitDetector? _detector;
  static _CloseListener? _listener;
  static AppLifecycleListener? _lifecycle;
  static Future<CrashCandidate?>? _begun;

  /// יציאה מסודרת התבקשה (אולי בזמן שהזיהוי עוד רץ, לפני שיש `_detector`).
  static bool _cleanExitRequested = false;

  /// תחילת התהליך, נלכדת בראש `main`: רשומות שהעלייה הנוכחית כתבה לפני
  /// הבדיקה אינן ראיה לקריסה של ההפעלה הקודמת.
  static DateTime processStartedAt = DateTime.now();

  static bool get isSupported =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  /// מתחיל את הזיהוי ואת פתיחת הנעילה **מוקדם** (`main`, בלי להמתין), כדי
  /// שגם עלייה שנתקעת לפני הפריים הראשון תשאיר נעילה. ההצעה למשתמש נשארת
  /// אחרי הפריים. קריאה חוזרת מקבלת את אותה תוצאה.
  static Future<CrashCandidate?> begin({
    required String logsDirectory,
    required String version,
    UncleanExitDetector? detector,
    bool Function(int pid)? isProcessAlive,
  }) =>
      _begun ??= detectAndStartSession(
        logsDirectory: logsDirectory,
        version: version,
        detector: detector,
        isProcessAlive: isProcessAlive,
      );

  /// מזהה קריסה של ההפעלה הקודמת ומיד פותח את נעילת ההפעלה הנוכחית.
  /// הסדר קריטי: [UncleanExitDetector.startSession] דורס את הנעילה הקודמת —
  /// והיא נפתחת גם כשהזיהוי עצמו נכשל, אחרת ההפעלה נשארת בלי הגנה.
  static Future<CrashCandidate?> detectAndStartSession({
    required String logsDirectory,
    required String version,
    UncleanExitDetector? detector,
    bool Function(int pid)? isProcessAlive,
  }) async {
    if (!isSupported) return null;
    final active = detector ??
        UncleanExitDetector(
          logsDirectory: logsDirectory,
          isProcessAlive: isProcessAlive ?? LauncherCrashSession.isProcessAlive,
          processStartedAt: processStartedAt,
        );
    CrashCandidate? candidate;
    try {
      candidate = await active.detectPreviousCrash();
    } catch (error) {
      AppLogger.maybeInstance?.warn('זיהוי הקריסה הקודמת נכשל: $error');
    }
    // סגירה בזמן הזיהוי: לא כותבים נעילה שתשרוד סגירה מסודרת. הנעילה הישנה
    // נשארת, וההפעלה הבאה תזהה שוב את הקריסה.
    if (!_cleanExitRequested) {
      try {
        await active.startSession(version: version);
      } catch (error) {
        AppLogger.maybeInstance?.warn('כתיבת נעילת ההפעלה נכשלה: $error');
      }
    }
    _detector = active;
    // ואם הסגירה הגיעה בזמן הכתיבה עצמה — מוחקים מיד.
    if (_cleanExitRequested) active.markCleanExitSync();
    return candidate;
  }

  /// מוחק את הנעילה. סינכרוני — חלק מהמסלולים מסתיימים ב-`exit(0)` מיד אחריו.
  static void markCleanExitSync() {
    _cleanExitRequested = true;
    _detector?.markCleanExitSync();
  }

  /// יציאה מסודרת מהתהליך: בלי מחיקת הנעילה ההפעלה הבאה נראית כקריסה.
  static void exitCleanly([void Function(int code)? exitProcess]) {
    try {
      markCleanExitSync();
    } finally {
      (exitProcess ?? exit)(0);
    }
  }

  static Future<void> installCloseHooks({
    void Function(int code)? exitProcess,
  }) async {
    if (!isSupported || _listener != null) return;
    final listener = _listener = _CloseListener(exitProcess);
    try {
      windowManager.addListener(listener);
      await windowManager.setPreventClose(true);
    } catch (_) {
      windowManager.removeListener(listener);
      _listener = null;
    }
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        markCleanExitSync();
        return AppExitResponse.exit;
      },
    );
  }

  static Future<void> closeWindow({
    Future<void> Function()? destroy,
    void Function(int code)? exitProcess,
  }) async {
    try {
      markCleanExitSync();
    } catch (error) {
      AppLogger.maybeInstance?.warn('מחיקת נעילת ההפעלה נכשלה: $error');
    }
    try {
      await (destroy ?? windowManager.destroy)();
    } catch (error) {
      AppLogger.maybeInstance?.warn('סגירת החלון נכשלה: $error');
    }
    try {
      await AppLogger.maybeInstance?.flush().timeout(
            const Duration(milliseconds: 500),
          );
    } catch (_) {}
    (exitProcess ?? exit)(0);
  }

  /// ב-Windows: OpenProcess+GetExitCodeProcess (קריאות kernel זולות, בלי
  /// תהליך חיצוני). במק ובלינוקס `kill(pid, 0)`.
  static bool isProcessAlive(int processId) {
    if (!Platform.isWindows) {
      return UncleanExitDetector.defaultIsProcessAlive(processId);
    }
    // הקריאה הראשונה ל-GetLastError טוענת את הפונקציה (איתור סמל) ודורסת את
    // השגיאה — כך נראה pid מת כחי בבדיקה הראשונה. מחממים אותה לפני.
    GetLastError();
    final handle =
        OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, processId);
    // ומיד אחרי הקריאה, בלי שום דבר באמצע: רק 87 אומר "אין תהליך כזה".
    if (handle == 0) return GetLastError() != ERROR_INVALID_PARAMETER;
    final exitCode = calloc<Uint32>();
    try {
      final ok = GetExitCodeProcess(handle, exitCode);
      return ok == 0 || exitCode.value == STILL_ACTIVE;
    } finally {
      calloc.free(exitCode);
      CloseHandle(handle);
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _detector = null;
    _begun = null;
    _cleanExitRequested = false;
    _lifecycle?.dispose();
    _lifecycle = null;
    final listener = _listener;
    if (listener != null) windowManager.removeListener(listener);
    _listener = null;
  }
}

class _CloseListener with WindowListener {
  _CloseListener(this._exitProcess);

  final void Function(int code)? _exitProcess;

  @override
  void onWindowClose() =>
      unawaited(LauncherCrashSession.closeWindow(exitProcess: _exitProcess));
}

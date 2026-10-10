import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../port/crash_signature.dart';
import 'launcher_log.dart';

/// תוכן `logs/session.lock` — סימן שהתהליך רץ ועוד לא נסגר כראוי.
class SessionLock {
  const SessionLock({
    required this.pid,
    required this.version,
    required this.startedAt,
    this.host,
  });

  final int pid;
  final String version;
  final DateTime startedAt;

  /// המחשב שכתב את הנעילה. הכונן נודד, ו-pid ממחשב אחר אינו אומר כאן דבר.
  final String? host;

  Map<String, dynamic> toJson() => {
        'pid': pid,
        'version': version,
        'startedAt': startedAt.toUtc().toIso8601String(),
        if (host != null) 'host': host,
      };

  static SessionLock? tryParse(String content) {
    try {
      final json = jsonDecode(content);
      if (json is! Map) return null;
      final pid = json['pid'];
      final startedAt = DateTime.tryParse('${json['startedAt']}');
      if (pid is! int || startedAt == null) return null;
      final host = json['host'];
      return SessionLock(
        pid: pid,
        version: '${json['version'] ?? ''}',
        startedAt: startedAt,
        host: host is String ? host : null,
      );
    } catch (_) {
      return null;
    }
  }
}

/// קריסה של ההפעלה הקודמת: הנעילה שנשארה, הראיות והחתימה.
class CrashCandidate {
  const CrashCandidate({
    required this.previousSession,
    required this.entries,
    required this.signature,
    required this.hasStartupStall,
  });

  final SessionLock previousSession;

  /// רשומות היומן מאז תחילת ההפעלה הקודמת, מהישנה לחדשה.
  final List<LauncherLogBlock> entries;

  /// מראיית הקריסה החדשה ביותר.
  final CrashSignature? signature;
  final bool hasStartupStall;
}

/// מזהה יציאה לא נקייה של ההפעלה הקודמת. לוגיקה בלבד — הקריאה מהעלייה
/// והסימון בסגירה שייכים ללאנצ'ר.
class UncleanExitDetector {
  UncleanExitDetector({
    required this.logsDirectory,
    bool Function(int pid)? isProcessAlive,
    int? currentPid,
    String? currentHost,
    DateTime? processStartedAt,
    DateTime Function()? clock,
  })  : _isProcessAlive = isProcessAlive ?? defaultIsProcessAlive,
        _currentPid = currentPid ?? pid,
        _currentHost = currentHost ?? localHost(),
        _processStartedAt = processStartedAt ?? (clock ?? DateTime.now)();

  static const String lockFileName = 'session.lock';

  /// כל קובץ יומן נקרא רק עד הגודל הזה מסופו.
  static const int maxLogReadBytes = 4 * 1000 * 1000;

  final String logsDirectory;
  final bool Function(int pid) _isProcessAlive;
  final int _currentPid;
  final String _currentHost;
  final DateTime _processStartedAt;

  String get lockPath => p.join(logsDirectory, lockFileName);

  static String localHost() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return '';
    }
  }

  /// כותב את נעילת ההפעלה הנוכחית. יש לקרוא אחרי [detectPreviousCrash].
  Future<void> startSession({required String version}) async {
    final lock = SessionLock(
      pid: _currentPid,
      version: version,
      startedAt: _processStartedAt,
      host: _currentHost,
    );
    final file = File(lockPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(lock.toJson()), flush: true);
  }

  /// מוחק את הנעילה ביציאה מסודרת.
  Future<void> markCleanExit() async {
    try {
      final file = File(lockPath);
      if (!_ownsLock(file)) return;
      await file.delete();
    } on FileSystemException {
      // אין נעילה — אין מה לסמן.
    }
  }

  /// גרסה סינכרונית למסלול סגירה שאינו יכול להמתין.
  void markCleanExitSync() {
    try {
      final file = File(lockPath);
      if (!_ownsLock(file)) return;
      file.deleteSync();
    } on FileSystemException {
      // אין נעילה — אין מה לסמן.
    }
  }

  /// נעילה של תהליך אחר שייכת להפעלה שטרם נבדקה — מחיקתה תאבד את הקריסה.
  bool _ownsLock(File file) {
    try {
      if (!file.existsSync()) return false;
      final lock = SessionLock.tryParse(file.readAsStringSync());
      return lock == null || lock.pid == _currentPid;
    } catch (_) {
      return false;
    }
  }

  /// מחזיר מועמד לקריסה רק כשנשארה נעילה של תהליך שאינו חי, ויש ראיה לקריסה:
  /// שגיאה שלא נתפסה מאז תחילתו, או תקיעה בעלייה.
  Future<CrashCandidate?> detectPreviousCrash() async {
    final SessionLock lock;
    try {
      final file = File(lockPath);
      if (!await file.exists()) return null;
      final parsed = SessionLock.tryParse(await file.readAsString());
      if (parsed == null) return null;
      lock = parsed;
    } catch (_) {
      return null;
    }

    // נעילה ממחשב אחר: היומן המשותף אינו קשור למערכת ולאבחון של המחשב הזה,
    // ולכן אין הצעה ואין שליחה — startSession פשוט דורס אותה.
    if (lock.host != null && lock.host != _currentHost) return null;
    if (lock.pid == _currentPid) return null;
    if (_isStillRunning(lock)) return null;

    final blocks = await _blocksSince(lock.startedAt);
    final evidence = blocks.where((b) => b.isCrashEvidence).toList();
    if (evidence.isEmpty) return null;

    return CrashCandidate(
      previousSession: lock,
      entries: blocks,
      signature: evidence.last.signature,
      hasStartupStall: blocks.any((b) => b.isStartupStall),
    );
  }

  bool _isStillRunning(SessionLock lock) {
    try {
      return _isProcessAlive(lock.pid);
    } catch (_) {
      // בלי בדיקה אמינה: נעילה שנכתבה לפני שהתהליך הזה עלה שייכת להפעלה קודמת.
      return !lock.startedAt.isBefore(_processStartedAt);
    }
  }

  Future<List<LauncherLogBlock>> _blocksSince(DateTime since) async {
    final parts = <String>[];
    for (final name in LauncherLogFormat.fileNames) {
      try {
        final file = File(p.join(logsDirectory, name));
        if (!await file.exists()) continue;
        if ((await file.stat()).modified.isBefore(since)) continue;
        parts.add(await readTail(file, maxLogReadBytes));
      } catch (_) {
        // קובץ נעול או חסר אינו ראיה.
      }
    }
    if (parts.isEmpty) return const [];
    return _blocksInIsolate(parts.join('\n'), since, _processStartedAt);
  }

  /// סטטית: סגירה בתוך מתודת מופע עלולה ללכוד את `this` שאינו ניתן להעברה.
  static Future<List<LauncherLogBlock>> _blocksInIsolate(
    String content,
    DateTime since,
    DateTime until,
  ) =>
      Isolate.run(
        () => parseLauncherLog(content)
            .where(
              (b) =>
                  b.timestamp != null &&
                  !b.timestamp!.isBefore(since) &&
                  // רשומות של התהליך הנוכחי אינן ראיה לקריסה של הקודם.
                  b.timestamp!.isBefore(until),
            )
            .toList()
          ..sort((a, b) => a.timestamp!.compareTo(b.timestamp!)),
      );

  /// סוף הקובץ בלבד: היומן גדל עד 2MB לפני סבב, והבדיקה רצה בעלייה.
  static Future<String> readTail(File file, int maxBytes) async {
    final raf = await file.open();
    try {
      final length = await raf.length();
      final start = length > maxBytes ? length - maxBytes : 0;
      await raf.setPosition(start);
      return utf8.decode(await raf.read(length - start), allowMalformed: true);
    } finally {
      await raf.close();
    }
  }

  /// `kill(pid, 0)` במק ובלינוקס; בשאר זורק ונופלים להשוואת זמנים. ב-Windows
  /// הלאנצ'ר מזריק בדיקה דרך win32 (החבילה הזו אינה תלויה בו).
  static bool defaultIsProcessAlive(int processId) {
    if (Platform.isMacOS || Platform.isLinux) return _posixAlive(processId);
    throw UnsupportedError('no process probe on ${Platform.operatingSystem}');
  }

  static const int _eperm = 1;
  static const int _esrch = 3;

  /// תוצאת `kill(pid, 0)`: 0 או EPERM — התהליך קיים; ESRCH — לא. כל שגיאה
  /// אחרת אינה תשובה, ולכן זורקת וההכרעה נופלת להשוואת זמנים.
  static bool interpretKillResult(int result, int errno) {
    if (result == 0 || errno == _eperm) return true;
    if (errno == _esrch) return false;
    throw StateError('kill(pid, 0) failed with errno $errno');
  }

  static bool _posixAlive(int processId) {
    final libc = DynamicLibrary.process();
    final kill = libc.lookupFunction<Int32 Function(Int32, Int32),
        int Function(int, int)>('kill');
    // errno נקרא בקריאת FFI שנייה, וה-VM עלול לדרוס אותו; כל ערך לא צפוי זורק,
    // וההכרעה נופלת להשוואת זמנים — בטוח.
    final errnoLocation = libc
        .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
      Platform.isMacOS ? '__error' : '__errno_location',
    );
    final result = kill(processId, 0);
    return interpretKillResult(result, errnoLocation().value);
  }
}

/// מגביל דיווחי קריסה אוטומטיים: פעם אחת לכל חתימה בכל גרסה, ועד 3 ביום.
class AutoCrashReportThrottle {
  AutoCrashReportThrottle({required this.filePath, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  /// קובץ ברירת המחדל, ליד היומן.
  factory AutoCrashReportThrottle.inLogs(
    String logsDirectory, {
    DateTime Function()? clock,
  }) =>
      AutoCrashReportThrottle(
        filePath: p.join(logsDirectory, 'app_report_throttle.json'),
        clock: clock,
      );

  static const int maxPerDay = 3;

  final String filePath;
  final DateTime Function() _clock;

  /// האם מותר לשלוח דיווח אוטומטי על [signatureHash] בגרסה [appVersion].
  Future<bool> canReport({
    required String signatureHash,
    required String appVersion,
  }) async {
    final state = await _read();
    final sent = (state['signatures'] as Map)[appVersion];
    if (sent is List && sent.contains(signatureHash)) return false;
    final today = (state['days'] as Map)[_today()];
    return !(today is int && today >= maxPerDay);
  }

  /// רושם דיווח אוטומטי שנשלח (או נשמר בתור).
  Future<void> recordReported({
    required String signatureHash,
    required String appVersion,
  }) async {
    final state = await _read();
    // רק הגרסה הנוכחית והיום הנוכחי רלוונטיים; השאר נזרק כדי שהקובץ לא יגדל.
    final signatures = state['signatures'] as Map;
    final known = signatures[appVersion];
    final list = <String>{
      if (known is List) ...known.whereType<String>(),
      signatureHash,
    }.toList();
    final days = state['days'] as Map;
    final today = _today();
    final count = (days[today] is int ? days[today] as int : 0) + 1;
    final updated = {
      'signatures': {appVersion: list},
      'days': {today: count},
    };
    try {
      final file = File(filePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(updated), flush: true);
    } catch (_) {
      // מגבלה שלא נשמרה עדיפה על עלייה שנכשלת.
    }
  }

  String _today() {
    final now = _clock();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  Future<Map<String, dynamic>> _read() async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        if (json is Map && json['signatures'] is Map && json['days'] is Map) {
          return Map<String, dynamic>.from(json);
        }
      }
    } catch (_) {
      // קובץ פגום מתנהג כריק.
    }
    return {'signatures': <String, dynamic>{}, 'days': <String, dynamic>{}};
  }
}

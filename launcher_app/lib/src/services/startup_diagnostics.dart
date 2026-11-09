import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show FrameTiming, PlatformDispatcher, TimingsCallback;

import 'package:error_reports_manager/error_reports_manager.dart'
    show LauncherLogFormat;
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

import 'app_logger.dart';

/// אבחון העלייה. "מסך שחור" בדיווח משתמש נראה זהה בשני מצבים שונים לגמרי:
/// קוד שתקוע לפני הפריים הראשון, או פריים שנבנה ומעולם לא הגיע למסך — תקלת
/// GPU. בלי עדות מהמחשב עצמו אי אפשר להפריד ביניהם (issue #28), ולכן נרשמות
/// כאן שורת סביבה ושתי נקודות ציון: הפריים הראשון שנבנה, והפריים הראשון
/// שהוצג. חוסר של אחת מהן הוא האבחנה.
class StartupDiagnostics {
  StartupDiagnostics._();

  /// אחרי הזמן הזה בלי פריים שהוצג נרשמת אזהרה — זו החתימה של מסך שחור.
  static const Duration presentTimeout = Duration(seconds: 15);

  static bool _started = false;
  static bool _presented = false;
  static Stopwatch? _since;
  static Timer? _timeout;
  static TimingsCallback? _onTimings;

  /// נקרא פעם אחת ב-`main`, אחרי שיש לוג ולפני `runApp`.
  static void start() {
    if (_started) return;
    _started = true;
    _since = Stopwatch()..start();
    AppLogger.maybeInstance?.info(machineLine());

    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      AppLogger.maybeInstance?.info(
        'הפריים הראשון נבנה אחרי ${_elapsedMs()}ms',
      );
      unawaited(_logDisplayAdapter());
    });

    // `addTimingsCallback` מדווח רק על פריים שהרסטר שלו הסתיים — כלומר על
    // ציור שבאמת יצא אל המסך, ולא רק נבנה בצד ה-Dart.
    void onTimings(List<FrameTiming> timings) {
      if (_presented || timings.isEmpty) return;
      _presented = true;
      _timeout?.cancel();
      final callback = _onTimings;
      if (callback != null) binding.removeTimingsCallback(callback);
      final first = timings.first;
      AppLogger.maybeInstance?.info(
        'הפריים הראשון הוצג אחרי ${_elapsedMs()}ms (בנייה '
        '${first.buildDuration.inMilliseconds}ms, ציור '
        '${first.rasterDuration.inMilliseconds}ms)',
      );
    }

    _onTimings = onTimings;
    binding.addTimingsCallback(onTimings);
    binding.addTimingsCallback(_logSlowFrames);
    _watchUiThread();

    // הקידומת היא מה שזיהוי הקריסה מחפש: הפעלה שנהרגה במצב הזה היא תקיעה.
    const tag = LauncherLogFormat.startupStallTag;
    _timeout = Timer(presentTimeout, () {
      if (_presented) return;
      AppLogger.maybeInstance?.warn(
        '$tag עברו ${presentTimeout.inSeconds} שניות ואף פריים לא הוצג — הציור '
        'אינו מגיע למסך',
      );
    });
  }

  static int _elapsedMs() => _since?.elapsedMilliseconds ?? -1;

  static const Duration _tick = Duration(milliseconds: 500);

  /// מעל זה הממשק נחשב תקוע: Windows מסמן "לא מגיב" אחרי חמש שניות.
  static const Duration stallThreshold = Duration(seconds: 2);

  /// פער ארוך מזה הוא שינה של המחשב, לא תקיעה.
  static const Duration _sleepGap = Duration(minutes: 10);

  /// כמה זמן ה-thread של הממשק לא הגיע לטיימר, או `null` כשאין תקיעה.
  @visibleForTesting
  static Duration? stallBetweenTicks(Duration sinceLastTick) {
    final lateness = sinceLastTick - _tick;
    if (lateness < stallThreshold || sinceLastTick >= _sleepGap) return null;
    return lateness;
  }

  // נרשם רק אחרי שהממשק חזר; תקיעה שנגמרה בסגירה כפויה נראית בלוג כשתיקה.
  static void _watchUiThread() {
    if (kDebugMode) return; // דיבאגר שעצר את התהליך אינו תקיעה.
    final clock = awakeClock();
    var last = clock();
    Timer.periodic(_tick, (_) {
      final now = clock();
      final stall = stallBetweenTicks(now - last);
      last = now;
      if (stall != null) {
        AppLogger.maybeInstance?.warn(
          'UI stall: הממשק לא הגיב ${stall.inMilliseconds}ms',
        );
      }
    });
  }

  @visibleForTesting
  static const String unbiasedTimeSymbol = 'QueryUnbiasedInterruptTime';

  /// שעון שאינו סופר שינה של המחשב; ב-Windows ה-Stopwatch כן סופר אותה.
  @visibleForTesting
  static Duration Function() awakeClock() {
    final stopwatch = Stopwatch()..start();
    if (!Platform.isWindows) return () => stopwatch.elapsed;
    try {
      final query = DynamicLibrary.open('kernel32.dll').lookupFunction<
          Int32 Function(Pointer<Uint64>),
          int Function(Pointer<Uint64>)>(unbiasedTimeSymbol);
      final out = calloc<Uint64>(); // חי כל עוד התהליך חי.
      return () {
        query(out);
        return Duration(microseconds: out.value ~/ 10);
      };
    } catch (_) {
      return () => stopwatch.elapsed;
    }
  }

  static void _logSlowFrames(List<FrameTiming> timings) {
    for (final timing in timings) {
      final raster = timing.rasterDuration;
      if (raster < stallThreshold) continue;
      AppLogger.maybeInstance?.warn(
        'Raster stall: ציור פריים לקח ${raster.inMilliseconds}ms',
      );
    }
  }

  /// שורת הסביבה. באנגלית בכוונה, כמו שורת הפתיחה של הלוג: זה מידע על
  /// המכונה שנועד להישלח בדיווח תקלה, לא מלל למשתמש.
  @visibleForTesting
  static String machineLine() {
    final buffer = StringBuffer('--- machine: ');
    buffer.write('${Platform.operatingSystem} ');
    buffer.write(Platform.operatingSystemVersion);
    // ה-ABI של התהליך מול זה של המערכת: 32 סיביות כאן פוסל את כל השאר.
    buffer.write(' | process ${Abi.current()}');
    // שני משתני הסביבה האלה קיימים בווינדוס בלבד; ב-macOS הארכיטקטורה כבר
    // נאמרה ב-`Abi.current()` שלמעלה, ו-"cpu ?" היה רק רעש.
    final cpu = Platform.environment['PROCESSOR_ARCHITEW6432'] ??
        Platform.environment['PROCESSOR_ARCHITECTURE'];
    buffer.write(cpu == null
        ? ' | cpu x${Platform.numberOfProcessors}'
        : ' | cpu $cpu x${Platform.numberOfProcessors}');
    buffer.write(' | ${_viewsDescription()}');
    buffer.write(' ---');
    return buffer.toString();
  }

  /// `EnumDisplayDevices` היא קריאת דרייבר סינכרונית — רצה ב-isolate אחרי
  /// שהפריים הראשון נבנה, ולעולם לא על thread הפלטפורמה בעלייה.
  static Future<void> _logDisplayAdapter() async {
    try {
      final (adapter, image) = await Isolate.run(
        () => (primaryDisplayAdapter(), imageLocation()),
      );
      if (adapter != null) {
        AppLogger.maybeInstance?.info('--- display $adapter ---');
      }
      if (image != null) AppLogger.maybeInstance?.info('--- image $image ---');
    } catch (e) {
      AppLogger.maybeInstance?.warn('זיהוי כרטיס המסך נכשל: $e');
    }
  }

  /// חלון שאין לו view הוא כשל אחר לגמרי מחלון שיש לו ולא צויר.
  static String _viewsDescription() {
    try {
      final views = PlatformDispatcher.instance.views;
      if (views.isEmpty) return 'no view';
      final view = views.first;
      final size = view.physicalSize;
      return 'view ${size.width.round()}x${size.height.round()} '
          '@${view.devicePixelRatio}';
    } catch (_) {
      return 'view ?';
    }
  }

  /// סוג הכונן שהקוד נטען ממנו, והאם `flutter_windows.dll` מסומן לטעינה
  /// מלאה לזיכרון (`package.ps1`); בלי הסימון כונן עמוס מקפיא את הממשק.
  static String? imageLocation() {
    if (!Platform.isWindows) return null;
    final exe = Platform.resolvedExecutable;
    final prefix = p.rootPrefix(exe);
    final rootPtr =
        (prefix.endsWith('\\') ? prefix : '$prefix\\').toNativeUtf16();
    final String drive;
    try {
      drive = switch (GetDriveType(rootPtr)) {
        DRIVE_REMOVABLE => 'removable',
        DRIVE_FIXED => 'fixed',
        DRIVE_REMOTE => 'remote',
        final other => 'type $other',
      };
    } finally {
      calloc.free(rootPtr);
    }
    final flags = peCharacteristics(
      p.join(p.dirname(exe), 'flutter_windows.dll'),
    );
    final swap = flags == null
        ? '?'
        : (flags & runFromSwapFlags) == runFromSwapFlags
            ? 'on'
            : 'off';
    return '$drive drive, run-from-swap $swap';
  }

  /// `IMAGE_FILE_REMOVABLE_RUN_FROM_SWAP | IMAGE_FILE_NET_RUN_FROM_SWAP`.
  static const int runFromSwapFlags = 0x0C00;

  /// שדה Characteristics של כותרת ה-COFF, או `null` כשאין PE קריא.
  @visibleForTesting
  static int? peCharacteristics(String path) {
    RandomAccessFile? file;
    try {
      file = File(path).openSync();
      final head = file.readSync(1024);
      if (head.length < 0x40 || head[0] != 0x4D || head[1] != 0x5A) return null;
      final pe = ByteData.sublistView(head).getUint32(0x3C, Endian.little);
      if (pe + 24 > head.length) return null;
      final view = ByteData.sublistView(head);
      if (view.getUint32(pe, Endian.little) != 0x00004550) return null;
      return view.getUint16(pe + 22, Endian.little);
    } catch (_) {
      return null;
    } finally {
      file?.closeSync();
    }
  }

  /// שם כרטיס המסך הראשי. זה הנתון שחסר בכל דיווח על מסך שחור "במחשב ישן":
  /// בלעדיו אי אפשר לדעת אם מדובר בשבב שהדרייבר שלו כבר לא נתמך.
  static String? primaryDisplayAdapter() {
    if (!Platform.isWindows) return null;
    final device = calloc<DISPLAY_DEVICE>();
    try {
      String? fallback;
      for (var i = 0; i < 8; i++) {
        device.ref.cb = sizeOf<DISPLAY_DEVICE>();
        if (EnumDisplayDevices(nullptr, i, device, 0) == 0) break;
        final flags = device.ref.StateFlags;
        if ((flags & DISPLAY_DEVICE_ATTACHED_TO_DESKTOP) == 0) continue;
        final name = device.ref.DeviceString.trim();
        if (name.isEmpty) continue;
        if ((flags & DISPLAY_DEVICE_PRIMARY_DEVICE) != 0) return name;
        fallback ??= name;
      }
      return fallback;
    } catch (_) {
      // אבחון בלבד — כשל בקריאה לא ימנע את עליית התוכנה.
      return null;
    } finally {
      calloc.free(device);
    }
  }
}

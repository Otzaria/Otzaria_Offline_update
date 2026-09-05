import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:ui' show FrameTiming, PlatformDispatcher, TimingsCallback;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
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

    _timeout = Timer(presentTimeout, () {
      if (_presented) return;
      AppLogger.maybeInstance?.warn(
        'עברו ${presentTimeout.inSeconds} שניות ואף פריים לא הוצג — הציור '
        'אינו מגיע למסך',
      );
    });
  }

  static int _elapsedMs() => _since?.elapsedMilliseconds ?? -1;

  /// שורת הסביבה. באנגלית בכוונה, כמו שורת הפתיחה של הלוג: זה מידע על
  /// המכונה שנועד להישלח בדיווח תקלה, לא מלל למשתמש.
  @visibleForTesting
  static String machineLine() {
    final buffer = StringBuffer('--- machine: ');
    buffer.write('${Platform.operatingSystem} ');
    buffer.write(Platform.operatingSystemVersion);
    // ה-ABI של התהליך מול זה של המערכת: 32 סיביות כאן פוסל את כל השאר.
    buffer.write(' | process ${Abi.current()}');
    final cpu = Platform.environment['PROCESSOR_ARCHITEW6432'] ??
        Platform.environment['PROCESSOR_ARCHITECTURE'] ??
        '?';
    buffer.write(' | cpu $cpu x${Platform.numberOfProcessors}');
    final adapter = primaryDisplayAdapter();
    if (adapter != null) buffer.write(' | display $adapter');
    buffer.write(' | ${_viewsDescription()}');
    buffer.write(' ---');
    return buffer.toString();
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

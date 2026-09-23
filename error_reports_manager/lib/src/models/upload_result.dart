import 'dart:async';

/// מצב ריצת העלאה, לתצוגה. [waitRemaining] אינו null בזמן ההמתנה בין
/// מנות — השרת מקבל מספר מוגבל של דיווחים בדקה.
class ReportUploadProgress {
  const ReportUploadProgress({
    required this.total,
    required this.done,
    this.waitRemaining,
  });

  final int total;

  /// נשלחו או נדחו — כלומר כבר אינם בתיבת היציאה.
  final int done;
  final Duration? waitRemaining;

  bool get isWaiting => waitRemaining != null;
}

/// דיווח שהשרת דחה סופית ולכן נמחק. נשמר רק ליומן.
class ReportRejection {
  const ReportRejection({
    required this.reportId,
    required this.bookTitle,
    required this.reason,
  });

  final String reportId;
  final String bookTitle;

  /// קוד והתחלת התשובה, או "endpoint not allowed" — למפתח, לא למסך.
  final String reason;
}

/// סיכום ריצת העלאה. [remaining] הם מה שנשאר בתיבת היציאה, וממנו ממשיכים.
class ReportUploadResult {
  const ReportUploadResult({
    required this.total,
    required this.sent,
    required this.rejected,
    required this.remaining,
    this.rejections = const [],
    this.error,
    this.cancelled = false,
  });

  final int total;
  final int sent;
  final int rejected;
  final int remaining;
  final List<ReportRejection> rejections;

  /// כשל זמני (רשת, זמן קצוב, קוד שרת שאינו דחייה) שעצר את הריצה.
  final String? error;
  final bool cancelled;
}

/// בקשת עצירה להעלאה שרצה. נכנסת לתוקף מיד — גם באמצע ההמתנה בין מנות.
class ReportUploadCancellation {
  bool _cancelled = false;
  final List<void Function()> _listeners = [];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List.of(_listeners)) {
      listener();
    }
    _listeners.clear();
  }

  void _listen(void Function() listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }

  void _unlisten(void Function() listener) => _listeners.remove(listener);

  /// כמה מאזינים עוד רשומים — לבדיקה שהם אינם מצטברים.
  int get listenerCount => _listeners.length;
}

/// [future] או עצירה, המוקדם מביניהם. `null` = נעצר.
Future<T?> raceCancellation<T>(
  Future<T> future,
  ReportUploadCancellation? cancellation,
) {
  if (cancellation == null) return future;
  final completer = Completer<T?>();
  void onCancel() {
    if (!completer.isCompleted) completer.complete(null);
  }

  cancellation._listen(onCancel);
  // בלי ההסרה, כל בקשה וכל שנייה של המתנה השאירו מאזין עד סוף הריצה.
  future.then(
    (value) {
      cancellation._unlisten(onCancel);
      if (!completer.isCompleted) completer.complete(value);
    },
    onError: (Object error, StackTrace stack) {
      cancellation._unlisten(onCancel);
      if (!completer.isCompleted) completer.completeError(error, stack);
    },
  );
  return completer.future;
}

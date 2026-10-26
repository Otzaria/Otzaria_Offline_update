/// מהירות וזמן שנותר מתוך מונה בייטים מצטבר. טהור: הזמן מוזרק, ובלי
/// טיימרים — מוזן מכל דיווח התקדמות.
class TransferRateMeter {
  TransferRateMeter({
    this.window = const Duration(seconds: 8),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// כמה אחורה ממצעים: מספיק כדי לא לקפוץ, וקצר מספיק כדי להגיב לשינוי.
  final Duration window;
  final DateTime Function() _clock;
  final List<({DateTime at, int bytes})> _samples = [];

  /// פחות משנייה של מדידה אינה אומרת דבר על המהירות.
  static const Duration minSpan = Duration(seconds: 1);

  /// בלי בייט חדש זמן כזה — ההורדה תקועה, ואין מהירות להציג.
  static const Duration stallAfter = Duration(seconds: 5);

  /// [bytes] — כמה ירד עד עכשיו. ירידה במונה היא קובץ או רכיב חדש: מתחילים
  /// למדוד מחדש.
  void add(int bytes) {
    final now = _clock();
    if (_samples.isNotEmpty && bytes < _samples.last.bytes) _samples.clear();
    if (_samples.isNotEmpty && bytes == _samples.last.bytes) return;
    _samples.add((at: now, bytes: bytes));
    while (_samples.length > 2 && now.difference(_samples[1].at) >= window) {
      _samples.removeAt(0);
    }
  }

  void reset() => _samples.clear();

  /// היו מדידות, אבל שום בייט לא הגיע כבר [stallAfter].
  bool get isStalled =>
      _samples.isNotEmpty && _clock().difference(_samples.last.at) > stallAfter;

  /// בייטים לשנייה עד **עכשיו** (לא עד הדגימה האחרונה — אחרת עצירה מציגה
  /// את המהירות האחרונה לנצח), או `null` עד שיש מספיק מדידה או כשתקוע.
  double? get bytesPerSecond {
    if (_samples.length < 2 || isStalled) return null;
    final first = _samples.first;
    final span = _clock().difference(first.at);
    if (span < minSpan) return null;
    final bytes = _samples.last.bytes - first.bytes;
    if (bytes <= 0) return null;
    return bytes * Duration.microsecondsPerSecond / span.inMicroseconds;
  }

  /// הזמן שנותר עד [total], או `null` כשאין מהירות.
  Duration? remaining(int total) {
    final rate = bytesPerSecond;
    if (rate == null || _samples.isEmpty) return null;
    final left = total - _samples.last.bytes;
    if (left <= 0) return Duration.zero;
    return Duration(seconds: (left / rate).ceil());
  }
}

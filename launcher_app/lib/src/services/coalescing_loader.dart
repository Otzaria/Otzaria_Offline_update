import 'dart:async';

/// טעינה אחת בכל פעם: קריאה בזמן שטעינה רצה מצטרפת אליה ומבקשת טעינה חוזרת
/// אחת, גם אם הבקשה הגיעה בין סיום הלולאה לניקוי ה-`_running` (רגע של כמה
/// microtasks שבו בקשה הייתה אובדת).
class CoalescingLoader {
  CoalescingLoader(this._action, {bool Function()? isActive})
      : _isActive = isActive ?? (() => true);

  final Future<void> Function() _action;
  final bool Function() _isActive;

  Future<void>? _running;
  bool _again = false;

  /// מחזיר את הטעינה הרצה, או מתחיל אחת. מי שממתין מקבל את הטעינה הראשונה
  /// ואת כל החוזרות שהתכנסו אליה בלולאה.
  Future<void> run() {
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    return _running = _loop().whenComplete(() {
      _running = null;
      // בקשה שהגיעה אחרי בדיקת הלולאה ולפני הניקוי.
      if (_again && _isActive()) unawaited(run());
    });
  }

  Future<void> _loop() async {
    do {
      _again = false;
      await _action();
    } while (_again && _isActive());
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';

/// מדלל הודעות **התקדמות** בלבד.
///
/// למה: `PatchDownloader` מדווח `onProgress` על כל צ'אנק. בהורדת מסד של ~1GB
/// אלה עשרות אלפי קריאות, וכל אחת מהן עברה ל-`notifyListeners` → `setState`
/// של `AppShell` → בנייה מחדש של כל עץ ה-widgets. זה בזבז יותר CPU מההורדה
/// עצמה והקפיא את הממשק. כאן ההודעה הראשונה יוצאת מיד, ואחריה לכל היותר אחת
/// לכל [interval] — כשהאחרונה תמיד נמסרת, כדי שמד ההתקדמות לא ייתקע על 99%.
mixin ProgressNotifier on ChangeNotifier {
  /// 100ms ≈ 10 עדכונים בשנייה — יותר מהדרוש לעין, ופחות מ-1% מהקריאות.
  static const Duration interval = Duration(milliseconds: 100);

  Stopwatch? _since;
  Timer? _pending;
  bool _disposed = false;

  /// מודיע על התקדמות, מדולל. אין להשתמש בזה לשינויי **מצב** (התחלה/סיום/
  /// שגיאה) — אלה חייבים `notifyListeners` רגיל ומיידי.
  void notifyProgress() {
    if (_disposed) return;
    final since = _since;
    if (since == null || since.elapsed >= interval) {
      _pending?.cancel();
      _pending = null;
      _since = Stopwatch()..start();
      notifyListeners();
      return;
    }
    // הערך האחרון יימסר גם אם לא יגיעו עוד צ'אנקים אחריו.
    _pending ??= Timer(interval - since.elapsed, () {
      _pending = null;
      if (_disposed) return;
      _since = Stopwatch()..start();
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _pending?.cancel();
    _pending = null;
    super.dispose();
  }
}

import 'dart:async';

/// מריץ הורדות של **קבצים שונים** במקביל, עד [maxConcurrent] בכל רגע.
///
/// **למה זו הדרך היחידה להאיץ כאן.** מאיץ הורדות רגיל מפצל קובץ אחד לכמה
/// חיבורים דרך כותרת `Range` — וזה לא עובד מול GitHub: ה-CDN של נכסי
/// ה-releases מתעלם מ-`Range` (וגם מ-`x-ms-range`) ומחזיר תמיד 200 עם הגוף
/// המלא, למרות שהוא מכריז `Accept-Ranges: bytes`. לעומת זאת החנק שלו הוא
/// **לכל חיבור**: מדידה מול נכס אמיתי נתנה ~0.7MB/ש בחיבור בודד מול
/// ~2.1MB/ש בארבעה במקביל. לכן מה שמאיץ הוא ריבוי קבצים, לא ריבוי חיבורים
/// לאותו קובץ.
///
/// המופע הוא **סמפור משותף**: כמה קוראים ([LibraryMirrorExporter],
/// `CompanionAssetsMirror`) יכולים לחלוק אותו ולרוץ בו-זמנית מבלי שמספר
/// החיבורים הכולל יעלה על התקרה. זה מה שמאפשר לקובצי הנלווים לרדת לצד המסד
/// הגדול בלי להציף את המחשב.
class DownloadScheduler {
  DownloadScheduler({int maxConcurrent = defaultMaxConcurrent})
      : maxConcurrent = maxConcurrent < 1 ? 1 : maxConcurrent;

  /// ארבע הורדות במקביל. מכפיל את הקצב פי ~3 ועדיין צנוע: כל הורדה מחזיקה
  /// חוצץ כתיבה של 4MB (`PatchDownloader`), וכונן נייד איטי הוא היעד.
  static const int defaultMaxConcurrent = 4;

  final int maxConcurrent;

  /// כמה משבצות תפוסות כרגע, וכמה ממתינים בתור להן.
  int _active = 0;
  final List<Completer<void>> _waiting = <Completer<void>>[];

  /// כמה הורדות רצות ברגע זה — לבדיקות ולניפוי.
  int get activeCount => _active;

  /// מריץ את [tasks] ומחזיר את התוצאות **בסדר שבו נמסרו**.
  ///
  /// כישלון עוצר את *ההתחלה* של משימות נוספות, אבל ממתין לאלה שכבר רצות
  /// לפני שהוא זורק: הורדה שנשארת רצה ברקע ממשיכה לכתוב לדיסק אחרי שהקורא
  /// כבר ניקה אחריו (ראו `MirrorDownloadUndo`). מוחזרת השגיאה הראשונה.
  Future<List<T>> run<T>(List<Future<T> Function()> tasks) async {
    if (tasks.isEmpty) return const [];

    final results = List<T?>.filled(tasks.length, null);
    Object? firstError;
    StackTrace? firstStack;

    Future<void> runOne(int index) async {
      await _acquire();
      try {
        // משימה שהמתינה בתור בזמן שאחרת נכשלה — אין טעם להתחיל אותה.
        if (firstError != null) return;
        results[index] = await tasks[index]();
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      } finally {
        _release();
      }
    }

    await Future.wait([for (var i = 0; i < tasks.length; i++) runOne(i)]);

    final error = firstError;
    if (error != null) Error.throwWithStackTrace(error, firstStack!);
    return [for (final value in results) value as T];
  }

  Future<void> _acquire() async {
    if (_active < maxConcurrent) {
      _active++;
      return;
    }
    final gate = Completer<void>();
    _waiting.add(gate);
    // מי שמשחרר מעביר את המשבצת ישירות, ולכן אין כאן `_active++`.
    await gate.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).complete();
      return;
    }
    _active--;
  }
}

/// מאחד את דיווחי הבייטים של כמה הורדות מקבילות למונה אחד — בלי זה מד
/// ההתקדמות מקבל ערכים של קבצים שונים לסירוגין וקופץ קדימה ואחורה.
///
/// כל הורדה מקבלת [slot] משלה, והמונה המשותף הוא סכום כל המשבצות מול סכום
/// הגדלים המתוכנן. כך המד מתאר את **כל** ההורדה ולא את הקובץ שבמקרה מדווח
/// אחרון — וגם לא מתאפס בין קובץ לקובץ.
///
/// **בייטים שכבר על הדיסק אינם נספרים** — לא במונה ולא ביעד. נכס שלם שרק
/// מאומת ותחילית של הורדה שנקטעה אינם עוברים ברשת, וספירתם הכריזה "1.86
/// ג״ב" על הורדה שמשכה 1.36: 511 מ״ב של קבצים נלווים שכבר ישבו על הכונן.
/// ראו [ByteProgressSlot.markExisting].
class ByteProgressAggregator {
  ByteProgressAggregator({this.totalBytes, this.onProgress});

  /// סכום הגדלים הידוע מראש, **לפני** ניכוי מה שכבר על הדיסק. `null` = לא
  /// ידוע, ואז מדווח סכום ה-`total`-ים שההורדות עצמן מדווחות (וכל עוד אחת
  /// מהן לא דיווחה — אין סכום כלל).
  final int? totalBytes;

  final void Function(int downloaded, int? total)? onProgress;

  final List<int> _received = <int>[];
  final List<int?> _totals = <int?>[];
  final List<int> _existing = <int>[];
  int _sum = 0;

  /// הבייטים שנצברו עד כה בכל המשבצות — משמש לקינון של מאחד בתוך מאחד.
  int get receivedBytes => _sum;

  /// סינק התקדמות להורדה בודדת.
  ByteProgressSlot slot() {
    _received.add(0);
    _totals.add(null);
    _existing.add(0);
    return ByteProgressSlot._(this, _received.length - 1);
  }

  void _report(int index, int downloaded, int? total) {
    // שיא ולא ערך אחרון: קובץ שכבר שלם מדווח את גודלו המלא ואז מאמת
    // sha256 מאפס על אותו סינק — בלי השיא המד היה צונח באמצע.
    if (downloaded > _received[index]) {
      _received[index] = downloaded;
      _resum();
    }
    if (total != null) _totals[index] = total;
    _emit();
  }

  void _markExisting(int index, int bytes) {
    final value = bytes < 0 ? 0 : bytes;
    if (_existing[index] == value) return;
    _existing[index] = value;
    _resum();
    _emit();
  }

  /// תרומת כל משבצת היא מה שעבר בה ברשת: הדיווח פחות מה שכבר היה בדיסק.
  void _resum() {
    var sum = 0;
    for (var i = 0; i < _received.length; i++) {
      final net = _received[i] - _existing[i];
      if (net > 0) sum += net;
    }
    _sum = sum;
  }

  void _emit() => onProgress?.call(_sum, knownTotal());

  /// הסכום הכולל שידוע כרגע, או `null` כשעדיין אי אפשר לדעת אותו.
  int? knownTotal() {
    final planned = totalBytes;
    var total = 0;
    if (planned == null) {
      for (var i = 0; i < _totals.length; i++) {
        final value = _totals[i];
        if (value == null) return null;
        final net = value - _existing[i];
        if (net > 0) total += net;
      }
    } else {
      total = planned;
      for (final existing in _existing) {
        total -= existing;
      }
      if (total < 0) total = 0;
    }
    // נכס שגודלו לא היה ידוע מראש יכול לחרוג מהאומדן; מד שמראה 120% גרוע
    // יותר מאומדן שגדל.
    return total < _sum ? _sum : total;
  }
}

/// המשבצת של הורדה בודדת בתוך [ByteProgressAggregator].
class ByteProgressSlot {
  ByteProgressSlot._(this._owner, this._index);

  final ByteProgressAggregator _owner;
  final int _index;

  /// דיווח ההתקדמות של ההורדה — נמסר לה כ-`onProgress`.
  void report(int downloaded, int? total) =>
      _owner._report(_index, downloaded, total);

  /// כמה מהבייטים שההורדה מדווחת עליהם כבר היו על הדיסק: נכס שלם שרק
  /// מאומת, או תחילית שממשיכים ממנה. **מחליף** ולא מצטבר — תחילית שנזרקה
  /// (שרת שהתעלם מ-`Range`) חוזרת ל-0, כי אז הקובץ כולו באמת יורד.
  void markExisting(int bytes) => _owner._markExisting(_index, bytes);
}

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/app_logger.dart';
import '../services/faq_store.dart';
import '../services/serial_queue.dart';
import '../settings/faq_customization.dart';

/// מחזיק את ההתאמות להדרכה ושומר אותן בדיסק.
class FaqController extends ChangeNotifier {
  FaqController({required String dataDir, String? readOnlyDriveDir})
      : _store =
            FaqStore(stateDir: dataDir, readOnlyDriveDir: readOnlyDriveDir);

  final FaqStore _store;

  FaqCustomization _value = const FaqCustomization();
  FaqCustomization get value => _value;

  Future<void>? _initialLoad;
  Future<void>? get initialLoad => _initialLoad;
  bool _disposed = false;
  bool _edited = false;

  Future<void> load() => _initialLoad ??= _load();

  Future<void> _load() async {
    try {
      final value = await _store.load();
      if (value == null || _disposed || _edited) return;
      _value = value;
      notifyListeners();
    } catch (e, st) {
      // קובץ פגום מחזיר את ההדרכה לנוסח המקורי, ואינו מונע הפעלה.
      AppLogger.maybeInstance?.error('טעינת התאמות ההדרכה נכשלה', e, st);
    }
  }

  final SerialQueue _queue = SerialQueue();

  Future<void> update(FaqCustomization next) {
    _pendingSave?.cancel();
    _edited = true;
    _value = next;
    notifyListeners();
    return _queue.run(_save);
  }

  Timer? _pendingSave;

  /// שינוי שנכתב לדיסק רק אחרי [delay] בלי שינוי נוסף — הקלדה בשדה, שעל
  /// כונן נייד לא תכתוב קובץ בכל הקשה. [flush] כותב מיד.
  void updateDeferred(FaqCustomization next, Duration delay) {
    _pendingSave?.cancel();
    _edited = true;
    _value = next;
    notifyListeners();
    _pendingSave = Timer(delay, () => unawaited(_queue.run(_save)));
  }

  /// כותב מיד שינוי שממתין, וממתין גם לכתיבה שכבר רצה. נקרא ביציאה מהעריכה
  /// ולפני סגירת החלון.
  Future<void> flush() {
    final pending = _pendingSave;
    if (pending == null || !pending.isActive) return _queue.run(() async {});
    pending.cancel();
    return _queue.run(_save);
  }

  @override
  void dispose() {
    _disposed = true;
    _pendingSave?.cancel();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      await _store.save(_value);
    } catch (e, st) {
      AppLogger.instance.error('שמירת התאמות ההדרכה נכשלה', e, st);
    }
  }
}

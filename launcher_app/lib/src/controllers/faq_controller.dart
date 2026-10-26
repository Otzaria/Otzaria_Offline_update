import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../services/app_logger.dart';
import '../services/serial_queue.dart';
import '../settings/faq_customization.dart';

/// מחזיק את ההתאמות שהמשתמש עשה להדרכה וכותב אותן לדיסק. אותה כתיבה אטומית
/// כמו ב-`SettingsController` (קובץ זמני + rename), מאותה סיבה.
class FaqController extends ChangeNotifier {
  FaqController({required String dataDir})
      : _file = File(p.join(dataDir, 'faq_customization.json'));

  final File _file;

  FaqCustomization _value = const FaqCustomization();
  FaqCustomization get value => _value;

  Future<void> load() async {
    try {
      if (!await _file.exists()) return;
      final raw = jsonDecode(await _file.readAsString());
      if (raw is! Map<String, dynamic>) return;
      _value = FaqCustomization.fromJson(raw);
      notifyListeners();
    } catch (e, st) {
      // קובץ פגום מחזיר את ההדרכה לנוסח המקורי, ואינו מונע הפעלה.
      AppLogger.maybeInstance?.error('טעינת התאמות ההדרכה נכשלה', e, st);
    }
  }

  final SerialQueue _queue = SerialQueue();

  Future<void> update(FaqCustomization next) {
    _pendingSave?.cancel();
    _value = next;
    notifyListeners();
    return _queue.run(_save);
  }

  Timer? _pendingSave;

  /// שינוי שנכתב לדיסק רק אחרי [delay] בלי שינוי נוסף — הקלדה בשדה, שעל
  /// כונן נייד לא תכתוב קובץ בכל הקשה. [flush] כותב מיד.
  void updateDeferred(FaqCustomization next, Duration delay) {
    _pendingSave?.cancel();
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
    _pendingSave?.cancel();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      await _file.parent.create(recursive: true);
      final temp = File('${_file.path}.tmp');
      await temp.writeAsString(
        const JsonEncoder.withIndent('  ').convert(_value.toJson()),
        flush: true,
      );
      await temp.rename(_file.path);
    } catch (e, st) {
      AppLogger.instance.error('שמירת התאמות ההדרכה נכשלה', e, st);
    }
  }
}

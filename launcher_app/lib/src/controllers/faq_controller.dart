import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../services/app_logger.dart';
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

  Future<void> update(FaqCustomization next) async {
    _value = next;
    notifyListeners();
    await _save();
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

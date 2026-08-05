import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../services/app_logger.dart';
import 'app_settings.dart';

/// מחזיק את [AppSettings] הפעילות וכותב אותן לדיסק. הכתיבה אטומית (קובץ
/// זמני + rename) כדי שהפסקת חשמל לא תשאיר JSON חצי־כתוב (תכנון §10.1).
class SettingsController extends ChangeNotifier {
  SettingsController({required String dataDir})
      : _file = File(p.join(dataDir, 'launcher_settings.json'));

  final File _file;

  AppSettings _settings = const AppSettings();
  AppSettings get settings => _settings;

  Future<void> load() async {
    try {
      if (!await _file.exists()) return;
      final raw = jsonDecode(await _file.readAsString());
      if (raw is! Map<String, dynamic>) return;
      _settings = AppSettings.fromJson(raw);
      notifyListeners();
    } catch (e, st) {
      // קובץ פגום לא ימנע הפעלה — נשארים על ברירות המחדל.
      AppLogger.instance.error('טעינת ההגדרות נכשלה', e, st);
    }
  }

  Future<void> update(AppSettings next) async {
    _settings = next;
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      await _file.parent.create(recursive: true);
      final temp = File('${_file.path}.tmp');
      await temp.writeAsString(
        const JsonEncoder.withIndent('  ').convert(_settings.toJson()),
        flush: true,
      );
      await temp.rename(_file.path);
    } catch (e, st) {
      AppLogger.instance.error('שמירת ההגדרות נכשלה', e, st);
    }
  }
}

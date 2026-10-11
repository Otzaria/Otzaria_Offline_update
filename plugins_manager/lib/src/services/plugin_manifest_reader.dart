import 'dart:convert';

import 'package:archive/archive.dart';

/// מחלץ את ה-id האמיתי של התוסף מתוך `manifest.json` שבקובץ ה-`.otzplugin`.
///
/// **למה זה קריטי:** ה-`id` שה-API הציבורי מחזיר הוא מזהה מסד-הנתונים של
/// האתר, ואילו אוצריא מתקינה תחת `installed/<manifest.id>/`. השוואה לפי
/// ה-id של הקטלוג לעולם לא תזהה תוסף מותקן.
abstract final class PluginManifestReader {
  static const _manifestEntryName = 'manifest.json';

  /// מחזיר את ה-id, או `null` אם הקובץ אינו ZIP תקין / חסר manifest / ה-id
  /// ריק. **לא זורק** — תוסף בודד עם קובץ פגום פשוט לא ישווה למותקן, וזה
  /// עדיף על הפלת הסנכרון כולו.
  static String? readId(String pluginFilePath) {
    final manifest = read(pluginFilePath);
    final id = manifest?['id'];
    return id is String && id.trim().isNotEmpty ? id.trim() : null;
  }

  static Map<String, dynamic>? read(String pluginFilePath) {
    InputFileStream? input;
    try {
      input = InputFileStream(pluginFilePath);
      final archive = ZipDecoder().decodeStream(input, verify: false);
      final entry = archive.files.where(
        (f) => f.isFile && f.name == _manifestEntryName,
      );
      if (entry.isEmpty) return null;

      final text = utf8
          .decode(entry.first.content, allowMalformed: true)
          .replaceFirst('\uFEFF', '');
      final decoded = jsonDecode(text);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    } finally {
      input?.closeSync();
    }
  }
}

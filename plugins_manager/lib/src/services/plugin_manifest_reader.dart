import 'dart:convert';
import 'dart:io';

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

  /// קורא את ה-manifest כולו. מחזיר `null` באותם מקרים כמו [readId].
  static Map<String, dynamic>? read(String pluginFilePath) {
    try {
      final bytes = File(pluginFilePath).readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes, verify: false);
      final entry = archive.files.where(
        (f) => f.isFile && f.name == _manifestEntryName,
      );
      if (entry.isEmpty) return null;

      // הסרת BOM: עורכים בווינדוס שומרים לעיתים JSON עם U+FEFF מוביל,
      // ו-jsonDecode נופל עליו.
      final text = utf8
          .decode(entry.first.content as List<int>, allowMalformed: true)
          .replaceFirst('﻿', '');
      final decoded = jsonDecode(text);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }
}

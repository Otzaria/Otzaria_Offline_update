import 'dart:io';

import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:test/test.dart';

/// תיקייה זמנית שנמחקת בסוף הבדיקה. הבדיקות כאן נוגעות בדיסק אמיתי
/// בכוונה — כל הערך של המרשם הוא מה שקורה לקבצים.
String tempMirrorRoot() {
  final dir = Directory.systemTemp.createTempSync('custom_apps_test_');
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });
  return dir.path;
}

AppDescriptor descriptor({
  String id = 'org.example.app',
  String name = 'תוכנה לדוגמה',
  String? publisher,
  String? installDir,
  AppDetectRules detect = const AppDetectRules(),
}) =>
    AppDescriptor(
      id: id,
      name: name,
      publisher: publisher,
      sourceKind: AppSourceKind.manual,
      installDir: installDir,
      detect: detect,
    );

/// יוצר קובץ עם תוכן נתון ומחזיר את נתיבו.
String writeFile(String path, [String content = 'x']) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
  return path;
}
